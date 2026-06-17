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
still uses local diagnostic text for many driver errors instead of reporting the
exact Basic `DiagnosticEngine` IDs and ranges everywhere. The dependency shape
now permits selected `option -> basic` de-isolation, but a full diagnostic pass
still needs careful call-site-by-call-site migration to preserve behavior.

This pass de-isolates the remaining local print/usage formatting wrappers that
could be safely moved inside the current dependency graph: Option now delegates
`Errorln`, `Warningln`, `Infoln`, `Println`, help indentation, and command
description formatting to the real `cangjie_compiler::basic` print helpers
while preserving Option's public wrapper surface for existing call sites. The
driver-owned `TempFileInfo` duplicate is still local because importing
`driver` from `option` would invert the current package layering
(`driver -> frontend_tool -> option`) and pull tool/frontend dependencies into
the core option package.

The same pass restores more C++ post-action behavior and state. `GlobalOptions`
now carries the C++ `symbolsNeedLocalizedPerPkg` map, reports C++-matching
errors or warnings for output-dir conflicts, `lib-macro_` outputs,
compile-macro/output-type conflicts, coverage normalization, scan-dependency
mode errors, sanitizer/LTO/compile-as-exe/LTO-visibility/PGO conflicts, CJMP
common-part mismatches, invalid compile-target placement, object-only linking
without `--experimental`, unsupported APC targets, and OHOS `--static-std`
normalization. Target triple parsing, custom optimization, sancov level,
error-count, and jobs/APC value parsing now emit the reference diagnostics
instead of failing silently.

This continuation removes Option's local compatibility copy of the diagnostic
warning-group enum and index table. `-Woff`/`-Won` now use the real
`cangjie_compiler::basic` `WarnGroup`/`WarnGroupIndex` definitions that back the
shared `WarningOptionMgr`, and unknown warning-group values now fail option
processing like the C++ `WARN_GROUP_MAP` path instead of being accepted
silently.

This pass removes another compatibility enum: Option's local
`OverflowStrategy` copy is replaced by the real `cangjie_compiler::utils`
definition, re-exported through Option to preserve the public include-like
surface. `GlobalOptions.overflowStrategy` now has the same type consumed by sema,
so the old sema-side conversion bridge is gone. `--int-overflow-mode` also uses
the shared Utils parser/validator, accepting the full C++ set (`no`, `checked`,
`wrapping`, `throwing`, `saturating`) and preserving the C++ abort-on-invalid
serialization path.

This continuation tightens action-level parity with `OptionAction.cpp`.
`--common-part-cjo` and `--common-part-chir` now match the C++ action contract:
invalid paths are not added, but the option action itself still succeeds so
diagnostics/post-action processing can proceed. `--render-chir=na` is also
accepted by the action path, matching the C++ `DUMP_CHIR_MODE_MAP` entry even
though the visible predefined value list remains unchanged.

This pass de-isolates conditional-compilation cfg diagnostics onto the real
`cangjie_compiler::basic.DiagnosticEngine` surface for the paths owned by
`OptionAction.cpp`. `--cfg` now reports the C++ diagnostic IDs for malformed
key/value input, invalid identifiers, builtin-key reuse, duplicate keys,
non-directory cfg paths, ignored cfg paths, missing explicit `cfg.toml` files,
and malformed cfg file lines. `SetupConditionalCompilationCfgFromFile` also
reports `driver_cfg_file_read_failed` with the failure reason returned by the
shared `utils.FileUtil.ReadFileContent` path, matching the C++ `%s` diagnostic
arguments instead of using a placeholder reason. The directory-valued
`--output-dir` and `--save-temps` actions now also emit the shared
`no_such_directory` diagnostic before failing, as `OptionAction.cpp` does.

This continuation moves the core path-validation helpers onto the C++ diagnostic
surface. `CheckDirectoryPath` and `CheckInputFilePath` now emit the same driver
warning IDs and ignored-argument suffix used by `RaiseArgumentUnusedMessage`,
while `ValidateDirectoryPath` and `ValidateInputFilePath` report shared Basic
errors for missing paths, permission denial, directory/file mismatches, invalid
paths, and path-length overflow. Input classification now passes the C++
source-vs-binary not-found diagnostic kind for `.cj`/`.cj.d`/`.bc` versus
`.o`/`.a`/`.obj`/`.cjo` inputs. `--jobs` and `--apc` numeric validation also
matches the C++ check order: non-digit values are diagnosed before the maximum
length check.

This pass continues that diagnostic migration through the post-action checks
that already have shared Basic driver diagnostics in the reference. LTO now
reports `driver_target_lto_unsupported` with the C++ OS spelling, compile-as-exe
and LTO-visible-package validation use their dedicated driver errors/warnings,
PGO conflicts and profile-file validation use the C++ diagnostic IDs, CJMP
common-part extension/count checks use the same unexpected-extension warning
and count error, output-mode/source/object checks use
`driver_invalid_compile_target`, `driver_source_file_empty`, and
`driver_require_experimental`, and OHOS `--static-std` normalization emits
`driver_static_std_for_ohos`.

