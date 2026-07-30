package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor

public class CheckTopLevelFuncTypes <: Handler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckTopLevelFuncTypes.cpp:19-43.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        let fd = ctx.target as FuncDecl
        if (fd.isNone()) {
            return
        }

        let funcDecl = fd.getOrThrow()
        let funcBody = funcDecl.funcBody.getOrThrow()
        for (paramList in funcBody.paramLists) {
            for (param in paramList.params) {
                if (!TypeMapper.IsObjCCompatible(param.GetTy().getOrThrow())) {
                    DiagnoseRefactor(ctx.diag,
                        DiagKindRefactor.sema_objc_interop_toplevel_param_must_be_objc_compatible,
                        param.typeNode.getOrThrow(), funcDecl.identifier.Val()).Emit()
                    funcDecl.EnableAttr(Attribute.IS_BROKEN)
                }
            }
        }
        if (let Some(retType) <- funcBody.retType) {
            if (!TypeMapper.IsObjCCompatible(retType.GetTy().getOrThrow())) {
                DiagnoseRefactor(ctx.diag,
                    DiagKindRefactor.sema_objc_interop_toplevel_ret_must_be_objc_compatible,
                    retType, funcDecl.identifier.Val()).Emit()
                funcDecl.EnableAttr(Attribute.IS_BROKEN)
            }
        }
    }
}
