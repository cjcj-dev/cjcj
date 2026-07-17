package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.MakeRange as BasicMakeRange
import cjcj::modules.SemaImportManager
import cjcj::sema.*
import cjcj::sema.Plugin.*
import cjcj::utils.CJC_ASSERT

private let LEVEL_IDENTIFIER: String = "level"
private let SYSCAP_IDENTIFIER: String = "syscap"

private func IfAvailableInvalid(iae: IfAvailableExpr): Ty {
    return TcInvalid(iae)
}

private func IsValidIfAvailableLevelLiteral(expr: Expr): Bool {
    if (let Some(lit) <- (expr as LitConstExpr)) {
        if (lit.kind == LitConstKind.INTEGER) {
            return true
        }
        if (lit.kind == LitConstKind.STRING) {
            return if (let Some(_) <- APILevelVersion.ParseChecked(lit.stringValue, APILevelParseRule.TRIPLE_ONLY)) {
                true
            } else {
                false
            }
        }
    }
    return false
}

private func IsLiteralLevelCondition(condExpr: Expr): Bool {
    if (let Some(callExpr) <- (condExpr as CallExpr)) {
        if (callExpr.args.size == 1) {
            if (let Some(argExpr) <- callExpr.args[0].expr) {
                return argExpr.astKind == ASTKind.LIT_CONST_EXPR
            }
        }
        return false
    }
    if (let Some(binaryExpr) <- (condExpr as BinaryExpr)) {
        if (binaryExpr.op == TokenKind.AND) {
            if (let Some(leftExpr) <- binaryExpr.leftExpr) {
                if (let Some(rightExpr) <- binaryExpr.rightExpr) {
                    return IsLiteralLevelCondition(leftExpr) && IsLiteralLevelCondition(rightExpr)
                }
            }
            return false
        }
        if (let Some(rightExpr2) <- binaryExpr.rightExpr) {
            return rightExpr2.astKind == ASTKind.LIT_CONST_EXPR
        }
    }
    return false
}

private func ChkIfImportDeviceInfo(diag: BasicDiagnosticEngine, importManager: SemaImportManager,
    iae: IfAvailableExpr): Bool {
    if (iae.GetFullPackageName() == "ohos.device_info") {
        return true
    }
    for (importedPkg in importManager.GetAllImportedPackages(false)) {
        if (importedPkg.srcPackage.fullPackageName == "ohos.device_info") {
            return true
        }
    }
    let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_use_expr_without_import, iae,
        arguments: ["ohos.device_info", "IfAvailable"])
    builder.AddNote("depend on declaration 'DeviceInfo'")
    builder.Emit()
    return false
}

private func ChkIfImportBase(diag: BasicDiagnosticEngine, importManager: SemaImportManager,
    iae: IfAvailableExpr): Bool {
    if (iae.GetFullPackageName() == "ohos.base") {
        return true
    }
    for (importedPkg in importManager.GetAllImportedPackages(false)) {
        if (importedPkg.srcPackage.fullPackageName == "ohos.base") {
            return true
        }
    }
    let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_use_expr_without_import, iae,
        arguments: ["ohos.base", "IfAvailable"])
    builder.AddNote("depend on declaration 'canIUse'")
    builder.Emit()
    return false
}

private class IfAvailableCheckState {
    public var res: Bool = true
    public var hasHardError: Bool = false

    public init() {}
}

private func ChkLevelArgument(diag: BasicDiagnosticEngine, importManager: SemaImportManager,
    iae: IfAvailableExpr, desugaredIf: IfExpr, state: IfAvailableCheckState): Unit {
    let hasDeviceInfoImport = ChkIfImportDeviceInfo(diag, importManager, iae)
    state.res = hasDeviceInfoImport && state.res
    state.hasHardError = !hasDeviceInfoImport || state.hasHardError
    let arg = iae.GetArg().getOrThrow()
    let argExpr = arg.expr.getOrThrow()
    if (!IsValidIfAvailableLevelLiteral(argExpr)) {
        if (let Some(lit) <- (argExpr as LitConstExpr)) {
            if (lit.kind == LitConstKind.STRING) {
                DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_apilevel_invalid_version_format, arg,
                    arguments: [lit.stringValue]).Emit()
            } else {
                DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_ifavailable_arg_not_literal, arg).Emit()
            }
        } else {
            DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_ifavailable_arg_not_literal, arg).Emit()
        }
        state.hasHardError = true
        state.res = false
    }
    if (!IsLiteralLevelCondition(desugaredIf.condExpr.getOrThrow())) {
        DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_ifavailable_arg_not_literal, arg).Emit()
        state.res = false
        state.hasHardError = true
    }
}

