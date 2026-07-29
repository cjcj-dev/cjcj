package cjcj::sema.NativeFFI.ObjC.TypeCheck

import cjcj::basic.{DiagKindRefactor, MakeRange}
import cjcj::sema.NativeFFI.ObjC.Handler as ObjCHandler

public class CheckGeneric <: ObjCHandler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckGeneric.cpp:20-27.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        if (let Some(generic) <- ctx.target.generic) {
            ctx.diag.DiagnoseRefactor(DiagKindRefactor.sema_objc_cjmapping_generic_not_supported,
                MakeRange(generic.leftAnglePos, generic.rightAnglePos), ctx.target.identifier.Val()).Emit()
        }
    }
}
