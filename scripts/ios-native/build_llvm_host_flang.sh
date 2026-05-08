#!/usr/bin/env bash
set -euo pipefail

: "${LLVM_TAG:=llvmorg-22.1.5}"
: "${LLVM_REPO_URL:=https://github.com/llvm/llvm-project.git}"
: "${NATIVE_ROOT:=$PWD/.native}"
: "${LLVM_BUILD_JOBS:=$(sysctl -n hw.ncpu 2>/dev/null || echo 2)}"

LLVM_ROOT="$NATIVE_ROOT/llvm-$LLVM_TAG"
LLVM_SRC="$LLVM_ROOT/src"
LLVM_BUILD="$LLVM_ROOT/build-host"
LLVM_PREFIX="$LLVM_ROOT/install-host"
HOST_BUILD_TARGET="${LLVM_HOST_BUILD_TARGET:-flang}"

mkdir -p "$LLVM_ROOT"

# This step builds host tools that must execute on the macOS runner
# (tblgen, clang, flang). Keep iOS deployment env out of this CMake
# configure; target runtimes are built by build_flang_rt_ios.sh.
unset IPHONEOS_DEPLOYMENT_TARGET
HOST_MACOS_SDK="$(xcrun --sdk macosx --show-sdk-path)"

if [[ ! -d "$LLVM_SRC/.git" ]]; then
  git clone --depth 1 --branch "$LLVM_TAG" "$LLVM_REPO_URL" "$LLVM_SRC"
fi

cmake -S "$LLVM_SRC/llvm" -B "$LLVM_BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$LLVM_PREFIX" \
  -DCMAKE_OSX_SYSROOT="$HOST_MACOS_SDK" \
  -DLLVM_ENABLE_PROJECTS="mlir;flang" \
  -DLLVM_TARGETS_TO_BUILD="AArch64" \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_BUILD_TOOLS=ON \
  -DLLVM_ENABLE_ASSERTIONS=OFF \
  -DFLANG_ENABLE_FLANG_RT=OFF

cmake --build "$LLVM_BUILD" --target "$HOST_BUILD_TARGET" -j"$LLVM_BUILD_JOBS"
cmake --build "$LLVM_BUILD" --target module_files -j"$LLVM_BUILD_JOBS"
cmake --build "$LLVM_BUILD" --target install-flang-module-interfaces -j"$LLVM_BUILD_JOBS" || true

mkdir -p "$LLVM_PREFIX/bin" "$LLVM_PREFIX/include/flang"
cp "$LLVM_BUILD/bin/flang" "$LLVM_PREFIX/bin/flang"
rsync -a "$LLVM_BUILD/include/flang/" "$LLVM_PREFIX/include/flang/"

test -f "$LLVM_PREFIX/include/flang/iso_c_binding.mod"
test -f "$LLVM_PREFIX/include/flang/__fortran_builtins.mod"

"$LLVM_PREFIX/bin/flang" --version
