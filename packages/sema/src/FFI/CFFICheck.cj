package cangjie_compiler::sema.FFI

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::sema.*
import cangjie_compiler::basic.DiagArgument as BasicDiagArgument
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::option.BackendType as OptionBackendType
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions
import cangjie_compiler::option.IsUnsafeBackend as OptionIsUnsafeBackend

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

private func IdentifierRange(identifier: SrcIdentifier): BasicRange {
    return ToBasicRange(identifier.GetRawPos(), identifier.GetRawEndPos())
}

private func FuncBodyTypeRange(body: FuncBody, typeNode: Type): BasicRange {
    if (!typeNode.begin.IsZero()) {
        return NodeRange(typeNode)
    }
    if (let Some(funcDecl) <- body.funcDecl) {
        return IdentifierRange(funcDecl.identifier)
    }
    return NodeRange(typeNode)
}

public func GetFuncBodyRange(body: FuncBody, typeNode: Type): BasicRange {
    if (!typeNode.begin.IsZero()) {
        return NodeRange(typeNode)
    }
    let funcDecl = body.funcDecl.getOrThrow()
    return IdentifierRange(funcDecl.identifier)
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

private func HasModifier(decl: Decl, kind: TokenKind): Bool {
    for (modifier in decl.modifiers) {
        if (modifier.modifier == kind) {
            return true
        }
    }
    return false
}

private func HasCAnnotation(decl: Decl): Bool {
    for (annotation in decl.annotations) {
        if (annotation.kind == AstAnnotationKind.C) {
            return true
        }
    }
    return false
}

private func IsNonStaticMember(target: Decl): Bool {
    return !target.TestAttr(Attribute.STATIC) &&
        (target.TestAnyAttr(Attribute.IN_CLASSLIKE, Attribute.IN_STRUCT, Attribute.IN_ENUM) ||
        target.TestAttr(Attribute.IN_EXTEND))
}

private func IsInoutZeroSizedArg(arg: FuncArg): Bool {
    if (!arg.withInout) {
        return false
    }
    if (let Some(expr) <- arg.expr) {
        if (expr.astKind != ASTKind.REF_EXPR && expr.astKind != ASTKind.MEMBER_ACCESS) {
            return false
        }
        if (let Some(ty) <- expr.GetTy()) {
            return Ty.IsMetCType(ty) && IsZeroSizedTy(ty)
        }
    }
    return false
}

private func IsStructZeroSized(structTy: Ty, visited: ArrayList<Ty>): Bool {
    for (ty in visited) {
        if (SameTy(ty, structTy)) {
            return false
        }
    }
    if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(structTy))) {
        if (let Some(structDecl) <- (decl as StructDecl)) {
            visited.add(structTy)
            for (member in structDecl.GetMemberDecls()) {
                if (member.astKind != ASTKind.VAR_DECL || member.TestAttr(Attribute.STATIC)) {
                    continue
                }
                if (let Some(memberTy) <- member.GetTy()) {
                    if (!IsZeroSizedTyImpl(memberTy, visited)) {
                        return false
                    }
                } else {
                    return false
                }
            }
            return true
        }
    }
    return false
}

private func IsZeroSizedTyImpl(ty: Ty, visited: ArrayList<Ty>): Bool {
    if (ty.IsUnit() || ty.IsNothing()) {
        return true
    }
    if (let Some(_) <- (ty as StructTy)) {
        return IsStructZeroSized(ty, visited)
    }
    return false
}

public func IsZeroSizedTy(ty: Ty): Bool {
    return IsZeroSizedTyImpl(ty, ArrayList<Ty>())
}

public func IsInCFunc(ctx: ASTContext, refExpr: RefExpr): Bool {
    var symbolOpt = ScopeManager.GetCurSymbolByKind(SymbolKind.FUNC_LIKE, ctx, refExpr.scopeName)
    while (let Some(symbol) <- symbolOpt) {
        if (symbol.scopeName.isEmpty()) {
            return false
        }
        if (let Some(node) <- symbol.node) {
            if (let Some(lambdaExpr) <- (node as LambdaExpr)) {
                if (let Some(lambdaTy) <- lambdaExpr.GetTy()) {
                    if (Ty.IsTyCorrect(lambdaTy) && lambdaTy.IsCFunc()) {
                        return true
                    }
                }
            }
        }
        symbolOpt = ScopeManager.GetCurSymbolByKind(SymbolKind.FUNC_LIKE, ctx, symbol.scopeName)
    }
    return false
}

