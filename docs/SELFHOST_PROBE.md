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

### Faithfulness follow-up: make the bare-return guard condition 1:1 with C++

A review-gate pass over the first cut found the new bare-return guard condition was not yet a faithful
match for C++ `ParserImpl::ParseReturnExpr` (`src/Parse/ParseAtom.cpp:921-924`), which is
`(SeeingDecl() && !SeeingContextualKeyword()) || SeeingAny({SEMI, COMMA, RPAREN, RSQUARE, RCURL, CASE,
END, DOUBLE_ARROW}) || SeeingCombinator(combinedDoubleArrow)`. Two divergences were corrected:

1. **Missing `!SeeingContextualKeyword()` guard.** C++ excludes contextual keywords from the `SeeingDecl()`
   arm (`SeeingContextualKeyword()`, `src/Parse/ParserImpl.h:190-193`, over `CONTEXTUAL_KEYWORD_TOKEN`
   in `src/Lex/Lexer.cpp:46-50`) so that `return open` / `return public` parse the contextual keyword as a
   real operand (`ParseExpr()`, `ParseAtom.cpp:945`) rather than synthesizing a bare unit. The selfhost
   `SeeingDecl()` (`ParseDecl.cj`) is true for every contextual keyword that is also a modifier
   (`ModifierKindFromToken`), so without the guard the cut would have taken the synth-unit branch for those.
   A `SeeingContextualKeyword()` helper was added to `packages/parse/src/ParserUtils.cj`, mirroring
   `ParserImpl.h:190-193` over `GetContextualKeyword()` (already in `packages/lex/src/Tokens.cj:433`), and the
   `SeeingDecl()` arm is now `(SeeingDecl() && !SeeingContextualKeyword())`.

   Note: this guard is currently latent — the selfhost declaration/atom parser does not yet accept a
   contextual keyword as a binding/reference identifier anywhere (`let open = …` / `func open(…)` /
   `return open(5)` all fail to parse on both base `2b60b17` and this cut, whereas the reference cjc accepts
   them). So no observable behavior changes today, but the guard makes the condition 1:1 with C++ and removes
   the latent defect that would surface once the deeper contextual-keyword-as-identifier gap is closed.

2. **Missing `CASE` token.** C++ lists `CASE` in the terminator set so that a bare `return` as a match-arm
   body immediately before the next `case` synthesizes a unit. The selfhost `AtTerminator()` does not include
   `CASE`, and because `skipNL` defaults true the trailing newline is skipped before lookahead (lookahead is
   the `case` token, not `NL`), so both the same-line and the common multi-line `case X => return` shapes hit
   `ParseExpr(case)` and failed to parse. Adding `Seeing(TokenKind.CASE)` to the guard fixes this (verified:
   `match (x) { case 0 => return; case _ => println(...) }` now compiles on the selfhost and matches the
   reference). Regression corpus `scripts/difftest_corpus/104_match_arm_bare_return.cj`.

The guard condition is now
`(SeeingDecl() && !SeeingContextualKeyword()) || AtTerminator() || Seeing(TokenKind.CASE) || SeeingDoubleArrow()`.

Remaining (pre-existing, not introduced by this cut, documented for a later cut): `AtTerminator()` also
includes `NL` (a superset, inert because NL is skipped before lookahead); the selfhost `SeeingDecl()` is the
scoped `SeeingDeclInScope(UNKNOWN_SCOPE)` rather than C++'s no-arg `SeeingDecl()` (different inert edge tokens
`CONST/PROP/INIT`); and the `ParseExpr()` else-branch omits C++'s `newlineSkipped` `parse_nl_warning` and the
`IS_BROKEN` `ConsumeUntilAny` error-recovery (diagnostics-only). The deeper contextual-keyword-as-identifier
gap in the declaration/atom parser is a separate frontier.

## Probe 11 (lex match string-pattern + enum-arm invalid type)

Probe 11 targeted the next lex frontier in `packages/lex/src/LexerImpl.cj`, `LookupKeyword`, where
`let mapped = match (literal) { case "." => TokenKind.DOT ... }` reached CHIR with `mapped` and the
initializer match expression typed as `Invalid`.

### Diagnosis

Fresh oracle re-verification with the selfhost compiler contradicted the earlier narrow trigger: `m1`
and `m4` failed as expected, `m2` passed, but `m3` (string-literal const patterns with `Int64` arms)
also failed before the fix. Instrumenting sema showed the exact failure point was before result-type
join and before CHIR:

- selector type: `Struct-String`;
- each enum arm body type: `Enum-E` for `m1`, and each int arm body type was correct for `m3`;
- `ChkMatchCasePatterns` returned `false` for each string-literal const pattern;
- `ChkMatchCaseActions` returned `true`;
- `SynNormalMatchCaseBody` set the whole match expression to `Invalid` because `patternOk` was false.

So the enum-arm join hypothesis was refuted in this worktree. The bad interaction was not
`JoinAndMeet`: the selfhost never reached the join for the failing cases. The actual C++ divergence is
constant-pattern literal checking. C++ checks every non-rune/byte special constant-pattern literal by
calling the full expression checker against the selector type:

- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckPattern.cpp:244-258`:
  `ChkConstPattern` calls `Check(ctx, &target, p.literal.get())`.
- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckPattern.cpp:259-279`: after that check, C++ requires
  exact type equality, rejects interpolation, sets the pattern type to `TryGreedySubst(&target)`, and
  dispatches string equality through the synthesized `==` call.
- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckPattern.cpp:282-305`: the synthesized string
  equality call removes type-check cache entries for the synthetic `CallExpr` and `MemberAccess`,
  skips synthesis for the dummy receiver, calls `Check(ctx, boolTy, callExpr.get())`, and stores
  `p.operatorCallExpr` when that succeeds.
- `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckMatchExpr.cpp:92-130`: only after all
  `ChkMatchCasePatterns`, guards, and actions succeed does C++ collect match-case types and join them.

The selfhost had a standalone `CheckConstPatternLiteral` path for string literals. It did not call the
real `TypeChecker.Check(ctx, target, literal)`, so string literal patterns could remain untyped or
incorrectly typed during the pattern pass. The match-case action bodies were still correctly typed, but
the false `patternOk` forced `SynNormalMatchCaseBody` to `Invalid` before `JoinCaseTys`.

### Faithful Fix

`packages/sema/src/TypeCheckPattern.cj` now accepts a `ConstPatternExprChecker` callback and uses it for
the same sites where C++ calls `Check(ctx, &target, ...)`: checking the const-pattern literal against
the selector type and checking the synthesized overloaded `==` call against `Bool`. This keeps the
standalone fallback for non-`TypeChecker` callers, but the main type checker passes its real
`Check(ctx, target, expr)` function through `SynthesizeMatchChildren`, `SynMatchExpr`, and
`ChkMatchExpr`.

The synthesized const-pattern equality path was also aligned with C++ by removing type-check cache
entries for the synthetic call/base nodes and applying `AddCurFile` to the whole synthetic call tree,
matching `/root/cj_build/cangjie_compiler/src/Sema/TypeCheckPattern.cpp:285-300`.

Regression corpus `scripts/difftest_corpus/105_match_string_enum.cj` covers:

- string-literal patterns with enum arms in a `let`;
- string-literal patterns with enum arms in a `return`;
- int patterns with enum arms;
- string-literal patterns with int arms.

Reference and selfhost outputs match for the new corpus program:

```text
A
B
C
A
B
3
```

### Current lex result

The `LookupKeyword` invalid match-expression frontier is cleared. Re-running the full lex package with
the selfhost compiler now gets past that CHIR abort and stops later with the existing frontend
unsupported-construct diagnostic:

```text
error: unsupported construct in package 'cangjie_compiler::lex' (not yet implemented in real pipeline)
 ==> packages/lex/src/AnnotationToken.cj:1:1
```

No `lex@cangjie_compiler.cjo` or `self-liblex.a` is produced yet in Probe 11.

### Verification

Commands run after the fix, as separate commands:

```sh
rm -rf target && cjpm build
./target/release/bin/cangjie_compiler::cjc /tmp/cjtasks/match_oracle/m1.cj -o /tmp/cjtasks/match_oracle/m1.self
./target/release/bin/cangjie_compiler::cjc /tmp/cjtasks/match_oracle/m2.cj -o /tmp/cjtasks/match_oracle/m2.self
./target/release/bin/cangjie_compiler::cjc /tmp/cjtasks/match_oracle/m3.cj -o /tmp/cjtasks/match_oracle/m3.self
./target/release/bin/cangjie_compiler::cjc /tmp/cjtasks/match_oracle/m4.cj -o /tmp/cjtasks/match_oracle/m4.self
bash scripts/difftest.sh
bash scripts/septest/run.sh
bash scripts/septest/run_write.sh
bash scripts/septest/run_diag.sh
bash scripts/septest/run_write_types.sh
bash scripts/septest/run_write_struct.sh
```

Results:

- `cjpm build`: success.
- Oracle `m1`, `m2`, `m3`, and `m4`: selfhost compiles and runs; outputs match the reference.
- New corpus program `105_match_string_enum`: selfhost output matches reference.
- `difftest`: `TOTAL=89  PASS=89  MISMATCH=0  FAIL=0`.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

### Review-gate residuals (documented for follow-up cuts)

An independent adversarial faithfulness review confirmed the core fix is 1:1 with C++
(`ChkConstPattern`/`ChkOpOverloadForConstPattern`, `src/Sema/TypeCheckPattern.cpp:244-311`): routing the
const-pattern literal and the synthesized `selector == literal` equality through the full `Check` (via the
`ConstPatternExprChecker` callback) exactly mirrors C++. Independent verification: clean build, difftest
`TOTAL=89 PASS=89` (one tail FAIL on `45_string_methods` was a spurious contention OOM — verified standalone
PASS), all 5 septests, and `m1`–`m4` match the reference. No valid-program regression (the `big` for-in over
an array-literal that now reaches a downstream codegen `load/store type` frontier was already blocked at the
old match-Invalid sema frontier on base `dca2193` — the fix advanced it, did not regress it).

Residuals NOT addressed by this cut (all confirmed by the review as either diagnostics-only or pre-existing
adjacent frontiers, none a regression):

1. **DiagSuppressor + `sema_not_overload_in_match` (diagnostics-only).** C++ `ChkOpOverloadForConstPattern`
   (`TypeCheckPattern.cpp:300-310`) wraps the trial `Check(ctx, boolTy, callExpr)` in a `DiagSuppressor` and
   emits `sema_not_overload_in_match` on failure. The selfhost (which HAS `DiagSuppressor.cj`) routes the
   trial through the live diag engine without suppression and emits no such diagnostic. Inert on valid
   programs (the overload succeeds → no diagnostics emitted); only the failure path (invalid programs / no
   `==` overload) diverges. Part of foundational sema-validation-diagnostic debt.

2. **Nested / sugar const-pattern paths not yet threaded (pre-existing valid-program frontiers).** The
   `exprChecker` is threaded only through the top-level match path. A string-literal const pattern nested
   inside an enum pattern (`case Some("a") => …`), a tuple pattern with an enum-typed arm
   (`case ("a", 1) => E.X`), an `if-let`/`LetPattern` const pattern, and the quest-sugar (`?.`/`??`) match
   path all still take the narrow checker and leave an Invalid match type → CHIR abort. These fail identically
   on base `dca2193` (pre-existing, not regressed) and are a coherent follow-up cut: thread the const-pattern
   `Check` through `ChkEnumPattern` and the remaining nested/sugar pattern paths, mirroring C++'s uniform
   `Check`-through-`ChkPattern` recursion.


## Probe 12 (lex unsupported-construct / array member access)

### Diagnosis

The package-level diagnostic

```text
error: unsupported construct in package 'cangjie_compiler::lex' (not yet implemented in real pipeline)
  ==> packages/lex/src/AnnotationToken.cj:1:1
