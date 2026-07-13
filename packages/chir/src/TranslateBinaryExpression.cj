package cjcj::chir

import cjcj::utils.{CJC_ASSERT, OverflowStrategyIndex, StaticCast}

public func TranslateBinaryExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    CJC_ASSERT(expr.GetNumOfOperands() == 2)
    let binaryExpression = StaticCast<BinaryExpression>(expr)
    let opCode = BCHIRBinaryExprKindToOpCode(expr.GetExprKind())
    context.definition.PushOp(opCode)
    context.definition.PushCell(BCHIRTypeKindCell(binaryExpression.GetOperand(0).GetType()))
    context.definition.PushCell(OverflowStrategyIndex(binaryExpression.GetOverflowStrategy()))
    if (opCode == OpCode.BIN_LSHIFT || opCode == OpCode.BIN_RSHIFT) {
        context.definition.PushCell(BCHIRTypeKindCell(binaryExpression.GetOperand(1).GetType()))
    }
}
