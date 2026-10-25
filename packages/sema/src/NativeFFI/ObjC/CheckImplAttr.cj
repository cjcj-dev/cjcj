package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor

public class CheckImplAttr <: Handler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckImplAttr.cpp:20-34.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        let ty = ctx.target.GetTy().getOrThrow()
        if (!IsObjCMirrorSubtype(ty)) {
            return
        }

        if (IsObjCMirror(ty) || IsObjCImpl(ty)) {
            return
        }

        let kind = if (ty.IsInterface()) {
            DiagKindRefactor.sema_objc_mirror_interface_subtype_must_be_annotated
        } else {
            DiagKindRefactor.sema_objc_mirror_subtype_must_be_annotated
        }
        let builder = DiagnoseRefactor(ctx.diag, kind, ctx.target)
        builder.AddMainHintArguments(ctx.target.identifier.Val())
        builder.Emit()
        ctx.target.EnableAttr(Attribute.IS_BROKEN)
    }
}
