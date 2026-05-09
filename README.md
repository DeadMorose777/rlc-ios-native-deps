# rlc-ios-native-deps

Public build sandbox for RaceLineCalc iOS native numerical dependencies.

This repository intentionally contains only generic native dependency build infrastructure:

- LLVM/Flang host compiler proof scripts
- iOS Flang runtime build scripts
- iOS Flang runtime audit/link-smoke scripts
- GitHub Actions workflows for public standard runners

It must not contain private RaceLineCalc app code, Rust solver crates, product fixtures, Expo/EAS credentials, Apple/Google credentials, certificates, provisioning profiles, or secrets.

## Current gates

Run the manual Flang runtime workflow:

```bash
gh workflow run ios-flang-rt-proof.yml --ref master
```

Acceptance:

- host `flang` builds from the pinned LLVM tag;
- iOS static Flang runtime libs are produced for `ios-arm64` and `ios-arm64-simulator`;
- archive object members have iOS/iOS Simulator platform markers;
- tiny Fortran `bind(C)` link smoke succeeds;
- smoke binary has no Homebrew, macOS LLVM, standalone Fortran, or gfortran dylib dependency.

The workflow is intentionally manual and heavy. Do not run it on every push.

Run the full IPOPT/MUMPS native dependency workflow:

```bash
gh workflow run ios-ipopt-proof.yml --ref master
```

Current full native-deps acceptance:

- host Flang comes from the pinned LLVM tag and includes intrinsic modules;
- iOS Flang runtime static libs are produced for `ios-arm64` and
  `ios-arm64-simulator`;
- MUMPS sequential static libs are produced with real `libseq`;
- IPOPT static libs are produced with MUMPS backend;
- final link smoke force-loads IPOPT, MUMPS, libseq, PORD, and Flang runtime;
- smoke binary has no unresolved `_mpi_`, `__Q.*EXdtX`, or `__FortranA`
  symbols;
- smoke binary has no Homebrew, macOS LLVM, standalone Fortran, or gfortran
  dylib dependency.

## Release artifact

The release payload is produced by `ios-ipopt-proof.yml` as:

```text
dist/
  rlc-ios-native-deps-<version>.tar.gz
  rlc-ios-native-deps-<version>.tar.gz.sha256
```

The archive contains:

```text
native-deps/
  ios-arm64/
    lib/*.a
    include/
    logs/
    manifest.json
  ios-arm64-simulator/
    lib/*.a
    include/
    logs/
    manifest.json
  manifest.json
  LICENSES/
```

Only generic native dependencies are published here. The private Rust solver
static library and `RlcSolverMobile.xcframework` are built in the private
RaceLineCalc repository.
