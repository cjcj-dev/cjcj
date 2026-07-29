package cjcj::sema.NativeFFI.ObjC.TypeCheck

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor
import cjcj::sema.NativeFFI.ObjC.Handler as ObjCHandler
import cjcj::sema.NativeFFI.ObjC.TypeMapper

public class CheckImplInheritMirror <: ObjCHandler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckImplInheritMirror.cpp:19-48.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        let targetTy = ctx.target.GetTy().getOrThrow()
        if (!TypeMapper.IsObjCImpl(targetTy)) {
            return
        }

        // C++ TODO branch retained until hierarchy-root @ObjCImpl is supported.
        if (let Some(classTy) <- (targetTy as ClassTy)) {
            var hasOnlyMirrorSuperInterfaces = classTy.GetSuperInterfaceTys().size > 0
            for (superInterfaceTy in classTy.GetSuperInterfaceTys()) {
                if (!TypeMapper.IsValidObjCMirror(superInterfaceTy)) {
                    hasOnlyMirrorSuperInterfaces = false
                    break
                }
            }

            let superClassTy = classTy.GetSuperClassTy()
            if (hasOnlyMirrorSuperInterfaces &&
                (superClassTy.isNone() || superClassTy.getOrThrow().IsObject())) {
                DiagnoseRefactor(ctx.diag,
                    DiagKindRefactor.sema_objc_impl_must_have_objc_mirror_super_class,
                    ctx.target).Emit()
                ctx.target.EnableAttr(Attribute.IS_BROKEN)
            }
        }

        if (TypeMapper.IsValidObjCMirrorSubtype(targetTy)) {
            return
        }

        DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_mirror_subtype_must_inherit_mirror,
            ctx.target).Emit()
        ctx.target.EnableAttr(Attribute.IS_BROKEN)
    }
}
