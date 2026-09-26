package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::modules.SemaImportManager
import cjcj::sema.TypeManager

private class CtorPair {
    public let user: FuncDecl
    public let generated: FuncDecl

    public init(user: FuncDecl, generated: FuncDecl) {
        this.user = user
        this.generated = generated
    }
}

private class ClassFuncPair {
    public let owner: ClassDecl
    public let wrappingFunc: FuncDecl

    public init(owner: ClassDecl, wrappingFunc: FuncDecl) {
        this.owner = owner
        this.wrappingFunc = wrappingFunc
    }
}

private class ClassVarPair {
    public let owner: ClassDecl
    public let field: VarDecl

    public init(owner: ClassDecl, field: VarDecl) {
        this.owner = owner
        this.field = field
    }
}

private class SuperCtorNativeList {
    public let funcs = ArrayList<Option<FuncDecl>>()
}

public class AfterTypeCheckContext {
    public let importManager: SemaImportManager
    public let typeManager: TypeManager
    public let pkg: Package
    public let hasMirrorOrImpl: Bool
    private let javaMirrors: ArrayList<ClassLikeDecl>
    private let javaImplReferenceWrappers: ArrayList<ClassDecl>
    private let javaImplRegistryCompanions: ArrayList<ClassDecl>
    private let ctorPairs: ArrayList<CtorPair> = ArrayList<CtorPair>()
    private let wrappingCtors: ArrayList<ClassFuncPair> = ArrayList<ClassFuncPair>()
    private let registryFields: ArrayList<ClassVarPair> = ArrayList<ClassVarPair>()
    private let generatedDecls: ArrayList<Decl> = ArrayList<Decl>()
    private let javaImplUserCtorToNativeFuncs = HashMap<FuncDecl, SuperCtorNativeList>()
    private let javaImplUserCtorToOriginalSuperCall = HashMap<FuncDecl, CallExpr>()

    public init(importManager: SemaImportManager, typeManager: TypeManager, pkg: Package, hasMirrorOrImpl: Bool) {
        this.importManager = importManager
        this.typeManager = typeManager
        this.pkg = pkg
        this.hasMirrorOrImpl = hasMirrorOrImpl
        javaMirrors = GetJavaMirrors(pkg)
        javaImplReferenceWrappers = GetJavaImpls(pkg)
        javaImplRegistryCompanions = GetJavaImplRegistryCompanions(pkg)
    }

    public func GetJavaMirrors(): ArrayList<ClassLikeDecl> {
        return javaMirrors
    }

    public func GetJavaImplReferenceWrappers(): ArrayList<ClassDecl> {
        return javaImplReferenceWrappers
    }

    public func GetJavaImplRegistryCompanions(): ArrayList<ClassDecl> {
        return javaImplRegistryCompanions
    }

    public func GetJavaImplRegistryCompanion(referenceWrapper: ClassDecl): Option<ClassDecl> {
        let name = GetImplRegistryCompanionClassName(referenceWrapper)
        for (companion in javaImplRegistryCompanions) {
            if (companion.identifier.Val() == name) {
                return Some(companion)
            }
        }
        return None
    }

    public func CacheJavaImplWrappingConstructor(refWrapper: ClassDecl, wrappingCtor: FuncDecl): Unit {
        wrappingCtors.add(ClassFuncPair(refWrapper, wrappingCtor))
    }

    public func GetJavaImplWrappingConstructor(refWrapper: ClassDecl): Option<FuncDecl> {
        for (pair in wrappingCtors) {
            if (pair.owner == refWrapper) {
                return Some(pair.wrappingFunc)
            }
        }
        return None
    }

    public func CacheJavaImplRegistryCompanionReferenceField(refWrapper: ClassDecl, field: VarDecl): Unit {
        registryFields.add(ClassVarPair(refWrapper, field))
    }

    public func CacheJavaImplReferenceWrapperConstructorsPair(userDefinedCtor: FuncDecl, generatedCtor: FuncDecl): Unit {
        ctorPairs.add(CtorPair(userDefinedCtor, generatedCtor))
    }

    public func GetJavaImplUserDefinedConstructors(refWrapper: ClassDecl): ArrayList<FuncDecl> {
        let ctors = ArrayList<FuncDecl>()
        for (member in refWrapper.GetMemberDecls()) {
            if (let Some(fd) <- (member as FuncDecl)) {
                if (fd.TestAttr(Attribute.CONSTRUCTOR) && !fd.TestAttr(Attribute.COMPILER_ADD)) {
                    ctors.add(fd)
                }
            }
        }
        return ctors
    }

    public func CacheJavaImplSuperCtorArgNativeFunc(ctor: FuncDecl, nativeFunc: Option<FuncDecl>): Unit {
        if (javaImplUserCtorToNativeFuncs.get(ctor).isNone()) {
            javaImplUserCtorToNativeFuncs[ctor] = SuperCtorNativeList()
        }
        javaImplUserCtorToNativeFuncs.get(ctor).getOrThrow().funcs.add(nativeFunc)
    }

    public func GetJavaImplSuperCtorArgNativeFuncs(ctor: FuncDecl): ArrayList<Option<FuncDecl>> {
        if (javaImplUserCtorToNativeFuncs.get(ctor).isNone()) {
            javaImplUserCtorToNativeFuncs[ctor] = SuperCtorNativeList()
        }
        return javaImplUserCtorToNativeFuncs.get(ctor).getOrThrow().funcs
    }

    public func HasDesugaredJavaImplSuperConstructorCall(userCtor: FuncDecl): Bool {
        return javaImplUserCtorToNativeFuncs.get(userCtor).isSome()
    }

    public func CacheJavaImplSuperCtorCall(ctor: FuncDecl, call: CallExpr): Unit {
        javaImplUserCtorToOriginalSuperCall[ctor] = call
    }

    public func GetJavaImplSuperCtorCall(ctor: FuncDecl): CallExpr {
        return javaImplUserCtorToOriginalSuperCall.get(ctor).getOrThrow()
    }

    public func AddGeneratedDecl(decl: Decl): Unit {
        generatedDecls.add(decl)
    }

    public func FlushGeneratedDecls(): Unit {
        for (decl in generatedDecls) {
            if (let Some(file) <- decl.curFile) {
                file.decls.add(decl)
            }
        }
        generatedDecls.clear()
    }
}
