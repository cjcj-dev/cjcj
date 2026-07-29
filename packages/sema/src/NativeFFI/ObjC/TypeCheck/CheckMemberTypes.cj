package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor
import cjcj::sema.NativeFFI.IsObjCGeneratedMember
import cjcj::utils.CJC_ABORT

public class CheckMemberTypes <: Handler<TypeCheckContext> {
    private let interopType: InteropType

    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/Handlers.h:58-61.
    public init(interopType: InteropType) {
        this.interopType = interopType
    }

    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMemberTypes.cpp:22-45.
    public func HandleImpl(ctx: TypeCheckContext): Unit {
        let isImpl = ctx.typeMapper.IsObjCImpl(ctx.target.GetTy().getOrThrow())
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
        if (ctx.typeMapper.IsObjCCompatible(pd.GetTy().getOrThrow())) {
            return
        }

        DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_interop_prop_must_be_objc_compatible,
            pd.typeNode.getOrThrow(), GetDeclInteropName()).Emit()
        pd.EnableAttr(Attribute.IS_BROKEN)
        let outerDecl = pd.outerDecl.getOrThrow()
        outerDecl.EnableAttr(Attribute.HAS_BROKEN)
        outerDecl.EnableAttr(Attribute.IS_BROKEN)
    }

    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMemberTypes.cpp:59-69.
    private func CheckVarTypes(vd: VarDecl, ctx: TypeCheckContext): Unit {
        if (ctx.typeMapper.IsObjCCompatible(vd.GetTy().getOrThrow())) {
            return
        }

        DiagnoseRefactor(ctx.diag, DiagKindRefactor.sema_objc_interop_field_must_be_objc_compatible,
            vd.typeNode.getOrThrow(), GetDeclInteropName()).Emit()
        vd.EnableAttr(Attribute.IS_BROKEN)
        let outerDecl = vd.outerDecl.getOrThrow()
        outerDecl.EnableAttr(Attribute.HAS_BROKEN)
        outerDecl.EnableAttr(Attribute.IS_BROKEN)
    }

    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMemberTypes.cpp:71-82.
    private func CheckFuncTypes(fd: FuncDecl, ctx: TypeCheckContext): Unit {
        if (fd.funcBody.isNone() || IsObjCGeneratedMember(fd)) {
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
            if (!ctx.typeMapper.IsObjCCompatible(retType.GetTy().getOrThrow())) {
                DiagnoseRefactor(ctx.diag,
                    DiagKindRefactor.sema_objc_interop_method_ret_must_be_objc_compatible,
                    retType, GetDeclInteropName()).Emit()

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
                if (ctx.typeMapper.IsObjCCompatible(param.GetTy().getOrThrow())) {
                    continue
                }

                fd.EnableAttr(Attribute.IS_BROKEN)
                let outerDecl = fd.outerDecl.getOrThrow()
                outerDecl.EnableAttr(Attribute.HAS_BROKEN)
                outerDecl.EnableAttr(Attribute.IS_BROKEN)

                DiagnoseRefactor(ctx.diag, errKind, param, GetDeclInteropName()).Emit()
            }
        }
    }

    // C++ src/Sema/NativeFFI/ObjC/TypeCheck/CheckMemberTypes.cpp:115-126.
    private func GetDeclInteropName(): String {
        if (interopType == InteropType.ObjC_Mirror) {
            return "Objective-C mirror"
        } else if (interopType == InteropType.CJ_Mapping) {
            return "cangjie mirror decl"
        } else {
            CJC_ABORT()
            return ""
        }
    }
}
