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
