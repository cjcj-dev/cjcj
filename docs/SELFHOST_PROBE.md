# Selfhost Bootstrap Probe

Date: 2026-06-21

## Target

Probe target: `packages/lex/src`.

The dependency packages used for the selfhost probe were the reference-built artifacts from the initial workspace build:

- `target/release/basic@cangjie_compiler/basic@cangjie_compiler.cjo`
- `target/release/basic@cangjie_compiler/libbasic@cangjie_compiler.a`
- `target/release/utils@cangjie_compiler/utils@cangjie_compiler.cjo`
- `target/release/utils@cangjie_compiler/libutils@cangjie_compiler.a`

Reference compile command:

```sh
/root/.cjv/bin/cjc -p packages/lex/src --output-type=staticlib -o "$WORK/liblex.a" \
  --import-path target/release/basic@cangjie_compiler \
  --import-path target/release/utils@cangjie_compiler \
  -L target/release/basic@cangjie_compiler \
  -L target/release/utils@cangjie_compiler \
  -lbasic@cangjie_compiler -lutils@cangjie_compiler --set-runtime-rpath -V
```

Reference result: success, producing `lex@cangjie_compiler.cjo` and `liblex.a`.

Selfhost compile command:

```sh
./target/release/bin/cangjie_compiler::cjc -p packages/lex/src --output-type=staticlib -o "$WORK/liblex.a" \
  --import-path target/release/basic@cangjie_compiler \
  --import-path target/release/utils@cangjie_compiler \
  -L target/release/basic@cangjie_compiler \
  -L target/release/utils@cangjie_compiler \
  -lbasic@cangjie_compiler -lutils@cangjie_compiler --set-runtime-rpath -V
```

## Progress

Before this probe, the selfhost parser rejected four lex files at line 1 because valid syntax inside the file set caused parser diagnostics:

- `AnnotationToken.cj`
- `LexerImpl.cj`
- `Token.cj`
- `Tokens.cj`

Two parser gaps were ported from C++:

- `extend T <: Interface { ... }` parsing in `ParseExtendDecl`, mirroring `/root/cj_build/cangjie_compiler/src/Parse/ParseDecl.cpp`, `ParserImpl::ParseExtendDecl`.
- index access range parsing such as `s[1..]`, `s[..3]`, and `s[1..3]`, mirroring `/root/cj_build/cangjie_compiler/src/Parse/ParseExpr.cpp`, `ParserImpl::ParseExpr(ExprKind::INDEX_EXPR)`, `ParserImpl::ParseIndexAccess`, and `ParserImpl::ParseSubscriptExpr`.

After the parser ports, `packages/lex/src` no longer stops at a parser error. The current package-level frontier is later in semantic analysis/runtime memory use while checking the full lex package:

```text
generics type arguments do not match the constraint of 'Class-TreeSet<Generics-T>'
packages/lex/src/LexerImpl.cj:215:47
note: 'Class-Token' is not a subtype of 'Interface-Comparable<Class-Token>'
...
Out of memory
```

## Remaining Frontier

### Sema gap: same-package inherited conformance

Files hit:

- `packages/lex/src/LexerImpl.cj`

Symptom:

```text
TreeSet<Token> = TreeSet<Token>()
'Class-Token' is not a subtype of 'Interface-Comparable<Class-Token>'
```

`Token.cj` declares `public struct Token <: Comparable<Token> & Hashable & Equatable<Token>`, so the selfhost sema is failing to make the conformance available when checking `LexerImpl.cj` as a separate source against the same package context. This is a sema/imported-declaration frontier, not a parser frontier.

C++ reference area for the next cut:

- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckDecl.cpp`
- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckClassLike.cpp`
- `/root/cj_build/cangjie_compiler/src/Sema/InheritanceChecker/*`
- `/root/cj_build/cangjie_compiler/src/Sema/GenericInstantiation/*`

Suggested next cut: isolate same-package multi-file conformance lookup using a small `struct S <: Comparable<S>` file plus a second file using `TreeSet<S>`, then mirror the C++ conformance collection and constraint checking path.

### CHIR gap: invalid type in match expression lowering

Files hit:

- `packages/lex/src/AnnotationToken.cj`
- `packages/lex/src/Tokens.cj`

Symptom:

```text
IllegalArgumentException: unsupported AST type kind for CHIRType.TranslateType: Invalid
at packages/chir/src/CHIRType.cj:325
via Translator::Visit(MatchExpr)
```

These files use enum-to-index functions implemented as `match` expressions. The parser accepts them; CHIR lowering sees an invalid semantic type.

C++ reference area for the next cut:

- `/root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/TranslateExpr.cpp`, match expression translation
- `/root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/TranslateType.cpp`, type translation
- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckMatchExpr.cpp`

Suggested next cut: compare the selfhost AST type assigned to a minimal enum `match` against C++ and fix the sema-to-CHIR type handoff before changing CHIR lowering.

### .cjo write / mangling gap: invalid type in member signatures

Files hit:

- `packages/lex/src/Lexer.cj`
- `packages/lex/src/Token.cj`

Symptom:

```text
IllegalArgumentException: Unexpected semantic type to be mangled: Invalid
at packages/mangle/src/BaseMangler.cj:111
via FrontendCjoFlatBufferWriter::SaveDeclBody
```

The failure happens while writing `.cjo` metadata and mangling member function signatures that still contain `Invalid` semantic types.

C++ reference area for the next cut:

- `/root/cj_build/cangjie_compiler/src/Mangle/BaseMangler.cpp`
- `/root/cj_build/cangjie_compiler/src/Modules/` and frontend serialization code that writes `.cjo`
- upstream sema files listed above, because the mangle failure is likely a downstream symptom of invalid type assignment.

Suggested next cut: instrument only enough to identify the declaration being serialized, then fix the earlier C++-faithful sema path that should assign its type.

### CHIR/codegen gap exposed by parser progress: index range access

The parser now accepts index range access syntax faithfully. A minimal `String` slice using `s[1..3]` compiles with the selfhost but crashes at runtime in `Range<...>::<init>`, while the reference compiler runs it successfully. This is not a parser issue after this cut.

C++ reference area for the next cut:

- `/root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/TranslateExpr.cpp`, subscript/range expression translation
- `/root/cj_build/cangjie_compiler/src/CodeGen/`, range construction and subscript lowering

Suggested next cut: compare selfhost CHIR for `s[1..3]` to reference CHIR and port the missing range/subscript lowering faithfully.

## Verification

Commands run after the fixes:

```sh
cjpm build
bash scripts/difftest.sh
bash scripts/septest/run.sh
bash scripts/septest/run_write.sh
bash scripts/septest/run_diag.sh
bash scripts/septest/run_write_types.sh
bash scripts/septest/run_write_struct.sh
```

Results:

- `cjpm build`: success.
- `difftest`: `TOTAL=72  PASS=72  MISMATCH=0  FAIL=0`; no non-PASS lines.
- All five septests printed final PASS lines.

## Probe 2 (`packages/option/src`)

Probe target: `packages/option/src` (`Option.cj`, `OptionAction.cj`, `OptionEnums.cj`, `OptionSupport.cj`,
`OptionTable.cj`, `Options.cj`, `Triple.cj`).

Dependency packages were built by the reference toolchain through the workspace `cjpm build`:

- `target/release/basic@cangjie_compiler/basic@cangjie_compiler.cjo`
- `target/release/basic@cangjie_compiler/libbasic@cangjie_compiler.a`
- `target/release/utils@cangjie_compiler/utils@cangjie_compiler.cjo`
- `target/release/utils@cangjie_compiler/libutils@cangjie_compiler.a`

Reference compile command:

```sh
/root/.cjv/bin/cjc -p packages/option/src --output-type=staticlib -o "$WORK/liboption.a" \
  --import-path target/release/basic@cangjie_compiler \
  --import-path target/release/utils@cangjie_compiler \
  -L target/release/basic@cangjie_compiler \
  -L target/release/utils@cangjie_compiler \
  -lbasic@cangjie_compiler -lutils@cangjie_compiler --set-runtime-rpath -V
