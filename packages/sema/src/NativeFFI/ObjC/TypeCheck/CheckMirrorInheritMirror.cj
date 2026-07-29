package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor

public class CheckMirrorInheritMirror <: Handler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMirrorInheritMirror.cpp:20-29.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        if (ctx.typeMapper.IsValidObjCMirror(ctx.target.GetTy().getOrThrow())) {
            return
        }

        DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_mirror_must_inherit_mirror,
            ctx.target).Emit()
        ctx.target.EnableAttr(Attribute.IS_BROKEN)
    }
}
