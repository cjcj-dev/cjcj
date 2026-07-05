// f5 macro-definition package: used only through a macro call at the use site.
// Backs the unused-import-suppression check (the IM3 focused gate): when an
// imported package is referenced ONLY by expanding one of its macros, the
// compiler must NOT report the import as unused. C++ records this via
// MacroEvaluation::SaveUsedMacros -> importManager->AddUsedMacroDecls
// (MacroEvaluation.cpp:737-746), consumed by CheckUnusedImport.
macro package f5def

import std.ast.*

public macro TwoFns(input: Tokens): Tokens {
    quote(
        func gen_a(): Int64 { 1 }
        func gen_b(): Int64 { 2 }
    )
}
