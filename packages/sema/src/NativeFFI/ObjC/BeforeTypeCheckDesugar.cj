package cjcj::sema.NativeFFI.ObjC

import std.collection.ArrayList
import cjcj::ast.*
import cjcj::mangle.BaseMangler
import cjcj::modules.SemaImportManager
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{INIT_IDENT, NSOBJECT_CLASS_IDENT,
    NSSTRING_CLASS_IDENT, TOSTRING_METHOD_IDENT}
import cjcj::utils.{CJC_ASSERT, STD_LIB_STRING}

// Upstream a51ced71, BeforeTypeCheck/Utils/BeforeTypeCheckASTTransformer.cpp:23-35.
private func CloneVisibilityAttribute(from: Decl, to: Decl): Unit {
    if (from.TestAttr(Attribute.PUBLIC)) {
        to.EnableAttr(Attribute.PUBLIC)
    } else if (from.TestAttr(Attribute.INTERNAL)) {
        to.EnableAttr(Attribute.INTERNAL)
    } else if (from.TestAttr(Attribute.PROTECTED)) {
        to.EnableAttr(Attribute.PROTECTED)
    } else if (from.TestAttr(Attribute.PRIVATE)) {
        to.EnableAttr(Attribute.PRIVATE)
    }
}

public class BeforeTypeCheckASTTransformer {
    // Upstream a51ced71, BeforeTypeCheck/Utils/BeforeTypeCheckASTTransformer.cpp:38-73.
    public func TransformToRegistryCompanion(regComp: ClassDecl, impl: ClassDecl): Unit {
        CloneVisibilityAttribute(impl, regComp)
        if (impl.IsOpen()) {
            regComp.EnableAttr(Attribute.OPEN)
        }
        regComp.EnableAttr(Attribute.OBJ_C_IMPL_REGISTRY_COMPANION)
        regComp.identifier = SrcIdentifier(NameGenerator.GenerateRegistryCompanionName(impl))
    }

    public func TransformToHandleWrapper(handleWrapper: ClassDecl, mirror: ClassLikeDecl): Unit {
        CloneVisibilityAttribute(mirror, handleWrapper)
        handleWrapper.EnableAttr(Attribute.OBJ_C_MIRROR_INTERFACE_HANDLE_WRAPPER)
        handleWrapper.identifier = SrcIdentifier(NameGenerator.GenerateHandleWrapperName(mirror))
        handleWrapper.inheritedTypes.add(CreateRefType(mirror))
    }

    public func TransformToToString(target: FuncDecl): Unit {
        target.identifier = SrcIdentifier(TOSTRING_METHOD_IDENT)
        target.EnableAttr(Attribute.PUBLIC)
        target.funcBody.getOrThrow().retType = Some(CreateRefType(STD_LIB_STRING))
        target.funcBody.getOrThrow().body.getOrThrow().EnableAttr(Attribute.IS_CHECK_VISITED)
    }

    public func TransformToInitFromString(target: FuncDecl): Unit {
        let param = CreateFuncParam("str", CreateRefType(STD_LIB_STRING), None, None)
        let paramLists = target.funcBody.getOrThrow().paramLists
        CJC_ASSERT(paramLists.size > 0)
        paramLists[0].params.add(param)
        target.identifier = SrcIdentifier(INIT_IDENT)
        target.EnableAttr(Attribute.PUBLIC)
        target.EnableAttr(Attribute.CONSTRUCTOR)
        target.funcBody.getOrThrow().body.getOrThrow().EnableAttr(Attribute.IS_CHECK_VISITED)
    }
}

// Upstream a51ced71, BeforeTypeCheck/PrepareTypeCheckContext.h:26-40.
public class PrepareTypeCheckContext {
    public let pkg: Package
    public let mirrors = ArrayList<ClassLikeDecl>()
    public let impls = ArrayList<ClassDecl>()
    public let typeManager: TypeManager
    public let importManager: SemaImportManager
    public let astTransformer = BeforeTypeCheckASTTransformer()
    public let astInserter = ASTInserter()
    public let mangler = BaseMangler()
    public let nameGenerator: NameGenerator

    public init(pkg: Package, typeManager: TypeManager, importManager: SemaImportManager) {
        this.pkg = pkg
        this.typeManager = typeManager
        this.importManager = importManager
        nameGenerator = NameGenerator(mangler, typeManager)
    }
}

