package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind

private func IsOverflowOp(op: TokenKind): Bool {
    return match (op) {
        case TokenKind.ADD => true
        case TokenKind.SUB => true
        case TokenKind.MUL => true
        case TokenKind.DIV => true
        case TokenKind.MOD => true
        case TokenKind.EXP => true
        case TokenKind.ADD_ASSIGN => true
        case TokenKind.SUB_ASSIGN => true
        case TokenKind.MUL_ASSIGN => true
        case TokenKind.DIV_ASSIGN => true
        case TokenKind.MOD_ASSIGN => true
        case TokenKind.EXP_ASSIGN => true
        case _ => false
    }
}

private func IsIntegerTy(ty: Option<Ty>): Bool {
    if (let Some(value) <- ty) {
        return value.kind != TypeKind.TYPE_INITIAL && value.IsInteger()
    }
    return false
}

private func IsNoOverflowStrategy(strategy: OverflowStrategy): Bool {
    return match (strategy) {
        case OverflowStrategy.NA => true
        case _ => false
    }
}

private func SetIncOrDecOverflowExpr(expr: IncOrDecExpr): Unit {
    if (!IsOverflowOp(expr.op)) {
        return
    }
    if (!IsIntegerTy(expr.GetTy())) {
        return
    }
    if (let Some(target) <- expr.expr) {
        if (!IsIntegerTy(target.GetTy())) {
            return
        }
        target.EnableAttr(Attribute.NUMERIC_OVERFLOW)
        target.overflowStrategy = expr.overflowStrategy
    }
    expr.EnableAttr(Attribute.NUMERIC_OVERFLOW)
}

private func SetAssignOverflowExpr(expr: AssignExpr): Unit {
    if (!IsOverflowOp(expr.op)) {
        return
    }
    if (let Some(left) <- expr.leftValue) {
        if (IsIntegerTy(left.GetTy())) {
            expr.EnableAttr(Attribute.NUMERIC_OVERFLOW)
        }
    }
}

private func SetUnaryOverflowExpr(expr: UnaryExpr): Unit {
    if (!IsOverflowOp(expr.op)) {
        return
    }
    if (let Some(value) <- expr.expr) {
        if (IsIntegerTy(value.GetTy())) {
            expr.EnableAttr(Attribute.NUMERIC_OVERFLOW)
        }
    }
}

private func SetBinaryOverflowExpr(expr: BinaryExpr): Unit {
    if (!IsOverflowOp(expr.op)) {
        return
    }
    if (let Some(left) <- expr.leftExpr) {
        if (let Some(right) <- expr.rightExpr) {
            if (IsIntegerTy(left.GetTy()) && IsIntegerTy(right.GetTy())) {
                expr.EnableAttr(Attribute.NUMERIC_OVERFLOW)
            }
        }
    }
}

public func SetOverflowFlag(node: Node): Unit {
    if (let Some(expr) <- (node as IncOrDecExpr)) {
        SetIncOrDecOverflowExpr(expr)
        return
    }
    if (let Some(expr) <- (node as AssignExpr)) {
        SetAssignOverflowExpr(expr)
        return
    }
    if (!IsIntegerTy(node.GetTy())) {
        return
    }
    if (let Some(expr) <- (node as UnaryExpr)) {
        SetUnaryOverflowExpr(expr)
        return
    }
    if (let Some(expr) <- (node as BinaryExpr)) {
        SetBinaryOverflowExpr(expr)
    }
}

public func SetOverflowStrategyForPkg(pkg: Package): Unit {
    SetOverflowStrategyForNode(pkg, OverflowStrategy.NA, OverflowStrategy.NA)
    let walker = Walker(pkg, visitPre: { curNode: Node =>
        SetOverflowFlag(curNode)
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func EffectiveOverflowStrategy(
    overflowStrategy: OverflowStrategy,
    optionStrategy: OverflowStrategy
): OverflowStrategy {
    if (IsNoOverflowStrategy(overflowStrategy)) {
        return optionStrategy
    }
    return overflowStrategy
}

private func SetExprOverflowStrategy(
    expr: Expr,
    overflowStrategy: OverflowStrategy,
    optionStrategy: OverflowStrategy
): Unit {
    match (expr.astKind) {
        case ASTKind.INC_OR_DEC_EXPR => applyExprOverflowStrategy(expr, overflowStrategy, optionStrategy)
        case ASTKind.ASSIGN_EXPR => applyExprOverflowStrategy(expr, overflowStrategy, optionStrategy)
        case ASTKind.UNARY_EXPR => applyExprOverflowStrategy(expr, overflowStrategy, optionStrategy)
        case ASTKind.BINARY_EXPR => applyExprOverflowStrategy(expr, overflowStrategy, optionStrategy)
        case ASTKind.TYPE_CONV_EXPR => applyExprOverflowStrategy(expr, overflowStrategy, optionStrategy)
        case _ => ()
    }
}

private func applyExprOverflowStrategy(
    expr: Expr,
    overflowStrategy: OverflowStrategy,
    optionStrategy: OverflowStrategy
): Unit {
    let selected = EffectiveOverflowStrategy(overflowStrategy, optionStrategy)
    expr.overflowStrategy = selected
    if (let Some(desugared) <- expr.desugarExpr) {
        desugared.overflowStrategy = selected
    }
}

public func SetOverflowStrategyForNode(
    root: Node,
    overflowStrategy: OverflowStrategy,
    optionStrategy: OverflowStrategy
): Unit {
    let walker = Walker(root, visitPre: { curNode: Node =>
        if (let Some(funcDecl) <- (curNode as FuncDecl)) {
            var funcHasOverflowStrategy = funcDecl.TestAttr(Attribute.NUMERIC_OVERFLOW)
            for (annotation in funcDecl.annotations) {
                if (annotation.kind == AstAnnotationKind.NUMERIC_OVERFLOW) {
                    funcHasOverflowStrategy = true
                    funcDecl.EnableAttr(Attribute.NUMERIC_OVERFLOW)
                    funcDecl.overflowStrategy = annotation.overflowStrategy
                    break
                }
            }
            if (funcHasOverflowStrategy) {
                if (let Some(funcBody) <- funcDecl.funcBody) {
                    SetOverflowStrategyForNode(funcBody, funcDecl.overflowStrategy, optionStrategy)
                }
                return VisitAction.SKIP_CHILDREN
            }
        } else if (let Some(lambdaExpr) <- (curNode as LambdaExpr)) {
            if (lambdaExpr.TestAttr(Attribute.NUMERIC_OVERFLOW)) {
                if (let Some(funcBody) <- lambdaExpr.funcBody) {
                    SetOverflowStrategyForNode(funcBody, lambdaExpr.overflowStrategy, optionStrategy)
                }
                return VisitAction.SKIP_CHILDREN
            }
        }
        if (let Some(expr) <- (curNode as Expr)) {
            SetExprOverflowStrategy(expr, overflowStrategy, optionStrategy)
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

public func SetIntegerOverflowStrategy(pkgs: ArrayList<Package>, optionStrategy: OverflowStrategy): Unit {
    if (IsNoOverflowStrategy(optionStrategy)) {
        return
    }
    for (pkg in pkgs) {
        SetOverflowStrategyForNode(pkg, OverflowStrategy.NA, optionStrategy)
    }
}

public func SetOverflowStrategyAfterTypeCheck(pkgs: ArrayList<Package>): Unit {
    for (pkg in pkgs) {
        SetOverflowStrategyForPkg(pkg)
    }
}
