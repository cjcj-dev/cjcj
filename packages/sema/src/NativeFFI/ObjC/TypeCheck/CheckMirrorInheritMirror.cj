package cjcj::sema.NativeFFI.ObjC.TypeCheck

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor
import cjcj::sema.NativeFFI.ObjC.Handler as ObjCHandler
import cjcj::sema.NativeFFI.ObjC.TypeMapper

public class CheckMirrorInheritMirror <: ObjCHandler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMirrorInheritMirror.cpp:20-29.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        if (TypeMapper.IsValidObjCMirror(ctx.target.GetTy().getOrThrow())) {
            return
        }

        DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_mirror_must_inherit_mirror,
            ctx.target).Emit()
        ctx.target.EnableAttr(Attribute.IS_BROKEN)
    }
}
