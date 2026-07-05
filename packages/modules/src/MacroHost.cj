package cangjie_compiler::modules

import std.collection.*
import cangjie_compiler::ast.Decl as ASTDecl
import cangjie_compiler::ast.File as ASTFile
import cangjie_compiler::ast.Package as ASTPackage
import cangjie_compiler::ast.PackageDecl as ASTPackageDecl
import cangjie_compiler::basic.DiagnosticEngine
import cangjie_compiler::basic.SourceManager
import cangjie_compiler::option.GlobalOptions

// Macro-expansion host injection surface (design MACRO_INTEGRATION_DESIGN Option B).
// The macro package operates over these interfaces instead of a private compat
// CompilerInstance; the live frontend implements them so macro expansion runs on the
// real compiler state. Macro-only importManager methods live here; the resolve-face
// (GetImportedPackageDecl/GetImportedDeclsByName/GetPackageMembersByName) is reused from
// SemaImportManager and not redeclared.
public interface MacroHostImportManager {
    func GetImportedPkgsForMacro(): ArrayList<ASTPackage>
    func GetImportedStdMacroPackages(): ArrayList<String>
    func GetSearchPath(): ArrayList<String>
    func GetAllImportedPackages(includeMacroPkg: Bool): ArrayList<ASTPackageDecl>
    func AddUsedMacroDecls(file: ASTFile, decl: ASTDecl): Unit
}

public interface MacroHost {
    func GetDiag(): DiagnosticEngine
    func GetGlobalOptions(): GlobalOptions
    prop importManager: MacroHostImportManager
    func GetSourceManager(): SourceManager
}
