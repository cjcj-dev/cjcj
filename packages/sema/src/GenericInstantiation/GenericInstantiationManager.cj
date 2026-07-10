package cjcj::sema.GenericInstantiation

import std.collection.*
import cjcj::ast.*
import cjcj::sema.{CompilerInstance, GenericInfo}
import cjcj::sema.Test.TestManager

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
