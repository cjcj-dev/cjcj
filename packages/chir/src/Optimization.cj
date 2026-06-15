package cangjie_compiler::chir

public class DeadCodeElimination {
    public init() {}

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
        if (expr.IsFuncCall() || expr.GetExprKind() == ExprKind.STORE || expr.GetExprKind() == ExprKind.DEBUGEXPR) {
            return false
        }
        if (let Some(result) <- expr.GetResult()) {
            return result.GetUsersRef().isEmpty()
        }
        return false
    }
}

public class MergeBlocks {
    public init() {}

    public func RunOnFunction(fn: Function): Int64 {
        // TODO(selfhost:CHIR): implement C++ MergeBlocks control-flow rewiring after all terminator subclasses are ported.
        if (fn.GetBody().isNone()) {
            return 0
        }
        return 0
    }
}

public class ConstPropagation {
    public init() {}

    public func RunOnFunction(fn: Function): Int64 {
        // TODO(selfhost:CHIR): port C++ constant lattice/evaluator; current package has no AST/Sema constant model dependency.
        if (fn.GetBody().isNone()) {
            return 0
        }
        return 0
    }
}
