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
        if (let Some(result) <- expr.GetResult()) {
            return result.GetUsersRef().isEmpty() && IsRemovableUnusedExpression(expr)
        }
        return false
    }

    private func IsRemovableUnusedExpression(expr: Expression): Bool {
        let kind = expr.GetExprKind()
        match (expr.GetExprMajorKind()) {
            case ExprMajorKind.UNARY_EXPR => return kind == ExprKind.NOT || kind == ExprKind.BITNOT
            case ExprMajorKind.BINARY_EXPR => return IsRemovableBinaryExpression(kind)
            case ExprMajorKind.MEMORY_EXPR => return kind == ExprKind.LOAD || kind == ExprKind.GET_ELEMENT_REF
            case ExprMajorKind.STRUCTURED_CTRL_FLOW_EXPR => return kind == ExprKind.LAMBDA
            case ExprMajorKind.OTHERS => return kind == ExprKind.CONSTANT || kind == ExprKind.TUPLE ||
                kind == ExprKind.FIELD || kind == ExprKind.FIELD_BY_NAME || kind == ExprKind.VARRAY
            case _ => return false
        }
    }

    private func IsRemovableBinaryExpression(kind: ExprKind): Bool {
        return kind == ExprKind.BITAND || kind == ExprKind.BITOR || kind == ExprKind.BITXOR ||
            kind == ExprKind.LT || kind == ExprKind.GT || kind == ExprKind.LE || kind == ExprKind.GE ||
            kind == ExprKind.EQUAL || kind == ExprKind.NOTEQUAL || kind == ExprKind.AND || kind == ExprKind.OR
    }
}
