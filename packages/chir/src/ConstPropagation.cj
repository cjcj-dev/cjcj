package cangjie_compiler::chir

public class ConstPropagation {
    private let builder: Option<CHIRBuilder>
    private let constEval: ConstEval = ConstEval()

    public init(builder!: Option<CHIRBuilder> = None) {
        this.builder = builder
    }

    public func RunOnPackage(pkg: Package): Int64 {
        var changed: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            changed += RunOnFunction(fn)
        }
        return changed
    }

    public func RunOnFunction(fn: Function): Int64 {
        if (let Some(body) <- fn.GetBody()) {
            return SimplifyBody(body)
        }
        return 0
    }

    private func SimplifyBody(body: BlockGroup): Int64 {
        var changed: Int64 = 0
        for (block in body.GetBlocksRef()) {
            changed += SimplifyBlock(block)
            for (expr in block.GetExpressions()) {
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        changed += SimplifyBody(lambdaBody)
                    }
                }
            }
        }
        return changed
    }

    private func SimplifyBlock(block: Block): Int64 {
        var changed: Int64 = 0
        let exprs = block.GetExpressionsRef()
        var idx: Int64 = 0
        while (idx < exprs.size) {
            let expr = exprs[idx]
            if (TryFoldToConstant(expr)) {
                changed++
            } else if (TrySimplifyUnary(expr)) {
                changed++
            } else if (TrySimplifyBinary(expr)) {
                changed++
            } else {
                idx++
            }
        }
        return changed
    }

    private func TryFoldToConstant(expr: Expression): Bool {
        if (expr.IsConstant() || expr.IsTerminator() || expr.HasExceptionBranch()) {
            return false
        }
        if (builder.isNone()) {
            return false
        }
        if (let Some(foldedLiteral) <- constEval.EvaluateToLiteral(expr)) {
            if (let Some(result) <- expr.GetResult()) {
                if (let Some(resultTy) <- result.GetType()) {
                    if (let Some(parentBlock) <- expr.GetParentBlock()) {
                        if (let Some(chirBuilder) <- builder) {
                            let newExpr = chirBuilder.CreateConstant(resultTy, foldedLiteral, parentBlock)
                            newExpr.SetDebugLocation(expr.GetDebugLocation())
                            expr.ReplaceWith(newExpr)
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    private func TrySimplifyUnary(expr: Expression): Bool {
        if (!expr.IsUnaryExpr() || expr.GetNumOfOperands() != 1) {
            return false
        }
        let kind = expr.GetExprKind()
        if (kind != ExprKind.NOT && kind != ExprKind.BITNOT) {
            return false
        }
        let operand = expr.GetOperand(0)
        if (let Some(local) <- operand.AsLocalVar()) {
            if (let Some(operandExpr) <- local.GetExpr()) {
                if (operandExpr.GetExprKind() == kind && operandExpr.GetNumOfOperands() == 1) {
                    return ReplaceResultWithOperand(expr, operandExpr.GetOperand(0))
                }
            }
        }
        return false
    }

    private func TrySimplifyBinary(expr: Expression): Bool {
        if (!expr.IsBinaryExpr() || expr.GetNumOfOperands() != 2) {
            return false
        }
        let lhs = expr.GetOperand(0)
        let rhs = expr.GetOperand(1)
        let kind = expr.GetExprKind()
        if ((kind == ExprKind.ADD || kind == ExprKind.BITOR) && IsIntLiteral(lhs, 0)) {
            return ReplaceResultWithOperand(expr, rhs)
        }
        if ((kind == ExprKind.ADD || kind == ExprKind.SUB || kind == ExprKind.LSHIFT ||
            kind == ExprKind.RSHIFT || kind == ExprKind.BITOR) && IsIntLiteral(rhs, 0)) {
            return ReplaceResultWithOperand(expr, lhs)
        }
        if (kind == ExprKind.MUL && IsIntLiteral(lhs, 1)) {
            return ReplaceResultWithOperand(expr, rhs)
        }
        if ((kind == ExprKind.MUL || kind == ExprKind.DIV || kind == ExprKind.EXP) && IsIntLiteral(rhs, 1)) {
            return ReplaceResultWithOperand(expr, lhs)
        }
        if ((kind == ExprKind.BITAND || kind == ExprKind.BITOR) && lhs.nodeId == rhs.nodeId) {
            return ReplaceResultWithOperand(expr, lhs)
        }
        return false
    }

    private func ReplaceResultWithOperand(expr: Expression, operand: Value): Bool {
        if (let Some(result) <- expr.GetResult()) {
            result.ReplaceWith(operand, expr.GetParentBlockGroup())
            expr.RemoveSelfFromBlock()
            return true
        }
        return false
    }

    private func IsIntLiteral(value: Value, expected: Int64): Bool {
        if (let Some(local) <- value.AsLocalVar()) {
            if (let Some(expr) <- local.GetExpr()) {
                if (let Some(constant) <- (expr as Constant)) {
                    if (let Some(intLiteral) <- (constant.literal as IntLiteral)) {
                        return intLiteral.value == expected
                    }
                }
            }
        }
        return false
    }
}