```

Reference result: success, producing `option@cangjie_compiler.cjo` and `liboption.a`.

Selfhost compile command:

```sh
./target/release/bin/cangjie_compiler::cjc -p packages/option/src --output-type=staticlib -o "$WORK/liboption.a" \
  --import-path target/release/basic@cangjie_compiler \
  --import-path target/release/utils@cangjie_compiler \
  -L target/release/basic@cangjie_compiler \
  -L target/release/utils@cangjie_compiler \
  -lbasic@cangjie_compiler -lutils@cangjie_compiler --set-runtime-rpath -V
```

### Progress

Before this probe, the selfhost parser rejected `packages/option/src/OptionSupport.cj` at line 1. The actual
syntax gap was a top-level `foreign { ... }` block following `@When`.

Two faithful ports were landed:

- Top-level foreign block parsing, including cloning the block modifiers/annotations for each inner declaration,
  mirroring `/root/cj_build/cangjie_compiler/src/Parse/Parser.cpp`, `ParserImpl::ParseTopLevelDecl` and
  `ParserImpl::ParseForeignDecls`.
- Foreign-block declaration begin-position handling, mirroring
  `/root/cj_build/cangjie_compiler/src/Parse/ParseModifiers.cpp`, `ParserImpl::SetDeclBeginPos`.

After that parser port, `packages/option/src` no longer stops at the parser. The full package now runs until the
selfhost process exhausts its runtime heap:

```text
An exception has occurred:
    Out of memory
```

This cut did not attempt an OOM fix.

A small CHIR blocker was also exposed and fixed while probing individual option files:

- Parenthesized expression lowering, mirroring
  `/root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/TranslateASTNode/TranslateParenExpr.cpp`,
  `Translator::Visit(const AST::ParenExpr&)`.

`packages/option/src/OptionEnums.cj` now compiles by itself with the selfhost cjc against reference-built `basic`
and `utils`.

### Remaining Frontier

#### Sema/runtime memory frontier: full option package OOM

Files hit:

- package compile of `packages/option/src`
- single-file probes of larger files such as `Option.cj`, `OptionAction.cj`, `OptionTable.cj`, and `Triple.cj`
  did not produce a smaller categorized failure before timeout/OOM.

Symptom:

```text
Out of memory
```

C++ reference area for the next cut:

- `/root/cj_build/cangjie_compiler/src/Sema/`
- `/root/cj_build/cangjie_compiler/src/Frontend/CompilerInstance.cpp`, stage ordering around sema and generic
  instantiation

Suggested next cut: isolate the smallest option declaration or type-checking pattern that drives heap growth before
changing sema. Do not conflate this with the separately owned recursive generic-bound OOM unless the minimized case
proves it is the same path.

#### CHIR/.cjo frontier: invalid semantic type in option support/signatures

Files hit:

- `packages/option/src/OptionSupport.cj`
- `packages/option/src/Options.cj`

Symptoms:

```text
IllegalArgumentException: unsupported AST type kind for CHIRType.TranslateType: Invalid
via FaithfulAST2CHIR::CreateImportedFuncSignatureAndSetGlobalCache
```

and:

```text
IllegalArgumentException: unsupported AST type kind for CHIRType.TranslateType: Invalid
via FaithfulAST2CHIR::CreateFuncSignatureAndSetGlobalCache
```

C++ reference area for the next cut:

- `/root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/TranslateType.cpp`
- `/root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/AST2CHIR.cpp`
- upstream sema signature typing under `/root/cj_build/cangjie_compiler/src/Sema/`

Suggested next cut: identify the exact function signature still containing `Invalid` after sema, then fix the
upstream C++-faithful type assignment path rather than tolerating `Invalid` in CHIR.

#### Fallback observations

`packages/conditional_compilation/src` was tried as the first fallback with reference-built `ast`, `basic`, `option`,
and `utils`; it did not produce a categorized failure before a 180s selfhost timeout.

`packages/meta_transformation/src` was tried as the second fallback with reference-built `basic` and `chir`; it
stopped in sema diagnostic construction:

```text
IllegalStateException: diagnostic argument count does not match format placeholders
via TypeCheckReferenceFilterTargetsForFuncReference
```

C++ reference area for that fallback:

- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckReference.cpp`
- `/root/cj_build/cangjie_compiler/src/Basic/DiagnosticEngine.cpp`

Suggested next cut: minimize the lambda/member-reference in `meta_transformation` that triggers the diagnostic
argument mismatch, then port the C++ diagnostic call and format contract together.

### Verification

Commands run after the fixes:

```sh
cjpm build
bash scripts/difftest.sh
bash scripts/septest/run.sh
bash scripts/septest/run_write.sh
bash scripts/septest/run_diag.sh
bash scripts/septest/run_write_types.sh
bash scripts/septest/run_write_struct.sh
```

Additional corpus cases added:

- `scripts/difftest_corpus/91_paren_expr.cj`
- `scripts/difftest_corpus/92_foreign_block.cj`

Results:

- `cjpm build`: success.
- `difftest`: `TOTAL=76  PASS=76  MISMATCH=0  FAIL=0`; no non-PASS lines.
- All five septests printed final PASS lines.

## Probe 3 (lex re-probe)

Date: 2026-06-21

Probe target: `packages/lex/src`, re-run after the recursive generic-bound memoization fix on main
(`c09f869`). Dependency artifacts were the reference-built `basic` and `utils` `.cjo`/static libraries under
`target/release`, matching the septest-style setup used in earlier probes.

