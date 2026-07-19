# runtime_patch

Vendored patch series applied to the official Cangjie runtime source when building
the `libcangjie-runtime.so` shipped in a cjcj SDK release. Built from source in CI
(`ci/build_patched_runtime.sh`) for reproducibility — the `.so` is never vendored.

## Why

The cjcj compiler is a Cangjie program shipped as `bin/cjc` (official SDK layout).
The stock Linux runtime excludes any executable named `cjc` from GC stack-root
scanning (`StackManager::InitAddressScope` → `GetEachSoAddrScope({"cjc\n"})`), a
correct optimization for the native C++ `cjc` (no managed stack roots) but fatal
for a Cangjie-built `cjc`: its own managed frames are skipped by GC and corrupt
memory on any non-trivial compile ("There are no one managed frame in the stack
block", SIGSEGV).

## Base

Pinned official gitcode commit `18cd0af893b06bfd0aedcef82aaa9eaf31cc40d2`
(v1.2.0-alpha.12 line). ABI-verified: a runtime built from this base loads the
1.2.0-alpha.20260619 SDK stdlib (std.core / std.ast / macro engine) unchanged.

## Series (apply in order)

1. `0001-mutator-writer-preference.diff` — upstream `2bbd308a`. Gives the
   mutator-management write lock writer-preference so heavy parallel compilation
   does not starve the GC writer (false-positive "mutator list lock timeout").
   Prerequisite of patch 2 (its direct parent) and hardens large builds.
2. `0002-detect-cjc-via-cjmetadata.diff` — upstream `f56e60bf`. Gates the Linux
   `cjc` name exclusion on the main executable's ELF `.cjmetadata` section, so a
   Cangjie-built `cjc` (which has that section) is scanned normally while the
   native C++ `cjc` (which does not) stays excluded. Fails safe to the existing
   exclusion on unreadable/malformed ELF.

Author of both: Zxilly <zxilly@outlook.com>.

## Platform scope

Linux only. The Darwin (`InitAddressInfoOnDarwin("/cjc", ...)`) and Windows
(`InitAddressInfoOnWindows("cjc.exe", ...)`) branches of `StackManager.cpp` carry
the same name exclusion **ungated** (TODO-only in `f56e60bf`). Renaming to `cjc`
on macOS/Windows needs the discriminator extended to the Mach-O / PE section
first; until then those platforms cannot ship a `cjc`-named cjcj. See
reports/REPORT-relmatrix.md.
