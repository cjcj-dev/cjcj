package cjcj::chir

public enum IResult {
    | INotRun
    | IException(InterpreterValue)
    | ISuccess(InterpreterValue)
}

public class ConstEval {
    public init() {}

    public func EvaluateToLiteral(expr: Expression): Option<LiteralValue> {
        if (let Some(constant) <- (expr as Constant)) {
            return constant.literal
        }
        if (expr.IsUnaryExpr() && expr.GetNumOfOperands() == 1) {
            return EvaluateUnary(expr)
        }
        if (expr.IsBinaryExpr() && expr.GetNumOfOperands() == 2) {
            return EvaluateBinary(expr)
        }
        return None
    }

    private func EvaluateValue(value: Value): Option<LiteralValue> {
        if (let Some(local) <- value.AsLocalVar()) {
            if (let Some(expr) <- local.GetExpr()) {
                return EvaluateToLiteral(expr)
            }
        }
        if (let Some(globalVar) <- value.AsGlobalVar()) {
            if (let Some(initValue) <- globalVar.GetInitializer()) {
                return initValue
            }
        }
        return None
    }

    private func EvaluateUnary(expr: Expression): Option<LiteralValue> {
        if (let Some(operandLiteral) <- EvaluateValue(expr.GetOperand(0))) {
            let kind = expr.GetExprKind()
            if (let Some(intLiteral) <- (operandLiteral as IntLiteral)) {
                if (kind == ExprKind.NEG) {
                    return IntLiteral(-intLiteral.value)
                }
                if (kind == ExprKind.BITNOT) {
                    return IntLiteral(-intLiteral.value - 1)
                }
            }
            if (let Some(floatLiteral) <- (operandLiteral as FloatLiteral)) {
                if (kind == ExprKind.NEG) {
                    return FloatLiteral(-floatLiteral.value)
                }
            }
            if (let Some(boolLiteral) <- (operandLiteral as BoolLiteral)) {
                if (kind == ExprKind.NOT) {
                    return BoolLiteral(!boolLiteral.value)
                }
            }
        }
        return None
    }

    private func EvaluateBinary(expr: Expression): Option<LiteralValue> {
        let leftLit = EvaluateValue(expr.GetOperand(0))
        let rightLit = EvaluateValue(expr.GetOperand(1))
        if (leftLit.isNone() || rightLit.isNone()) {
            return None
        }
        if (let Some(leftValue) <- leftLit) {
            if (let Some(rightValue) <- rightLit) {
                if (let Some(leftInt) <- (leftValue as IntLiteral)) {
                    if (let Some(rightInt) <- (rightValue as IntLiteral)) {
                        return EvaluateIntBinary(expr.GetExprKind(), leftInt.value, rightInt.value)
                    }
                }
                if (let Some(leftFloat) <- (leftValue as FloatLiteral)) {
                    if (let Some(rightFloat) <- (rightValue as FloatLiteral)) {
                        return EvaluateFloatBinary(expr.GetExprKind(), leftFloat.value, rightFloat.value)
                    }
                }
                if (let Some(leftBool) <- (leftValue as BoolLiteral)) {
                    if (let Some(rightBool) <- (rightValue as BoolLiteral)) {
                        return EvaluateBoolBinary(expr.GetExprKind(), leftBool.value, rightBool.value)
                    }
                }
                if (let Some(leftString) <- (leftValue as StringLiteral)) {
                    if (let Some(rightString) <- (rightValue as StringLiteral)) {
                        return EvaluateStringBinary(expr.GetExprKind(), leftString.value, rightString.value)
                    }
                }
                if (leftValue.IsNullLit() && rightValue.IsNullLit()) {
                    return EvaluateUnitLikeBinary(expr.GetExprKind())
                }
                if (leftValue.IsUnitLit() && rightValue.IsUnitLit()) {
                    return EvaluateUnitLikeBinary(expr.GetExprKind())
                }
            }
        }
        return None
    }

    private func EvaluateIntBinary(kind: ExprKind, left: Int64, right: Int64): Option<LiteralValue> {
        return match (kind) {
            case ExprKind.ADD => IntLiteral(left + right)
            case ExprKind.SUB => IntLiteral(left - right)
            case ExprKind.MUL => IntLiteral(left * right)
            case ExprKind.DIV => if (right == 0) { None } else { IntLiteral(left / right) }
            case ExprKind.MOD => if (right == 0) { None } else { IntLiteral(left % right) }
            case ExprKind.EXP => EvaluateIntPow(left, right)
            case ExprKind.LSHIFT => if (right < 0) { None } else { IntLiteral(left << right) }
            case ExprKind.RSHIFT => if (right < 0) { None } else { IntLiteral(left >> right) }
            case ExprKind.BITAND => IntLiteral(left & right)
            case ExprKind.BITOR => IntLiteral(left | right)
            case ExprKind.BITXOR => IntLiteral(left ^ right)
            case ExprKind.LT => BoolLiteral(left < right)
            case ExprKind.GT => BoolLiteral(left > right)
            case ExprKind.LE => BoolLiteral(left <= right)
            case ExprKind.GE => BoolLiteral(left >= right)
            case ExprKind.EQUAL => BoolLiteral(left == right)
            case ExprKind.NOTEQUAL => BoolLiteral(left != right)
            case _ => None
        }
    }

    private func EvaluateFloatBinary(kind: ExprKind, left: Float64, right: Float64): Option<LiteralValue> {
        return match (kind) {
            case ExprKind.ADD => FloatLiteral(left + right)
            case ExprKind.SUB => FloatLiteral(left - right)
            case ExprKind.MUL => FloatLiteral(left * right)
            case ExprKind.DIV => FloatLiteral(left / right)
            case ExprKind.LT => BoolLiteral(left < right)
            case ExprKind.GT => BoolLiteral(left > right)
            case ExprKind.LE => BoolLiteral(left <= right)
            case ExprKind.GE => BoolLiteral(left >= right)
            case ExprKind.EQUAL => BoolLiteral(left == right)
            case ExprKind.NOTEQUAL => BoolLiteral(left != right)
            case _ => None
        }
    }

    private func EvaluateBoolBinary(kind: ExprKind, left: Bool, right: Bool): Option<LiteralValue> {
        return match (kind) {
            case ExprKind.AND => BoolLiteral(left && right)
            case ExprKind.OR => BoolLiteral(left || right)
            case ExprKind.EQUAL => BoolLiteral(left == right)
            case ExprKind.NOTEQUAL => BoolLiteral(left != right)
            case _ => None
        }
    }

    private func EvaluateStringBinary(kind: ExprKind, left: String, right: String): Option<LiteralValue> {
        return match (kind) {
            case ExprKind.EQUAL => BoolLiteral(left == right)
            case ExprKind.NOTEQUAL => BoolLiteral(left != right)
            case _ => None
        }
    }

    private func EvaluateUnitLikeBinary(kind: ExprKind): Option<LiteralValue> {
        return match (kind) {
            case ExprKind.EQUAL => BoolLiteral(true)
            case ExprKind.NOTEQUAL => BoolLiteral(false)
            case _ => None
        }
    }

    private func EvaluateIntPow(baseValue: Int64, exponent: Int64): Option<LiteralValue> {
        if (exponent < 0) {
            return None
        }
        var result: Int64 = 1
        var idx: Int64 = 0
        while (idx < exponent) {
            result *= baseValue
            idx++
        }
        return IntLiteral(result)
    }
}
