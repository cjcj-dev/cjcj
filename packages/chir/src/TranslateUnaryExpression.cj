package cjcj::chir

import cjcj::utils.{CJC_ASSERT, OverflowStrategyIndex, StaticCast}
import std.collection.*

public func TranslateUnaryExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext, expr: Expression): Unit {
    CJC_ASSERT(expr.GetNumOfOperands() == 1)
    let opCode = BCHIRUnaryExprKindToOpCode(expr.GetExprKind())
    let unaryExpression = StaticCast<UnaryExpression>(expr)
    compiler.PushOpCodeWithAnnotations(context, opCode, expr,
        args: ArrayList<Int64>([
            BCHIRTypeKindCell(expr.GetResultType()),
            OverflowStrategyIndex(unaryExpression.GetOverflowStrategy())
        ]), storeCodePos: true)
}
