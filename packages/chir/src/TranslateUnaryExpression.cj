package cjcj::chir

import cjcj::utils.{CJC_ASSERT, OverflowStrategyIndex, StaticCast}

public func TranslateUnaryExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    CJC_ASSERT(expr.GetNumOfOperands() == 1)
    let opCode = BCHIRUnaryExprKindToOpCode(expr.GetExprKind())
    let unaryExpression = StaticCast<UnaryExpression>(expr)
    context.definition.PushOp(opCode)
    context.definition.PushCell(BCHIRTypeKindCell(expr.GetResultType()))
    context.definition.PushCell(OverflowStrategyIndex(unaryExpression.GetOverflowStrategy()))
}
