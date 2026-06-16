package cangjie_compiler::sema.FFI

import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::sema.*
import cangjie_compiler::basic.DiagArgument as BasicDiagArgument
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange

private let CFUNC_NAME: String = "CFunc"

private func ToBasicPosition(pos: Position): BasicPosition {
    return BasicPosition(pos.fileID, pos.line, pos.column)
}

private func ToBasicRange(begin: Position, end: Position): BasicRange {
    var fixedEnd = end
    if (begin.fileID != end.fileID) {
        fixedEnd = begin + 1
    }
    return BasicRange(ToBasicPosition(begin), ToBasicPosition(fixedEnd))
}

private func NodeRange(node: Node): BasicRange {
    return ToBasicRange(node.begin, node.end)
}

private func EmitRefactor(diag: BasicDiagnosticEngine, kind: BasicDiagKindRefactor, node: Node,
    args!: Array<String> = Array<String>()): Unit {
    let builder = diag.DiagnoseRefactor(kind, NodeRange(node), arguments: args)
    builder.Emit()
}

private func EmitLegacy(diag: BasicDiagnosticEngine, kind: BasicDiagKind, node: Node,
    args!: Array<BasicDiagArgument> = Array<BasicDiagArgument>()): Unit {
    let builder = diag.Diagnose(node.begin, kind, args: args)
    builder.Emit()
}

private func IsTopLevelDecl(decl: Decl): Bool {
    if (let Some(_) <- decl.outerDecl) {
        return false
    }
    return decl.scopeLevel == 0u32
}

public func CheckAnnoC(decl: Decl, annotation: Annotation, diag: BasicDiagnosticEngine): Unit {
    if (!annotation.args.isEmpty()) {
        EmitRefactor(diag, BasicDiagKindRefactor.sema_annotation_error_arg_num, annotation, args: ["@C", "no"])
    }
    if (decl.astKind == ASTKind.FUNC_DECL) {
        if (let Some(generic) <- decl.GetGeneric()) {
            EmitLegacy(
                diag,
                BasicDiagKind.sema_cffi_cannot_have_type_param,
                generic,
                args: [BasicDiagArgument(CFUNC_NAME)])
        }
    }
    if (decl.astKind != ASTKind.FUNC_DECL && decl.astKind != ASTKind.STRUCT_DECL) {
        EmitLegacy(
            diag,
            BasicDiagKind.sema_illegal_use_of_annotation,
            annotation,
            args: [BasicDiagArgument(DeclKindToString(decl)), BasicDiagArgument("@C")])
    } else if (!IsTopLevelDecl(decl)) {
        EmitRefactor(diag, BasicDiagKindRefactor.sema_illegal_scope_use_of_annotation, annotation, args: ["@C"])
    }
}

public func CheckAnnoCallingConv(decl: Decl, annotation: Annotation, diag: BasicDiagnosticEngine): Unit {
    if (!IsTopLevelDecl(decl)) {
        EmitRefactor(diag, BasicDiagKindRefactor.sema_illegal_scope_use_of_annotation, annotation, args: ["@CallingConv"])
        return
    }
    if (decl.astKind != ASTKind.FUNC_DECL || (!decl.TestAttr(Attribute.FOREIGN) && !decl.TestAttr(Attribute.C))) {
        EmitRefactor(diag, BasicDiagKindRefactor.sema_only_cfunc_can_use_annotation, annotation, args: ["@CallingConv"])
        return
    }
    if (annotation.args.size != 1) {
        EmitRefactor(diag, BasicDiagKindRefactor.sema_annotation_error_arg_num, annotation, args: ["@CallingConv", "one"])
        return
    }
    if (let Some(expr) <- annotation.args[0].expr) {
        if (let Some(refExpr) <- (expr as RefExpr)) {
            if (refExpr.ref.identifier.Val() == "CDECL") {
                decl.EnableAttr(Attribute.C)
                return
            }
            EmitRefactor(
                diag,
                BasicDiagKindRefactor.sema_annotation_calling_conv_not_support,
                annotation,
                args: [refExpr.ref.identifier.Val()])
            return
        }
    }
    EmitRefactor(diag, BasicDiagKindRefactor.sema_annotation_invalid_args_type, annotation, args: ["@CallingConv"])
}

public func CheckAnnoFastNative(decl: Decl, annotation: Annotation, diag: BasicDiagnosticEngine): Unit {
    if (!annotation.args.isEmpty()) {
        EmitRefactor(diag, BasicDiagKindRefactor.sema_annotation_error_arg_num, annotation, args: ["@FastNative", "no"])
    }
    if (decl.astKind != ASTKind.FUNC_DECL || !decl.TestAttr(Attribute.FOREIGN)) {
        let prefix = if (decl.astKind == ASTKind.FUNC_DECL) { "non-foreign " } else { "" }
        EmitLegacy(
            diag,
            BasicDiagKind.sema_illegal_use_of_annotation,
            annotation,
            args: [BasicDiagArgument(prefix + DeclKindToString(decl)), BasicDiagArgument("@FastNative")])
        return
    }
    if (!IsTopLevelDecl(decl)) {
        EmitRefactor(diag, BasicDiagKindRefactor.sema_illegal_scope_use_of_annotation, annotation, args: ["@FastNative"])
    }
}

