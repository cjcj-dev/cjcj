package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor

public class CheckMirrorInheritMirror <: Handler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMirrorInheritMirror.cpp:20-29.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        if (IsValidObjCMirror(ctx.target.GetTy().getOrThrow())) {
            return
        }

        DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_mirror_must_inherit_mirror,
            ctx.target).Emit()
        ctx.target.EnableAttr(Attribute.IS_BROKEN)
    }
}

private func IsValidObjCMirror(ty: Ty): Bool {
    let classLikeTy = ty as ClassLikeTy
    if (let None <- classLikeTy) { return false }
    let value = classLikeTy.getOrThrow()
    if (let None <- value.commonDecl) { return false }
    if (!IsObjCMirror(value.commonDecl.getOrThrow())) { return false }
    for (parent in value.GetSuperInterfaceTys()) { if (!IsValidObjCMirror(parent)) { return false } }
    if (let Some(classTy) <- (ty as ClassTy)) {
        if (let None <- classTy.GetSuperClassTy()) { return true }
        let superTy = classTy.GetSuperClassTy().getOrThrow()
        if (superTy.IsObject()) { return true }
        return IsValidObjCMirror(superTy)
    }
    return true
}
