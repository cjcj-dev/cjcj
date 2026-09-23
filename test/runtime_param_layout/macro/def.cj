// f1 macro-definition package: identity decl macro.
// Exercises MacroExpansion Collect -> Evaluate -> ReplaceAST on the simplest
// path (single macro call, single expanded decl). C++: MacroExpansion.cpp
// Execute/CollectMacros/ReplaceAST; MacroEvaluation returns input unchanged.
macro package f1def

import std.ast.*

// Returns the annotated declaration's tokens unchanged.
public macro Keep(input: Tokens): Tokens {
    input
}
