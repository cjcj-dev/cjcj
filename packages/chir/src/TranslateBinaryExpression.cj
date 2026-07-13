package cjcj::chir

import cjcj::utils.{OverflowStrategy, OverflowStrategyIndex}

public func TranslateBinaryExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    let opCode = BCHIRBinaryExprKindToOpCode(expr.GetExprKind())
    if (opCode == OpCode.INVALID) {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
        return
    }
    context.definition.PushOp(opCode)
    if (expr.GetNumOfOperands() > 0) {
        context.definition.PushCell(BCHIRTypeKindCell(expr.GetOperand(0).GetType()))
    } else {
        context.definition.PushCell(BCHIRTypeKindCell(expr.GetResultType()))
    }
    let overflowStrategy = if (let Some(binaryExpr) <- (expr as BinaryExpression)) {
        binaryExpr.GetOverflowStrategy()
    } else {
        OverflowStrategy.NA
    }
    context.definition.PushCell(OverflowStrategyIndex(overflowStrategy))
    if (opCode == OpCode.BIN_LSHIFT || opCode == OpCode.BIN_RSHIFT) {
        if (expr.GetNumOfOperands() > 1) {
            context.definition.PushCell(BCHIRTypeKindCell(expr.GetOperand(1).GetType()))
        } else {
            context.definition.PushCell(TypeKindIndex(TypeKind.TYPE_INVALID))
        }
    }
}