public class WarmupContext <: Handler<PrepareTypeCheckContext> {
    // Upstream a51ced71, BeforeTypeCheck/WarmupContext.cpp:21-39.
    public func HandleImpl(ctx: PrepareTypeCheckContext): Unit {
        for (file in ctx.pkg.files) {
            for (decl in file.decls) {
                if (decl.TestAnyAttr(Attribute.HAS_BROKEN, Attribute.IS_BROKEN)) {
                    continue
                }
                if (let Some(mirror) <- (decl as ClassLikeDecl)) {
                    if (mirror.TestAttr(Attribute.OBJ_C_MIRROR)) {
                        ctx.mirrors.add(mirror)
                    }
                }
                if (let Some(impl) <- (decl as ClassDecl)) {
                    if (impl.TestAttr(Attribute.OBJ_C_IMPL)) {
                        ctx.impls.add(impl)
                    }
                }
            }
        }
    }
}

public class ReplaceFieldsWithProps <: Handler<PrepareTypeCheckContext> {
    public func HandleImpl(ctx: PrepareTypeCheckContext): Unit {
        for (mirror in ctx.mirrors) {
            if (let Some(cd) <- (mirror as ClassDecl)) {
                InsertMirrorVarProp(cd, Attribute.OBJ_C_MIRROR)
            }
        }
    }
}

public class InsertToString <: Handler<PrepareTypeCheckContext> {
    public func HandleImpl(ctx: PrepareTypeCheckContext): Unit {
        for (mirror in ctx.mirrors) {
            if (let Some(cd) <- (mirror as ClassDecl)) {
                if (!IsNSObject(cd)) {
                    continue
                }
                let paramLists = ArrayList<FuncParamList>()
                paramLists.add(CreateFuncParamList(ArrayList<FuncParam>()))
                let decl = CreateFuncDecl("", CreateFuncBody(paramLists, None,
                    CreateBlock(ArrayList<Node>(), None), None), None)
                ctx.astTransformer.TransformToToString(decl)
                ctx.astInserter.InsertInto(mirror, decl)
            }
        }
    }
}

public class InsertFromStringCtor <: Handler<PrepareTypeCheckContext> {
    public func HandleImpl(ctx: PrepareTypeCheckContext): Unit {
        for (mirror in ctx.mirrors) {
            if (let Some(cd) <- (mirror as ClassDecl)) {
                if (!IsNSString(cd)) {
                    continue
                }
                let paramLists = ArrayList<FuncParamList>()
                paramLists.add(CreateFuncParamList(ArrayList<FuncParam>()))
                let decl = CreateFuncDecl("", CreateFuncBody(paramLists, None,
                    CreateBlock(ArrayList<Node>(), None), None), None)
                ctx.astTransformer.TransformToInitFromString(decl)
                ctx.astInserter.InsertInto(mirror, decl)
            }
        }
    }
}

public class InsertRegCompanionDecl <: Handler<PrepareTypeCheckContext> {
    // Upstream a51ced71, BeforeTypeCheck/InsertRegCompanionDecl.cpp:21-34.
    public func HandleImpl(ctx: PrepareTypeCheckContext): Unit {
        for (impl in ctx.impls) {
            let decl = ClassDecl()
            decl.body = ClassBody()
            decl.EnableAttr(Attribute.COMPILER_ADD)
            ctx.astTransformer.TransformToRegistryCompanion(decl, impl)
            ctx.astInserter.InsertInto(impl.curFile.getOrThrow(), decl)
            ctx.importManager.GetCjoManager().AddGeneratedDeclToDeclMap(decl)
        }
    }
}

public class InsertHandleWrapperDecl <: Handler<PrepareTypeCheckContext> {
    // Upstream a51ced71, BeforeTypeCheck/InsertHandleWrapperDecl.cpp:21-38.
    public func HandleImpl(ctx: PrepareTypeCheckContext): Unit {
        for (mirror in ctx.mirrors) {
            if (mirror.astKind != ASTKind.INTERFACE_DECL) {
                continue
            }
            let decl = ClassDecl()
            decl.body = ClassBody()
            decl.EnableAttr(Attribute.COMPILER_ADD)
            ctx.astTransformer.TransformToHandleWrapper(decl, mirror)
            ctx.astInserter.InsertInto(mirror.curFile.getOrThrow(), decl)
            ctx.importManager.GetCjoManager().AddGeneratedDeclToDeclMap(decl)
        }
    }
}

// Upstream a51ced71, BeforeTypeCheck/Desugar.cpp:21-32.
public func PrepareTypeCheck(pkg: Package, importManager: SemaImportManager, typeManager: TypeManager): Unit {
    let ctx = PrepareTypeCheckContext(pkg, typeManager, importManager)
    HandlerFactory.Start<PrepareTypeCheckContext>(WarmupContext())
        .Use(ReplaceFieldsWithProps())
        .Use(InsertToString())
        .Use(InsertFromStringCtor())
        .Use(InsertRegCompanionDecl())
        .Use(InsertHandleWrapperDecl())
        .Handle(ctx)
}
