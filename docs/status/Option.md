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

Remaining fidelity gaps are not hidden behind self-host markers: this package
still uses local diagnostics instead of Basic diagnostic IDs, and some file-mode
permission checks are represented by the currently available Cangjie filesystem
predicates rather than the exact C++ `FileUtil::Access` surface.