Reference command:

```sh
/root/.cjv/bin/cjc -p packages/lex/src --output-type=staticlib -o "$WORK/ref-liblex.a" \
  --import-path target/release/basic@cangjie_compiler \
  --import-path target/release/utils@cangjie_compiler \
  -L target/release/basic@cangjie_compiler \
  -L target/release/utils@cangjie_compiler \
  -lbasic@cangjie_compiler -lutils@cangjie_compiler --set-runtime-rpath -V
```

Reference result: success, producing `lex@cangjie_compiler.cjo` (204104 bytes) and `ref-liblex.a`
(976806 bytes).

Selfhost command:

```sh
./target/release/bin/cangjie_compiler::cjc -p packages/lex/src --output-type=staticlib -o "$WORK/self-liblex.a" \
  --import-path target/release/basic@cangjie_compiler \
  --import-path target/release/utils@cangjie_compiler \
  -L target/release/basic@cangjie_compiler \
  -L target/release/utils@cangjie_compiler \
  -lbasic@cangjie_compiler -lutils@cangjie_compiler --set-runtime-rpath -V
```

### Result

The old recursive-bound frontier is confirmed gone as a diagnostic path: the selfhost re-probe no longer reports
`TreeSet<Token>` / `Token <: Comparable<Token>` constraint failure. The full package still does not compile. With
the default Cangjie heap (256 MiB), the selfhost compiler runs into runtime OOM during the package compile with no
frontend diagnostic:

```text
Out of memory
```

With `cjHeapSize=1GB`, the full package made no diagnostic progress before a 180s timeout. An earlier long 1GB
run reached roughly 653 MiB RSS and was killed after more than 8 minutes with no stdout/stderr diagnostics. This
looks like a separate lex package memory/progress frontier, not the already-fixed recursive generic-bound
`declInstantiationStatus` path.

Suggested next cut: isolate full-package lex progress by file/stage, starting with `LexerImpl.cj` and package
symbol-table/sema traversal. Compare against:

- `/root/cj_build/cangjie_compiler/src/Sema/Collector.cpp`
- `/root/cj_build/cangjie_compiler/src/Sema/TypeChecker.cpp`
- `/root/cj_build/cangjie_compiler/src/Sema/InheritanceChecker/*`
- `/root/cj_build/cangjie_compiler/src/Sema/GenericInstantiation/*`

### Faithful fixes landed

#### Sema collector: string literal core refs

Selfhost shallow typing of string literals could still produce `Invalid` when no contextual `String` type had
already been supplied. The collector now seeds string literal `RefType`s for `String` and `JString` with
`COMPILER_ADD` and `IN_CORE`, and collects a symbol for the synthetic ref.

C++ reference:

- `/root/cj_build/cangjie_compiler/src/Sema/Collector.cpp`, `Collector::CollectLitConstExpr`
- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckExpr/LitConstExpr.cpp`,
  `TypeCheckerImpl::SynLitConstStringExpr`

Regression case:

- `scripts/difftest_corpus/94_string_literal_equality.cj`

#### Sema check path: array literals and string literal targets

The check path now handles `LitConstExpr` and `ArrayLit` before the generic synthesize-then-check fallback. For
array literals this mirrors the C++ behavior of checking each child against the target element type, which lets
context such as `Array<String>` reach the string literal children.

C++ reference:

- `/root/cj_build/cangjie_compiler/src/Sema/TypeChecker.cpp`, check dispatch for `LIT_CONST_EXPR` and `ARRAY_LIT`
- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckBuiltinExpr.cpp`,
  `TypeCheckerImpl::ChkArrayLit`

Existing array/string corpus cases and the new string-literal equality case cover this path under reference/selfhost
difftest.

#### After-type-check desugar: array literal constructor binding

The after-type-check desugar walker now binds array literal constructor metadata, matching the C++ after-type-check
pass. The helper is exported so that desugar and type-check synthesis share the same constructor binding logic.

C++ reference:

