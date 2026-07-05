// f4 macro-definition package: attribute macro (two-parameter form).
// An attribute macro receives the bracketed attribute tokens plus the annotated
// declaration tokens. Exercises the C++ attribute path
// (MacroEvaluation::CheckAttrTokens; MacroCall hasAttr / attrs) and the
// (attr, input) invocation shape.
macro package f4def

import std.ast.*

// Ignores the attribute payload and returns the decl unchanged.
public macro Attr(attr: Tokens, input: Tokens): Tokens {
    quote($input)
}