```

was not anchored at the culprit declaration. `AnnotationToken.cj:1:1` is the package diagnostic position chosen
by `GenerateCHIRForPkg` when `BuildRealCHIRForASTPackage` returns `None` without an existing diagnostic.

Instrumentation of `BuildRealCHIRForASTPackage` showed that the actual `None` came from the selfhost
`FaithfulAST2CHIR` post-translation CHIR checker. The smallest standalone matching frontier is:

```cj
main() {
    let a: Array<String> = ["x", "y"]
    println(a.size)
}
```

Before the fix, selfhost failed it with the same CHIR-level unsupported construct; the reference compiler prints
`2`. The checker failure was an `Apply` argument mismatch for the array `size` getter:

```text
Apply(std.core._CNat5ArrayIG_E<std.core._CNat6StringE>->@_CNatXRNat5ArrayIG_E4sizepgHv, %array)
```

where the loaded receiver had concrete type `Array<String>`, while the imported getter function still exposed its
generic extension receiver type `Array<T>`.

For the full lex package, `--chir-wfc on` reports the first checker failure in
`Lexer.GetComments`, with the same shape:

```text
value ... Array<Token> has type Array<Token>, but Array<Generic-T> type is expected
```

followed by more `Array`/`ArrayList` generic member-call checker errors. `AnnotationToken.cj` remains only the
package-level anchor; the lex package failure is a checker-level generic receiver/member-call frontier, not a
single unsupported AST declaration in `AnnotationToken.cj`.

The relevant C++ lowering already computes the instantiated member-call receiver/parent:

- `src/CHIR/AST2CHIR/TranslateASTNode/TranslateMemberAccess.cpp:269-307` builds `InstCalleeInfo` from member
  access, including `thisType`, instantiated parent type, parameter types, return type, and instantiated type args.
- `src/CHIR/AST2CHIR/TranslateASTNode/TranslateMemberAccess.cpp:133-190` inserts `thisType` into non-static member
  parameter types and calls `GetExactParentType`.
- `src/CHIR/AST2CHIR/TranslateASTNode/TranslateArrayExpr.cpp:158-225` resolves builtin/extension parent types;
  lines `195-211` build the generic replacement table for extension targets and return the instantiated extended
  type.
- The C++ CHIR checker then re-instantiates apply callees using the apply's instantiated parent type:
  `src/CHIR/Checker/CHIRChecker.cpp:2029-2070`, especially `CalculateInstFuncType(...,
  expr.GetInstParentCustomTyOfCallee(builder))`, and
  `src/CHIR/Utils/Utils.cpp:1303-1427`.

The selfhost divergence was earlier than that C++ checker path: it always ran its AST2CHIR WFC pass during normal
release selfhost compilation. Reference C++ does not do that in the release compiler. `src/CMakeLists.txt:42-46`
defines `CANGJIE_CHIR_WFC_OFF` for Release builds without assertions; `include/cangjie/Option/Option.h:630-634`
therefore defaults `chirWFC` to `false`; and `src/CHIR/AST2CHIR/AST2CHIR.cpp:485-489` returns immediately when
`opts.chirWFC` is false, even though `ToCHIRPackage` still calls `AST2CHIRCheck` at
`src/CHIR/AST2CHIR/AST2CHIR.cpp:583-589`.

### Faithful Fix

`GlobalOptions.chirWFC` now defaults to `false`, matching the release C++ default. `FaithfulAST2CHIR` takes the
actual frontend `globalOptions.chirWFC` and only runs `AST2CHIRCheck()` when that option is enabled, preserving the
explicit `--chir-wfc on` debugging behavior.

This is deliberately not a checker workaround and does not special-case arrays, lex, `size`, or any symbol name.
The underlying checker gap remains visible with `--chir-wfc on`; normal release compilation now follows the C++
pipeline and proceeds past the debug-only checker.

### Current lex result

With the faithful WFC default, the lex package gets materially further: it no longer returns `None` from
`BuildRealCHIRForASTPackage` and no longer emits the package-level unsupported-construct diagnostic.

The next blocker is in real codegen. Compiling `packages/lex/src` as a staticlib now reaches
`EmitRealCodeGenForCompilerInstance` and crashes while emitting `StoreElementRef` for array/object element storage:

```text
SIGSEGV in llvm::PointerType::get
  at packages/codegen/src/IRBuilder.cj:1033
  via packages/codegen/src/ArrayImpl.cj:495 CreateElementAddress
  via packages/codegen/src/ArrayImpl.cj:338 GenerateStoreElementRef
