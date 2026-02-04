#pragma once

#if defined(__clang__)
#    pragma clang diagnostic push
#    pragma clang diagnostic ignored "-Wunused-macros"
#endif

#include <base/defines.h>
#include <base/types.h>

/* This file contains macros and helpers for writing platform-dependent code.
 *
 * Macros DECLARE_<Arch>_SPECIFIC_CODE will wrap code inside it into the
 * namespace TargetSpecific::<Arch> and enable Arch-specific compile options.
 * Thus, it's allowed to call functions inside these namespaces only after
 * checking platform in runtime (see isArchSupported() below).
 *
 * If compiler is not gcc/clang or target isn't x86_64 or ENABLE_MULTITARGET_CODE
 * was set to OFF in cmake, all code inside these macros will be removed and
 * USE_MULTITARGET_CODE will be set to 0. Use #if USE_MULTITARGET_CODE whenever you
 * use anything from this namespaces.
 *
 * For similarities there is a macros DECLARE_DEFAULT_CODE, which wraps code
 * into the namespace TargetSpecific::Default but doesn't specify any additional
 * copile options. Functions and classes inside this macros are available regardless
 * of USE_MUTLITARGE_CODE.
 *
 * Example of usage:
 *
 * DECLARE_DEFAULT_CODE (
 * int funcImpl() {
 *     return 1;
 * }
 * ) // DECLARE_DEFAULT_CODE
 *
 * DECLARE_AVX2_SPECIFIC_CODE (
 * int funcImpl() {
 *     return 2;
 * }
 * ) // DECLARE_AVX2_SPECIFIC_CODE
 *
 * int func() {
 * #if USE_MULTITARGET_CODE
 *     if (isArchSupported(TargetArch::AVX2))
 *         return TargetSpecific::AVX2::funcImpl();
 * #endif
 *     return TargetSpecific::Default::funcImpl();
 * }
 *
 * Sometimes code may benefit from compiling with different options.
 * For these purposes use DECLARE_MULTITARGET_CODE macros. It will create a copy
 * of the code for every supported target and compile it with different options.
 * These copies are available via TargetSpecific namespaces described above.
 *
 * Inside every TargetSpecific namespace there is a constexpr variable BuildArch,
 * which indicates the target platform for current code.
 *
 * Example:
 *
 * DECLARE_MULTITARGET_CODE(
 * int funcImpl(int size, ...) {
 *     int iteration_size = 1;
 *     if constexpr (BuildArch == TargetArch::SSE42)
 *         iteration_size = 2
 *     else if constexpr (BuildArch == TargetArch::AVX || BuildArch == TargetArch::AVX2)
 *         iteration_size = 4;
 *     for (int i = 0; i < size; i += iteration_size)
 *     ...
 * }
 * ) // DECLARE_MULTITARGET_CODE
 *
 * // All target-specific and default implementations are available here via
 * TargetSpecific::<Arch>::funcImpl. Use runtime detection to choose one.
 *
 * If you want to write IFunction or IExecutableFunctionImpl with several implementations
 * see PerformanceAdaptors.h.
 */

