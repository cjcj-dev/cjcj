package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.WithinFile

// Existing CJ-mapping forward-class handlers, separated from the ObjC mirror/impl pipeline.

public class InsertFwdNativeHandleGetterDecl <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (fwdClass in ctx.fwdClasses) {
            if (fwdClass.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            if (GetNativeHandleGetter(fwdClass).isSome()) {
                continue
            }
            fwdClass.body.getOrThrow().decls.add(ctx.factory.CreateNativeHandleGetterDecl(fwdClass))
        }
    }
}

public class InsertFwdFinalizer <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (fwdClass in ctx.fwdClasses) {
            if (fwdClass.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            fwdClass.body.getOrThrow().decls.add(ctx.factory.CreateHasInitedField(fwdClass))
            fwdClass.body.getOrThrow().decls.add(ctx.factory.CreateFinalizer(fwdClass))
        }
    }
}

public class InsertFwdNativeHandleGetterBody <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (fwdClass in ctx.fwdClasses) {
            if (fwdClass.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            let getterDecl = GetNativeHandleGetter(fwdClass).getOrThrow()
            let nativeHandleFieldExpr = ctx.factory.CreateNativeHandleFieldExpr(fwdClass)
            getterDecl.funcBody.getOrThrow().body.getOrThrow().body.add(nativeHandleFieldExpr)
        }
    }
}

public class InsertFwdBaseCtorDecl <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (fwdClass in ctx.fwdClasses) {
            if (fwdClass.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            fwdClass.body.getOrThrow().decls.add(ctx.factory.CreateObjCMirrorBaseCtorDecl(fwdClass))
        }
    }
}

public class InsertFwdBaseCtorBody <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (fwdClass in ctx.fwdClasses) {
            if (fwdClass.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            let ctor = ctx.factory.GetGeneratedBaseCtor(fwdClass).getOrThrow()
            let curFile = ctor.curFile
            let handleParam = WithinFile<RefExpr>(
                CreateRefExpr(ctor.funcBody.getOrThrow().paramLists[0].params[0]), curFile)
            let lhs = ctx.factory.CreateNativeHandleFieldExpr(fwdClass)
            let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
            ctor.funcBody.getOrThrow().body.getOrThrow().body.add(
                CreateAssignExpr(lhs, handleParam, unitTy))
        }
    }
}

public class InsertFwdNativeHandleField <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (fwdClass in ctx.fwdClasses) {
            if (fwdClass.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            fwdClass.body.getOrThrow().decls.add(ctx.factory.CreateNativeHandleField(fwdClass))
        }
    }
}
