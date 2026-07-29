package cjcj::sema.NativeFFI.ObjC.TypeCheck

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor
import cjcj::sema.NativeFFI.ObjC.Handler as ObjCHandler
import cjcj::sema.NativeFFI.ObjC.{IsStaticInitMethod, TypeMapper}

public class CheckInitMethod <: ObjCHandler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckInitMethod.cpp:20-46.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        if (!TypeMapper.IsObjCMirror(ctx.target)) {
            return
        }

        for (member in ctx.target.GetMemberDeclPtrs()) {
            if (!IsStaticInitMethod(member)) {
                continue
            }
            let method = (member as FuncDecl).getOrThrow()
            let fTy = method.GetTy().getOrThrow() as FuncTy
            if (fTy.isNone()) {
                continue
            }
            let methodBody = method.funcBody.getOrThrow()
            if (methodBody.retType.isNone()) {
                continue
            }
            let retTy = fTy.getOrThrow().retTy
            let mirrorTy = method.outerDecl.getOrThrow().GetTy().getOrThrow()
            if (ctx.typeManager.IsTyEqual(retTy, mirrorTy)) {
                continue
            }

            let builder = DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_mismatched_types,
                methodBody.retType.getOrThrow())
            builder.AddMainHintArguments(Ty.ToString(Some(mirrorTy)), Ty.ToString(Some(retTy)))
            builder.Emit()
            ctx.target.EnableAttr(Attribute.IS_BROKEN)
        }
    }
}
