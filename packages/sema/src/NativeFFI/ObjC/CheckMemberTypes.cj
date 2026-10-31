package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor
public class CheckMemberTypes <: Handler<TypeCheckContext> {
    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMemberTypes.cpp:22-45.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        let isImpl = IsObjCImpl(ctx.target.GetTy().getOrThrow())
        for (decl in ctx.target.GetMemberDeclPtrs()) {
            if (isImpl && !decl.TestAttr(Attribute.PUBLIC)) {
                continue
            }

            match (decl.astKind) {
                case ASTKind.FUNC_DECL => CheckFuncTypes((decl as FuncDecl).getOrThrow(), ctx)
                case ASTKind.PROP_DECL => CheckPropTypes((decl as PropDecl).getOrThrow(), ctx)
                case ASTKind.VAR_DECL => CheckVarTypes((decl as VarDecl).getOrThrow(), ctx)
                case _ => ()
            }
        }
    }

    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMemberTypes.cpp:47-57.
    private func CheckPropTypes(pd: PropDecl, ctx: TypeCheckContext): Unit {
        if (IsObjCCompatible(pd.GetTy().getOrThrow())) {
            return
        }

        let kind = if (!IsObjCImpl(pd.outerDecl.getOrThrow().GetTy().getOrThrow()) &&
            pd.TestAttr(Attribute.DESUGARED_FOREIGN_FIELD)) {
            DiagKindRefactor.sema_objc_interop_field_must_be_objc_compatible
        } else { DiagKindRefactor.sema_objc_interop_prop_must_be_objc_compatible }
        let builder = DiagnoseRefactor(ctx.diag, kind,
            pd.typeNode.getOrThrow(), GetDeclInteropName(ctx))
        builder.AddMainHintArguments(Ty.ToString(pd.GetTy()))
        builder.Emit()
        pd.EnableAttr(Attribute.IS_BROKEN)
        let outerDecl = pd.outerDecl.getOrThrow()
        outerDecl.EnableAttr(Attribute.HAS_BROKEN)
        outerDecl.EnableAttr(Attribute.IS_BROKEN)
    }

    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMemberTypes.cpp:59-69.
    private func CheckVarTypes(vd: VarDecl, ctx: TypeCheckContext): Unit {
        if (IsObjCCompatible(vd.GetTy().getOrThrow())) {
            return
        }

        let builder = DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_interop_field_must_be_objc_compatible,
            vd.typeNode.getOrThrow(), GetDeclInteropName(ctx))
        builder.AddMainHintArguments(Ty.ToString(vd.GetTy()))
        builder.Emit()
        vd.EnableAttr(Attribute.IS_BROKEN)
        let outerDecl = vd.outerDecl.getOrThrow()
        outerDecl.EnableAttr(Attribute.HAS_BROKEN)
        outerDecl.EnableAttr(Attribute.IS_BROKEN)
    }

    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMemberTypes.cpp:71-82.
    private func CheckFuncTypes(fd: FuncDecl, ctx: TypeCheckContext): Unit {
        if (fd.funcBody.isNone() || IsGeneratedMember(fd)) {
            return
        }

        if (!fd.TestAttr(Attribute.CONSTRUCTOR)) {
            CheckFuncRetType(fd, ctx)
        }

        CheckFuncParamTypes(fd, ctx)
    }

    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMemberTypes.cpp:84-93.
    private func CheckFuncRetType(fd: FuncDecl, ctx: TypeCheckContext): Unit {
        let funcBody = fd.funcBody.getOrThrow()
        if (let Some(retType) <- funcBody.retType) {
            if (!IsObjCCompatible(retType.GetTy().getOrThrow(), TypePosition.OUT)) {
                let builder = DiagnoseRefactor(ctx.diag,
                    DiagKindRefactor.sema_objc_interop_method_ret_must_be_objc_compatible,
                    retType, GetDeclInteropName(ctx))
                builder.AddMainHintArguments(retType.ToString())
                builder.Emit()

                fd.EnableAttr(Attribute.IS_BROKEN)
                let outerDecl = fd.outerDecl.getOrThrow()
                outerDecl.EnableAttr(Attribute.HAS_BROKEN)
                outerDecl.EnableAttr(Attribute.IS_BROKEN)
            }
        }
    }

    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMemberTypes.cpp:95-113.
    private func CheckFuncParamTypes(fd: FuncDecl, ctx: TypeCheckContext): Unit {
        let errKind = if (fd.TestAttr(Attribute.CONSTRUCTOR)) {
            DiagKindRefactor.sema_objc_interop_ctor_param_must_be_objc_compatible
        } else {
            DiagKindRefactor.sema_objc_interop_method_param_must_be_objc_compatible
        }

        for (paramList in fd.funcBody.getOrThrow().paramLists) {
            for (param in paramList.params) {
                if (IsObjCCompatible(param.GetTy().getOrThrow(), TypePosition.IN)) {
                    continue
                }

                fd.EnableAttr(Attribute.IS_BROKEN)
                let outerDecl = fd.outerDecl.getOrThrow()
                outerDecl.EnableAttr(Attribute.HAS_BROKEN)
                outerDecl.EnableAttr(Attribute.IS_BROKEN)

                let builder = DiagnoseRefactor(ctx.diag, errKind, param, GetDeclInteropName(ctx))
                builder.AddMainHintArguments(Ty.ToString(param.GetTy()))
                builder.Emit()
            }
        }
    }

    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMemberTypes.cpp:115-126.
    private func GetDeclInteropName(ctx: TypeCheckContext): String {
        return if (IsObjCImpl(ctx.target.GetTy().getOrThrow())) { "exported '@ObjC'" } else { "'@ObjC' foreign" }
    }
}