This continuation tightens the remaining post-action ordering and diagnostic
parity around input/output validation. `ReprocessInputs` now reports the C++
`no_such_file_or_directory` and `input_file_overwritten_by_generated_output`
diagnostics instead of failing silently. The scan-dependency post-checks now use
`driver_not_accept_cjo_inputs_when`,
`driver_require_package_directory_scan_dependency`, and
`driver_source_cjo_empty`. Reflection normalization is sequenced after
output/input reprocessing as in `Option.cpp`, output-mode validation runs before
obfuscation and CJMP checks, and CJMP common-part validation now accumulates all
bad extension warnings plus the count mismatch before failing, matching the C++
`ok &= VerifyFileExtension(...)` behavior.

This pass deepens the remaining high-traffic parser/action paths. Cache path
hashing now delegates to the real sibling `utils.SipHash` implementation instead
of an Option-local fallback hash. `OptionTable.ParseOptionArg` now rejects
frontend-only options when the table is in driver mode after the normal
backend/group lookup, matching the explicit C++ guard. Deprecated options and
`--module-name` now use the shared Basic diagnostic IDs
`driver_deprecated_option` and `driver_useless_option`.

Input classification has been split into C++-shaped handlers for
object/archive inputs, `.cj`, `.cj.d`, `.bc`, `.cjo`, directories, and unknown
files. These handlers now preserve the C++ source-vs-binary diagnostic kinds,
rewrite object/bitcode ordered inputs to absolute paths, verify resolved file
extensions before adding inputs, report duplicate `.cjo` scan-dependency inputs
with `driver_require_one_package_directory_scan_dependency`, warn on unused
non-directory files with `driver_warning_argument_unused`, and report missing
package paths with `driver_require_package_directory`. Output path length
warnings/errors now also use the C++ diagnostic IDs rather than local warning
text.

Action-level parity also moved forward: plugin suffix failures now report the
reference error text, common-part CJO/CHIR actions use
`ValidateInputFilePath` like `OptionAction.cpp`, cfg keys are NFC-normalized
through the real utils Unicode normalization path, `--error-count-limit`
diagnostics name the actual option spelling, and explicit/default APC enablement
updates the shared utils semaphore count with the C++ two-slot allowance.

Remaining gaps: the generated-looking `Options.cj`/`OptionEnums.cj` are still
hand-maintained Cangjie mirrors rather than being produced directly from
`Options.inc`; a few diagnostics still use local `Errorln` strings where the C++
reference also uses formatted print helpers rather than `DiagnosticEngine`; host
triple defaults are static to the current build assumptions instead of being
fully preprocessor-derived for every target; and external users still see local
`Maybe*` compatibility wrappers until the wider port standardizes on native
`Option<T>` across package boundaries.

This continuation removes another small layer of Option-local compatibility
logic. The `SplitLines` shim now delegates to the real Basic package splitter.
Custom optimization levels, sancov levels, `--error-count-limit`, and
`GlobalOptions.ParseIntOptionValue` now use the shared utils `TryParseInt`
semantics that the C++ reference uses for those paths, so non-digit input,
overflow, and signed/negative spellings fail at the same decision point. Android
API suffix validation now uses the shared `Stoi` helper instead, matching the
reference `std::stoi` numeric-prefix behavior for targets such as
`android24foo` while preserving the existing support/illegal diagnostics.

Remaining gaps: `Options.cj`/`OptionEnums.cj` remain hand-maintained mirrors
rather than generated artifacts from `Options.inc`; local `Maybe*` wrappers and
some compatibility helper entry points remain to keep current sibling packages
building; host target defaults are still statically modeled for this port; and
obfuscation-specific option handling still lives in the driver subclass layer
rather than the base Option action surface.

This pass continues the same de-isolation and action-parity work. The
Option-level `SplitString` compatibility wrapper now delegates to the shared
utils splitter, and jobs/APC numeric parsing uses the same shared
`TryParseInt` path as the other C++ `Utils::TryParseInt`-backed options while
preserving the C++ digit-only and nine-character prechecks. The `--output`
action now emits the reference non-empty-value error, missing `--plugin` inputs
now emit the plugin-specific "existing dynamic library path" error after the
shared path warning, and `CompileTargetToSerializedString` now aborts on
`DEFAULT` instead of serializing an invented sentinel, matching the C++
internal-error behavior.

Remaining gaps: the option table/enums are still hand-maintained mirrors of
`Options.inc`; public `Maybe*` and numeric compatibility wrappers remain where
other current packages import them; several print-style diagnostics still use
local `Errorln` text rather than a formatted-print wrapper; and host target
defaults/driver obfuscation option handling remain outside the base Option
module's fully faithful surface.