public func CheckAnnoC(decl: Decl, annotation: Annotation, diag: BasicDiagnosticEngine): Unit {
    if (!annotation.args.isEmpty()) {
        EmitLegacy(
            diag,
            BasicDiagKind.sema_annotation_error_arg_num,
            annotation.args[0],
            args: [BasicDiagArgument("@C"), BasicDiagArgument("no")])
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
        EmitLegacy(
            diag,
            BasicDiagKind.sema_annotation_error_arg_num,
            annotation.args[0],
            args: [BasicDiagArgument("@FastNative"), BasicDiagArgument("no")])
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
        EmitLegacy(
            diag,
            BasicDiagKind.sema_annotation_error_arg_num,
            annotation.args[0],
            args: [BasicDiagArgument("@Frozen"), BasicDiagArgument("no")])
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
    if (HasModifier(decl, TokenKind.FOREIGN) && !HasCAnnotation(decl)) {
        if (decl.astKind == ASTKind.CLASS_DECL) {
            EmitLegacy(
                diag,
                BasicDiagKind.sema_unexpected_wrapper,
                decl,
                args: [BasicDiagArgument("class declaration")])
        } else if (decl.astKind == ASTKind.INTERFACE_DECL) {
            EmitLegacy(
                diag,
                BasicDiagKind.sema_unexpected_wrapper,
                decl,
                args: [BasicDiagArgument("interface declaration")])
        } else if (decl.astKind == ASTKind.VAR_DECL) {
            EmitLegacy(diag, BasicDiagKind.sema_native_var_error, decl)
        }
    }
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
            if (!Ty.IsTyCorrect(retType.GetTy())) {
                return
            }
            if (let Some(retTy) <- retType.GetTy()) {
                if (!Ty.IsMetCType(retTy)) {
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_invalid_cfunc_return_type,
                        FuncBodyTypeRange(body, retType))
                    builder.AddNote("return type is " + retTy.String())
                    builder.Emit()
                } else if (let Some(_) <- (retTy as VArrayTy)) {
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_varray_in_cfunc,
                        FuncBodyTypeRange(body, retType))
                    builder.Emit()
                }
            }
        }
    }
}

public func CheckInvalidRefInCFunc(ctx: ASTContext, refExpr: RefExpr, target: Decl, diag: BasicDiagnosticEngine): Unit {
    if (!IsInCFunc(ctx, refExpr) || target.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.ENUM_CONSTRUCTOR)) {
        return
    }
    if (IsNonStaticMember(target)) {
        EmitLegacy(
            diag,
            BasicDiagKind.sema_cfunc_cannot_capture_this,
            refExpr,
            args: [BasicDiagArgument("this")])
    }
}

public func CheckInvalidRefInCFunc(ctx: ASTContext, refExpr: RefExpr, diag: BasicDiagnosticEngine): Unit {
    if (!IsInCFunc(ctx, refExpr)) {
        return
    }
    if (refExpr.isThis) {
        EmitLegacy(
            diag,
            BasicDiagKind.sema_cfunc_cannot_capture_this,
            refExpr,
            args: [BasicDiagArgument("this")])
    } else if (refExpr.isSuper) {
        EmitLegacy(
            diag,
            BasicDiagKind.sema_cfunc_cannot_capture_this,
            refExpr,
            args: [BasicDiagArgument("super")])
    }
}

public func CheckCTypeMember(decl: Decl, diag: BasicDiagnosticEngine): Unit {
    if (decl.astKind != ASTKind.VAR_DECL) {
        return
    }
    if (Ty.IsInitialTy(decl.GetTy())) {
        return
    }
    if (let None <- decl.outerDecl) {
        return
    }
    if (let Some(varDecl) <- (decl as VarDecl)) {
        if (let Some(outer) <- decl.outerDecl) {
            if (!Ty.IsTyCorrect(outer.GetTy())) {
                return
            }
            if (let Some(outerTy) <- outer.GetTy()) {
                if (!Ty.IsCStructType(outerTy)) {
                    return
                }
            }
            if (let Some(varTy) <- varDecl.GetTy()) {
                if (varTy.IsUnit()) {
                    EmitLegacy(
                        diag,
                        BasicDiagKind.sema_cstruct_cannot_have_unit_fields,
                        varDecl,
                        args: [BasicDiagArgument(varDecl.identifier.Val())])
                    return
                }
                if (Ty.IsMetCType(varTy)) {
                    return
                }
            }
            EmitLegacy(
                diag,
                BasicDiagKind.sema_illegal_member_of_cstruct,
                varDecl,
                args: [BasicDiagArgument(varDecl.identifier.Val()), BasicDiagArgument(outer.identifier.Val())])
        }
    }
}

public func CheckUnsafeInvoke(
    call: CallExpr,
    diag: BasicDiagnosticEngine,
    backendType!: OptionBackendType = OptionGlobalOptions().backend
): Unit {
    if (!OptionIsUnsafeBackend(backendType)) {
        return
    }
    if (let Some(resolved) <- call.resolvedFunction) {
        if (!Ty.IsTyCorrect(resolved.GetTy())) {
            return
        }
        var isUnsafe = resolved.TestAnyAttr(Attribute.UNSAFE, Attribute.FOREIGN)
        if (let Some(funcTy) <- (resolved.GetTy().getOrThrow() as FuncTy)) {
            isUnsafe = isUnsafe || funcTy.isC
        }
        if (isUnsafe && !call.TestAttr(Attribute.UNSAFE)) {
            EmitLegacy(diag, BasicDiagKind.sema_unsafe_function_invoke_failed, call)
        }
    }
}

public func CheckLegalityOfUnsafeAndInout(
    root: Node,
    diag: BasicDiagnosticEngine,
    backendType!: OptionBackendType = OptionGlobalOptions().backend
): Unit {
    let walker = Walker(root, visitPre: { node: Node =>
        if (let Some(call) <- (node as CallExpr)) {
            CheckUnsafeInvoke(call, diag, backendType: backendType)
        } else if (let Some(arg) <- (node as FuncArg)) {
            if (IsInoutZeroSizedArg(arg)) {
                EmitRefactor(
                    diag,
                    BasicDiagKindRefactor.sema_inout_modify_cstring_or_zerosized,
                    arg,
                    args: ["zero-sized type"])
            }
        }
        return VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}
