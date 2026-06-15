# Parse Port Status

Date: 2026-06-16

Build: `cjpm build` passes.

## Summary

Replaced the Parse scaffold with a multi-file Cangjie package that mirrors the C++
Parse component split. The package now has local parser-facing source positions,
tokens, diagnostics, AST node shapes, a lexer, parser state, top-level parsing,
declaration parsing, expression parsing, type parsing, pattern parsing, imports,
annotations, modifiers, features, macro-call capture, quote capture, comment
collection, modifier-rule queries, AST checking, AST hashing, CJMP entry wiring,
and Java/ObjC native FFI parser checks.

## Important Blocker

`packages/parse/cjpm.toml` currently has no dependencies, and this task forbids
editing manifests. A faithful production Parse port must import the real
`cangjie_compiler::lex`, `cangjie_compiler::ast`, and
`cangjie_compiler::basic` packages. Without those manifest dependencies, this
pass keeps a local compatibility layer so the workspace still compiles. That
means the parser is behavior-bearing but not yet wired to the real sibling
package public APIs.

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

## Remaining Work

- Replace the local compatibility layer with the real Basic/Lex/AST APIs when
  manifest edits are allowed.
- Audit grammar and diagnostic parity against the full C++ Parse test corpus;
  the current parser is substantial and compiling, but not a complete faithful
  replacement for all 17k+ lines of C++ parser behavior.
- Remaining Parse self-host markers: 0.
