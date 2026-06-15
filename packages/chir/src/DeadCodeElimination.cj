package cangjie_compiler::chir

public class DeadCodeElimination {
    public init() {}

    public func RunOnPackage(pkg: Package): Int64 {
        var removed: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            removed += RunOnFunction(fn)
        }
        return removed
    }

    public func RunOnFunction(fn: Function): Int64 {
        var removed: Int64 = 0
        if (let Some(body) <- fn.GetBody()) {
            for (block in body.GetBlocksRef()) {
                removed += RunOnBlock(block)
            }
        }
        return removed
    }

    private func RunOnBlock(block: Block): Int64 {
        var removed: Int64 = 0
        let exprs = block.GetExpressionsRef()
        var idx: Int64 = 0
        while (idx < exprs.size) {
            let expr = exprs[idx]
            if (CanRemove(expr)) {
                expr.RemoveSelfFromBlock()
                removed++
            } else {
                idx++
            }
        }
        return removed
    }

    private func CanRemove(expr: Expression): Bool {
        if (expr.IsTerminator() || expr.HasExceptionBranch()) {
            return false
        }
        if (expr.GetExprKind() == ExprKind.STORE || expr.GetExprKind() == ExprKind.DEBUGEXPR) {
            return false
        }
        if (expr.IsFuncCall() && !IsNoSideEffectCall(expr)) {
            return false
        }
        if (let Some(result) <- expr.GetResult()) {
            return result.GetUsersRef().isEmpty()
        }
        return false
    }

    private func IsNoSideEffectCall(expr: Expression): Bool {
        if (!expr.IsFuncCall() || expr.GetNumOfOperands() == 0) {
            return false
        }
        if (let Some(callee) <- expr.GetOperand(0).AsFunction()) {
            return callee.TestAttr(Attribute.NO_SIDE_EFFECT)
        }
        return false
    }
}
