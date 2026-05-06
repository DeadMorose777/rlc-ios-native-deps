#!/usr/bin/env bash
set -euo pipefail

: "${LLVM_TAG:=llvmorg-22.1.5}"
: "${IPHONEOS_DEPLOYMENT_TARGET:=13.0}"
: "${NATIVE_ROOT:=$PWD/.native}"
: "${LLVM_BUILD_JOBS:=$(sysctl -n hw.ncpu 2>/dev/null || echo 2)}"

LLVM_ROOT="$NATIVE_ROOT/llvm-$LLVM_TAG"
LLVM_SRC="$LLVM_ROOT/src"
LLVM_HOST_BUILD="$LLVM_ROOT/build-host"
LLVM_HOST_PREFIX="$LLVM_ROOT/install-host"

FLANG="$LLVM_HOST_PREFIX/bin/flang"
REAL_CLANG="$(xcrun --find clang)"
REAL_CLANGXX="$(xcrun --find clang++)"

if [[ ! -x "$FLANG" ]]; then
  echo "Missing host flang at $FLANG. Run scripts/ios-native/build_llvm_host_flang.sh first." >&2
  exit 1
fi

build_one_runtime() {
  local name="$1"
  local sdk="$2"
  local target="$3"
  local min_flag="$4"

  local sysroot
  local ar
  local ranlib
  local build
  local prefix
  local wrapper_dir
  local cc_wrapper
  local cxx_wrapper
  local fc_wrapper

  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  ar="$(xcrun --sdk "$sdk" --find ar)"
  ranlib="$(xcrun --sdk "$sdk" --find ranlib)"
  build="$LLVM_ROOT/build-flangrt-$name"
  prefix="$LLVM_ROOT/install-flangrt-$name"
  wrapper_dir="$LLVM_ROOT/compiler-wrappers-$name"
  cc_wrapper="$wrapper_dir/clang-wrapper.sh"
  cxx_wrapper="$wrapper_dir/clangxx-wrapper.sh"
  fc_wrapper="$wrapper_dir/flang-wrapper.sh"

  rm -rf "$build"
  mkdir -p "$build" "$prefix" "$wrapper_dir"

  export RLC_REAL_CLANG="$REAL_CLANG"
  export RLC_REAL_CLANGXX="$REAL_CLANGXX"
  export RLC_REAL_FLANG="$FLANG"

  cat > "$cc_wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args=()
for arg in "$@"; do
  case "$arg" in
    -mmacosx-version-min=*) ;;
    *) args+=("$arg") ;;
  esac
done
exec "$RLC_REAL_CLANG" "${args[@]}"
EOF

  cat > "$cxx_wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args=()
for arg in "$@"; do
  case "$arg" in
    -mmacosx-version-min=*) ;;
    *) args+=("$arg") ;;
  esac
done
exec "$RLC_REAL_CLANGXX" "${args[@]}"
EOF

  cat > "$fc_wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args=()
skip_next=0
for arg in "$@"; do
  if [[ "$skip_next" == 1 ]]; then
    skip_next=0
    continue
  fi

  case "$arg" in
    -mmacosx-version-min=*|-miphoneos-version-min=*|-mios-simulator-version-min=*) ;;
    -arch) skip_next=1 ;;
    *) args+=("$arg") ;;
  esac
done
exec "$RLC_REAL_FLANG" "${args[@]}"
EOF

  chmod +x "$cc_wrapper" "$cxx_wrapper" "$fc_wrapper"

  cmake -S "$LLVM_SRC/runtimes" -B "$build" -G Ninja \
    -DLLVM_BINARY_DIR="$LLVM_HOST_BUILD" \
    -DLLVM_ENABLE_RUNTIMES=flang-rt \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$target" \
    -DLLVM_TARGET_TRIPLE="$target" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IPHONEOS_DEPLOYMENT_TARGET" \
    -DCMAKE_SYSROOT="$sysroot" \
    -DCMAKE_C_COMPILER="$cc_wrapper" \
    -DCMAKE_CXX_COMPILER="$cxx_wrapper" \
    -DCMAKE_Fortran_COMPILER="$fc_wrapper" \
    -DCMAKE_C_COMPILER_TARGET="$target" \
    -DCMAKE_CXX_COMPILER_TARGET="$target" \
    -DCMAKE_Fortran_COMPILER_TARGET="$target" \
    -DCMAKE_C_FLAGS="-target $target -isysroot $sysroot $min_flag -fPIC -O2" \
    -DCMAKE_CXX_FLAGS="-target $target -isysroot $sysroot $min_flag -fPIC -O2 -stdlib=libc++" \
    -DCMAKE_Fortran_FLAGS="-target $target -isysroot $sysroot -fPIC -O2" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_C_COMPILER_WORKS=YES \
    -DCMAKE_CXX_COMPILER_WORKS=YES \
    -DCMAKE_Fortran_COMPILER_WORKS=YES \
    -DCMAKE_AR="$ar" \
    -DCMAKE_RANLIB="$ranlib" \
    -DFLANG_RT_ENABLE_STATIC=ON \
    -DFLANG_RT_ENABLE_SHARED=OFF \
    -DFLANG_RT_INCLUDE_TESTS=OFF \
    -DFLANG_RUNTIME_F128_MATH_LIB=""

  cmake --build "$build" --target install -j"$LLVM_BUILD_JOBS"

  echo "Runtime libs for $name:"
  find "$prefix" -type f \( \
    -name 'libflang_rt.runtime.a' -o \
    -name 'libflang_rt.quadmath.a' -o \
    -name 'libFortranRuntime.a' -o \
    -name 'libFortranDecimal.a' \
  \) -print | sort
}

build_one_runtime \
  "ios-arm64" \
  "iphoneos" \
  "arm64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}" \
  "-miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET}"

build_one_runtime \
  "ios-arm64-simulator" \
  "iphonesimulator" \
  "arm64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}-simulator" \
  "-mios-simulator-version-min=${IPHONEOS_DEPLOYMENT_TARGET}"
