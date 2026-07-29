package cjcj::sema.NativeFFI.ObjC.TypeCheck

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor
import cjcj::sema.NativeFFI.ObjC.Handler as ObjCHandler
import cjcj::sema.NativeFFI.ObjC.TypeMapper

public class CheckMirrorSubtypeAttr <: ObjCHandler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMirrorSubtypeAttr.cpp:20-34.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        let ty = ctx.target.GetTy().getOrThrow()
        if (!TypeMapper.IsValidObjCMirrorSubtype(ty)) {
            return
        }

        if (TypeMapper.IsValidObjCMirror(ty) || TypeMapper.IsObjCImpl(ty)) {
            return
        }

        DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_mirror_subtype_must_be_annotated,
            ctx.target).Emit()
        ctx.target.EnableAttr(Attribute.IS_BROKEN)
    }
}
