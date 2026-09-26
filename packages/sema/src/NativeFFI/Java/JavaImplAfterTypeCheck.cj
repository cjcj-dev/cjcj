package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{CreateThisRef, InteropLibBridge, JAVA_IMPL_ENTITY_ARG_NAME_IN_GENERATED_CTOR, WithinFile}
import cjcj::utils.CJC_ASSERT

public class GenerateJavaImplApiStub {
    private let typeManager: TypeManager
    private let ilib: InteropLibBridge
    private let jni: JniBridge

    public init(typeManager: TypeManager, ilib: InteropLibBridge, jni: JniBridge) {
        this.typeManager = typeManager
        this.ilib = ilib
        this.jni = jni
    }

    private func CreateWrappingConstructorStub(refWrapper: ClassDecl): Option<FuncDecl> {
        let javaEntityDecl = ilib.GetJavaEntityDecl()
        if (let None <- javaEntityDecl) {
            return None
        }
        let entity = javaEntityDecl.getOrThrow()
        let paramList = CreateFuncParamList(ArrayList<FuncParam>(), None)
        paramList.EnableAttr(Attribute.COMPILER_ADD)
        let entityParam = CreateFuncParam(JAVA_IMPL_ENTITY_ARG_NAME_IN_GENERATED_CTOR, Some(CreateRefType(entity)), None,
            entity.GetTy())
        paramList.params.add(entityParam)
        let regIdParam = jni.CreateRegistryIdParam()
        paramList.params.add(regIdParam)
        let paramTys = ArrayList<Ty>()
        paramTys.add(entityParam.GetTy().getOrThrow())
        paramTys.add(regIdParam.GetTy().getOrThrow())
        let retTy = refWrapper.GetTy().getOrThrow()
        let ctorTy = typeManager.GetFunctionTy(paramTys.toArray(), retTy)
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(paramList)
        let block = CreateBlock(ArrayList<Node>(), Some(retTy))
        let ctorFuncBody = CreateFuncBody(paramLists, Some(CreateRefType(refWrapper)), Some(block), Some(ctorTy))
        let ctor = CreateFuncDecl("init", Some(ctorFuncBody), Some(ctorTy))
        ctor.funcBody.getOrThrow().funcDecl = ctor
        ctor.EnableAttr(Attribute.CONSTRUCTOR)
        return Some(ctor)
    }

    public func InsertWrappingConstructor(refWrapper: ClassDecl): Option<FuncDecl> {
        let stub = CreateWrappingConstructorStub(refWrapper)
        if (let None <- stub) {
            return None
        }
        let ctor = WithinFile<FuncDecl>(stub.getOrThrow(), refWrapper.curFile)
        ctor.outerDecl = Some(refWrapper)
        ctor.fullPackageName = refWrapper.fullPackageName
        ctor.moduleName = refWrapper.moduleName
        if (let Some(body) <- refWrapper.body) {
            ctor.begin = body.begin
            ctor.end = body.begin
        }
        ctor.funcBody.getOrThrow().parentClassLike = Some(refWrapper)
        ctor.EnableAttr(Attribute.IN_CLASSLIKE)
        ctor.EnableAttr(Attribute.PUBLIC)
        refWrapper.GetMemberDecls().add(ctor)
        return Some(ctor)
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (refWrapper in ctx.GetJavaImplReferenceWrappers()) {
            if (let Some(ctor) <- InsertWrappingConstructor(refWrapper)) {
                ctx.CacheJavaImplWrappingConstructor(refWrapper, ctor)
            }
        }
    }
}

public class GenerateInJavaImplRegistryCompanion {
    private let typeManager: TypeManager
    private let ilib: InteropLibBridge

    public init(typeManager: TypeManager, ilib: InteropLibBridge) {
        this.typeManager = typeManager
        this.ilib = ilib
    }

    private func GenerateConstructor(companion: ClassDecl): Option<FuncDecl> {
        let file = companion.curFile
        let javaEntityDecl = ilib.GetJavaEntityDecl()
        if (let None <- javaEntityDecl) {
            return None
        }
        let entityDecl = javaEntityDecl.getOrThrow()
        let entityParam = CreateFuncParam(JAVA_IMPL_ENTITY_ARG_NAME_IN_GENERATED_CTOR, Some(CreateRefType(entityDecl)),
            None, entityDecl.GetTy())
        let entityParamRef = WithinFile<RefExpr>(CreateRefExpr(entityParam), file)
        let params = ArrayList<FuncParam>()
        params.add(entityParam)
        let paramList = CreateFuncParamList(params, None)
        paramList.EnableAttr(Attribute.COMPILER_ADD)
        let paramLists = ArrayList<FuncParamList>()
        paramLists.add(paramList)
        let companionTy = companion.GetTy().getOrThrow()
        let entityTy = entityDecl.GetTy().getOrThrow()
        let ctorTy = typeManager.GetFunctionTy([entityTy], companionTy)
        let nodes = ArrayList<Node>()
        if (let Some(env) <- ilib.CreateGetJniEnvCall(file)) {
            if (let Some(put) <- ilib.CreatePutSetToRegistryCall(env, entityParamRef,
                CreateThisRef(Some(companion), Some(companionTy), file))) {
                nodes.add(put)
            }
        }
        let block = CreateBlock(nodes, Some(companionTy))
        let ctorFuncBody = CreateFuncBody(paramLists, Some(CreateRefType(companion)), Some(block), Some(ctorTy))
        let ctor = CreateFuncDecl("init", Some(ctorFuncBody), Some(ctorTy))
        ctor.funcBody.getOrThrow().funcDecl = ctor
        ctor.constructorCall = ConstructorCall.SUPER
        ctor.EnableAttr(Attribute.CONSTRUCTOR)
        ctor.EnableAttr(Attribute.IN_CLASSLIKE)
        ctor.EnableAttr(Attribute.PUBLIC)
        ctor.outerDecl = Some(companion)
        ctor.funcBody.getOrThrow().parentClassLike = Some(companion)
        ctor.fullPackageName = companion.fullPackageName
        ctor.moduleName = companion.moduleName
        ctor.curFile = file
        return Some(ctor)
    }

    public func Process(companion: ClassDecl): Unit {
        CJC_ASSERT(IsImplRegistryCompanion(companion))
        if (let Some(ctor) <- GenerateConstructor(companion)) {
            companion.GetMemberDecls().add(ctor)
        }
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (refWrapper in ctx.GetJavaImplReferenceWrappers()) {
            if (refWrapper.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let Some(companion) <- ctx.GetJavaImplRegistryCompanion(refWrapper)) {
                Process(companion)
            }
        }
    }
}

public class DesugarJavaImplSuperConstructorCall {
    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplWrappingConstructor(impl)) {
                continue
            }
        }
    }
}

public class GenerateInJavaImplReferenceWrapper {
    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplRegistryCompanion(impl)) {
                continue
            }
        }
    }
}

public class DesugarJavaImplSuperMethodCall {
    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplWrappingConstructor(impl)) {
                continue
            }
        }
    }
}

public class RewriteJavaImplReferenceWrapperFields {
    public func Process(ctx: AfterTypeCheckContext, desugarPropRef: (Node) -> Unit): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplRegistryCompanion(impl)) {
                continue
            }
        }
        let _ = desugarPropRef
    }
}

public class GenerateNativeBridgeForJavaImpl {
    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (impl in ctx.GetJavaImplReferenceWrappers()) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (let None <- ctx.GetJavaImplRegistryCompanion(impl)) {
                continue
            }
        }
    }
}
