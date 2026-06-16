# Parse Port Status

Date: 2026-06-17

Build: `cjpm build` passes.

## Summary

Replaced the Parse scaffold with a multi-file Cangjie package that mirrors the C++
Parse component split. The package now imports real Basic positions/source
manager, real Lex tokens/token tables, real AST kind/attribute/annotation
enums, real Utils overflow strategy helpers, and real Option compiler
configuration types. It still has local
parser-facing diagnostics, AST node shapes, a lexer, parser state, top-level parsing,
declaration parsing, expression parsing, type parsing, pattern parsing, imports,
annotations, modifiers, features, macro-call capture, quote capture, comment
collection, modifier-rule queries, AST checking, AST hashing, CJMP entry wiring,
and Java/ObjC native FFI parser checks.

## Current De-Isolation

`packages/parse/cjpm.toml` now depends on `basic`, `lex`, `ast`, `option`, and
`utils`.
`Position.cj` and `Token.cj` no longer own compatibility copies of the Basic
position/source types or Lex token types. `ASTCore.cj` no longer owns local
copies of `ASTKind`, `Attribute`, or `AnnotationKind`; it imports the real AST
definitions and keeps only Parse-local lightweight node classes that still
diverge from the real AST class layout. The local `Annotation` scaffold now uses
the real Utils `OverflowStrategy` type rather than a Parse-local copy.
`ParserTypes.cj` no longer owns local copies of `GlobalOptions`, `OutputMode`,
`InteropLanguage`, `BackendType`, or `Triple`; those names are public aliases of
the real Option package types.

## Implemented In This Pass

- Removed `ParseScaffold.cj`.
- Added 35 `.cj` files under `packages/parse/src`, following the C++ Parse file
  breakdown and keeping all source files in package `cangjie_compiler::parse`.
- Implemented a local lexer for Cangjie keywords, identifiers, raw identifiers,
  literals, nested block comments, line comments, delimiters, and operators.
- Implemented parser entry points for `ParseTopLevel`, `ParseDecl`, `ParseExpr`,
  `ParseExprLibast`, `ParseType`, `ParsePattern`, annotation argument parsing,
  macro-node parsing, comment attachment, and public parser state helpers.
- Implemented top-level package/import/features handling, declaration parsing
  for functions, macros, main, variables, type aliases, class/interface/struct/
  enum/extend declarations, constructors, and properties.
- Implemented Pratt-style expression parsing with unary, binary, assignment,
  range, `is`/`as`, calls, member access, subscripts, tuples, arrays, blocks,
  `if`, `match`, `try`, loops, returns, jumps, throw/perform/resume, spawn,
  synchronized, quote, lambda, and macro expansion expressions.
- Implemented type parsing for primitive, reference, qualified, generic,
  optional, constant, VArray, parenthesized, tuple, function, and `This` types.
- Implemented pattern parsing for wildcard, variable, constant, tuple, enum, and
  type patterns.
- Implemented modifier conflict and attribute mapping rules, AST range checking,
  and deterministic structural hashing helpers.
- Continued the port by replacing the remaining Parse self-host TODO markers
  with concrete CJMP common/specific validation and Java/Objective-C/foreign
  annotation validation based on the C++ `ParseCJMPDecl.cpp` and
  `NativeFFI/*ParserImpl.cpp` behavior available in the local compatibility
  model.
- Added declaration attribute tracking, generic/common/specific/default/interop
  attributes, member ownership propagation, and top-level declaration
  finalization so CJMP and FFI checks run after class-like members have their
  enclosing declaration recorded.
- Continued grammar parity by adding the `LetPatternDestructor` expression node
  and parser path for `let pattern <- expr` conditions, parsing `unsafe { ... }`
  as a block expression instead of a declaration modifier sequence, and matching
  the C++ operator-function flow where `operator` is a function modifier and the
  overloadable token (`+`, `[]`, `()`, `>>`, `>=`, and the supported operator
  set) becomes the function identifier and recorded operator kind.
- Added match-case pattern guard parsing (`case ... where expr =>`), recorded
  case `|` positions, added for-in `where` guard fields and parsing, fixed
  `perform` to build a real `PERFORM_EXPR`, and matched the C++ `resume with`
  / `resume throwing` operand parsing shape.