namespace DB
{

enum class TargetArch : UInt32
{
    Default = 0, /// Without any additional compiler options.
    SSE42 = (1 << 0), /// SSE4.2
    AVX = (1 << 1),
    AVX2 = (1 << 2),
    AVX512F = (1 << 3),
    AVX512BW = (1 << 4),
    AVX512VBMI = (1 << 5),
    AVX512VBMI2 = (1 << 6),
    AVX512BF16 = (1 << 7),
    GenuineIntel = (1 << 8), /// Not an instruction set, but a CPU vendor.
};

/// Runtime detection.
UInt32 getSupportedArchs();
inline ALWAYS_INLINE bool isArchSupported(TargetArch arch)
{
    static UInt32 arches = getSupportedArchs();
    return arch == TargetArch::Default || (arches & static_cast<UInt32>(arch));
}

String toString(TargetArch arch);

#ifndef ENABLE_MULTITARGET_CODE
#   define ENABLE_MULTITARGET_CODE 0
#endif

#if ENABLE_MULTITARGET_CODE && defined(__GNUC__) && defined(__x86_64__)


#define USE_MULTITARGET_CODE 1

/// Target attribute strings - each defined once and used by both function attributes and pragmas

/// Intel Nehalem (2008), AMD Bulldozer (2011)
#define SSE42_TARGET "sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt"

/// Intel Sandy Bridge (2011), AMD Bulldozer (2011)
#define AVX_TARGET "sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx"

/// x86-64-v3: Intel Haswell (2013), AMD Excavator (2015)
/// Adds: AVX2, FMA, F16C, BMI1, BMI2
#define AVX2_TARGET "sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx,avx2,fma,f16c,bmi,bmi2"

/// Intel Skylake-X (2017), AMD Zen 4 (2022)
/// Adds: AVX512F (Foundation), AVX512CD (Conflict Detection)
#define AVX512F_TARGET "sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx,avx2,fma,f16c,bmi,bmi2,avx512f,avx512cd"

/// Intel Skylake-X (2017), AMD Zen 4 (2022)
/// Adds: AVX512BW (Byte/Word), AVX512DQ (Doubleword/Quadword), AVX512VL (Vector Length)
/// Note: AVX512BW, AVX512DQ, and AVX512VL were introduced together and always ship together
#define AVX512BW_TARGET "sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx,avx2,fma,f16c,bmi,bmi2,avx512f,avx512cd,avx512bw,avx512dq,avx512vl"

/// Intel Ice Lake (2019), AMD Zen 4 (2022)
/// Adds: AVX512VBMI (Vector Byte Manipulation Instructions)
#define AVX512VBMI_TARGET "sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx,avx2,fma,f16c,bmi,bmi2,avx512f,avx512cd,avx512bw,avx512dq,avx512vl,avx512vbmi"

/// Intel Ice Lake (2019), AMD Zen 4 (2022)
/// Adds: AVX512VBMI2 (Vector Byte Manipulation Instructions 2)
#define AVX512VBMI2_TARGET "sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx,avx2,fma,f16c,bmi,bmi2,avx512f,avx512cd,avx512bw,avx512dq,avx512vl,avx512vbmi,avx512vbmi2"

/// Intel Cooper Lake (2020), AMD Zen 4 (2022)
/// Adds: AVX512BF16 (BFloat16)
#define AVX512BF16_TARGET "sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx,avx2,fma,f16c,bmi,bmi2,avx512f,avx512cd,avx512bw,avx512dq,avx512vl,avx512vbmi,avx512vbmi2,avx512bf16"

/// Function-specific attributes
#define SSE42_FUNCTION_SPECIFIC_ATTRIBUTE __attribute__((target(SSE42_TARGET)))
#define AVX_FUNCTION_SPECIFIC_ATTRIBUTE __attribute__((target(AVX_TARGET)))
#define AVX2_FUNCTION_SPECIFIC_ATTRIBUTE __attribute__((target(AVX2_TARGET)))
#define AVX512_FUNCTION_SPECIFIC_ATTRIBUTE __attribute__((target(AVX512F_TARGET)))
#define AVX512BW_FUNCTION_SPECIFIC_ATTRIBUTE __attribute__((target(AVX512BW_TARGET)))
#define AVX512VBMI_FUNCTION_SPECIFIC_ATTRIBUTE __attribute__((target(AVX512VBMI_TARGET)))
#define AVX512VBMI2_FUNCTION_SPECIFIC_ATTRIBUTE __attribute__((target(AVX512VBMI2_TARGET)))
#define AVX512BF16_FUNCTION_SPECIFIC_ATTRIBUTE __attribute__((target(AVX512BF16_TARGET)))
#define DEFAULT_FUNCTION_SPECIFIC_ATTRIBUTE

/// Begin target-specific code blocks
#define BEGIN_SSE42_SPECIFIC_CODE \
    _Pragma("clang attribute push(__attribute__((target(\"sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt\"))),apply_to=function)")
#define BEGIN_AVX_SPECIFIC_CODE \
    _Pragma("clang attribute push(__attribute__((target(\"sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx\"))),apply_to=function)")
#define BEGIN_AVX2_SPECIFIC_CODE \
    _Pragma("clang attribute push(__attribute__((target(\"sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx,avx2,fma,f16c,bmi,bmi2\"))),apply_to=function)")
#define BEGIN_AVX512F_SPECIFIC_CODE \
    _Pragma("clang attribute push(__attribute__((target(\"sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx,avx2,fma,f16c,bmi,bmi2,avx512f,avx512cd\"))),apply_to=function)")
#define BEGIN_AVX512BW_SPECIFIC_CODE \
    _Pragma("clang attribute push(__attribute__((target(\"sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx,avx2,fma,f16c,bmi,bmi2,avx512f,avx512cd,avx512bw,avx512dq,avx512vl\"))),apply_to=function)")
#define BEGIN_AVX512VBMI_SPECIFIC_CODE \
    _Pragma("clang attribute push(__attribute__((target(\"sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx,avx2,fma,f16c,bmi,bmi2,avx512f,avx512cd,avx512bw,avx512dq,avx512vl,avx512vbmi\"))),apply_to=function)")
#define BEGIN_AVX512VBMI2_SPECIFIC_CODE \
    _Pragma("clang attribute push(__attribute__((target(\"sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx,avx2,fma,f16c,bmi,bmi2,avx512f,avx512cd,avx512bw,avx512dq,avx512vl,avx512vbmi,avx512vbmi2\"))),apply_to=function)")
#define BEGIN_AVX512BF16_SPECIFIC_CODE \
    _Pragma("clang attribute push(__attribute__((target(\"sse,sse2,sse3,ssse3,sse4.1,sse4.2,popcnt,avx,avx2,fma,f16c,bmi,bmi2,avx512f,avx512cd,avx512bw,avx512dq,avx512vl,avx512vbmi,avx512vbmi2,avx512bf16\"))),apply_to=function)")
#define END_TARGET_SPECIFIC_CODE \
    _Pragma("clang attribute pop")

/* Clang shows warning when there aren't any objects to apply pragma.
 * To prevent this warning we define this function inside every macros with pragmas.
 */
#   define DUMMY_FUNCTION_DEFINITION [[maybe_unused]] void _dummy_function_definition();


#define DECLARE_SSE42_SPECIFIC_CODE(...) \
BEGIN_SSE42_SPECIFIC_CODE \
namespace TargetSpecific::SSE42 { \
    DUMMY_FUNCTION_DEFINITION \
    using namespace DB::TargetSpecific::SSE42; \
    __VA_ARGS__ \
} \
END_TARGET_SPECIFIC_CODE

#define DECLARE_AVX_SPECIFIC_CODE(...) \
BEGIN_AVX_SPECIFIC_CODE \
namespace TargetSpecific::AVX { \
    DUMMY_FUNCTION_DEFINITION \
    using namespace DB::TargetSpecific::AVX; \
    __VA_ARGS__ \
} \
END_TARGET_SPECIFIC_CODE

#define DECLARE_AVX2_SPECIFIC_CODE(...) \
BEGIN_AVX2_SPECIFIC_CODE \
namespace TargetSpecific::AVX2 { \
    DUMMY_FUNCTION_DEFINITION \
    using namespace DB::TargetSpecific::AVX2; \
    __VA_ARGS__ \
} \
END_TARGET_SPECIFIC_CODE

#define DECLARE_AVX512F_SPECIFIC_CODE(...) \
BEGIN_AVX512F_SPECIFIC_CODE \
namespace TargetSpecific::AVX512F { \
    DUMMY_FUNCTION_DEFINITION \
    using namespace DB::TargetSpecific::AVX512F; \
    __VA_ARGS__ \
} \
END_TARGET_SPECIFIC_CODE

#define DECLARE_AVX512BW_SPECIFIC_CODE(...) \
BEGIN_AVX512BW_SPECIFIC_CODE \
namespace TargetSpecific::AVX512BW { \
    DUMMY_FUNCTION_DEFINITION \
    using namespace DB::TargetSpecific::AVX512BW; \
    __VA_ARGS__ \
} \
END_TARGET_SPECIFIC_CODE

#define DECLARE_AVX512VBMI_SPECIFIC_CODE(...) \
BEGIN_AVX512VBMI_SPECIFIC_CODE \
namespace TargetSpecific::AVX512VBMI { \
    DUMMY_FUNCTION_DEFINITION \
    using namespace DB::TargetSpecific::AVX512VBMI; \
    __VA_ARGS__ \
} \
END_TARGET_SPECIFIC_CODE

#define DECLARE_AVX512VBMI2_SPECIFIC_CODE(...) \
BEGIN_AVX512VBMI2_SPECIFIC_CODE \
namespace TargetSpecific::AVX512VBMI2 { \
    DUMMY_FUNCTION_DEFINITION \
    using namespace DB::TargetSpecific::AVX512VBMI2; \
    __VA_ARGS__ \
} \
END_TARGET_SPECIFIC_CODE

#define DECLARE_AVX512BF16_SPECIFIC_CODE(...) \
BEGIN_AVX512BF16_SPECIFIC_CODE \
namespace TargetSpecific::AVX512BF16 { \
    DUMMY_FUNCTION_DEFINITION \
    using namespace DB::TargetSpecific::AVX512BF16; \
    __VA_ARGS__ \
} \
END_TARGET_SPECIFIC_CODE

#else

#define USE_MULTITARGET_CODE 0

/* Multitarget code is disabled, just delete target-specific code.
 */
#define DECLARE_SSE42_SPECIFIC_CODE(...)
#define DECLARE_AVX_SPECIFIC_CODE(...)
#define DECLARE_AVX2_SPECIFIC_CODE(...)
#define DECLARE_AVX512F_SPECIFIC_CODE(...)
#define DECLARE_AVX512BW_SPECIFIC_CODE(...)
#define DECLARE_AVX512VL_SPECIFIC_CODE(...)
#define DECLARE_AVX512VBMI_SPECIFIC_CODE(...)
#define DECLARE_AVX512VBMI2_SPECIFIC_CODE(...)
#define DECLARE_AVX512BF16_SPECIFIC_CODE(...)

#endif

#define DECLARE_DEFAULT_CODE(...) \
namespace TargetSpecific::Default { \
    using namespace DB::TargetSpecific::Default; \
    __VA_ARGS__ \
}


#define DECLARE_MULTITARGET_CODE(...) \
DECLARE_DEFAULT_CODE         (__VA_ARGS__) \
DECLARE_SSE42_SPECIFIC_CODE  (__VA_ARGS__) \
DECLARE_AVX_SPECIFIC_CODE    (__VA_ARGS__) \
DECLARE_AVX2_SPECIFIC_CODE   (__VA_ARGS__) \
DECLARE_AVX512F_SPECIFIC_CODE(__VA_ARGS__) \
DECLARE_AVX512BW_SPECIFIC_CODE    (__VA_ARGS__) \
DECLARE_AVX512VBMI_SPECIFIC_CODE  (__VA_ARGS__) \
DECLARE_AVX512VBMI2_SPECIFIC_CODE (__VA_ARGS__) \
DECLARE_AVX512BF16_SPECIFIC_CODE (__VA_ARGS__)

DECLARE_DEFAULT_CODE(
    constexpr auto BuildArch = TargetArch::Default;
)

DECLARE_SSE42_SPECIFIC_CODE(
    constexpr auto BuildArch = TargetArch::SSE42;
)

DECLARE_AVX_SPECIFIC_CODE(
    constexpr auto BuildArch = TargetArch::AVX;
)

DECLARE_AVX2_SPECIFIC_CODE(
    constexpr auto BuildArch = TargetArch::AVX2;
)

DECLARE_AVX512F_SPECIFIC_CODE(
    constexpr auto BuildArch = TargetArch::AVX512F;
)

DECLARE_AVX512BW_SPECIFIC_CODE(
    constexpr auto BuildArch = TargetArch::AVX512BW;
)

DECLARE_AVX512VBMI_SPECIFIC_CODE(
    constexpr auto BuildArch = TargetArch::AVX512VBMI;
)

DECLARE_AVX512VBMI2_SPECIFIC_CODE(
    constexpr auto BuildArch = TargetArch::AVX512VBMI2;
)

DECLARE_AVX512BF16_SPECIFIC_CODE(
    constexpr auto BuildArch = TargetArch::AVX512BF16;
)

/** Runtime Dispatch helpers for class members.
  *
  * Example of usage:
  *
  * class TestClass
  * {
  * public:
  *     MULTITARGET_FUNCTION_AVX512BW_AVX512F_AVX2(
  *     MULTITARGET_FUNCTION_HEADER(int), testFunctionImpl, MULTITARGET_FUNCTION_BODY((int value)
  *     {
  *          return value;
  *     })
  *     )
  *
  *     void testFunction(int value) {
  *         if (isArchSupported(TargetArch::AVX512BW))
  *         {
  *             testFunctionImplAVX512BW(value);
  *         }
  *         else if (isArchSupported(TargetArch::AVX512F))
  *         {
  *             testFunctionImplAVX512F(value);
  *         }
  *         else if (isArchSupported(TargetArch::AVX2))
  *         {
  *             testFunctionImplAVX2(value);
  *         }
  *         else
  *         {
  *             testFunction(value);
  *         }
  *     }
  *};
  *
  */

/// Function header
#define MULTITARGET_FUNCTION_HEADER(...) __VA_ARGS__

/// Function body
#define MULTITARGET_FUNCTION_BODY(...) __VA_ARGS__

#if ENABLE_MULTITARGET_CODE && defined(__GNUC__) && defined(__x86_64__)

#define MULTITARGET_FUNCTION_AVX512BW_AVX512F_AVX2(FUNCTION_HEADER, name, FUNCTION_BODY) \
    FUNCTION_HEADER \
    \
    AVX512BW_FUNCTION_SPECIFIC_ATTRIBUTE \
    name##AVX512BW \
    FUNCTION_BODY \
    \
    FUNCTION_HEADER \
    \
    AVX512_FUNCTION_SPECIFIC_ATTRIBUTE \
    name##AVX512F \
    FUNCTION_BODY \
    \
    FUNCTION_HEADER \
    \
    AVX2_FUNCTION_SPECIFIC_ATTRIBUTE \
    name##AVX2 \
    FUNCTION_BODY \
    \
    FUNCTION_HEADER \
    \
    name \
    FUNCTION_BODY \

#define MULTITARGET_FUNCTION_AVX512BW_AVX2(FUNCTION_HEADER, name, FUNCTION_BODY) \
    FUNCTION_HEADER \
    \
    AVX512BW_FUNCTION_SPECIFIC_ATTRIBUTE \
    name##AVX512BW \
    FUNCTION_BODY \
    \
    FUNCTION_HEADER \
    \
    AVX2_FUNCTION_SPECIFIC_ATTRIBUTE \
    name##AVX2 \
    FUNCTION_BODY \
    \
    FUNCTION_HEADER \
    \
    name \
    FUNCTION_BODY \

#define MULTITARGET_FUNCTION_AVX2(FUNCTION_HEADER, name, FUNCTION_BODY) \
    FUNCTION_HEADER \
    \
    AVX2_FUNCTION_SPECIFIC_ATTRIBUTE \
    name##AVX2 \
    FUNCTION_BODY \
    \
    FUNCTION_HEADER \
    \
    name \
    FUNCTION_BODY \


#else

#define MULTITARGET_FUNCTION_AVX512BW_AVX512F_AVX2(FUNCTION_HEADER, name, FUNCTION_BODY) \
    FUNCTION_HEADER \
    \
    name \
    FUNCTION_BODY \

#define MULTITARGET_FUNCTION_AVX512BW_AVX2(FUNCTION_HEADER, name, FUNCTION_BODY) \
    FUNCTION_HEADER \
    \
    name \
    FUNCTION_BODY \

#define MULTITARGET_FUNCTION_AVX2(FUNCTION_HEADER, name, FUNCTION_BODY) \
    FUNCTION_HEADER \
    \
    name \
    FUNCTION_BODY \

#endif

}

#if defined(__clang__)
#    pragma clang diagnostic pop
#endif
