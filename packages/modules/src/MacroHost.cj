package cangjie_compiler::modules

import std.collection.*
import cangjie_compiler::ast.Decl as ASTDecl
import cangjie_compiler::ast.File as ASTFile
import cangjie_compiler::ast.Package as ASTPackage
import cangjie_compiler::basic.DiagnosticEngine
import cangjie_compiler::basic.SourceManager
import cangjie_compiler::option.GlobalOptions

// Macro-expansion host injection surface (design MACRO_INTEGRATION_DESIGN Option B).
// The macro package operates over these interfaces instead of a private compat
// CompilerInstance; the live frontend implements them so macro expansion runs on the
// real compiler state. Only the macro-exclusive importManager methods are declared here;
// the resolve-face (GetImportedPackageDecl/GetImportedDeclsByName/GetPackageMembersByName)
// and GetAllImportedPackages are inherited from SemaImportManager, not redeclared, so the
// live ImportManager implements a single surface.
public interface MacroHostImportManager <: SemaImportManager {
    func GetImportedPkgsForMacro(): ArrayList<ASTPackage>
    func GetImportedStdMacroPackages(): ArrayList<String>
    func GetSearchPath(): ArrayList<String>
    func AddUsedMacroDecls(file: ASTFile, decl: ASTDecl): Unit
}

public interface MacroHost {
    func GetDiag(): DiagnosticEngine
    func GetGlobalOptions(): GlobalOptions
    func GetRuntimeLibPath(): String
    prop importManager: MacroHostImportManager
    func GetSourceManager(): SourceManager
}
