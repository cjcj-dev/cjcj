package cangjie_compiler::sema

import cangjie_compiler::ast.*

public func ChkFloatTypeOverflow(expr: LitConstExpr): Bool {
    return match (expr.constNumValue.asFloat.flowStatus) {
        case FlowStatus.OVER => false
        case FlowStatus.UNDER => false
        case _ => true
    }
}

public func ChkLitConstExprRange(expr: LitConstExpr): Bool {
    if (!Ty.IsTyCorrect(expr.GetTy())) {
        return false
    }
    InitializeLitConstValue(expr)
    if (let Some(exprTy) <- expr.GetTy()) {
        if (exprTy.IsInteger()) {
            expr.constNumValue.asInt.SetOutOfRange(exprTy)
            if (expr.constNumValue.asInt.IsOutOfRange()) {
                expr.SetTy(TypeManager.GetInvalidTy())
                return false
            }
        } else if (exprTy.IsFloating()) {
            if (!ChkFloatTypeOverflow(expr)) {
                expr.SetTy(TypeManager.GetInvalidTy())
                return false
            }
        }
    }
    return true
}

public func ReplaceIdealTy(typeManager: TypeManager, node: Node): Bool {
    if (!Ty.IsTyCorrect(node.GetTy())) {
        return false
    }
    if (let Some(nodeTy) <- node.GetTy()) {
        node.SetTy(typeManager.ReplaceIdealTy(nodeTy))
        if (let Some(lit) <- (node as LitConstExpr)) {
            return ChkLitConstExprRange(lit)
        }
        return true
    }
    return false
}
