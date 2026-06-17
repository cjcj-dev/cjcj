# Parse Port Status

Date: 2026-06-18

Build: `cjpm build` passes.

## Summary

Replaced the Parse scaffold with a multi-file Cangjie package that mirrors the C++
Parse component split. The package now imports real Basic positions/source
manager, real Lex tokens/token tables, real AST kind/attribute/annotation
enums, real Utils overflow strategy helpers, and real Option compiler
configuration types. It still has local
parser-facing diagnostics, AST node shapes, parser state, top-level parsing,
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
`MacroInvocation` now reuses the real Basic `MacroCallDiagInfo` for macro
origin/identifier diagnostic mapping while the surrounding macro node classes
remain Parse-local until the full AST node hierarchy can be replaced.
`Lexer.cj` has been removed from Parse. The parser now imports and constructs the
real `cangjie_compiler::lex.Lexer`, with a real Basic diagnostic engine reserved
for lexing while the remaining parser-facing diagnostics still use the local
Parse shim.

## Implemented In This Pass

- Removed `ParseScaffold.cj`.
- Added 35 `.cj` files under `packages/parse/src`, following the C++ Parse file
  breakdown and keeping all source files in package `cangjie_compiler::parse`.
- Initially implemented a local lexer for Cangjie keywords, identifiers, raw
  identifiers, literals, nested block comments, line comments, delimiters, and
  operators; that scanner has since been deleted in favor of the real Lex
  package.
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
- Reworked package/import parsing toward `Parser.cpp` and `ParseImports.cpp`:
  package headers now record macro-package state, `::` organization separators,
  separator positions, package-name fields, raw-identifier errors, module-name
  derivation, and package-name length checks. Import specs now model C++ import
  kinds (`single`, `alias`, `all`, `multi`), `::`, prefix separator positions,
  `as` positions, brace/comma positions, `import a.{b, c as d}` parsing,
  import-all parsing, import annotation validation, multi-import desugaring, and
  import package-name length checks.
- Reworked top-level parsing toward the C++ `Parser.cpp` preamble shape:
  `features? package? import* decl*` is now parsed in distinct phases instead
  of allowing package/import/features repeatedly anywhere, import annotations
  are preserved for the first declaration when they are not followed by an
  import, modifiers before non-package declarations are no longer consumed by
  the package probe, late package/import/features forms are diagnosed, top-level
  declarations get `Attribute.GLOBAL`, and `macro package` now diagnoses public
  non-macro declarations.
- Deepened atom/declaration parity with C++ `ParseAtom.cpp` and
  `ParseDecl.cpp`: bare `{...}` atoms now enter the lambda parser instead of
  becoming block expressions, lambda parameter parsing uses C++-style lookahead
  so tail closures with omitted `=>` keep their body tokens, `if`/`while`
  conditions validate that `let pattern <- expr` subconditions are only joined
  with `&&`/`||`, call arguments record `inout`, and negative numeric/rune-byte
  literals are preserved in constant patterns.
- Added local C++-shaped string interpolation scaffolding: lexer string-part
  records are consumed for `${...}` holes, `LitConstExpr` can own a
  `StrInterpolationExpr`, and each interpolation hole is reparsed as a block
  via a nested parser using the hole source position.
- Added class/struct primary-constructor and class finalizer parsing paths:
  class-like body parsing now tracks the enclosing primary declaration name,
  recognizes `C(...)`/near-match primary constructors only in class/struct
  scope, builds `PrimaryCtorDecl` with constructor/primary/in-classlike or
  in-struct attributes, and parses `~init` finalizers with parameter/return-type
  diagnostics.
- Tightened `VArray` type parsing toward the C++ grammar by requiring the
  second type argument to use the `$` constant-size form (`VArray<T, $n>`) and
  diagnosing missing comma, missing `$`, or non-integer size literals.
- Continued the de-isolation pass by deleting the Parse-local scanner and
  switching parser tokenization, lookahead, string-part extraction, comments, and
  token-stream access to the real Lex package. Comment attachment now adapts the
  real Lex comment array into the existing `TokenVecMap`, and parser line counts
  are recorded as tokens are consumed so `GetLineNum` no longer depends on a
  cached local token list.
- Added C++-shaped parser combinator helpers from `ParserUtils.cpp`:
  adjacent-token `SeeingCombinator`, `SeeingTokenAndCombinator`,
  `SkipCombinator`, `SkipCombinedDoubleArrow`, `SkipCombinedBackarrow`,
  `LookupSeenCombinator`, and `SkipAmbiguousToken`. Match cases, selectorless
  match cases, lambda arrows, let-pattern back arrows, operator overload names,
  optional suffix checks, and Pratt expression parsing now handle the same
  adjacent split-token forms (`=>`, `<-`, `>>`, `>=`, `>>=`, `??`) that the C++
  parser accepts during macro/token-stream parsing and recovery.
- Replaced the local hand-maintained expression precedence table with the real
  Lex `TokenPrecedence` table while preserving the local Pratt parser's explicit
  assignment precedence. This restores missing C++ precedence for shift,
  pipeline, composition, exponent, range, comparison, and logical operators.