```

No `lex@cangjie_compiler.cjo` or `self-liblex.a` is produced yet. This is a separate codegen frontier, consistent
with the earlier `Array<String>` sibling failures: `Array<Int64>.size` now compiles and runs, while
`Array<String>.size` reaches LLVM/codegen and fails later.

### Verification

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
- New corpus program `106_array_int_size`: selfhost output matches reference (`3`, `2`).
- `difftest`: `TOTAL=90  PASS=90  MISMATCH=0  FAIL=0`.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 14 (JoinAndMeet residual faithfulness gaps)

### C++ divergences closed

**Gap A: JoinAndMeet accessibility filtering.** C++ `BatchJoin` filters common supertypes through
`impMgr->IsTyAccessible(*curFile, *ty)` (`src/Sema/JoinAndMeet.cpp:159-161`). That only extracts decls for
struct/class/interface/enum tys and keeps all other tys (`src/Modules/ImportManager.cpp:1349-1364`), then
uses package equality, imported-decl lookup, package-prefix import plus `Modules::IsVisible`, and alias-import
lookup (`src/Modules/ImportManager.cpp:1367-1388`; `include/cangjie/Modules/ModulesUtils.h:71-77`). The
selfhost had a hand-rolled same-file/public/private/same-package check in `JoinAndMeet.cj`, so visible
non-public supertypes could be dropped.

The port now mirrors the C++ shape: `JoinAndMeet.cj:272-298` extracts only struct/class/interface/enum decls,
so `TypeAliasTy` and builtin/structural tys follow the C++ keep-by-default path; `JoinAndMeet.cj:300-332`
filters through `TypeManager.IsDeclAccessible`. The selfhost frontend already seeds resolved imports for
lookup; `GenericInstantiationManager.cj:19-26` now also seeds the same data into `TypeManager`, whose
`IsDeclAccessible` (`TypeManager.cj:878-925`) follows the C++ package/imported-name/package-prefix-visible
logic using the selfhost `PackageRelation` helpers. This is a valid-program behavior fix.

Oracle: added `scripts/septest/pkgA4/pkgA4.cj` and `scripts/septest/pkgB4/protected_lub.cj`. `pkgA4` exposes
public sibling classes with a protected common base; `pkgA4.child` imports `pkgA4.*` and joins the two branch
types. Reference C++ and selfhost both compile and run with output `17` (`SEPTEST-protected_lub-PASS`).

**Gap B: common-supertype construction.** C++ constructs `GetAllCommonSuperTys` by intersecting each operand's
`GetAllSuperTys(ty)` plus the operand itself (`src/Sema/TypeManager.cpp:1558-1577`). The selfhost used a
`HasSuperTy` filter over the first operand's candidates, which could drift from enumeration. The port in
`TypeManager.cj:852-875` now builds the same set intersection. This is a latent correctness fix for any case
where `HasSuperTy` and enumerated supertypes diverge; no separate failing valid-program oracle was isolated.

**Gap C: inheritable-type predicate and recursion defaults.** C++ `IsInheritableType` rejects non-class-like
tys (`src/Sema/TypeManager.cpp:449-457`) and the nominal-super walkers recurse with default `withExtended=true`
(`src/Sema/TypeManager.cpp:1428-1451`). The selfhost accepted all nominal tys and propagated `withExtended`.
`TypeManager.cj:1236-1242` now requires `IsClassLike`, and `TypeManager.cj:2957-2978` calls `GetAllSuperTys`
and `HasSuperTy` with their defaults. This is mostly latent 1:1 parity for valid programs, because inherited
types should already be class/interface, but it prevents malformed or partially typed struct/enum inherited
entries from adding spurious common supertypes.

**Gap D: `TypeAliasTy` common supertype filtering.** C++ `ImportManager::IsTyAccessible` does not extract a
decl from `TypeAliasTy`; non struct/class/interface/enum tys return accessible (`src/Modules/ImportManager.cpp:1349-1364`).
The selfhost used `Ty.GetDeclPtrOfTy`, which includes aliases. `JoinAndMeet.cj:272-298` now matches the C++
typed-decl extraction, so alias common supertypes are retained. This is a lower-risk valid-program fix; no
separate failing oracle was isolated.

### Verification

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
- `difftest`: `TOTAL=89  PASS=89  MISMATCH=0  FAIL=0`.
- `run.sh`: `SEPTEST-PASS`, including new `SEPTEST-protected_lub-PASS output=17 exit=0`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 15 (contextual keyword as identifier)

### Root cause and C++ reference

The selfhost parser rejected contextual-keyword tokens such as `features`, `open`, and `common` in ordinary
identifier/reference positions. The reference parser accepts those tokens by position:

- `src/Parse/ParseAtom.cpp:111-112`: `ParseAtom` dispatches `IDENTIFIER || SeeingContextualKeyword()` to
  `ParseRefExpr`.
- `src/Parse/ParserUtils.cpp:607-615`: `ExpectIdentifierWithPos` reads both normal identifiers and keyword
  identifiers through `SkipKeyWordIdentifier`, preserving the token text as the identifier.
- `src/Parse/ParserUtils.cpp:654-667`: `SeeingKeywordAndOperater` recognizes contextual keywords followed by
  expression operators as expression starts, not declaration modifiers.
- `src/Parse/ParseDecl.cpp:1904-1907`: modifier parsing stops on `SeeingKeywordAndOperater()`.
- `src/Parse/Parser.cpp:552-556`: block `ParseExprOrDecl` routes `SeeingKeywordAndOperater()` to `ParseExpr`.
- `src/Parse/ParserUtils.cpp:683-688` plus `src/Parse/ParseAtom.cpp:1149-1152`: named call arguments accept
  contextual-keyword argument names through the same identifier path.
- `src/Parse/ParseType.cpp:24-25`: type parsing treats contextual keywords as identifier-like type names;
  this is the C++ shape that expression type-argument parsing relies on after `<`.

### Faithful fix

The selfhost port now mirrors those C++ gates:

- `packages/parse/src/ParseAtom.cj`: `ParseAtom` includes `SeeingContextualKeyword()` in the reference-expression
  dispatch, and the type-argument lookahead scanner treats contextual keywords as identifier-like tokens before
  handing control to `ParseTypeArguments`.
- `packages/parse/src/ParserUtils.cj`: added the C++-shaped `SeeingKeywordAndOperater()` helper.
- `packages/parse/src/ParseModifiers.cj`: modifier parsing now stops when a contextual keyword is actually an
  expression start, matching the C++ guard.
- `packages/parse/src/ParseExpr.cj`: `ParseExprOrDecl` routes `SeeingKeywordAndOperater()` to expression parsing,
  and named call arguments accept contextual-keyword names.

The identifier text round-trips through the existing `ParseIdentifierFromToken` / `ExpectIdentifierWithPos`
path, so the token value becomes the binding/reference name rather than demoting token kind globally.

### Oracle and corpus

The original oracle now matches the reference:

```cj
main(): Int64 {
    let features = 3
    return features
}
```

Reference compile/run and selfhost compile/run both succeed, returning exit code `3`.

Added `scripts/difftest_corpus/107_contextual_kw_identifier.cj`, covering:

- contextual keyword as let-binding name plus expression reference: `features`
- contextual keyword as parameter name and named call argument: `common`
- contextual keyword as member name and member access: `features`
- genuine keyword/modifier use remains covered by existing class/member syntax in the same corpus run.

### Current package frontier after this blocker

Follow-up package probes no longer stop on the `return features` / contextual-reference parser gap:

- `packages/ast/src`: gets past the former `PrintNode.cj` parser failure and now reaches runtime OOM in the
  selfhost compile, even with `cjHeapSize=4GB`.
- `packages/parse/src`: gets past contextual-keyword reference expressions; the next observed parser blocker is
  `packages/parse/src/ParseImports.cj:5` on the top-level `private const PACKAGE_NAME_LEN_LIMIT` declaration.
- `packages/modules/src` and `packages/sema/src`: with `cjHeapSize=2GB`, the next observed blocker is runtime OOM.
- `packages/chir/src`: next observed blocker is import accessibility:
  `packages/chir/src/Translator.cj:58-59` imports `TokenKind` / `TokenKindValue` from `cangjie_compiler::ast`,
  where they are not accessible.
- `packages/codegen/src`: with `cjHeapSize=2GB`, the next observed blocker is runtime OOM.

### Verification

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
- Contextual keyword oracle: reference and selfhost compile/run match, exit code `3`.
- `difftest`: `TOTAL=90  PASS=90  MISMATCH=0  FAIL=0`.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 13 (nested/sugar const-pattern paths)

### Diagnosis

Probe 11's `ConstPatternExprChecker` was threaded only through the top-level match path. C++ has no callback
split: recursive `ChkPattern` dispatches `CONST_PATTERN` to `ChkConstPattern` and `ENUM_PATTERN` /
`TUPLE_PATTERN` to their recursive checkers uniformly
(`/root/cj_build/cangjie_compiler/src/Sema/TypeCheckPattern.cpp:194-223`). `ChkConstPattern` checks the
literal with full `Check` and then checks the synthesized string `==` call with full `Check`
(`/root/cj_build/cangjie_compiler/src/Sema/TypeCheckPattern.cpp:244-311`).

The selfhost enum pattern path dropped the callback: `ChkEnumPattern` delegated to
`IsFuncTyEnumPatternMatched`, whose payload loop recursively called `ChkPattern` without the checker. This
diverged from C++'s payload recursion
(`/root/cj_build/cangjie_compiler/src/Sema/TypeCheckPattern.cpp:371-428`) and left `case Some("a")` with an
Invalid nested const-pattern type. The tuple checker was already threaded; C++ tuple recursion checks each
element with the normal pattern `Check` path
(`/root/cj_build/cangjie_compiler/src/Sema/TypeCheckPattern.cpp:467-492`), so E2's remaining failure was not
Sema.

E2's true root was backend ABI/lowering. The tuple-nested string const pattern reached codegen, but the
selfhost treated LLVM struct-shaped values such as `String`, tuple values, and option-like non-ref enum values
as by-value call arguments. That produced first-class aggregate string/tuple values live across Cangjie GC
statepoints or aggregate stores where the reference passes LLVM struct-shaped arguments by pointer. C++ does
this in `CGFunctionType`: parameters whose CHIR type is struct/tuple, whose size is unknown, or whose CG type
is an LLVM struct/array are lowered to pointers
(`/root/cj_build/cangjie_compiler/src/CodeGen/Base/CGTypes/CGFunctionType.cpp:117-129`) and the contained
function-argument CG types are likewise fixed to refs
(`/root/cj_build/cangjie_compiler/src/CodeGen/Base/CGTypes/CGFunctionType.cpp:176-195`). C++ defines
`CGType::IsStructType` / `IsVArrayType` from the LLVM type shape, not only from the source CHIR kind
(`/root/cj_build/cangjie_compiler/src/CodeGen/Base/CGTypes/CGType.h:97-105`). For struct-pointer stores, C++
copies through `memcpy`
(`/root/cj_build/cangjie_compiler/src/CodeGen/CJNative/CJNativeIRBuilder.cpp:731-738`).

The first ABI fix regressed nested struct field access by making `FieldByName`/`Field` on a pointer base return
the struct-shaped field address directly. That broke `o.i.v`: the intermediate `o.i` CHIR value was mapped as an
`Inner` value but carried the LLVM address of `Outer.i`, so the following `.v` extraction treated a pointer as a
first-class struct. C++ separates these paths. Value member access loads from a reference base after building the
address with `GetElementRef`
(`/root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/TranslateASTNode/TranslateMemberAccess.cpp:443-448`), and
value-base member access emits a `FieldByName` value
(`/root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/TranslateASTNode/TranslateMemberAccess.cpp:449-453`). When a
member access is only the base for a later field, C++ first loads the referenced member value, then continues with
that value as the base
(`/root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/TranslateASTNode/TranslateMemberAccess.cpp:596-607`). The
selfhost fix therefore restores `FieldByName`/`Field` as value-producing loads and leaves address-producing
behavior to the `GetElementRef` lowering used by left values.

The remaining quest-sugar probe exposed a separate, larger frontier. The const-pattern checker is now threaded
into `LetPattern` checking to match C++ `SynLetPatternDestructor`
(`/root/cj_build/cangjie_compiler/src/Sema/TypeCheckExpr/IfExpr.cpp:133-155`) and into the quest-sugar match
case checker to match C++ `SynMatchExprHasSelector` / `SynQuestSugarMatchCaseBody`
(`/root/cj_build/cangjie_compiler/src/Sema/TypeCheckMatchExpr.cpp:76-89`,
`/root/cj_build/cangjie_compiler/src/Sema/TypeCheckMatchExpr.cpp:153-187`). Quest-sugar still hits the existing
frontend unsupported-construct path before a const-pattern oracle can run.

### Faithful Fix

- Threaded the same `exprChecker` through `ChkEnumPattern` and its payload recursion, matching C++'s uniform
  `ChkPattern -> ChkEnumPattern -> ChkPattern` recursion.
- Threaded `exprChecker` through `SynQuestSugarMatchCaseBody` and both of its `ChkMatchCasePatterns` calls,
  matching C++'s quest-sugar case checking.
- Threaded a full `TypeChecker.Check` callback into `CheckLetPatternCondition`, matching C++ let-pattern
  recursion.
- Fixed the E2 backend root by matching the C++ ABI rule for LLVM struct-shaped parameters: `CGType` now
  identifies struct/array by LLVM type shape, `CGFunctionType` and parameter mapping pass those parameters by
  pointer, and `FixFuncArg` materializes aggregate actuals into argument slots.
- Fixed the nested-struct regression by restoring pointer-base `FieldByName`/`Field` lowering to load the final
  field value, matching C++ value member access. Further field access still receives an address through
  `GetElementRef`, matching C++ left-value/base lowering.

### Confirmation

Focused oracles after the fix:

- E1 `match (o: Option<String>) { case Some("a") => ... }`: selfhost output matches reference: `1`, `2`, `3`.
- E2 `match (t: (String, Int64)) { case ("a", 1) => E.X; ... }`: selfhost output matches reference: `X`, `Y`.
- if-let `if (let Some("a") <- o)`: selfhost output matches reference: `1`, `0`, `0`.
- s1/s3/s4/s6 battery: selfhost output matches reference, including s3 nested struct field output `11`, `5`.
- s2 tuple-with-String parameter and s5 `VArray<Int64, $3>` parameter remain the same pre-existing selfhost
  compile failures noted by the battery.
- New corpus program `109_match_nested_const.cj`: selfhost output matches reference: `1`, `2`, `3`, `X`, `Y`.
- New corpus program `108_nested_struct_field.cj`: selfhost output matches reference: `11`, `5`.

Full verification for this probe: clean `cjpm build`, `difftest` `TOTAL=91 PASS=91 MISMATCH=0 FAIL=0`, and all
five septests pass as separate commands: `run.sh`, `run_write.sh`, `run_diag.sh`, `run_write_types.sh`, and
`run_write_struct.sh`.

## Probe 16 (where-clause multiple constraints)

### Root cause and C++ reference

The selfhost parser treated `where` as if each `where` introduced exactly one generic constraint. In
`packages/parse/src/ParserUtils.cj`, `ParseGenericConstraints` looped on `while (Skip(TokenKind.WHERE))`, parsed one
`T <: Bound`, and returned with a comma still pending for sources such as:

```cj
public func HashPair<T1, T2>(pair: (T1, T2)): Int64 where T1 <: Hashable, T2 <: Hashable {
    return pair[0].hashCode() ^ pair[1].hashCode()
}
```

The C++ parser has the opposite shape: a single `where` introduces a comma-separated list of constraints.
`/root/cj_build/cangjie_compiler/src/Parse/ParseDecl.cpp:1868-1888` builds one `GenericConstraint`, records either the
initial `wherePos` or the previous constraint's `commaPos` at `:1874-1878`, parses the upper-bound list, and repeats
with `while (Skip(TokenKind::COMMA))`. It then performs the duplicate constrained type-name diagnostic pass at
`/root/cj_build/cangjie_compiler/src/Parse/ParseDecl.cpp:1889-1899`. The upper-bound helper records `<:` and `&`
positions at `/root/cj_build/cangjie_compiler/src/Parse/ParseDecl.cpp:1833-1864`.

### Faithful fix

`packages/parse/src/ParserUtils.cj` now mirrors that structure:

- no constraints are parsed unless the caller position actually has `where`;
- the first constraint records `wherePos`;
- each following comma records `commaPos` on the previous `GenericConstraint` before parsing the next one;
- `<:` is recorded in `operatorPos`;
- `&` multi-bounds continue to parse and now record `bitAndPos`;
- a duplicate constrained type-name pass diagnoses repeated constrained type names after parsing the list.

This is a parser-grammar fix only; it does not special-case `HashPair` or any corpus file.

### Oracle and corpus

The original oracle now matches the reference: selfhost and reference both compile the `HashPair<T1, T2> ... where
T1 <: Hashable, T2 <: Hashable` snippet successfully.

Added `scripts/difftest_corpus/110_where_multi_constraint.cj`, covering:

- a generic function with multiple comma-separated `where` constraints;
- a generic class with multiple comma-separated `where` constraints;
- a generic struct with multiple comma-separated `where` constraints;
- a single-constraint `where T <: Hashable`;
- `&` multi-bound constraints such as `T1 <: Hashable & Named`.

Standalone reference/selfhost compile-run for the new corpus case matches: output `48`, exit `0`.

### Current package frontier after this blocker

`packages/utils/src` now gets past the former parser blocker in `Utils.cj` at
`where T1 <: Hashable, T2 <: Hashable`. The next observed blocker is runtime OOM during selfhost compilation of the
package with:

```sh
./target/release/bin/cangjie_compiler::cjc -p packages/utils/src --output-type=staticlib -o "$tmpdir/utils"
```

The failure occurs after parsing and reports `Out of memory`; no follow-up fix was attempted here.

### Verification

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
- Original multi-constraint oracle: reference and selfhost both compile successfully.
- New corpus case: reference and selfhost compile/run match, output `48`, exit `0`.
- `difftest`: `TOTAL=92  PASS=92  MISMATCH=0  FAIL=0`.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 17 (public-import re-export visibility)

### C++ divergence closed

C++ import checking looks up the imported declaration in the package member map, not just in declarations directly
owned by the imported package source file. The reference code calls
`cjoManager->GetPackageMembersByName(package->fullPackageName, import->content.identifier)` and filters that
member set with `Modules::IsVisible` before emitting `package_decl_not_find_in_package`
(`src/Modules/ImportManager.cpp:648-655`). That member map is populated through `CjoManager::AddPackageDeclMap`,
which recursively folds visible `public`/protected/internal re-export imports into `pkgInfo->declMap`
(`src/Modules/CjoManager.cpp:568-593`).

The selfhost `FrontendModel.cj` re-check only scanned `pkg.files[*].decls`, so a visible declaration re-exported
by `public import` was rejected as not accessible. The port now builds the same package-member view in
`FrontendModel.cj`, including serialized import specs from imported `.cjo` files, applies the re-export access
level when folding imported members, and makes `HasVisibleImportedDecl` query that member map plus the same
package-relation visibility predicate before reporting `package_decl_not_find_in_package`.

### Oracle

Added a septest cross-package case:

- `pkgReExportP` defines `public func reExportedValue(): Int64`.
- `pkgReExportQ` uses `public import pkgReExportP.reExportedValue`.
- `pkgReExportM` imports `pkgReExportQ.reExportedValue`.

`scripts/septest/run.sh` builds `pkgReExportP` and `pkgReExportQ` with the reference compiler, then compiles
`pkgReExportM` with both reference and selfhost. The selfhost now matches reference and prints
`SEPTEST-use_reexport-PASS output=7 exit=0`.

### Current package frontier after this blocker

- `packages/mangle/src`: gets past the former
  `OverflowStrategy` / `Linkage` not-accessible import blocker. With `cjHeapSize=2GB`, the next observed blocker is
  `IllegalStateException: diagnostic argument count does not match format placeholders` in
  `packages/basic/src/DiagnosticEngine.cj:399`, reached from `packages/sema/src/TypeCheckReference.cj:705`.
- `packages/chir/src`: gets past the former `TokenKind` / `TokenKindValue` not-accessible import blocker. With
  `cjHeapSize=2GB` and again with `cjHeapSize=4GB`, the next observed blocker is runtime OOM.

### Verification

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

- Clean `cjpm build`: success.
- `difftest`: `TOTAL=91  PASS=91  MISMATCH=0  FAIL=0`.
- `run.sh`: `SEPTEST-PASS`, including `SEPTEST-use_reexport-PASS output=7 exit=0`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 18 (top-level const declaration)

### C++ divergence closed

The rejection point was the selfhost top-level declaration gate after modifier parsing. `ParseTopLevelDecl` called
`ParseModifiers`, which consumed `const` as a modifier, leaving the identifier as lookahead. The old gate then only
called `ParseDecl` when `SeeingDecl()` was true, so bare `const A...` and modifier-prefixed `private const C...`
fell through to "unexpected token at top level" before reaching variable parsing.

C++ does not have that post-modifier gate: after `ParseModifiers`, top-level parsing calls
`ParseDecl(ScopeKind::TOPLEVEL, modifiers, ...)` directly (`src/Parse/Parser.cpp:241-254`). In `ParseDecl`, C++
then handles a consumed `const` modifier as a const variable when `HasModifier(modifiers, TokenKind::CONST)` and
`lastToken == "const"` (`src/Parse/ParseDecl.cpp:118-123`), routes it through `ParseConstVariable`
(`src/Parse/ParseDecl.cpp:248-252`), and records the declaration as const from the keyword token
(`src/Parse/ParseDecl.cpp:286-288`). C++ `SeeingDecl()` also does not list `CONST` as a declaration-start keyword;
it treats `const` through the modifier path (`src/Parse/ParserImpl.h:397-401`).

The selfhost port now mirrors that path: `SeeingDeclInScope` no longer lists `CONST` as an ordinary declaration
start, top-level parsing allows the already-consumed const modifier to enter `ParseDecl`, and `ParseDecl` has the
same consumed-const branch. `ParseConstVariable` reuses the existing variable/pattern declaration parsing with
`isConst = true`, so the AST remains a real const declaration rather than a `let`.

### Oracle

The narrowed oracle now matches the reference compiler:

- `/tmp/cjtasks/const_oracle/c1.cj`: `const A: Int64 = 5`, reference and selfhost compile successfully.
- `/tmp/cjtasks/const_oracle/c3.cj`: `private const C: Int64 = 5`, reference and selfhost compile successfully.
- `/tmp/cjtasks/const_oracle/c4.cj`: `const D = 5`, reference and selfhost compile successfully.

Added `scripts/difftest_corpus/111_toplevel_const.cj`, covering a private top-level const with a type annotation,
a public top-level const with inferred type, and function use of both. Standalone reference/selfhost compile-run
matches: output `42`, exit `0`.

Function-local `const`, static class-member `const`, and top-level `let`/`var` were also rechecked with the
selfhost compiler and still compile.

### Current package frontier after this blocker

`packages/parse/src` no longer reports the former real-parser failure at `packages/parse/src/ParseImports.cj` on
`private const PACKAGE_NAME_LEN_LIMIT: Int64 = 200`. A focused package compile with `cjHeapSize=2GB` and the
reference-built dependency artifacts produced no parser diagnostic and hit the 300s timeout instead:

```sh
timeout 300 env cjHeapSize=2GB ./target/release/bin/cangjie_compiler::cjc -p packages/parse/src \
  --output-type=staticlib -o "$WORK/self-libparse.a" \
  --import-path target/release/basic@cangjie_compiler \
  --import-path target/release/utils@cangjie_compiler \
  --import-path target/release/option@cangjie_compiler \
  --import-path target/release/ast@cangjie_compiler \
  --import-path target/release/lex@cangjie_compiler \
  -L target/release/basic@cangjie_compiler \
  -L target/release/utils@cangjie_compiler \
  -L target/release/option@cangjie_compiler \
  -L target/release/ast@cangjie_compiler \
  -L target/release/lex@cangjie_compiler \
  -lbasic@cangjie_compiler -lutils@cangjie_compiler -loption@cangjie_compiler \
  -last@cangjie_compiler -llex@cangjie_compiler --set-runtime-rpath -V
