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
