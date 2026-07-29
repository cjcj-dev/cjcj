package cjcj::sema.NativeFFI.ObjC.TypeCheck

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor
import cjcj::sema.NativeFFI.ObjC.Handler as ObjCHandler

public class CheckAbstractClass <: ObjCHandler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckAbstractClass.cpp:19-25.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        if (let Some(cd) <- (ctx.target as ClassDecl)) {
            if (cd.TestAttr(Attribute.ABSTRACT)) {
                DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_interop_not_supported,
                    cd, "abstract").Emit()
                cd.EnableAttr(Attribute.IS_BROKEN)
            }
        }
    }
}
