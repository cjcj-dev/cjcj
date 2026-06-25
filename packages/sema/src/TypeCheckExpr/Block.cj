package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public func SynthesizeAndReplaceIdealTy(typeManager: TypeManager, node: Node): Bool {
    if (!Ty.IsTyCorrect(node.GetTy())) {
        if (let Some(expr) <- (node as Expr)) {
            let _ = SynExprShallow(typeManager, expr)
        }
    }
    if (!Ty.IsTyCorrect(node.GetTy())) {
        return false
    }
    return ReplaceIdealTy(typeManager, node)
}

private func UnitTy(): Ty {
    return TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
}

private func InvalidBlock(b: Block): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    b.SetTy(invalidTy)
    return invalidTy
}

private func LastNodeForCheck(b: Block): Option<Node> {
    if (let Some(lastNode) <- b.GetLastExprOrDecl()) {
        if (!b.TestAttr(Attribute.COMPILER_ADD) && lastNode.TestAttr(Attribute.COMPILER_ADD) &&
            lastNode.astKind == ASTKind.RETURN_EXPR) {
            if (let Some(returnExpr) <- (lastNode as ReturnExpr)) {
                if (let Some(innerExpr) <- returnExpr.expr) {
                    return innerExpr
                }
            }
        }
        return lastNode
    }
    return None
}

public func SynBlock(typeManager: TypeManager, b: Block): Ty {
    if (b.body.isEmpty()) {
        let unitTy = UnitTy()
        b.SetTy(unitTy)
        return unitTy
    }
    var existInvalid = false
    for (node in b.body) {
        if (!SynthesizeAndReplaceIdealTy(typeManager, node)) {
            existInvalid = true
        }
    }
    if (existInvalid) {
        return InvalidBlock(b)
    }
    if (let Some(lastNode) <- b.GetLastExprOrDecl()) {
        if (lastNode.IsDecl()) {
            let unitTy = UnitTy()
            b.SetTy(unitTy)
            return unitTy
        }
        if (let Some(lastTy) <- lastNode.GetTy()) {
            b.SetTy(lastTy)
            return lastTy
        }
    }
    return InvalidBlock(b)
}

public func ChkBlock(typeManager: TypeManager, target: Ty, b: Block): Bool {
    let unitTy = UnitTy()
    if (b.body.isEmpty()) {
        b.SetTy(unitTy)
        return typeManager.IsSubtype(unitTy, target)
    }

    var isWellTyped = true
    if (b.body.size > 1) {
        for (idx in 0..b.body.size - 1) {
            if (!SynthesizeAndReplaceIdealTy(typeManager, b.body[idx])) {
                isWellTyped = false
            }
        }
    }

    if (let Some(lastNode) <- LastNodeForCheck(b)) {
        if (lastNode.IsDecl()) {
            let typeMatched = typeManager.IsSubtype(unitTy, target)
            isWellTyped = SynthesizeAndReplaceIdealTy(typeManager, lastNode) && typeMatched && isWellTyped
            if (isWellTyped) {
                b.SetTy(unitTy)
                return true
            }
            let _ = InvalidBlock(b)
            return false
        }
        if (let Some(lastExpr) <- (lastNode as Expr)) {
            let checked = ChkExprShallow(typeManager, target, lastExpr)
            if (isWellTyped && checked) {
                if (let Some(lastTy) <- lastExpr.GetTy()) {
                    b.SetTy(lastTy)
                    return true
                }
            }
        }
    }
    let _ = InvalidBlock(b)
    return false
}
