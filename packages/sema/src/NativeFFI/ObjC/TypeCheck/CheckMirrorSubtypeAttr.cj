package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor

public class CheckMirrorSubtypeAttr <: Handler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMirrorSubtypeAttr.cpp:20-34.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        let ty = ctx.target.GetTy().getOrThrow()
        if (!ctx.typeMapper.IsValidObjCMirrorSubtype(ty)) {
            return
        }

        if (ctx.typeMapper.IsValidObjCMirror(ty) || ctx.typeMapper.IsObjCImpl(ty)) {
            return
        }

        DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_mirror_subtype_must_be_annotated,
            ctx.target).Emit()
        ctx.target.EnableAttr(Attribute.IS_BROKEN)
    }
}
