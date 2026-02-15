import argparse
import glob
import os
import platform
import shutil

from ci.praktika.result import Result
from ci.praktika.utils import MetaClasses, Shell, Utils

TEMP = "/tmp"
LLVM_SOURCE_DIR = f"{TEMP}/llvm-project"
STAGE1_BUILD_DIR = f"{TEMP}/toolchain-stage1"
STAGE1_INSTALL_DIR = f"{TEMP}/toolchain-stage1-install"
STAGE2_BUILD_DIR = f"{TEMP}/toolchain-stage2"
STAGE2_INSTALL_DIR = f"{TEMP}/toolchain-stage2-install"
CH_PROFILE_BUILD_DIR = f"{TEMP}/toolchain-ch-profile"
CH_BOLT_BUILD_DIR = f"{TEMP}/toolchain-ch-bolt"
PROFDATA_PATH = f"{TEMP}/clang.profdata"
BOLT_PROFILES_DIR = f"{TEMP}/bolt-profiles"
BOLT_FDATA_PATH = f"{TEMP}/bolt.fdata"

REPO_PATH = "/ClickHouse"

OUTPUT_DIR = f"{Utils.cwd()}/ci/tmp"


class JobStages(metaclass=MetaClasses.WithIter):
    CLONE_LLVM = "clone_llvm"
    STAGE1_BUILD = "stage1_build"
    PROFILE_COLLECTION = "profile_collection"
    STAGE2_BUILD = "stage2_build"
    BOLT_OPTIMIZATION = "bolt_optimization"
    PACKAGE = "package"


def get_arch():
    machine = platform.machine()
    if machine == "x86_64":
        return "x86_64"
    elif machine == "aarch64":
        return "aarch64"
    else:
        raise RuntimeError(f"Unsupported architecture: {machine}")


def get_toolchain_file():
    arch = get_arch()
    return f"{REPO_PATH}/cmake/linux/toolchain-{arch}.cmake"


def clean_dirs(*dirs):
    for d in dirs:
        if os.path.exists(d):
            print(f"Cleaning {d}")
            shutil.rmtree(d, ignore_errors=True)


def parse_args():
    parser = argparse.ArgumentParser(description="Build PGO+BOLT optimized clang")
    parser.add_argument(
        "--param",
        help="Optional user-defined job start stage (for local run)",
        default=None,
    )
    return parser.parse_args()


