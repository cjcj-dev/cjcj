package cjcj::sema.NativeFFI.ObjC.TypeCheck

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor
import cjcj::sema.NativeFFI.ObjC.Handler as ObjCHandler

public class CheckInheritanceInterface <: ObjCHandler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckInheritanceInterface.cpp:19-29.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        let inheritableDecl = (ctx.target as InheritableDecl).getOrThrow()
        for (parent in inheritableDecl.inheritedTypes) {
            if (let Some(parentTy) <- parent.GetTy()) {
                if (parentTy.IsInterface()) {
                    DiagnoseRefactor(ctx.diag,
                        DiagKindRefactor.sema_objc_cjmapping_inheritance_interface_not_supported,
                        parent).Emit()
                    inheritableDecl.EnableAttr(Attribute.IS_BROKEN)
                    return
                }
            }
        }
    }
}
