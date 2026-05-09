# Native Dependency Notices

This directory is copied into the native-deps archive produced by
`ios-ipopt-proof.yml`.

The workflow also copies license-like files from the pinned upstream sources
when they are present in the downloaded source trees:

- LLVM / Flang: `llvmorg-22.1.5`
- IPOPT: `3.14.17`
- MUMPS: `5.7.3`

The binary artifact is an engineering native-dependency payload for
RaceLineCalc iOS builds. Before App Store or commercial redistribution, verify
the copied notices against the exact upstream source archives and project legal
requirements.
