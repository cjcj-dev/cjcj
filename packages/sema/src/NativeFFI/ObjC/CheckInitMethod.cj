package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor

public class CheckInitMethod <: Handler<TypeCheckContext> {
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
            let fTy = method.GetTy() as FuncTy
            let methodBody = method.funcBody.getOrThrow()
            if (fTy.isNone() || methodBody.retType.isNone()) {
                continue
            }
            let retTy = fTy.getOrThrow().retTy
            let mirrorTy = method.outerDecl.getOrThrow().GetTy()
            if (let Some(mirror) <- mirrorTy) {
                if (ctx.typeManager.IsTyEqual(retTy, mirror)) {
                    continue
                }
            }

            let builder = DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_mismatched_types,
                methodBody.retType.getOrThrow())
            builder.AddMainHintArguments(Ty.ToString(mirrorTy), Ty.ToString(Some(retTy)))
            builder.Emit()
            ctx.target.EnableAttr(Attribute.IS_BROKEN)
        }
    }
}
