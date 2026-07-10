package cangjie_compiler::sema.GenericInstantiation

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.{CompilerInstance, GenericInfo}
import cangjie_compiler::sema.Test.TestManager

public class GenericInstantiationManager {
    private let impl: GenericInstantiationManagerImpl

    public init(ci: CompilerInstance, testManager: TestManager) {
        impl = GenericInstantiationManagerImpl(ci)
        impl.SetTestManager(testManager)
    }

    public func GenericInstantiatePackage(pkg: Package, resetGlobalState!: Bool = true): Unit {
        impl.GenericInstantiatePackage(pkg, resetGlobalState: resetGlobalState)
    }

    public func GetInstantiatedDeclWithGenericInfo(genericInfo: GenericInfo, pkg: Package): Option<Decl> {
        return impl.GetInstantiatedDeclWithGenericInfo(genericInfo, pkg)
    }

    public func GetInstantiatedDecls(genericDecl: Decl): ArrayList<Decl> {
        return impl.GetInstantiatedDecls(genericDecl)
    }

    public func ResetGenericInstantiationStage(): Unit {
        impl.ResetGenericInstantiationStage()
    }

    public func GetAllGenericToInsDecls(): ArrayList<(Decl, ArrayList<Decl>)> {
        return impl.GetAllGenericToInsDecls()
    }
}
