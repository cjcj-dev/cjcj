package cangjie_compiler::chir

public class ConstPropagation {
    public init() {}

    public func RunOnPackage(pkg: Package): Int64 {
        var changed: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            changed += RunOnFunction(fn)
        }
        return changed
    }

    public func RunOnFunction(fn: Function): Int64 {
        // TODO(selfhost:CHIR): port C++ constant lattice/evaluator and branch rewriting.
        var changed: Int64 = 0
        if (let Some(body) <- fn.GetBody()) {
            for (block in body.GetBlocksRef()) {
                changed += SimplifyBlock(block)
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
            if (TrySimplifyBinary(expr)) {
                changed++
            } else {
                idx++
            }
        }
        return changed
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
            result.ReplaceWith(operand)
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
