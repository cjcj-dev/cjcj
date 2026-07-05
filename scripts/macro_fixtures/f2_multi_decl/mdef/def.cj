// f2 macro-definition package: decl macro expanding to MULTIPLE decls.
// Exercises MacroExpansion.ReplaceDecls / replaceDeclVector, which erases the
// macro node and splices several generated decls into the package decl vector
// (C++ MacroExpansion.cpp:232-253).
macro package f2def

import std.ast.*

// Expands one annotated placeholder into two top-level functions.
public macro TwoFns(input: Tokens): Tokens {
    quote(
        func gen_a(): Int64 { 1 }
        func gen_b(): Int64 { 2 }
    )
}