- Deepened quote parsing toward `ParseQuote.cpp`: `quote(...)` now records the
  quote and delimiter positions, enters/exits the real lexer quote mode, emits
  `TokenPart` expression nodes for literal token runs, parses `$identifier` as a
  quote-dollar reference expression, parses `$(expr)` by temporarily restoring
  normal lexer mode, and removed the non-C++ brace quote form.
- Deepened macro parsing toward `ParseMacro.cpp`: macro invocations now carry
  C++-shaped name, delimiter, attr/arg, parent/decl, and diagnostic fields; parse
  dotted macro names and `@!`; preserve macro attributes separately from input
  args; record origin positions with the real Basic `MacroCallDiagInfo`; handle
  escaped macro-call tokens; and capture no-parentheses declaration input by
  reparsing the following declaration into `invocation.decl` while mirroring its
  consumed tokens in `args`/legacy `tokens`.
- Reworked macro declarations away from the ordinary function path: `macro`
  declarations now enable `MACRO_FUNC`, reject builtin macro/annotation names,
  require `public`, require a macro package when a current file is available,
  validate one or two `Tokens` parameters, synthesize a default `Tokens` return
  type, and parse bodies in `MACRO_BODY` scope.
- Deepened `ParseType.cpp` parity: local type nodes now carry C++/AST-shaped
  source metadata for comma, colon, type-parameter name/raw state, option
  question-counts, and qualified generic delimiters. Type parsing now accepts
  contextual-keyword type names, records named tuple/function type parameters,
  diagnoses duplicate and mixed named/unnamed parameter lists, handles
  `() -> T`, multiple leading `?`, `onlyRef`, qualified generic delimiter
  positions, unexpected post-type arrows, and VArray comma/source tracking.
- Deepened declaration/pattern parsing toward `ParseDecl.cpp` and
  `ParsePattern.cpp`: `VarWithPatternDecl` now derives from
  `VarDeclAbstract`, uses the real AST field name `irrefutablePattern`, and
  participates in child traversal with its pattern, type annotation, and
  initializer. `let`/`var`/`const` dispatch now follows the C++ split between
  ordinary identifier declarations and wildcard/tuple/enum-looking pattern
  declarations, preserving `let x: T` as `VarDecl`. Pattern declarations reuse
  `ParseTypeAndExpr`, check C++-shaped missing initializer/type cases, reject
  declaration patterns in class/struct bodies, and enum-pattern starts now
  consume qualified names and generic argument lists via the shared
  `SeeingIdentifierAndTargetOp` helper.
- Deepened pattern parsing further toward `ParsePattern.cpp`: pattern constants
  now include split-token unit literals `(` `)` for macro/token-stream inputs,
  wildcard type patterns (`_: T`) are parsed as `TypePattern`, bare identifiers
  in non-declaration patterns now produce `VarOrEnumPattern`, tuple patterns
  diagnose illegal nested `|` patterns and single-field tuple patterns, and
  tuple nodes now preserve C++-shaped left/right brace position aliases.
- Audited `ScopeKind` and `ExprKind` de-isolation against the real AST package.
  The real AST enums currently expose an additional `UNKNOWN` variant that
  breaks downstream exhaustive matches through Parse's public API, so Parse
  keeps its local subset for now and uses explicit comparison helpers internally
  to prepare for a future API-aligned swap.

## Remaining Work

- Replace the remaining Parse-local AST node classes and parser diagnostics with
  real sibling package APIs where their public surfaces are sufficiently
  complete.
- Replace Parse-local `ScopeKind` and `ExprKind` only after downstream users can
  accept the real AST package's additional `UNKNOWN` variants, or after the AST
  package exposes a Parse-compatible subset.
- Top-level recovery still uses local message diagnostics rather than the exact
  C++ diagnostic IDs, suggestions, parser-scope reset objects, and bracket-stack
  cleanup.
- Lex diagnostics now flow through a Basic diagnostic engine owned by
  `ParserImpl`, while parser diagnostics are still message-based through the
  local Parse diagnostic shim. Converting parser diagnostics to real Basic
  diagnostic IDs remains the next major de-isolation step.
- Macro expansion parsing still lacks the full C++ parameter-macro and
  expression-scope no-parentheses reparsing behavior, exact macro diagnostic IDs,
  and interpolation string origin-position remapping.
- Type parsing still uses local message diagnostics and simplified recovery in
  several malformed generic/empty-parenthesis cases instead of the exact C++
  diagnostic IDs and parser cleanup paths.
- Enum-pattern constructors still use local lightweight identifier-piece
  storage rather than the full C++ expression-backed constructor node, so target
  binding/type-argument diagnostics remain approximate until Parse-local pattern
  nodes are replaced by real AST nodes.
- Audit grammar and diagnostic parity against the full C++ Parse test corpus;
  the current parser is substantial and compiling, but not a complete faithful
  replacement for all 17k+ lines of C++ parser behavior.
- Remaining Parse self-host markers: 0.