def main():
    args = parse_args()

    stages = list(JobStages)
    stage = args.param or JobStages.CLONE_LLVM
    if stage:
        assert stage in JobStages, f"--param must be one of [{list(JobStages)}]"
        print(f"Job will start from stage [{stage}]")
        while stage in stages:
            stages.pop(0)
        stages.insert(0, stage)

    arch = get_arch()
    toolchain_file = get_toolchain_file()
    print(f"Building toolchain for {arch}")
    print(f"Using ClickHouse toolchain file: {toolchain_file}")

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    res = True
    results = []

    if os.getuid() == 0:
        Shell.check(
            f"git config --global --add safe.directory {Utils.cwd()}"
        )

    # Stage 0: Clone LLVM
    if res and JobStages.CLONE_LLVM in stages:
        clean_dirs(LLVM_SOURCE_DIR)
        results.append(
            Result.from_commands_run(
                name="Clone LLVM",
                command=(
                    f"git clone --depth 1 --branch release/21.x"
                    f" https://github.com/llvm/llvm-project.git {LLVM_SOURCE_DIR}"
                ),
                retries=3,
            )
        )
        res = results[-1].is_ok()

    # Stage 1: Build instrumented clang for PGO profile collection
    if res and JobStages.STAGE1_BUILD in stages:
        clean_dirs(STAGE1_BUILD_DIR, STAGE1_INSTALL_DIR)
        os.makedirs(STAGE1_BUILD_DIR, exist_ok=True)

        cmake_cmd = (
            f"cmake -G Ninja"
            f' -DLLVM_ENABLE_PROJECTS="clang;lld;bolt"'
            f' -DLLVM_ENABLE_RUNTIMES="compiler-rt"'
            f" -DLLVM_TARGETS_TO_BUILD=Native"
            f" -DCMAKE_BUILD_TYPE=Release"
            f" -DLLVM_BUILD_INSTRUMENTED=IR"
            f" -DLLVM_ENABLE_TERMINFO=OFF"
            f" -DLLVM_ENABLE_ZLIB=OFF"
            f" -DLLVM_ENABLE_ZSTD=OFF"
            f" -DCMAKE_INSTALL_PREFIX={STAGE1_INSTALL_DIR}"
            f" -S {LLVM_SOURCE_DIR}/llvm"
            f" -B {STAGE1_BUILD_DIR}"
        )
        results.append(
            Result.from_commands_run(
                name="Stage 1 CMake (instrumented clang)",
                command=cmake_cmd,
            )
        )
        res = results[-1].is_ok()

        if res:
            results.append(
                Result.from_commands_run(
                    name="Stage 1 Build (instrumented clang)",
                    command=f"ninja -C {STAGE1_BUILD_DIR} clang lld llvm-profdata",
                )
            )
            res = results[-1].is_ok()

        if res:
            results.append(
                Result.from_commands_run(
                    name="Stage 1 Install",
                    command=(
                        f"ninja -C {STAGE1_BUILD_DIR}"
                        f" install-clang install-clang-resource-headers"
                        f" install-lld install-llvm-profdata"
                    ),
                )
            )
            res = results[-1].is_ok()

    # Stage 2: Profile collection - build ClickHouse with instrumented clang
    if res and JobStages.PROFILE_COLLECTION in stages:
        clean_dirs(CH_PROFILE_BUILD_DIR)

        # Checkout submodules first
        results.append(
            Result.from_commands_run(
                name="Checkout submodules for profile collection",
                command=[
                    f"git -C {REPO_PATH} submodule sync",
                    f"git -C {REPO_PATH} submodule init",
                    f"{REPO_PATH}/contrib/update-submodules.sh --max-procs 10",
                ],
                retries=3,
            )
        )
        res = results[-1].is_ok()

        if res:
            cmake_cmd = (
                f"cmake"
                f" -DCMAKE_BUILD_TYPE=None"
                f" -DENABLE_THINLTO=0"
                f" -DCMAKE_C_COMPILER={STAGE1_INSTALL_DIR}/bin/clang"
                f" -DCMAKE_CXX_COMPILER={STAGE1_INSTALL_DIR}/bin/clang++"
                f" -DCOMPILER_CACHE=none"
                f" -DENABLE_TESTS=0"
                f" -DENABLE_UTILS=0"
                f" -DCMAKE_TOOLCHAIN_FILE={toolchain_file}"
                f" {REPO_PATH}"
                f" -B {CH_PROFILE_BUILD_DIR}"
            )
            results.append(
                Result.from_commands_run(
                    name="Profile collection CMake",
                    command=cmake_cmd,
                )
            )
            res = results[-1].is_ok()

        if res:
            results.append(
                Result.from_commands_run(
                    name="Profile collection build (ClickHouse)",
                    command=f"ninja -C {CH_PROFILE_BUILD_DIR} clickhouse",
                )
            )
            res = results[-1].is_ok()

        if res:
            # Merge profraw files into a single profdata
            results.append(
                Result.from_commands_run(
                    name="Merge PGO profiles",
                    command=(
                        f"{STAGE1_INSTALL_DIR}/bin/llvm-profdata merge"
                        f" -output={PROFDATA_PATH}"
                        f" {STAGE1_BUILD_DIR}/profiles/"
                    ),
                )
            )
            res = results[-1].is_ok()

        # Clean up to free disk space (~80 GB)
        print("Cleaning Stage 1 build and CH profile build to free disk space")
        clean_dirs(STAGE1_BUILD_DIR, CH_PROFILE_BUILD_DIR, STAGE1_INSTALL_DIR)

    # Stage 3: Build PGO-optimized clang with BOLT-compatible flags
    if res and JobStages.STAGE2_BUILD in stages:
        clean_dirs(STAGE2_BUILD_DIR, STAGE2_INSTALL_DIR)
        os.makedirs(STAGE2_BUILD_DIR, exist_ok=True)

        cmake_cmd = (
            f"cmake -G Ninja"
            f' -DLLVM_ENABLE_PROJECTS="clang;lld;bolt"'
            f' -DLLVM_ENABLE_RUNTIMES="compiler-rt"'
            f" -DLLVM_TARGETS_TO_BUILD=Native"
            f" -DCMAKE_BUILD_TYPE=Release"
            f" -DLLVM_PROFDATA_FILE={PROFDATA_PATH}"
            f" -DCMAKE_C_COMPILER=clang-21"
            f" -DCMAKE_CXX_COMPILER=clang++-21"
            f" -DLLVM_ENABLE_LLD=ON"
            f" -DLLVM_ENABLE_LTO=Thin"
            f' -DCMAKE_EXE_LINKER_FLAGS="-Wl,--emit-relocs,-znow"'
            f' -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--emit-relocs,-znow"'
            f" -DLLVM_ENABLE_TERMINFO=OFF"
            f" -DLLVM_ENABLE_ZLIB=OFF"
            f" -DLLVM_ENABLE_ZSTD=OFF"
            f" -DCMAKE_INSTALL_PREFIX={STAGE2_INSTALL_DIR}"
            f" -S {LLVM_SOURCE_DIR}/llvm"
            f" -B {STAGE2_BUILD_DIR}"
        )
        results.append(
            Result.from_commands_run(
                name="Stage 2 CMake (PGO-optimized clang)",
                command=cmake_cmd,
            )
        )
        res = results[-1].is_ok()

        if res:
            results.append(
                Result.from_commands_run(
                    name="Stage 2 Build and Install",
                    command=(
                        f"ninja -C {STAGE2_BUILD_DIR}"
                        f" install-clang install-clang-resource-headers"
                        f" install-lld install-llvm-ar install-llvm-ranlib"
                        f" install-llvm-objcopy install-llvm-strip"
                        f" install-llvm-profdata install-llvm-bolt install-merge-fdata"
                    ),
                )
            )
            res = results[-1].is_ok()

        # Clean stage2 build dir, keep install
        print("Cleaning Stage 2 build directory to free disk space")
        clean_dirs(STAGE2_BUILD_DIR)

    # Stage 4: BOLT optimization
    if res and JobStages.BOLT_OPTIMIZATION in stages:
        clang_binary = f"{STAGE2_INSTALL_DIR}/bin/clang-21"

        # Find the actual clang binary (it may be clang-21, clang-20, etc.)
        if not os.path.exists(clang_binary):
            # Try to find the versioned clang binary
            candidates = sorted(
                glob.glob(f"{STAGE2_INSTALL_DIR}/bin/clang-[0-9]*"),
                reverse=True,
            )
            if candidates:
                clang_binary = candidates[0]
            else:
                clang_binary = f"{STAGE2_INSTALL_DIR}/bin/clang"

        print(f"BOLT target binary: {clang_binary}")
        llvm_bolt = f"{STAGE2_INSTALL_DIR}/bin/llvm-bolt"
        merge_fdata = f"{STAGE2_INSTALL_DIR}/bin/merge-fdata"
        clang_instrumented = f"{clang_binary}.inst"
        clang_bolted = f"{clang_binary}.bolt"

        clean_dirs(BOLT_PROFILES_DIR, CH_BOLT_BUILD_DIR)
        os.makedirs(BOLT_PROFILES_DIR, exist_ok=True)

        # Instrument clang with BOLT
        results.append(
            Result.from_commands_run(
                name="BOLT instrument clang",
                command=(
                    f"{llvm_bolt} {clang_binary}"
                    f" -o {clang_instrumented}"
                    f" -instrument"
                    f" --instrumentation-file-append-pid"
                    f" --instrumentation-file={BOLT_PROFILES_DIR}/prof"
                ),
            )
        )
        res = results[-1].is_ok()

        if res:
            # Build ClickHouse with BOLT-instrumented clang for profile collection
            cmake_cmd = (
                f"cmake"
                f" -DCMAKE_BUILD_TYPE=None"
                f" -DENABLE_THINLTO=0"
                f" -DCMAKE_C_COMPILER={clang_instrumented}"
                f" -DCMAKE_CXX_COMPILER={clang_instrumented}"
                f" -DCOMPILER_CACHE=none"
                f" -DENABLE_TESTS=0"
                f" -DENABLE_UTILS=0"
                f" -DCMAKE_TOOLCHAIN_FILE={toolchain_file}"
                f" {REPO_PATH}"
                f" -B {CH_BOLT_BUILD_DIR}"
            )
            results.append(
                Result.from_commands_run(
                    name="BOLT profile collection CMake",
                    command=cmake_cmd,
                )
            )
            res = results[-1].is_ok()

        if res:
            results.append(
                Result.from_commands_run(
                    name="BOLT profile collection build (ClickHouse)",
                    command=f"ninja -C {CH_BOLT_BUILD_DIR} clickhouse",
                )
            )
            res = results[-1].is_ok()

        if res:
            # Merge BOLT profiles
            bolt_profile_files = glob.glob(f"{BOLT_PROFILES_DIR}/prof.*")
            print(f"Found {len(bolt_profile_files)} BOLT profile files")
            results.append(
                Result.from_commands_run(
                    name="Merge BOLT profiles",
                    command=(
                        f"{merge_fdata} -o {BOLT_FDATA_PATH} {BOLT_PROFILES_DIR}/prof.*"
                    ),
                )
            )
            res = results[-1].is_ok()

        if res:
            # Apply BOLT optimization
            results.append(
                Result.from_commands_run(
                    name="BOLT optimize clang",
                    command=(
                        f"{llvm_bolt} {clang_binary}"
                        f" -o {clang_bolted}"
                        f" -data={BOLT_FDATA_PATH}"
                        f" -reorder-blocks=ext-tsp"
                        f" -reorder-functions=cdsort"
                        f" -split-functions"
                        f" -split-all-cold"
                        f" -split-eh"
                        f" -dyno-stats"
                        f" -use-gnu-stack"
                    ),
                )
            )
            res = results[-1].is_ok()

        if res:
            # Replace original binary with BOLTed version
            results.append(
                Result.from_commands_run(
                    name="Install BOLTed clang",
                    command=f"mv {clang_bolted} {clang_binary}",
                )
            )
            res = results[-1].is_ok()

        # Clean up BOLT intermediates
        print("Cleaning BOLT intermediate files")
        clean_dirs(CH_BOLT_BUILD_DIR, BOLT_PROFILES_DIR)
        for f in [clang_instrumented, BOLT_FDATA_PATH]:
            if os.path.exists(f):
                os.remove(f)

    # Stage 5: Package
    if res and JobStages.PACKAGE in stages:
        output_path = f"{OUTPUT_DIR}/clang-pgo-bolt.tar.zst"
        results.append(
            Result.from_commands_run(
                name="Package toolchain",
                command=(
                    f"tar -C {STAGE2_INSTALL_DIR} -cf - ."
                    f" | zstd -T0 -19 -o {output_path}"
                ),
            )
        )
        res = results[-1].is_ok()

        if res:
            file_size_mb = os.path.getsize(output_path) / (1024 * 1024)
            print(f"Toolchain archive size: {file_size_mb:.1f} MB")

    Result.create_from(results=results).complete_job()


if __name__ == "__main__":
    main()
