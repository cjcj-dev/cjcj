package cangjie_compiler::ast

public class RecoverDesugar {
    public init() {}

    public static func Recover(root: Node): Unit {
        let walker = Walker(root, visitPre: { node: Node =>
            if (let Some(expr) <- (node as Expr)) {
                expr.desugarExpr = None
                expr.mapExpr = None
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }
}

public func RecoverDesugarExpr(root: Node): Unit {
    RecoverDesugar.Recover(root)
}