private func ChkSyscapArgument(diag: BasicDiagnosticEngine, importManager: SemaImportManager,
    iae: IfAvailableExpr, desugaredIf: IfExpr, state: IfAvailableCheckState): Unit {
    let hasBaseImport = ChkIfImportBase(diag, importManager, iae)
    state.res = hasBaseImport && state.res
    state.hasHardError = !hasBaseImport || state.hasHardError
    let condExpr = desugaredIf.condExpr.getOrThrow()
    CJC_ASSERT(condExpr.astKind == ASTKind.CALL_EXPR)
    let callExpr = (condExpr as CallExpr).getOrThrow()
    CJC_ASSERT(callExpr.args.size == 1)
    if (callExpr.args[0].expr.getOrThrow().astKind != ASTKind.LIT_CONST_EXPR) {
        DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_ifavailable_arg_not_literal,
            iae.GetArg().getOrThrow()).Emit()
        state.res = false
        state.hasHardError = true
    }
}

extend TypeChecker {
    public func SynIfAvailableExpr(ctx: ASTContext, iae: IfAvailableExpr): Ty {
        let desugaredIf = if (let Some(value) <- (iae.desugarExpr.getOrThrow() as IfExpr)) {
            value
        } else {
            return TypeManager.GetInvalidTy()
        }
        let state = IfAvailableCheckState()
        let arg = iae.GetArg().getOrThrow()
        let argName = arg.name
        if (argName.Empty()) {
            DiagnoseRefactor(impl.diag.getOrThrow(), BasicDiagKindRefactor.sema_ifavailable_arg_no_name, arg).Emit()
            state.res = false
            state.hasHardError = true
        }
        if (argName.Val() == LEVEL_IDENTIFIER && desugaredIf.condExpr.isSome()) {
            ChkLevelArgument(impl.diag.getOrThrow(), impl.importManager.getOrThrow(), iae, desugaredIf, state)
        } else if (argName.Val() == SYSCAP_IDENTIFIER && desugaredIf.condExpr.isSome()) {
            ChkSyscapArgument(impl.diag.getOrThrow(), impl.importManager.getOrThrow(), iae, desugaredIf, state)
        } else {
            impl.diag.getOrThrow().DiagnoseRefactor(BasicDiagKindRefactor.sema_ifavailable_unknow_arg_name,
                BasicMakeRange(argName.Begin(), argName.End()), argName.Val()).Emit()
            state.res = false
            state.hasHardError = true
        }
        let targetTy = impl.typeManager.GetFunctionTy(Array<Ty>(), TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        state.res = Check(ctx, targetTy, iae.GetLambda1().getOrThrow()) && state.res
        state.res = Check(ctx, targetTy, iae.GetLambda2().getOrThrow()) && state.res
        if (!state.res) {
            iae.SetTy(TypeManager.GetInvalidTy())
            return iae.GetTy().getOrThrow()
        }
        iae.SetTy(Synthesize(ctx, SynPos.EXPR_ARG, desugaredIf))
        return iae.GetTy().getOrThrow()
    }

    public func ChkIfAvailableExpr(ctx: ASTContext, target: Ty, iae: IfAvailableExpr): Bool {
        let actualTy = SynIfAvailableExpr(ctx, iae)
        if (!Ty.IsTyCorrect(actualTy)) {
            return false
        }
        if (!impl.typeManager.IsSubtype(actualTy, target)) {
            DiagMismatchedTypes(impl.diag.getOrThrow(), iae, target)
            return false
        }
        return true
    }
}
