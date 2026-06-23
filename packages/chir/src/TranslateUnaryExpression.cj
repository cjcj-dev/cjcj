package cangjie_compiler::chir

import cangjie_compiler::utils.{OverflowStrategy, OverflowStrategyIndex}

public func CHIR2BCHIRTranslateUnaryExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    let opCode = BCHIRUnaryExprKindToOpCode(expr.GetExprKind())
    if (opCode == OpCode.INVALID) {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
        return
    }
    context.definition.PushOp(opCode)
    context.definition.PushCell(BCHIRTypeKindCell(expr.GetResultType()))
    let overflowStrategy = if (let Some(unaryExpr) <- (expr as UnaryExpression)) {
        unaryExpr.GetOverflowStrategy()
    } else {
        OverflowStrategy.NA
    }
    context.definition.PushCell(OverflowStrategyIndex(overflowStrategy))
}