- `/root/cj_build/cangjie_compiler/src/Sema/Desugar/AfterTypeCheck.cpp`, `ASTKind::ARRAY_LIT`
- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckUtil.cpp`, `AddArrayLitConstructor`

### Remaining frontiers

#### Package-level memory/progress frontier

Full `packages/lex/src` still OOMs at the default heap and times out under a 1GB heap without diagnostics. This is
the highest-impact remaining blocker because it prevents reaching a deterministic package-level CHIR/codegen
frontier.

Suggested next cut: add low-overhead phase/file progress isolation locally, then port the exact C++ sema/generic
path responsible for the growth. Do not add broad caches or lex-specific guards.

#### Single-file CHIR frontier: global initializer invalid type

After the sema fixes, `packages/lex/src/Tokens.cj` no longer dies in `Translator::Visit(LitConstExpr)` for the
`IsExperimental` string equality expression. Its next standalone failure is CHIR global-initializer classification:

```text
IllegalArgumentException: unsupported AST type kind for CHIRType.TranslateType: Invalid
via FaithfulAST2CHIR::NeedInitGlobalVarByInitFunc
```

This is exposed by global `Array<String>` initializers such as `TOKEN_KIND_VALUES` and `TOKENS`.

C++ reference area:

- `/root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/GlobalVarInitializer.cpp`,
  `NeedInitGlobalVarByInitFunc`
- `/root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/TranslateType.cpp`
- upstream array/string sema under `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckBuiltinExpr.cpp`

Suggested next cut: minimize a global `Array<String>` initializer that reaches this `Invalid`, then fix the upstream
type assignment or the exact C++ global-initializer predicate. A direct CHIR workaround is not acceptable.

#### Other single-file frontiers observed

- `packages/lex/src/AnnotationToken.cj`: codegen/LLVM verifier failure,
  `Explicit load/store type does not match pointee type of pointer operand`.
- `packages/lex/src/Lexer.cj` and `packages/lex/src/Token.cj`: `.cjo` write/mangle failure,
  `Unexpected semantic type to be mangled: Invalid`.
- `packages/lex/src/LexerDiag.cj`: frontend reports `unsupported construct ... not yet implemented in real pipeline`
  when compiled alone.
- `packages/lex/src/LexerImpl.cj`: standalone 1GB compile timed out after 90s with no diagnostics.

These were treated as secondary to the package-level memory/progress blocker and the tractable sema fixes above.

### Verification

Commands run after the fixes, as separate commands:

```sh
cjpm build
bash scripts/difftest.sh
bash scripts/septest/run.sh
bash scripts/septest/run_write.sh
bash scripts/septest/run_diag.sh
bash scripts/septest/run_write_types.sh
bash scripts/septest/run_write_struct.sh
```

Results:

- `cjpm build`: success.
- `difftest`: `TOTAL=78  PASS=78  MISMATCH=0  FAIL=0`; no non-PASS lines.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 8 (lex re-probe after faithful scope resolution)

Probe target: `packages/lex/src`, re-run on branch `lexprobe2` after Probe 7's faithful scope-gate name generation
and full sequential scope-assignment walk.

The selfhost compiler was rebuilt cleanly, then `packages/lex/src` was compiled with the selfhost compiler against the
reference-built `basic` and `utils` artifacts in `target/release/*@cangjie_compiler`, using the same package command as
Probe 4/6:

```sh
env cjHeapSize=1GB ./target/release/bin/cangjie_compiler::cjc -p packages/lex/src \
  --output-type=staticlib -o "$WORK/self-liblex.a" \
  --import-path target/release/basic@cangjie_compiler \
  --import-path target/release/utils@cangjie_compiler \
  -L target/release/basic@cangjie_compiler \
  -L target/release/utils@cangjie_compiler \
  -lbasic@cangjie_compiler -lutils@cangjie_compiler --set-runtime-rpath -V
```

### Re-probe result

The old pre-scope-fix note at `packages/lex/src/Lexer.cj:145` (`if (inDollar)`) did reproduce after the default-param
frontier was cleared, but it was no longer the first blocker. The fresh baseline first reached CHIR after about 5:45,
max RSS about 1.21 GiB, and failed while caching the synthetic default-parameter helper for
`packages/lex/src/LexerImpl.cj:89`:

```text
IllegalArgumentException: unsupported AST type kind for CHIRType.TranslateType: Initial
  at packages/chir/src/CHIRType.cj:325
  at packages/chir/src/FaithfulAST2CHIR.cj:1292 CreateFuncSignatureAndSetGlobalCache
```

The bad function was the constructor default-param helper for `LexerConfig.fileID`:

```text
func fileID.0()UInt64 { return 0u64 }
```

After the fixes below, lex advanced past both that default-param helper and the prior `Lexer.cj:145` CHIR invalid-type
frontier. The current real package frontier is now a sema overload-resolution diagnostic:

```text
packages/lex/src/LexerImpl.cj:1722:21: ambiguous use of 'lexDiagnose'
```

The current 1GB run reaches that diagnostic in 0:32.43 elapsed, max RSS 1,215,508 KiB. No
`lex@cangjie_compiler.cjo` or `self-liblex.a` is produced in Probe 8.

### Faithful fixes

- Default-param/property pre-pass: `AddDefaultParamFunctions` now also fills property getter/setter return/parameter
  types and prepares/synthesizes each generated default-param helper signature/body. This mirrors C++
  `/root/cj_build/cangjie_compiler/src/Sema/TypeChecker.cpp:2323-2338`
  (`CheckDefaultParamFuncsEntry`), `:283-325` (`AddUnitType`, `AddReturnTypeForPropMemDecl`), and `:2512-2550`
  (`GetSingleParamFunc` walks generated default-param functions). The helper-body synthesis matches
  `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckDecl.cpp:721-740`.
- Compiler-added return checking: `CheckBlock` now checks the inner expression of a compiler-added `return` when the
  parent block is not compiler-added, matching
  `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckExpr/Block.cpp:71-75`.
- Suffixed integer literal values: selfhost `IntLiteral` now accepts the validated numeric prefix before a type suffix
  during value parsing, matching C++ `GetBaseAndPureStringValue` plus `std::stoull/stoll` parsing in
  `/root/cj_build/cangjie_compiler/src/AST/IntLiteral.cpp:133-205` and
  `/root/cj_build/cangjie_compiler/src/Utils/StdUtils/StdUtils.cpp:47-59`. This keeps `0u64` typed and range-checked
  as `UInt64` instead of being invalidated during later shallow synthesis.
- Loop-control target resolution: selfhost sema now ports `ScopeManager::GetRefLoopSymbol` and uses it from
  `SynLoopControlExpr(ctx, jump)`, matching
  `/root/cj_build/cangjie_compiler/src/Sema/ScopeManager.cpp:29-77` and
  `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckExpr/JumpExpr.cpp:23-34`. This clears the `Lexer.cj:145`
  `continue`/`if` invalid-type CHIR frontier.

### Remaining blocker

Category: sema overload resolution, not parser, not OOM, and not CHIR fallback.

`packages/lex/src/LexerImpl.cj:1722` calls:

```cj
lexDiagnose(diag, DiagKindRefactor.lex_expected_identifier, GetPos(pCurrent), ConvertCurrentChar())
```

The overload set in `packages/lex/src/LexerDiag.cj` has both `(Position, String)` and `(Range, String)` variants. The
reference compiler resolves this call; selfhost currently reports it ambiguous. The next cut should focus on faithful
`TypeCheckCall` overload filtering/specificity, especially argument type compatibility and candidate comparison around
`/root/cj_build/cangjie_compiler/src/Sema/TypeCheckCall.cpp:667-721` and `:774-857`, instead of changing lex source or
adding a CHIR fallback.

### Verification

Commands run after the fixes, as separate commands:

```sh
rm -rf target && cjpm build
bash scripts/difftest.sh
bash scripts/septest/run.sh
bash scripts/septest/run_write.sh
bash scripts/septest/run_diag.sh
bash scripts/septest/run_write_types.sh
bash scripts/septest/run_write_struct.sh
```

Results:

- `cjpm build`: success.
- `difftest`: `TOTAL=85  PASS=85  MISMATCH=0  FAIL=0`; no standalone tail verification was needed.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 7 (scope-name same-name resolution root cause)

### Diagnosis

The three same-name repros were not a lookup-ranking problem. The true divergence was earlier: selfhost symbol
collection did not drive C++ scope-gate name generation before indexing symbols. The old selfhost
`packages/sema/src/Collector.cj` walked the AST and indexed whatever `node.scopeName` already contained, defaulting
empty scope names to `a`. Its `ScopeManager.cj` was only a stack stub, so it never reproduced C++'s monotonic
per-package gate sequence.

C++ ground truth:

- `/root/cj_build/cangjie_compiler/src/Sema/ScopeManager.cpp:79-104` increments scope depth and appends the next
  encoded layer name.
- `/root/cj_build/cangjie_compiler/src/Sema/ScopeManager.cpp:106-118` computes the next child gate name with `_`.
- `/root/cj_build/cangjie_compiler/src/Sema/ScopeManager.cpp:182-208` finalizes scopes and resets nested indexes only
  after leaving a top-level declaration.
- `/root/cj_build/cangjie_compiler/src/Sema/Collector.cpp:297-341`,
  `/root/cj_build/cangjie_compiler/src/Sema/Collector.cpp:440-467`, and
  `/root/cj_build/cangjie_compiler/src/Sema/Collector.cpp:947-971` call `CalcScopeGateName`,
  `InitializeScope`, and `FinalizeScope` around function bodies, `if`, `for`, and block scopes.
- `/root/cj_build/cangjie_compiler/src/Sema/PreCheck.cpp:285-286` strips gate tails with
  `GetScopeNameWithoutTail` before keying `declMap`.
- `/root/cj_build/cangjie_compiler/src/Sema/LookUpImpl.cpp:636-677` then walks parent scope names and picks the
  nearest visible declaration.

Temporary diagnostics after porting the C++ path showed the necessary scope separation:

```text
block repro: param x@a0a0a, inner let x@a0a0a0a, inner ref x@a0a0a0a -> var_decl@a0a0a0a
loop repro:  param n@a0a0a, loop pattern n@a0a0a0a, loop ref n@a0a0a0a -> var_decl@a0a0a0a
sibling repro: top helper@a_a, f param helper@a0b0a, f ref helper@a0b0a -> func_param@a0b0a,
                main ref helper@a0c0a -> func_decl@a_a
```

Before the fix these programs produced `5`, `400`, and a CHIR invalid-type failure. After the scope names are unique,
ordinary `Lookup` resolves the nearest declaration and the scope-unaware `CurrentFunctionParam` override is not
needed.

A follow-up scope-walk check found a remaining collector divergence: the selfhost assignment pass had a plain
subtree walker for non-special expression nodes, and that walker only copied the current scope without re-entering
the C++-shaped dispatch. Scope-bearing descendants hidden under calls, binary expressions, function arguments,
array literals, returns, and similar plain parents could therefore miss their gate and collapse into the enclosing
scope.

### Faithful Fix

- Ported the C++ `ScopeManager` counter/gate algorithm into selfhost
  `packages/sema/src/ScopeManager.cj`, including `InitializeScope`, `CalcScopeGateName`, `FinalizeScope`, base-52
  layer names, and top-level nested-index reset.
- Added a C++-shaped scope assignment pass in `packages/sema/src/Collector.cj` before indexing symbols. It assigns
  gates and child scopes for package/file declarations, nominal bodies, function bodies, generic parameters, local
  blocks, `if`, loops, match cases, try/catch/handler blocks, lambdas, enum body scopes, and extend body scopes.
- Completed the collector walk so plain expression parents re-dispatch any scope-bearing descendant through the same
  `AssignNode` path and skip that owned subtree. This mirrors C++ `Collector::BuildSymbolTable`'s single uniform
  recursion: embedded lambdas, blocks, `if`, loops, match cases, try, synchronized, and nested declarations now get
  their scopes regardless of the enclosing expression.
- Updated selfhost decl-map insertion to key declarations by `GetScopeNameWithoutTail(scopeName)`, matching C++
  `PreCheck.cpp:285-286`.
- Removed the selfhost-only `CurrentFunctionParam` override from `ResolveRefExpr`; resolution now comes from scoped
  `Lookup`.

### Confirmation

The three repros now match reference cjc:

```text
96_shadow_param_block  -> 99
97_shadow_param_loop   -> 103
98_sibling_param_name  -> 108
```

The embedded-scope repros also match reference after the walk-completeness fix:

```text
99_shadow_lambda_in_call -> 99
100_shadow_if_in_binary  -> 8
```

The lex-style `match (kind)` cross-function parameter case also resolves correctly in a focused check and prints `7`.

Verification commands run separately:

```sh
rm -rf target && cjpm build
bash scripts/difftest.sh
bash scripts/septest/run.sh
bash scripts/septest/run_write.sh
bash scripts/septest/run_diag.sh
bash scripts/septest/run_write_types.sh
bash scripts/septest/run_write_struct.sh
```

Results:

- `cjpm build`: success.
- `difftest`: `TOTAL=84  PASS=84  MISMATCH=0  FAIL=0`.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 4 (lex OOM diagnosis)

Date: 2026-06-21

Probe target: `packages/lex/src`, re-run on branch `lexoom` after Probe 3 and after the recursive generic-bound
memoization fix already present on main. The selfhost compiler was rebuilt with:

```sh
rm -rf target && cjpm build
```

The lex package was then compiled with the selfhost compiler and the same reference-built `basic`/`utils` dependency
artifacts used by Probe 3:

```sh
env cjHeapSize=1GB ./target/release/bin/cangjie_compiler::cjc -p packages/lex/src \
  --output-type=staticlib -o "$WORK/self-liblex.a" \
  --import-path target/release/basic@cangjie_compiler \
  --import-path target/release/utils@cangjie_compiler \
  -L target/release/basic@cangjie_compiler \
  -L target/release/utils@cangjie_compiler \
  -lbasic@cangjie_compiler -lutils@cangjie_compiler --set-runtime-rpath -V
```

### Diagnosis

This is a performance/memory-growth frontier from repeated linear uniqueness scans, not the earlier recursive-bound
nontermination. Initial TypeManager cache counters did not fire before the first timeout; sampled stacks showed the
compiler was still earlier in package symbol indexing:

- Before fixes: `Collector::BuildSymbolTable -> InvertedIndex::Index -> Trie::Insert -> addUniqueSymbol`, with trie
  node ID lists growing and every inserted character scanning the existing `ArrayList<Symbol>`.
- After the trie fix: the hot stack moved to `TypeManager::GenerateGenericMapping -> putTyVarScopeDepth`, matching
  the selfhost `ArrayList` visited/depth scans where C++ uses `std::unordered_set<Ptr<Ty>>` for the traversal and
  `std::map<Ptr<const GenericsTy>, size_t>` for depth tracking.
- After the generic-mapping fix: the next hot stack moved to
  `TypeCheckExpr::addImportedDeclToCurrentPackage -> addDeclUniqueToPackage`, another repeated imported-declaration
  uniqueness scan.
- After hashing `srcImportedNonGenericDecls`, lex reached a real diagnostic path in about 72s instead of a silent
  timeout, but the note range for imported candidates was zero and raised `IllegalStateException: begin of range is
  zero` at `TypeCheckReference.cj:236`.
- After porting the candidate-note range logic, lex now emits deterministic `ambiguous use of ''` diagnostics in
  `packages/lex/src/LexerImpl.cj:536` and following match cases. A 1GB heap run reached those diagnostics but then
  still exhausted the heap while resolving/formatting the remaining errors: 178.36s elapsed, 1,221,608 KiB max RSS,
  `148 errors generated, 8 errors printed`, then runtime OOM. A 2GB exploratory run also reached the same diagnostics
  and ended before timeout with `148 errors generated, 8 errors printed`, 178.26s elapsed, 2,321,444 KiB max RSS.

The observed behavior is therefore bounded forward progress through successive O(n) scan fronts, not a single
unbounded recursive loop. The package still does not produce `lex@cangjie_compiler.cjo`; the current material
milestone is that the no-diagnostic sema stall is replaced by emitted semantic diagnostics and the next front is a
separate ambiguous string-literal/match-case resolution issue plus remaining diagnostic memory pressure.

### Faithful fixes landed

- `TrieNode.ids` is now a keyed map instead of a linear `ArrayList`, mirroring C++ `TrieNode::ids` as `std::set<Symbol*>`.
  The key is derived from the same identity/equality fields that `SameSymbol` used, and insert/delete preserve the
  existing trie lifecycle.
- `TypeManager.GenerateGenericMapping` now uses a `HashSet` visited set, and `tyVarScopeDepth` is a keyed map instead
  of an `ArrayList`, matching the C++ hashed/set map structure while preserving the previous selfhost `SameTy` lookup
  semantics through a stable type key.
- `Package.srcImportedNonGenericDecls` now has a side key set for O(1) imported-declaration uniqueness in the hot
  package accumulation path. Mutations from inline-function checking clear the key set so the list and key cache keep
  the same lifecycle.
- Resolved imported declaration lookup now uses the same imported-aware key for its local uniqueness pass, avoiding
  another hot linear scan while preserving the prior equality semantics.
- Ambiguous imported candidate notes now use a selfhost port of C++ `MakeRangeForDeclIdentifier` behavior and fall
  back to an unlocated note only when no source range exists, avoiding the zero-range diagnostic exception without
  suppressing the diagnostic.

### Current lex result

`packages/lex/src` is materially further but not fully compiling. The selfhost compiler reaches real diagnostics in
`LexerImpl.cj` instead of hanging silently in sema. No `lex@cangjie_compiler.cjo` is produced in this probe. The next
frontier is to compare C++ and selfhost resolution for string literal match cases such as:

```text
packages/lex/src/LexerImpl.cj:536:18: ambiguous use of ''
case "." => TokenKind.DOT
```

and then reduce the remaining diagnostic/memory pressure once the spurious ambiguity is fixed.

### Verification

Commands run after the fixes, as separate commands:

```sh
rm -rf target && cjpm build
bash scripts/difftest.sh
bash scripts/septest/run.sh
bash scripts/septest/run_write.sh
bash scripts/septest/run_diag.sh
bash scripts/septest/run_write_types.sh
bash scripts/septest/run_write_struct.sh
```

Results:

- `cjpm build`: success.
- `difftest`: `TOTAL=78  PASS=78  MISMATCH=0  FAIL=0`; programs `88`-`92` also passed in the harness, so no
  standalone tail verification was needed.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 5 (lex string-literal match ambiguity)

Date: 2026-06-21

Probe target: `packages/lex/src`, re-run on branch `lexambig` after Probe 4.

### Diagnosis

The blocking `sema_ambiguous_use` diagnostics were not caused by the string-literal `String`/`JString` ref seeding
itself. A temporary local diagnostic probe at `ResolveRefExpr` showed that each failing `case "." => ...` path was
resolving the synthetic receiver used for constant-pattern `==`, not a user identifier:

```text
PROBE5 empty-ref targets=120 pos=(4, 536, 18) scope=''
```

The collected candidates for that empty reference were 120 imported `ExtendDecl` nodes whose identifiers are empty:

- `cangjie_compiler::basic`: 13 imported `ExtendDecl` candidates
- `std.collection`: 18 imported `ExtendDecl` candidates
- `std.core`: 89 imported `ExtendDecl` candidates

Because the dummy receiver is a fresh `RefExpr` with no identifier, normal reference synthesis looked it up as an
ordinary empty-name reference. That reached
`TypeCheckReferenceCheckAmbiguousImportedNonFuncs`, which correctly reported ambiguity for the candidate set it was
given, rendering the empty name as `ambiguous use of ''`.

The C++ reference avoids this lookup. In constant-pattern overload checking it creates a dummy `RefExpr`, assigns the
selector type directly, and explicitly marks the node so synthesis is skipped:

- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckPattern.cpp:284-293`:
  `ChkOpOverloadForConstPattern` creates the call, sets `callBase->baseExpr->SetTy(&target)`, then calls
  `ctx.SkipSynForCorrectTy(*callBase->baseExpr)`.
- `/root/cj_build/cangjie_compiler/src/Sema/TypeChecker.cpp:740-748`:
  `IsChecked` treats nodes with a `typeCheckCache` `lastKey` and a correct non-quest type as already checked.
- `/root/cj_build/cangjie_compiler/src/Sema/TypeChecker.cpp:751-768` and `771-777`:
  `PerformBasicChecksForSynthesize` returns the existing type before normal synthesis, and `Synthesize` records the
  cache key before continuing for non-skipped nodes.

### Faithful fix

The selfhost constant-pattern overload path now mirrors C++ by calling `ctx.SkipSynForCorrectTy(baseExpr)` immediately
after assigning the dummy receiver's target type. The selfhost `Synthesize`/`SynthesizeNameReference` path now honors
that skip marker for correct, non-quest expression types, matching the C++ early return described above. This is not a
name filter and does not suppress `sema_ambiguous_use`; real ambiguous references still flow through the existing
diagnostic path.

Regression coverage was added as:

- `scripts/difftest_corpus/95_string_match_case.cj`

The case is a string selector with several string-literal `case "..." =>` arms. It compiles and runs with both the
reference compiler and selfhost compiler, outputting `1`.

### Current lex result

The string-literal match ambiguity is cleared. Re-running `packages/lex/src` with the selfhost compiler no longer
prints any `ambiguous use of ''` diagnostics for `LexerImpl.cj:536` or the following string-literal match cases.

`packages/lex/src` still does not fully compile to `lex@cangjie_compiler.cjo`. The next observed package-level
frontier is memory pressure with no frontend diagnostic:

```text
Out of memory
```

At the default heap the package still OOMs. With `cjHeapSize=1GB`, the package also OOMs after the ambiguity is gone.
With `cjHeapSize=2GB`, an exploratory run timed out after 260s with no diagnostics and no `lex@cangjie_compiler.cjo`.
This is a distinct package memory/progress blocker after the string-literal match case fix.

### Verification

Commands run after the fixes, as separate commands:

```sh
rm -rf target && cjpm build
bash scripts/difftest.sh
bash scripts/septest/run.sh
bash scripts/septest/run_write.sh
bash scripts/septest/run_diag.sh
bash scripts/septest/run_write_types.sh
bash scripts/septest/run_write_struct.sh
```

Results:

- `cjpm build`: success.
- `difftest`: `TOTAL=79  PASS=79  MISMATCH=0  FAIL=0`; no standalone tail verification was needed.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 6 (lex heap pressure)

Date: 2026-06-21

Probe target: `packages/lex/src`, re-run on branch `lexheap` after Probe 5.

### Diagnosis

The Probe 5 string-literal constant-pattern ambiguity is gone. The next failure was no longer a frontend diagnostic:
`packages/lex/src` exhausted the runtime heap during the real selfhost sema pass.

Baseline reproduction with the Probe 5 compiler:

- `env cjHeapSize=1GB ... -p packages/lex/src`: runtime OOM after 1:20.40, max RSS 1,221,412 KiB, no frontend
  diagnostic.
- A sampled stack near failure was in runtime allocation/GC (`MObject::NewObject`, `RegionSpace::Allocate`,
  `WCollector::TraceHeap`), not in diagnostic rendering.

Temporary stage probes narrowed the failure to the real sema `TypeCheckForPackages` path, after precheck/extend-map
setup and while checking the source package. Temporary counters on the already-known TypeManager linear query caches
(`subtypeCache`, `declInstantiationStatus`, `checkedTyExtendRelation`, `tyUsedExtends`) did not identify a new
dominant bounded scan before the OOM. The evidence instead pointed at TypeManager type allocation: the selfhost
constructors returned fresh `Ty` objects for every `Get*Ty` request, while C++ interns all constructed types in a
hash table. That creates unbounded-equivalent heap pressure on a package that repeatedly instantiates tuple/function/
nominal types.

The C++ reference structure is:

- `/root/cj_build/cangjie_compiler/include/cangjie/Sema/TypeManager.h:426-427`: `allocatedTys` is an
  `std::unordered_set<TypePointer, TypeHash>`.
- `/root/cj_build/cangjie_compiler/src/Sema/TypeManager.cpp:81-91`: `GetTypeTy` probes `allocatedTys`, inserts only
  on miss, and returns the existing canonical type on hit.
- `/root/cj_build/cangjie_compiler/src/Sema/TypeManager.cpp:1702-1708`: `Clear` owns the lifecycle of the allocated
  type table.

The run after interning showed the former heap frontier was cleared: with `cjHeapSize=1GB`, the compile did not OOM in
sema. At 6:17 elapsed it was past sema and sampled in mangling
(`MangleAstAdapter::FindDecl -> ConvertDecl -> ConvertTy`) at about 504 MiB RSS. It then reached CHIR translation and
failed with a distinct blocker:

```text
IllegalArgumentException: unsupported AST type kind for CHIRType.TranslateType: Invalid
  at packages/chir/src/CHIRType.cj:325
  at packages/chir/src/Translator.cj:1417 (Visit(MatchExpr))
```

The same next blocker reproduced with `cjHeapSize=2GB` after 7:00.27 elapsed, max RSS 1,204,376 KiB. No
`lex@cangjie_compiler.cjo` or final static library is produced yet.

### Faithful fix

- Selfhost `TypeManager` now interns all constructed types through a keyed `allocatedTyCache`, mirroring C++
  `allocatedTys` as a hash set. The key uses the established `typeManagerTyKey` (`ty.Hash():ty.String()`), the same
  stable equality used by selfhost `SameTy`, so hits and misses preserve the previous type-equality semantics while
  avoiding duplicate heap objects.
- The allocated type cache is cleared in `TypeManager.Clear`, matching the C++ `allocatedTys.clear()` lifecycle.
- `ClearMapCache` now clears `subtypeCache`, matching `/root/cj_build/cangjie_compiler/include/cangjie/Sema/TypeManager.h:228-240`.
- `ReleasePostSemaCaches` now also releases sema query caches and `boxedNonGenericDecls`, matching
  `/root/cj_build/cangjie_compiler/src/Sema/TypeManager.cpp:52-61`.
- `TypeCheckTopLevelDecl` now wraps synthesis in a `TyVarScope`, matching
  `/root/cj_build/cangjie_compiler/src/Sema/TypeChecker.cpp:2120-2124`.

### Current lex result

`packages/lex/src` is materially further. The no-diagnostic sema/runtime OOM frontier is cleared: both 1GB and 2GB
runs reach CHIR translation. The next distinct blocker is an invalid AST type on a match expression during
`FaithfulAST2CHIR`, not another silent heap exhaustion. Lex still does not fully compile to
`lex@cangjie_compiler.cjo`.

### Verification

Commands run after the fixes, as separate commands:

```sh
rm -rf target && cjpm build
bash scripts/difftest.sh
bash scripts/septest/run.sh
bash scripts/septest/run_write.sh
bash scripts/septest/run_diag.sh
bash scripts/septest/run_write_types.sh
bash scripts/septest/run_write_struct.sh
```

Results:

- `cjpm build`: success.
- `difftest`: `TOTAL=79  PASS=79  MISMATCH=0  FAIL=0`; no standalone tail verification was needed.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 9 (lex overload ambiguity)

### Symptom

After Probe 8, selfhost `cjc` reached `packages/lex/src/LexerImpl.cj:1722:21` and emitted a false
overload-resolution diagnostic:

```text
ambiguous use of 'lexDiagnose'
```

The exact call is:

```cj
lexDiagnose(diag, DiagKindRefactor.lex_expected_identifier, GetPos(pCurrent), ConvertCurrentChar())
```

The relevant overloads in `packages/lex/src/LexerDiag.cj` are:

- `lexDiagnose(DiagnosticEngine, DiagKindRefactor, Position)`
- `lexDiagnose(DiagnosticEngine, DiagKindRefactor, Position, String)`
- `lexDiagnose(DiagnosticEngine, DiagKindRefactor, Range)`
- `lexDiagnose(DiagnosticEngine, DiagKindRefactor, Range, String)`

The C++ compiler picks the four-argument `Position, String` overload.

### Diagnosis

The spurious ambiguity was not caused by the final call candidate ranking. Instrumenting selfhost
`TypeCheckCall.cj` showed the call matcher accepted only the `Position, String` overload and rejected
the `Range, String` overload as incompatible.

The false diagnostic was emitted earlier while the name reference was still treated as an isolated
function reference. Selfhost `Collector` did not mark call bases as non-alone, so
`TypeCheckReferenceFilterTargetsForFuncReference` saw the base `lexDiagnose` as `isAlone == true`
with four overload targets and reported an ambiguous standalone function reference before normal
call overload resolution could own the decision.

The C++ reference does this in the collector:

- `/root/cj_build/cangjie_compiler/src/Sema/Collector.cpp:841-856`: for `CALL_EXPR`, call
  `TypeCheckUtil::SetIsNotAlone(*ce->baseFunc)` before visiting the base and arguments.
- `/root/cj_build/cangjie_compiler/src/Sema/Collector.cpp:860-866`: for member access, mark the base
  expression non-alone.
- `/root/cj_build/cangjie_compiler/src/Sema/Collector.cpp:872-880`: for subscript, mark the base
  expression non-alone.
- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckUtil.cpp:62-66`: `SetIsNotAlone` clears
  `NameReferenceExpr::isAlone`.
- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckReference.cpp:371-378`: a `RefExpr` enters the
  standalone function-reference filter only when it has no target type and `re.isAlone` is true.
- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckCall.cpp:1216-1249` and
  `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckCall.cpp:2147-2195`: actual call matching and
  best-result selection then handle the overload set.

The divergence was therefore a missing faithful collector pre-pass, not a missing `lexDiagnose`-specific
overload tie-break.

### Faithful fix

Selfhost `packages/sema/src/Collector.cj` now mirrors the C++ collector and marks call bases, member
access bases, and subscript bases as not-alone before symbol collection continues. This prevents a call
base overload set from being diagnosed as an ambiguous standalone function reference and lets the normal
call overload resolver choose the unique best candidate.

The optional finalizer parity branch was also added in the default-parameter pre-pass:
`packages/sema/src/TypeCheckExpr/TypeChecker.cj` now calls `AddUnitType` for finalizers, matching
`/root/cj_build/cangjie_compiler/src/Sema/TypeChecker.cpp:2327-2332`.

A regression corpus program was added at
`scripts/difftest_corpus/102_overload_call_base_not_func_ref.cj`. It reproduces the same overload shape:
two overloads differing by `Position` versus `Range`, a call through a non-empty overloaded name, and a
unique `Position, String` best match.

### Current lex result

`packages/lex/src` now compiles past the former `lexDiagnose` ambiguity. The next frontier is later in
CHIR translation:

```text
IllegalArgumentException: unsupported AST type kind for CHIRType.TranslateType: Invalid
  at packages/chir/src/CHIRType.cj:325
  at packages/chir/src/Translator.cj:791 Visit(IfExpr)
```

No `lex@cangjie_compiler.cjo` or final lex static library is produced yet.

### Verification

Commands run after the fix, as separate commands:

```sh
rm -rf target && cjpm build
bash scripts/difftest.sh
bash scripts/septest/run.sh
bash scripts/septest/run_write.sh
bash scripts/septest/run_diag.sh
bash scripts/septest/run_write_types.sh
bash scripts/septest/run_write_struct.sh
```

Results:

- `cjpm build`: success.
- `packages/lex/src` selfhost compile: passed the `lexDiagnose` ambiguity and reached the new CHIR
  invalid-type frontier above.
- `difftest`: `TOTAL=86  PASS=86  MISMATCH=0  FAIL=0`.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 10 (lex if-expr invalid type)

### Reproduction

Rebuilt the selfhost compiler cleanly and re-ran the Probe 4/6/8/9 lex package command:

```sh
env cjHeapSize=1GB ./target/release/bin/cangjie_compiler::cjc -p packages/lex/src \
  --output-type=staticlib -o "$WORK/self-liblex.a" \
  --import-path target/release/basic@cangjie_compiler \
  --import-path target/release/utils@cangjie_compiler \
  -L target/release/basic@cangjie_compiler \
  -L target/release/utils@cangjie_compiler \
  -lbasic@cangjie_compiler -lutils@cangjie_compiler --set-runtime-rpath -V
```

Temporary CHIR tracing identified the invalid `IfExpr` as `packages/lex/src/LexerImpl.cj:525` in
`CollectToken`:

```cj
if (!enableCollect) {
    return
}
```

At CHIR entry the if had type `Invalid`, its then block had type `Invalid`, and it had no else branch.

### Diagnosis

The invalid if was not a branch join failure. It was caused by selfhost parsing a bare `return` with
`ReturnExpr.expr == None`, so sema typed the return as `Invalid`; that made the then block invalid,
and the no-else if statement reached CHIR with an invalid AST type.

The C++ parser does not leave bare returns without an expression:

- `/root/cj_build/cangjie_compiler/src/Parse/ParseAtom.cpp:916-950`: `ParseReturnExpr` creates a
  compiler-added `LitConstExpr` of kind `UNIT`, value `"()"`, when `return` is followed by a
  terminator/declaration/double-arrow.
- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckExpr/ReturnExpr.cpp:18-57`: `SynReturnExpr`
  assumes a return expression exists, checks it against the function return type, then sets the
  `ReturnExpr` type to `Nothing`.
- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckExpr/IfExpr.cpp:40-45`: no-else if expressions
  are typed as `Unit` when their condition and branches are well typed.

The selfhost parser diverged at `packages/parse/src/ParseExpr.cj:1175-1184`: it only parsed an
expression when one was present and otherwise left `ret.expr` unset. That made the later sema code
hit an AST shape the C++ sema never sees for a bare return.

### Faithful fix

`packages/parse/src/ParseExpr.cj` now mirrors the C++ parser behavior for `return` followed by a
terminator/declaration/double-arrow: it synthesizes a compiler-added `()` `LitConstExpr`, assigns it
zero-width source positions at the return token end, preserves semicolon metadata, and always sets
`ReturnExpr.end` from the expression.

Added regression corpus program `scripts/difftest_corpus/103_if_bare_return_unit.cj`, which reproduces
the lex shape: an unused no-else if whose then branch is a bare `return` in a `Unit` function. The
selfhost and reference compilers both compile and run it with identical output:

```text
collected
```

### Current lex result

The original invalid-if CHIR frontier is cleared. Re-running the full selfhost lex package compile now
gets further and stops at the next invalid-type frontier:

```text
IllegalArgumentException: unsupported AST type kind for CHIRType.TranslateType: Invalid
  at packages/chir/src/CHIRType.cj:325
  at packages/chir/src/Translator.cj:496 Visit(VarDecl)
```

Temporary tracing identified that next node as local variable `mapped` in
`packages/lex/src/LexerImpl.cj:535`, inside `LookupKeyword`:

```cj
let mapped = match (literal) { ... }
```

No `lex@cangjie_compiler.cjo` or final lex static library is produced yet.

### Verification

Commands run after the fix, as separate commands:

```sh
rm -rf target && cjpm build
bash scripts/difftest.sh
bash scripts/septest/run.sh
bash scripts/septest/run_write.sh
bash scripts/septest/run_diag.sh
bash scripts/septest/run_write_types.sh
bash scripts/septest/run_write_struct.sh
```

Results:

- `cjpm build`: success.
- `packages/lex/src` selfhost compile: passed the invalid `IfExpr` at `LexerImpl.cj:525` and reached
  the new `VarDecl` invalid-type frontier at `Translator.cj:496`.
- `difftest`: `TOTAL=87  PASS=87  MISMATCH=0  FAIL=0`.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.
