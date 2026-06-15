# Option Port Status

Implemented a multi-file Cangjie Option package replacing the scaffold:
`Options.cj`, `OptionTable.cj`, `Option.cj`, `OptionAction.cj`, `Triple.cj`,
`WarningOptionMgr.cj`, and support/enums files.

This pass replaces the partial hand-written option table with a Cangjie table
generated from the 167 unique `Options.inc` option definitions, fixes `ID`
equality for the complete option-id surface, expands `GlobalOptions` to cover
the C++ option state fields, and implements broad action handling for
diagnostic modes, tests/mock, macro flags, CHIR/optimization controls, sanitizer
coverage, linker/toolchain flags, PGO, stack trace, and codegen toggles.

Post-parse processing now covers input classification, ordered linker input
tracking, compile-target defaults, sanitizer/LTO/compile-as-exe conflicts,
coverage interactions, PGO checks, CJMP common-part consistency, OHOS static std
normalization, and C++-shaped serialization helpers.

The follow-up pass replaced extension-based directory guessing with
`std.fs.FileInfo` predicates and `canonicalize`, implemented `--cfg` path vs
key/value mode including `cfg.toml` loading and duplicate/built-in key checks,
made cfg serialization deterministic, added environment path ingestion,
Cangjie library path-name helpers, compilation cache path/name helpers, and
corrected sanitizer coverage and target-triple edge cases.

This continuation aligns more C++ public behavior: compilation-cache hashing now
uses the same SipHash-2-4 constants and byte processing as `Utils::SipHash`,
`--output-type=hotreload` enables hot reload and disables static std linking,
the public triple-name matcher is present, and `GlobalOptions.ParseIntOptionValue`
matches the C++ signed `int` range validation helper.

The latest pass adds C++-shaped output and input reprocessing: `--output-dir`
now normalizes output paths, output path length and `lib-macro_` prefix checks
are enforced, input files that would be overwritten by output are rejected,
package directories are de-duplicated by canonical path, package `.cj` members
are considered for overwrite checks, `.bc`/object ordered inputs are rewritten
to absolute paths, common-part CJMP extensions are validated, and the public
`TempFileInfo`/frontend-output and builtin-dependency state used across the
driver/frontend boundary is represented.

This pass restores the C++ subclass extension surface on `GlobalOptions`:
`ParseOption`, `PerformPostActions`, `IsObfuscationEnabled`, and
`ReprocessObfuseOption` now exist as overridable hooks, unhandled option IDs no
longer silently succeed, the obfuscation hook participates in post-processing
and aggressive-parallel-compile normalization, and small public helpers such as
`SetFrontendMode`, `GetLtoVisiblePkgs`, `GetStackTraceFormat`,
`GetJobs`, and `ValidateDirectoryPath` are present. Triple full-string
serialization now follows the C++ empty-environment separator behavior and
`GetArchType` is exposed.

Remaining fidelity gaps are not hidden behind self-host markers: this package
still uses local diagnostics instead of Basic diagnostic IDs, and some file-mode
permission checks are represented by the currently available Cangjie filesystem
predicates rather than the exact C++ `FileUtil::Access` surface.
