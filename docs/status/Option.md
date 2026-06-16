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

This deepening pass de-isolates Option's path and filesystem layer to the real
`cangjie_compiler::utils.FileUtil` package, matching the C++ ownership model in
`Option.cpp`/`OptionAction.cpp`. Option now delegates normalization, extension
parsing, directory/file existence checks, absolute-path resolution, environment
path splitting, recursive directory creation, directory scans, file reads,
relative cache path computation, and `FileMode` read/write/execute permission
checks through `FileUtil`. The unused local `Position`/`DEFAULT_POSITION` copy
was removed from Option rather than retained as a compatibility type; `basic`
already owns the real position model. `--trimpath` intentionally uses
`FileUtil.Normalize` while other C++ call sites use `NormalizePath`, preserving
the distinction in the reference implementation.

This pass removes the remaining local ASCII-only conditional-compilation
identifier checker and uses `utils.FileUtil.IsIdentifier`, so raw identifiers,
keywords, and Unicode identifier rules come from the same shared implementation
as the C++ `Utils::IsIdentifier` path. `cfg.toml` loading now mirrors the C++
line discipline: empty lines and full-line comments are skipped by the file
reader, while malformed/blank content passed to the key-value parser is rejected.
Target-triple parsing now accepts the reference `unknown` arch/OS spellings,
empty environment fields, `arm64` as `aarch64`, `mingw32` as GNU, and Android
API suffixes with the same non-fatal diagnostic behavior as the C++ parser.

This continuation tightens cache-affecting serialization to the C++ contract.
`SelectedCHIROptsToSerializedString` now uses the shared `utils.Out64`
formatter instead of a local bit-string encoding, sanitizer coverage
serialization preserves the reference `traceMemCmp` spelling, and
`GlobalOptions.ToSerialized` now emits the same 39 fields as `Option.cpp`
rather than appending extra self-host-only state. Pre-action parsing also now
matches the C++ two-phase flow more closely: `--help`/`--version` mark normal
parsing to be skipped after all first-pass arguments have been scanned, instead
of returning immediately and ignoring later pre-actions.

This pass restores more of the C++ `OptionTable`/`Options.inc` behavior. Help
formatting now follows the reference `Usage`/`PrintInfo` layout, including the
28-column command width, continuous-option value spelling, per-value help rows,
experimental labels, backend filtering, and the C++ rule that experimental
options themselves are still listed in normal help. Joined and continuous
options now warn on empty values except for `--lto-keep-pkg-visibility=""`.
The predefined option values in `Options.cj` now carry the C++ help text,
backend tags, and stability tags instead of a flat local stable list, and
`GlobalOptions` rejects experimental option values without `--experimental`.
Input and post-action behavior also moved closer to the reference: `.cjo`
inputs are no longer rejected solely because package mode is enabled, sanitizer
post-checks validate the target sanitizer runtime library under
`cangjieHome/runtime/lib/<target>/<sanitizer>`, and `--jobs`/`--apc` parsing now
matches the C++ digit, maximum-length, empty-value, and zero-normalization
rules.

This continuation closes that jobs gap for Linux hosts: Option now obtains
hardware concurrency through a small C FFI binding to `get_nprocs`, uses it for
the default `jobs` value, and clamps explicit `--jobs`/`--apc` values to the
host thread count like the C++ `std::thread::hardware_concurrency` flow. Normal
and pre-action option processing now both run deprecated-option checks and
duplicate occurrence tracking, and duplicate warnings include aliases in the
C++ spelling. Conditional-compilation setup also reports ignored cfg paths when
key/value cfgs are already present and warns for missing explicit `cfg.toml`
files before continuing to later paths.

Remaining fidelity gaps are not hidden behind self-host markers: this package
still uses local diagnostics instead of Basic diagnostic IDs. Importing Basic
directly is currently blocked by the existing `basic -> option` dependency for
`WarningOptionMgr`, so diagnostic de-isolation needs a dependency-shape change
outside this package before it can faithfully use `DiagnosticEngine`.