- Added C++-shaped try expression storage and parsing for try-with-resources,
  resource comma/paren positions, resource variable declarations, catch paren
  positions, exception type patterns, `handle` clauses, effect type patterns,
  handler blocks, and `finally` positions.
- Added optional suffix expression nodes and postfix parsing for optional
  chaining forms such as `expr?.member`, `expr?()`, `expr?[index]`, and
  optional trailing-closure starts, preserving the C++ `hasQuestSuffix` marker
  on the resulting chain.
- Added selectorless match parsing with `MatchCaseOther` nodes for
  `match { case expr => ... }`, including wildcard expression cases, expression
  case bodies, and the `matchMode` split used by the C++ AST.
- Added atom parsing for primitive type conversion expressions, primitive type
  static member bases such as `Int64.foo`, and `VArray<T, $n>(...)` /
  `VArray<T, $n>{ ... }` value-array expressions with C++-shaped AST nodes.
- Added a distinct `IncOrDecExpr` node for postfix `++`/`--`, and aligned
  `spawn` / `synchronized` expression storage with the C++ parser's argument,
  mutex, keyword, and delimiter positions.
- Added builtin annotation-lambda recognition so `@Anno { ... }` parses as a
  lambda expression where the C++ parser accepts annotation lambdas, including
  the `spawn` task position.
- Continued the de-isolation pass by importing real Basic `Position`, `Range`,
  `Source`, and `SourceManager`; real Lex `Token`, `TokenKind`, `StringPart`,
  `TokenVecMap`, and token helper tables; and real AST `ASTKind`, `Attribute`,
  and `AnnotationKind`.
- Replaced the simplified modifier allowance/conflict/warning placeholders with
  C++-shaped rule mappings from `ParserModifierRules.cpp`, including top-level,
  class/interface/struct/enum/extend body, constructor, property, package, and
  interface warning rules. `INOUT` and `const` now follow the C++ mapping:
  `INOUT` has no AST attribute, and `const` is carried by declaration fields.
- Continued de-isolating compiler-wide option state by replacing Parse-local
  compatibility copies of `GlobalOptions`, `OutputMode`, `InteropLanguage`,
  `BackendType`, and `Triple` with real imports from `cangjie_compiler::option`.
  CJMP common-mode checks now use the real Option `OutputModeIndex` helper when
  comparing against `OutputMode.CHIR`.
- Reworked feature directive parsing to match `ParseFeatures.cpp` more closely:
  `features` now expects a `{ ... }` set instead of the previous parenthesized
  shape, records left/right brace positions, comma positions, dotted feature
  identifiers, feature annotations, and broken-node state for malformed sets.
  The local `FeatureId`, `FeaturesSet`, and `FeaturesDirective` scaffolding now
  mirrors the real AST/C++ field layout for feature directives.
- Reworked builtin annotation parsing toward `ParseAnnotations.cpp`: builtin
  annotations now use square-bracket argument lists, `@When[...]` stores a
  condition expression, `@Attribute[...]` stores attribute tokens and comma
  positions, overflow annotations store a real Utils `OverflowStrategy`, and
  `@Deprecated[...]` validates literal argument names/types. Custom annotations
  parse `@`/`@!`, preserve compile-time visibility, accept qualified names via
  `baseExpr`, and use square-bracket arguments. Macro-call classification now
  excludes builtin annotations and expression macro calls no longer accept
  `@!`, matching the C++ split more closely.

## Remaining Work

- Replace the remaining Parse-local AST node classes, parser diagnostics, and
  parser lexer implementation with real sibling package APIs where their public
  surfaces are sufficiently complete.
- Feature raw-identifier diagnostics still depend on finishing lexer
  de-isolation: the local Parse lexer strips backticks before parser recovery,
  while the real Lex lexer preserves raw identifier spelling in `Token.Value()`.
- Annotation diagnostics are still message-based through the local Parse
  diagnostic shim; converting them to real Basic diagnostic IDs remains part of
  the broader diagnostics de-isolation.
- Audit grammar and diagnostic parity against the full C++ Parse test corpus;
  the current parser is substantial and compiling, but not a complete faithful
  replacement for all 17k+ lines of C++ parser behavior.
- Remaining Parse self-host markers: 0.
