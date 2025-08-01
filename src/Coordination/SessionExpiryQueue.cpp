#include <Coordination/SessionExpiryQueue.h>
#include <Common/logger_useful.h>

namespace DB
{

bool SessionExpiryQueue::remove(int64_t session_id)
{
    std::lock_guard lock(mutex);
    auto session_it = session_to_expiration_time.find(session_id);
    if (session_it == session_to_expiration_time.end())
        return false;

    auto set_it = expiry_to_sessions.find(session_it->second);
    if (set_it != expiry_to_sessions.end())
        set_it->second.erase(session_id);

    /// No more sessions in this bucket
    if (set_it->second.empty())
        expiry_to_sessions.erase(set_it);

    session_to_expiration_time.erase(session_it);

    return true;
}

void SessionExpiryQueue::addNewSessionOrUpdate(int64_t session_id, int64_t timeout_ms)
{
    int64_t now = getNowMilliseconds();
    /// round up to next interval
    int64_t new_expiry_time = roundToNextInterval(now + timeout_ms);

    std::lock_guard lock(mutex);

    auto session_it = session_to_expiration_time.find(session_id);
    /// We already registered this session
    if (session_it != session_to_expiration_time.end())
    {
        int64_t prev_expiry_time = session_it->second;
        session_it->second = new_expiry_time;
        /// Nothing changed, session stay in the some bucket
        if (new_expiry_time == prev_expiry_time)
            return;

        /// This bucket doesn't exist, let's create it
        expiry_to_sessions[new_expiry_time].insert(session_id);

        auto prev_set_it = expiry_to_sessions.find(prev_expiry_time);
        /// Remove session from previous bucket
        if (prev_set_it != expiry_to_sessions.end())
            prev_set_it->second.erase(session_id);

        /// No more sessions in this bucket
        if (prev_set_it->second.empty())
            expiry_to_sessions.erase(prev_set_it);
    }
    else
    {
        /// Just add sessions to the new bucket
        session_to_expiration_time[session_id] = new_expiry_time;
        expiry_to_sessions[new_expiry_time].insert(session_id);
    }
}

std::vector<int64_t> SessionExpiryQueue::getExpiredSessions() const
{
    std::lock_guard lock(mutex);
    int64_t now = getNowMilliseconds();
    std::vector<int64_t> result;

    /// Check all buckets
    for (const auto & [expire_time, expired_sessions] : expiry_to_sessions)
    {
        if (expire_time <= now)
            result.insert(result.end(), expired_sessions.begin(), expired_sessions.end());
        else
            break;
    }

    return result;
}

void SessionExpiryQueue::clear()
{
    std::lock_guard lock(mutex);
    session_to_expiration_time.clear();
    expiry_to_sessions.clear();
}

}
