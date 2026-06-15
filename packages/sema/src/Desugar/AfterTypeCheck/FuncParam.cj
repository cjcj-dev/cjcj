package cangjie_compiler::sema.Desugar.AfterTypeCheck

import cangjie_compiler::ast.*
import cangjie_compiler::option.GlobalOptions

private func IsArrayArgLineInfoKind(kind: ASTKind): Bool {
    return kind == ASTKind.LIT_CONST_EXPR || kind == ASTKind.REF_EXPR || kind == ASTKind.ARRAY_LIT ||
        kind == ASTKind.TUPLE_LIT || kind == ASTKind.SUBSCRIPT_EXPR
}

private func IsDefaultParamLineInfoKind(kind: ASTKind): Bool {
    return IsArrayArgLineInfoKind(kind) || kind == ASTKind.RANGE_EXPR
}

private func RemoveSubScriptTypeLineInfo(assignmentExpr: Expr): Unit {
    if (let Some(desugar) <- assignmentExpr.desugarExpr) {
        if (let Some(arrayCallExpr) <- (desugar as CallExpr)) {
            if (arrayCallExpr.args.isEmpty()) {
                return
            }
            desugar.begin.Mark(PositionStatus.IGNORE)
            if (let Some(arrayArgExpr) <- arrayCallExpr.args[0].expr) {
                if (IsArrayArgLineInfoKind(arrayArgExpr.astKind)) {
                    arrayArgExpr.begin.Mark(PositionStatus.IGNORE)
                    arrayCallExpr.args[0].begin.Mark(PositionStatus.IGNORE)
                    if (let Some(subscriptExpr) <- (arrayArgExpr as SubscriptExpr)) {
                        RemoveSubScriptTypeLineInfo(subscriptExpr)
                    }
                }
            }
        }
    }
}

private func CleanCallExprLineInfo(callExpr: CallExpr): Unit {
    var isEnumCtor = false
    if (let Some(funcDecl) <- callExpr.resolvedFunction) {
        isEnumCtor = funcDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)
    }
    var isCStrCtor = false
    if (let Some(base) <- callExpr.baseFunc) {
        if (let Some(target) <- base.GetTarget()) {
            if (let Some(builtinDecl) <- (target as BuiltInDecl)) {
                isCStrCtor = builtinDecl.IsType(BuiltInType.CSTRING)
            }
        }
    }
    if (isCStrCtor) {
        callExpr.begin.Mark(PositionStatus.IGNORE)
    }
    if (isEnumCtor || isCStrCtor) {
        for (arg in callExpr.args) {
            if (let Some(argExpr) <- arg.expr) {
                CleanExprLineInfo(argExpr)
            }
        }
    }
}

private func CleanExprLineInfo(expr: Expr): Unit {
    if (expr.astKind == ASTKind.LIT_CONST_EXPR || expr.astKind == ASTKind.REF_EXPR ||
        expr.astKind == ASTKind.RANGE_EXPR) {
        expr.begin.Mark(PositionStatus.IGNORE)
        if (let Some(desugar) <- expr.desugarExpr) {
            desugar.begin.Mark(PositionStatus.IGNORE)
        }
    } else if (let Some(arrayExpr) <- (expr as ArrayLit)) {
        expr.begin.Mark(PositionStatus.IGNORE)
        for (child in arrayExpr.children) {
            CleanExprLineInfo(child)
        }
    } else if (let Some(tupleExpr) <- (expr as TupleLit)) {
        expr.begin.Mark(PositionStatus.IGNORE)
        for (child in tupleExpr.children) {
            CleanExprLineInfo(child)
        }
    } else if (let Some(block) <- (expr as Block)) {
        if (block.TestAttr(Attribute.UNSAFE)) {
            expr.begin.Mark(PositionStatus.IGNORE)
            block.unsafePos.Mark(PositionStatus.IGNORE)
            for (node in block.body) {
                if (let Some(bodyExpr) <- (node as Expr)) {
                    CleanExprLineInfo(bodyExpr)
                }
            }
        }
    } else if (let Some(callExpr) <- (expr as CallExpr)) {
        CleanCallExprLineInfo(callExpr)
    } else if (let Some(subscriptExpr) <- (expr as SubscriptExpr)) {
        if (let Some(desugar) <- subscriptExpr.desugarExpr) {
            expr.begin.Mark(PositionStatus.IGNORE)
            desugar.begin.Mark(PositionStatus.IGNORE)
            if (let Some(callExpr) <- (desugar as CallExpr)) {
                if (let Some(base) <- callExpr.baseFunc) {
                    if (let Some(memberAccess) <- (base as MemberAccess)) {
                        if (let Some(baseExpr) <- memberAccess.baseExpr) {
                            if (let Some(baseTy) <- baseExpr.GetTy()) {
                                if (baseTy.IsStructArray()) {
                                    baseExpr.begin.Mark(PositionStatus.IGNORE)
                                    RemoveSubScriptTypeLineInfo(expr)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private func ProcessDefaultParamLineInfo(funcDecl: FuncDecl): Unit {
    if (let Some(funcBody) <- funcDecl.funcBody) {
        if (let Some(body) <- funcBody.body) {
            if (body.body.isEmpty() || body.body[0].astKind != ASTKind.RETURN_EXPR) {
                return
            }
            if (let Some(paramAssignment) <- (body.body[0] as ReturnExpr)) {
                if (let Some(assignmentExpr) <- paramAssignment.expr) {
                    let isRefLiteral = IsDefaultParamLineInfoKind(assignmentExpr.astKind)
                    let isUnsafeBlock = assignmentExpr.astKind == ASTKind.BLOCK &&
                        assignmentExpr.TestAttr(Attribute.UNSAFE)
                    if (isRefLiteral || isUnsafeBlock) {
                        paramAssignment.begin.Mark(PositionStatus.IGNORE)
                    }
                    funcDecl.begin.Mark(PositionStatus.IGNORE)
                    CleanExprLineInfo(assignmentExpr)
                }
            }
        }
    }
}

public func PostProcessFuncParam(param: FuncParam, options: GlobalOptions): Unit {
    if (let Some(desugarDecl) <- param.desugarDecl) {
        if (let Some(funcBody) <- desugarDecl.funcBody) {
            if (let Some(_) <- funcBody.body) {
                if (!options.enableCoverage) {
                    ProcessDefaultParamLineInfo(desugarDecl)
                }
            }
        }
    }
}
