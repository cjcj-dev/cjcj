package cangjie_compiler::modules

import std.collection.*
import cangjie_compiler::ast.Decl as ASTDecl
import cangjie_compiler::ast.File as ASTFile
import cangjie_compiler::ast.Node as ASTNode
import cangjie_compiler::ast.Package as ASTPackage
import cangjie_compiler::ast.PackageDecl as ASTPackageDecl

public interface SemaCjoManager {
}

public interface SemaImportManager {
    func GetAllImportedPackages(includeMacroPkg: Bool): ArrayList<ASTPackageDecl>
    func GetPackageDecl(fullPackageName: String): Option<ASTPackageDecl>
    func GetPackage(fullPackageName: String): Option<ASTPackage>
    func GetImportedDecl<T>(fullPackageName: String, name: String): Option<T> where T <: ASTDecl
    func GetAstDecl<T>(name: String): Option<T> where T <: ASTDecl
    func GetCoreDecl<T>(name: String): Option<T> where T <: ASTDecl
    func GetSyncDecl(name: String): Option<ASTDecl>
    func GetImportedPackageDecl(node: ASTNode, packageName: String): (Option<ASTPackageDecl>, Bool)
    func GetAllImportedDecls(file: ASTFile): ArrayList<ASTDecl>
    func GetImportedDeclsByName(file: ASTFile, name: String): ArrayList<ASTDecl>
    func GetPackageMembersByName(pkg: ASTPackage, name: String): ArrayList<ASTDecl>
}
