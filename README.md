# rlc-ios-native-deps

Public build sandbox for RaceLineCalc iOS native numerical dependencies.

This repository intentionally contains only generic native dependency build infrastructure:

- LLVM/Flang host compiler proof scripts
- iOS Flang runtime build scripts
- iOS Flang runtime audit/link-smoke scripts
- GitHub Actions workflows for public standard runners

It must not contain private RaceLineCalc app code, Rust solver crates, product fixtures, Expo/EAS credentials, Apple/Google credentials, certificates, provisioning profiles, or secrets.

## Current gate

Run the manual workflow:

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