```

No follow-up fix was attempted here.

### Verification

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

- Clean `cjpm build`: success.
- `difftest`: `TOTAL=95  PASS=95  MISMATCH=0  FAIL=0`.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 22 (generic-func-without-type-arg diagnostic argument)

Selfhost `TypeCheckReferenceFilterTargetsForFuncReference` removed generic function targets when a reference used no
type arguments, then emitted `sema_generic_func_without_type_arg` with no diagnostic arguments
(`packages/sema/src/TypeCheckReference.cj:705`). That diagnostic format is
`"type arguments needed for the generic function%s"`, so `Diagnostic.InsertArguments` raised
`IllegalStateException` before a clean sema error could be printed.

The C++ reference helper computes the expression range, narrows member access to the field range, builds
`expr.symbol == nullptr ? "" : " '" + expr.symbol->name + "'"`, and passes that string as the format argument
(`src/Sema/Diags.cpp:369-379`; format in
`include/cangjie/Basic/DiagRefactor/DiagnosticSema.def:87-88`). The selfhost now mirrors that by reading
`expr.symbol`, constructing the same optional quoted name, and passing it through
`arguments: [name]` to `DiagnoseRefactor`.

Added a `run_diag.sh` regression for:

```cj
func id<T>(x: T): T { x }
main() { let f = id; println("hi") }
```

The test compares reference and selfhost JSON diagnostic kind, message, and main-hint range. The selfhost now emits
the clean matching error `type arguments needed for the generic function 'id'`, columns `18-20`, instead of throwing
`IllegalStateException`.

Verification:

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

- Clean `cjpm build`: success.
- `difftest`: `TOTAL=94  PASS=94  MISMATCH=0  FAIL=0`.
- `run.sh`: `SEPTEST-PASS`.
- `run_write.sh`: `SEPTEST-WRITE-PASS`.
- `run_diag.sh`: `SEPTEST-DIAG-PASS`, including the generic function diagnostic match.
- `run_write_types.sh`: `SEPTEST-WRITE-TYPES-PASS`.
- `run_write_struct.sh`: `SEPTEST-WRITE-STRUCT-PASS`.

## Probe 19 (constructor default field initializers)

Bug: source constructors translated by the selfhost skipped in-class instance field default initializers. Valid programs
such as `class C { public var x = 5; public func get(): Int64 { x } }` printed `0` from `C().get()` instead of
the reference `5`. The gap affected `var` and `let`, classes and structs, and non-integer defaults such as
`String` and `Bool`.

Root: `packages/chir/src/Translator.cj:336` translated every `AstFuncDecl` body directly through
`TranslateASTNode(astBody)` after parameter binding, with no constructor-specialized path to emit member default
initializers before the explicit constructor body.

C++ divergence: `/root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/TranslateASTNode/TranslateFuncDecl.cpp`
builds member initialization separately in `Translator::TranslateVariablesInit` by walking
`AST::GetVarsInitializationOrderWithPositions(parent)` and storing each initializer into `this`
(`TranslateFuncDecl.cpp:331-378`). Constructors then run that initialization before the body when there is no
delegated `this(...)` call (`TranslateConstructorFunc`, `TranslateFuncDecl.cpp:381-408`). The inline constructor
path shows the direct field-order lowering: start from the super-field offset, iterate non-static `VAR_DECL`
members in declaration order, translate each initializer, and `StoreElementRef` into `this`
(`TranslateConstructorFuncInline`, `TranslateFuncDecl.cpp:411-453`).

Faithful fix: `Translator.cj` now detects constructor functions, skips the initializer pass for delegated
`this(...)` constructors, computes the local field offset after super fields, translates each non-static member
initializer in declaration order, and stores it into the current constructor `this` through the existing
`StoreElementRef` path. String-valued field defaults also exercised struct-valued `StoreElementRef` codegen, so
the store-element lowering now materializes non-reference struct values before storing, matching the existing
plain `Store` handling instead of special-casing `String`.

Confirmation:

- Repro now prints `5` on selfhost and reference.
- Added `scripts/difftest_corpus/111_field_default_init.cj` covering `var` and `let`, `Int64`/`String`/`Bool`,
  struct field defaults, explicit constructors with defaulted fields, and delegated `this(...)` without double init.
- New corpus case matches reference output:
  `12`, `15`, `4`, `11`.
- Clean build succeeded.
- Full corpus: `TOTAL=95  PASS=95  MISMATCH=0  FAIL=0`.
- Septests passed separately: `run.sh`, `run_write.sh`, `run_diag.sh`, `run_write_types.sh`,
  `run_write_struct.sh`.
