#pragma once

#include <new>
#include <base/defines.h>

#include <Common/Concepts.h>
#include <Common/CurrentMemoryTracker.h>
#include <Common/ProfileEvents.h>
#include "config.h"

#if USE_JEMALLOC
#    include <jemalloc/jemalloc.h>
#endif

#if !USE_JEMALLOC
#    include <cstdlib>
#endif

#if defined(OS_LINUX)
#    include <malloc.h>
#elif defined(OS_DARWIN)
#    include <malloc/malloc.h>
#endif

/// Guard pages interface.
///
/// Uses MADV_GUARD_INSTALL/MADV_GUARD_REMOVE (since Linux 6.13+) which does
/// not splits VMA (unlike mprotect()), or fallback to mprotect()
///
/// Uses MADV_GUARD_INSTALL if available, or mprotect() if not
void memoryGuardInstall(void *addr, size_t len);
/// Uses MADV_GUARD_REMOVE if available, or mprotect() if not
void memoryGuardRemove(void *addr, size_t len);

namespace Memory
{

inline ALWAYS_INLINE size_t alignToSizeT(std::align_val_t align) noexcept
{
    return static_cast<size_t>(align);
}

inline ALWAYS_INLINE size_t alignUp(size_t size, size_t align) noexcept
{
    return (size + align - 1) / align * align;
}

template <std::same_as<std::align_val_t>... TAlign>
requires DB::OptionalArgument<TAlign...>
inline ALWAYS_INLINE void * newImpl(std::size_t size, TAlign... align)
{
    void * ptr = nullptr;
    if constexpr (sizeof...(TAlign) == 1)
        ptr = aligned_alloc(alignToSizeT(align...), alignUp(size, alignToSizeT(align...)));
    else
        ptr = malloc(size);

    if (likely(ptr != nullptr))
        return ptr;

    /// @note no std::get_new_handler logic implemented
    throw std::bad_alloc{};
}

inline ALWAYS_INLINE void * newNoExcept(std::size_t size) noexcept
{
    return malloc(size);
}

inline ALWAYS_INLINE void * newNoExcept(std::size_t size, std::align_val_t align) noexcept
{
    return aligned_alloc(static_cast<size_t>(align), size);
}

inline ALWAYS_INLINE void deleteImpl(void * ptr) noexcept
{
    free(ptr);
}

#if USE_JEMALLOC

template <std::same_as<std::align_val_t>... TAlign>
requires DB::OptionalArgument<TAlign...>
inline ALWAYS_INLINE void deleteSized(void * ptr, std::size_t size, TAlign... align) noexcept
{
    if (unlikely(ptr == nullptr))
        return;

    if constexpr (sizeof...(TAlign) == 1)
        sdallocx(ptr, size, MALLOCX_ALIGN(alignToSizeT(align...)));
    else
        sdallocx(ptr, size, 0);
}

#else

template <std::same_as<std::align_val_t>... TAlign>
requires DB::OptionalArgument<TAlign...>
inline ALWAYS_INLINE void deleteSized(void * ptr, std::size_t size [[maybe_unused]], TAlign... /* align */) noexcept
{
    free(ptr);
}

#endif

template <std::same_as<std::align_val_t>... TAlign>
requires DB::OptionalArgument<TAlign...>
inline ALWAYS_INLINE size_t getActualAllocationSize(size_t size, TAlign... align [[maybe_unused]])
{
    size_t actual_size = size;

#if USE_JEMALLOC
    /// The nallocx() function allocates no memory, but it performs the same size computation as the mallocx() function
    /// @note je_mallocx() != je_malloc(). It's expected they don't differ much in allocation logic.
    if (likely(size != 0))
    {
        if constexpr (sizeof...(TAlign) == 1)
            actual_size = nallocx(size, MALLOCX_ALIGN(alignToSizeT(align...)));
        else
            actual_size = nallocx(size, 0);
    }
#endif

    return actual_size;
}

template <std::same_as<std::align_val_t>... TAlign>
requires DB::OptionalArgument<TAlign...>
inline ALWAYS_INLINE size_t trackMemory(std::size_t size, AllocationTrace & trace, TAlign... align)
{
    std::size_t actual_size = getActualAllocationSize(size, align...);
    trace = CurrentMemoryTracker::allocNoThrow(actual_size);
    return actual_size;
}

template <std::same_as<std::align_val_t>... TAlign>
requires DB::OptionalArgument<TAlign...>
inline ALWAYS_INLINE size_t untrackMemory(void * ptr [[maybe_unused]], AllocationTrace & trace, std::size_t size [[maybe_unused]] = 0, TAlign... align [[maybe_unused]]) noexcept
{
    std::size_t actual_size = 0;

    try
    {
#if USE_JEMALLOC

        /// @note It's also possible to use je_malloc_usable_size() here.
        if (likely(ptr != nullptr))
        {
            if constexpr (sizeof...(TAlign) == 1)
                actual_size = sallocx(ptr, MALLOCX_ALIGN(alignToSizeT(align...)));
            else
                actual_size = sallocx(ptr, 0);
        }
#else
        if (size)
            actual_size = size;
#    if defined(_GNU_SOURCE)
        /// It's innaccurate resource free for sanitizers. malloc_usable_size() result is greater or equal to allocated size.
        else
            actual_size = malloc_usable_size(ptr);
#    endif
#endif
        trace = CurrentMemoryTracker::free(actual_size);
    }
    catch (...) /// NOLINT(bugprone-empty-catch)
    {
    }

    return actual_size;
}

}