public func CheckAnnoFrozen(decl: Decl, annotation: Annotation, diag: BasicDiagnosticEngine): Unit {
    if (!annotation.args.isEmpty()) {
        EmitRefactor(diag, BasicDiagKindRefactor.sema_annotation_error_arg_num, annotation, args: ["@Frozen", "no"])
    }
    if (decl.astKind != ASTKind.FUNC_DECL && decl.astKind != ASTKind.PROP_DECL) {
        EmitLegacy(
            diag,
            BasicDiagKind.sema_illegal_use_of_annotation,
            annotation,
            args: [BasicDiagArgument(DeclKindToString(decl)), BasicDiagArgument("@Frozen")])
        return
    }
    if (let Some(outer) <- decl.outerDecl) {
        if (outer.astKind == ASTKind.FUNC_DECL) {
            EmitLegacy(
                diag,
                BasicDiagKind.sema_illegal_use_of_annotation,
                annotation,
                args: [BasicDiagArgument("local function"), BasicDiagArgument("@Frozen")])
        }
    }
}

public func PreCheckAnnoForCFFI(decl: Decl, diag: BasicDiagnosticEngine): Unit {
    for (annotation in decl.annotations) {
        if (annotation.kind == AstAnnotationKind.C) {
            decl.EnableAttr(Attribute.C)
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (let Some(body) <- funcDecl.funcBody) {
                    body.EnableAttr(Attribute.C)
                }
            }
        }
    }
    for (annotation in decl.annotations) {
        match (annotation.kind) {
            case AstAnnotationKind.C => CheckAnnoC(decl, annotation, diag)
            case AstAnnotationKind.CALLING_CONV => CheckAnnoCallingConv(decl, annotation, diag)
            case AstAnnotationKind.FASTNATIVE => CheckAnnoFastNative(decl, annotation, diag)
            case AstAnnotationKind.FROZEN => CheckAnnoFrozen(decl, annotation, diag)
            case _ => ()
        }
    }
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (decl.TestAttr(Attribute.FOREIGN)) {
            decl.EnableAttr(Attribute.NO_MANGLE)
            funcDecl.linkage = Linkage.INTERNAL
        }
    }
}

public func CheckCFuncParam(param: FuncParam, diag: BasicDiagnosticEngine): Unit {
    let paramTy = param.GetTy()
    if (!Ty.IsTyCorrect(paramTy)) {
        return
    }
    if (param.isNamedParam) {
        EmitLegacy(diag, BasicDiagKind.sema_cfunc_cannot_have_named_args, param)
    }
    if (let Some(ty) <- paramTy) {
        if (ty.IsUnit()) {
            EmitLegacy(diag, BasicDiagKind.sema_cfunc_cannot_have_unit_args, param)
        } else if (!Ty.IsMetCType(ty)) {
            EmitLegacy(diag, BasicDiagKind.sema_invalid_cfunc_arg_type, param)
        }
    }
}

public func CheckCFuncParamType(typeNode: Type, diag: BasicDiagnosticEngine): Unit {
    if (let Some(ty) <- typeNode.GetTy()) {
        if (ty.IsUnit()) {
            EmitLegacy(diag, BasicDiagKind.sema_cfunc_cannot_have_unit_args, typeNode)
        } else if (!Ty.IsMetCType(ty)) {
            EmitLegacy(diag, BasicDiagKind.sema_invalid_cfunc_arg_type, typeNode)
        }
    }
}

public func CheckCFuncSignature(body: FuncBody, diag: BasicDiagnosticEngine): Unit {
    if (let Some(funcDecl) <- body.funcDecl) {
        if (!(funcDecl.TestAttr(Attribute.FOREIGN) || funcDecl.TestAttr(Attribute.C))) {
            return
        }
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                CheckCFuncParam(param, diag)
            }
        }
        if (let Some(retType) <- body.retType) {
            if (let Some(retTy) <- retType.GetTy()) {
                if (!Ty.IsMetCType(retTy)) {
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_invalid_cfunc_return_type,
                        NodeRange(retType))
                    builder.AddNote("return type is " + retTy.String())
                    builder.Emit()
                } else if (let Some(_) <- (retTy as VArrayTy)) {
                    EmitRefactor(diag, BasicDiagKindRefactor.sema_varray_in_cfunc, retType)
                }
            }
        }
    }
}

public func SelfhostPortStatus_FFI_CFFICheck(): Bool {
    return true
}
