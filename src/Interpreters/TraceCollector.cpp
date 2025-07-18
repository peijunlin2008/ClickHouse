#include <Interpreters/TraceCollector.h>
#include <Core/Field.h>
#include <IO/ReadBufferFromFileDescriptor.h>
#include <IO/ReadHelpers.h>
#include <IO/WriteBufferFromFileDescriptor.h>
#include <IO/WriteHelpers.h>
#include <Interpreters/TraceLog.h>
#include <Common/MemoryTrackerBlockerInThread.h>
#include <Common/Exception.h>
#include <Common/TraceSender.h>
#include <Common/ProfileEvents.h>
#include <Common/setThreadName.h>
#include <Common/logger_useful.h>
#include <Common/SymbolIndex.h>


namespace DB
{

namespace ErrorCodes
{
    extern const int LOGICAL_ERROR;
}

TraceCollector::TraceCollector()
{
    TraceSender::pipe.open();

    /** Turn write end of pipe to non-blocking mode to avoid deadlocks
      * when QueryProfiler is invoked under locks and TraceCollector cannot pull data from pipe.
      */
    TraceSender::pipe.setNonBlockingWrite();
    TraceSender::pipe.tryIncreaseSize(1 << 20);

    thread = ThreadFromGlobalPool(&TraceCollector::run, this);
}

void TraceCollector::initialize(std::shared_ptr<TraceLog> trace_log_)
{
    if (is_trace_log_initialized)
        throw DB::Exception(ErrorCodes::LOGICAL_ERROR, "TraceCollector is already initialized");

    trace_log_ptr = trace_log_;
    symbolize = trace_log_ptr->symbolize;
    is_trace_log_initialized.store(true, std::memory_order_release);
}

std::shared_ptr<TraceLog> TraceCollector::getTraceLog()
{
    if (!is_trace_log_initialized.load(std::memory_order_acquire))
        return nullptr;

    return trace_log_ptr;
}

void TraceCollector::tryClosePipe()
{
    try
    {
        TraceSender::pipe.close();
    }
    catch (...)
    {
        tryLogCurrentException("TraceCollector");
    }
}

TraceCollector::~TraceCollector()
{
    // Pipes could be already closed due to exception in TraceCollector::run.
    if (TraceSender::pipe.fds_rw[1] >= 0)
    {
        try
        {
            /** Sends TraceCollector stop message
            *
            * Each sequence of data for TraceCollector thread starts with a boolean flag.
            * If this flag is true, TraceCollector must stop reading trace_pipe and exit.
            * This function sends flag with a true value to stop TraceCollector gracefully.
            */
            WriteBufferFromFileDescriptor out(TraceSender::pipe.fds_rw[1]);
            writeChar(true, out);
            out.finalize();
        }
        catch (...)
        {
            tryLogCurrentException("TraceCollector");
        }
    }

    tryClosePipe();

    if (thread.joinable())
        thread.join();
    else
        LOG_ERROR(getLogger("TraceCollector"), "TraceCollector thread is malformed and cannot be joined");
}


void TraceCollector::run()
{
    setThreadName("TraceCollector");

    MemoryTrackerBlockerInThread untrack_lock(VariableContext::Global);
    ReadBufferFromFileDescriptor in(TraceSender::pipe.fds_rw[0]);

#if defined(__ELF__) && !defined(OS_FREEBSD)
    const auto * object = SymbolIndex::instance().thisObject();
#endif

    try
    {
        while (true)
        {
            char is_last;
            readChar(is_last, in);
            if (is_last)
                break;

            std::string query_id;
            UInt8 query_id_size = 0;
            readBinary(query_id_size, in);
            query_id.resize(query_id_size);
            in.readStrict(query_id.data(), query_id_size);

            UInt8 trace_size = 0;
            readIntBinary(trace_size, in);

            std::vector<UInt64> trace;
            trace.reserve(trace_size);

            for (size_t i = 0; i < trace_size; ++i)
            {
                uintptr_t addr = 0;
                readPODBinary(addr, in);

                /// Addresses in the main object will be normalized to the physical file offsets for convenience and security.
                uintptr_t offset = 0;
#if defined(__ELF__) && !defined(OS_FREEBSD)
                if (object && uintptr_t(object->address_begin) <= addr && addr < uintptr_t(object->address_end))
                    offset = uintptr_t(object->address_begin);
#endif

                trace.emplace_back(static_cast<UInt64>(addr) - offset);
            }

            TraceType trace_type;
            readPODBinary(trace_type, in);

            UInt64 thread_id;
            readPODBinary(thread_id, in);

            Int64 size;
            readPODBinary(size, in);

            UInt64 ptr;
            readPODBinary(ptr, in);

            ProfileEvents::Event event;
            readPODBinary(event, in);

            ProfileEvents::Count increment;
            readPODBinary(increment, in);

            if (auto trace_log = getTraceLog())
            {
                // time and time_in_microseconds are both being constructed from the same timespec so that the
                // times will be equal up to the precision of a second.
                struct timespec ts;
                clock_gettime(CLOCK_REALTIME, &ts); /// NOLINT(cert-err33-c)

                UInt64 time = static_cast<UInt64>(ts.tv_sec * 1000000000LL + ts.tv_nsec);
                UInt64 time_in_microseconds = static_cast<UInt64>((ts.tv_sec * 1000000LL) + (ts.tv_nsec / 1000));

                TraceLogElement element{symbolize, time_t(time / 1000000000), time_in_microseconds, time, trace_type, thread_id, query_id, std::move(trace), size, ptr, event, increment};
                trace_log->add(std::move(element));
            }
        }
    }
    catch (...)
    {
        tryLogCurrentException("TraceCollector");
        tryClosePipe();
        throw;
    }
}

}
