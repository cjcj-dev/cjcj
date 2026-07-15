package cjcj::chir

import cjcj::utils.{CJC_ASSERT, OverflowStrategyIndex, StaticCast}
import std.collection.*

public func TranslateBinaryExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext, expr: Expression): Unit {
    CJC_ASSERT(expr.GetNumOfOperands() == 2)
    let binaryExpression = StaticCast<BinaryExpression>(expr)
    let opCode = BCHIRBinaryExprKindToOpCode(expr.GetExprKind())
    let args = ArrayList<Int64>([
        BCHIRTypeKindCell(binaryExpression.GetOperand(0).GetType()),
        OverflowStrategyIndex(binaryExpression.GetOverflowStrategy())
    ])
    compiler.PushOpCodeWithAnnotations(context, opCode, expr, args: args, storeCodePos: true)
    if (opCode == OpCode.BIN_LSHIFT || opCode == OpCode.BIN_RSHIFT) {
        context.definition.PushCell(BCHIRTypeKindCell(binaryExpression.GetOperand(1).GetType()))
    }
}
