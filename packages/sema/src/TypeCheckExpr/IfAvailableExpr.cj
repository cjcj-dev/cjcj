package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.*
import cjcj::sema.Plugin.*

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

private func CheckIfAvailableArg(iae: IfAvailableExpr, desugaredIf: IfExpr): Bool {
    if (let Some(arg) <- iae.GetArg()) {
        if (arg.name.Empty()) {
            return false
        }
        let argName = arg.name.Val()
        if (argName == LEVEL_IDENTIFIER) {
            if (let Some(argExpr) <- arg.expr) {
                if (!IsValidIfAvailableLevelLiteral(argExpr)) {
                    return false
                }
            } else {
                return false
            }
            if (let Some(condExpr) <- desugaredIf.condExpr) {
                return IsLiteralLevelCondition(condExpr)
            }
            return false
        }
        if (argName == SYSCAP_IDENTIFIER) {
            if (let Some(condExpr2) <- desugaredIf.condExpr) {
                if (let Some(callExpr) <- (condExpr2 as CallExpr)) {
                    if (callExpr.args.size == 1) {
                        if (let Some(argExpr2) <- callExpr.args[0].expr) {
                            return argExpr2.astKind == ASTKind.LIT_CONST_EXPR
                        }
                    }
                }
            }
            return false
        }
    }
    return false
}

public func SynIfAvailableExpr(typeManager: TypeManager, iae: IfAvailableExpr,
    diag: BasicDiagnosticEngine): Ty {
    if (let Some(desugar) <- iae.desugarExpr) {
        if (let Some(desugaredIf) <- (desugar as IfExpr)) {
            var ok = CheckIfAvailableArg(iae, desugaredIf)
            let lambdaTy = typeManager.GetFunctionTy(Array<Ty>(), TcUnitTy())
            if (let Some(lambda1) <- iae.GetLambda1()) {
                ok = ChkLamExpr(typeManager, lambdaTy, lambda1) && ok
            } else {
                ok = false
            }
            if (let Some(lambda2) <- iae.GetLambda2()) {
                ok = ChkLamExpr(typeManager, lambdaTy, lambda2) && ok
            } else {
                ok = false
            }
            let ifTy = SynIfExpr(typeManager, desugaredIf, diag)
            ok = Ty.IsTyCorrect(ifTy) && ok
            if (ok) {
                iae.SetTy(ifTy)
                return ifTy
            }
        }
    }
    return IfAvailableInvalid(iae)
}

public func ChkIfAvailableExpr(typeManager: TypeManager, target: Ty, iae: IfAvailableExpr,
    diag: BasicDiagnosticEngine): Bool {
    let actualTy = SynIfAvailableExpr(typeManager, iae, diag)
    if (Ty.IsTyCorrect(actualTy) &&
        typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = IfAvailableInvalid(iae)
    return false
}

extend TypeChecker {
}
