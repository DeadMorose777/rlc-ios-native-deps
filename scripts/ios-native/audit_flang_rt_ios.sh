#!/usr/bin/env bash
set -euo pipefail

: "${LLVM_TAG:=llvmorg-22.1.5}"
: "${IPHONEOS_DEPLOYMENT_TARGET:=13.0}"
: "${NATIVE_ROOT:=$PWD/.native}"
: "${AUDIT_OUT:=$PWD/.native/flang-rt-audit}"

LLVM_ROOT="$NATIVE_ROOT/llvm-$LLVM_TAG"
LLVM_HOST_PREFIX="$LLVM_ROOT/install-host"
FLANG="$LLVM_HOST_PREFIX/bin/flang"

runtime_libs_for() {
  local name="$1"
  local prefix="$LLVM_ROOT/install-flangrt-$name"

  find "$prefix" -type f \( \
    -name 'libflang_rt.runtime.a' -o \
    -name 'libflang_rt.quadmath.a' -o \
    -name 'libFortranRuntime.a' -o \
    -name 'libFortranDecimal.a' \
  \) -print | sort
}

primary_runtime_for() {
  local name="$1"
  local runtime

  runtime="$(runtime_libs_for "$name" | grep 'libflang_rt.runtime.a$' | head -n 1 || true)"
  if [[ -z "$runtime" ]]; then
    runtime="$(runtime_libs_for "$name" | grep 'libFortranRuntime.a$' | head -n 1 || true)"
  fi

  if [[ -z "$runtime" ]]; then
    echo "Missing primary Flang runtime library for $name." >&2
    runtime_libs_for "$name" >&2 || true
    exit 1
  fi

  echo "$runtime"
}

audit_archive_platform() {
  local archive="$1"
  local expected="$2"
  local tmp

  tmp="$(mktemp -d)"
  (
    cd "$tmp"
    ar -x "$archive"
    for object in *.o; do
      xcrun vtool -show-build "$object" 2>/dev/null || true
    done > vtool.txt
    if ! grep -q "$expected" vtool.txt; then
      echo "Expected platform marker '$expected' was not found in $archive." >&2
      head -n 80 vtool.txt >&2
      exit 1
    fi
  )
  rm -rf "$tmp"
}

audit_one() {
  local name="$1"
  local sdk="$2"
  local target="$3"
  local min_flag="$4"
  local expected_platform="$5"
  local out_dir="$AUDIT_OUT/$name"
  local sysroot
  local runtime
  local runtime_args=()

  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  runtime="$(primary_runtime_for "$name")"

  rm -rf "$out_dir"
  mkdir -p "$out_dir"
  runtime_libs_for "$name" > "$out_dir/runtime-libs.txt"
  file "$runtime" | tee "$out_dir/runtime-file.txt"
  audit_archive_platform "$runtime" "$expected_platform"

  while IFS= read -r lib; do
    [[ -n "$lib" ]] || continue
    runtime_args+=("-Wl,-force_load,$lib")
  done < "$out_dir/runtime-libs.txt"

  cat > "$out_dir/flang_rt_probe.f90" <<'EOF'
subroutine flang_rt_probe(out) bind(C)
  use iso_c_binding
  integer(c_int), intent(out) :: out
  character(len=8) :: s
  character(len=:), allocatable :: a
  s = adjustl("  ok")
  allocate(character(len=8) :: a)
  a = s
  out = len_trim(a)
end subroutine
EOF

  cat > "$out_dir/flang_rt_probe_user.c" <<'EOF'
extern void flang_rt_probe(int *out);
int rlc_flang_rt_probe_user(void) {
  int out = 0;
  flang_rt_probe(&out);
  return out;
}
EOF

  "$FLANG" \
    -target "$target" \
    -isysroot "$sysroot" \
    "$min_flag" \
    -fPIC \
    -c "$out_dir/flang_rt_probe.f90" \
    -o "$out_dir/flang_rt_probe.o"

  xcrun --sdk "$sdk" clang \
    -target "$target" \
    -isysroot "$sysroot" \
    "$min_flag" \
    -fPIC \
    -c "$out_dir/flang_rt_probe_user.c" \
    -o "$out_dir/flang_rt_probe_user.o"

  xcrun --sdk "$sdk" clang \
    -target "$target" \
    -isysroot "$sysroot" \
    "$min_flag" \
    -dynamiclib \
    -Wl,-undefined,error \
    "$out_dir/flang_rt_probe.o" \
    "$out_dir/flang_rt_probe_user.o" \
    "${runtime_args[@]}" \
    -lm \
    -o "$out_dir/flang_rt_probe_link_smoke.dylib"

  otool -L "$out_dir/flang_rt_probe_link_smoke.dylib" | tee "$out_dir/otool.txt"
  xcrun vtool -show-build "$out_dir/flang_rt_probe_link_smoke.dylib" | tee "$out_dir/vtool.txt" || true

  if grep -E '/opt/homebrew|libflang|Fortran|LLVM|gfortran' "$out_dir/otool.txt"; then
    echo "Unexpected non-system dynamic Fortran/LLVM dependency in $name smoke binary." >&2
    exit 1
  fi

  rm -f "$out_dir/flang_rt_probe_link_smoke.dylib"
}

rm -rf "$AUDIT_OUT"
mkdir -p "$AUDIT_OUT"

audit_one \
  "ios-arm64" \
  "iphoneos" \
  "arm64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}" \
  "-miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET}" \
  "IOS"

audit_one \
  "ios-arm64-simulator" \
  "iphonesimulator" \
  "arm64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}-simulator" \
  "-mios-simulator-version-min=${IPHONEOS_DEPLOYMENT_TARGET}" \
  "IOSSIMULATOR"
