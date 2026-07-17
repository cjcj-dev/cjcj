package cjcj::modules

import std.collection.*
import cjcj::ast.Decl as ASTDecl
import cjcj::ast.ExtendDecl as ASTExtendDecl
import cjcj::ast.File as ASTFile
import cjcj::ast.ImportSpec as ASTImportSpec
import cjcj::ast.Node as ASTNode
import cjcj::ast.Package as ASTPackage
import cjcj::ast.PackageDecl as ASTPackageDecl
import cjcj::ast.Ty as ASTTy
import cjcj::basic.DiagnosticBuilder

public interface SemaCjoManager {
    func GetPackageNameByImport(importSpec: ASTImportSpec): String
    func GetPackageMembers(fullPackageName: String): HashMap<String, ArrayList<ASTDecl>>
}

public interface SemaImportManager {
    func ExportDeclsWithContent(saveFileWithAbsPath: Bool, pkg: ASTPackage): Unit
    func GetCjoManager(): SemaCjoManager
    func GetAllImportedPackages(includeMacroPkg: Bool): ArrayList<ASTPackageDecl>
    func GetPackageDecl(fullPackageName: String): Option<ASTPackageDecl>
    func GetPackage(fullPackageName: String): Option<ASTPackage>
    func GetDepPkgCjoPaths(): HashMap<String, String>
    func GetImportedDecl<T>(fullPackageName: String, name: String): Option<T> where T <: ASTDecl
    func GetAstDecl<T>(name: String): Option<T> where T <: ASTDecl
    func GetCoreDecl<T>(name: String): Option<T> where T <: ASTDecl
    func GetSyncDecl(name: String): Option<ASTDecl>
    func GetImportedPackageDecl(node: ASTNode, packageName: String): (Option<ASTPackageDecl>, Bool)
    func GetAllImportedDecls(file: ASTFile): ArrayList<ASTDecl>
    func GetUsedMacroDecls(file: ASTFile): HashMap<String, ArrayList<ASTDecl>>
    func GetImportedDeclsByName(file: ASTFile, name: String): ArrayList<ASTDecl>
    func GetPackageMembersByName(pkg: ASTPackage, name: String): ArrayList<ASTDecl>
    func ExportDeclsWithContent(saveFileWithAbsPath: Bool, pkg: ASTPackage): Unit
    func GetImportsOfDecl(fullPackageName: String): HashMap<ASTDecl, ArrayList<ASTImportSpec>>
    func IsExtendAccessible(file: ASTFile, ed: ASTExtendDecl, builder: Option<DiagnosticBuilder>): Bool
    func IsExtendMemberAccessible(file: ASTFile, member: ASTDecl, baseTy: ASTTy,
        builder: Option<DiagnosticBuilder>): Bool
}
