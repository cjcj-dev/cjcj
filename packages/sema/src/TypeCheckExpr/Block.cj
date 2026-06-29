package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::sema.*

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

private func ReplaceCorrectIdealTy(typeManager: TypeManager, node: Node,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    return Ty.IsTyCorrect(node.GetTy()) && ReplaceIdealTy(typeManager, node, diag: diag)
}

public func SynBlock(typeManager: TypeManager, b: Block, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (b.body.isEmpty()) {
        let unitTy = UnitTy()
        b.SetTy(unitTy)
        return unitTy
    }
    var existInvalid = false
    for (node in b.body) {
        if (!ReplaceCorrectIdealTy(typeManager, node, diag: diag)) {
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

public func ChkBlock(typeManager: TypeManager, target: Ty, b: Block,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let unitTy = UnitTy()
    if (b.body.isEmpty()) {
        b.SetTy(unitTy)
        return typeManager.IsSubtype(unitTy, target)
    }

    var isWellTyped = true
    if (b.body.size > 1) {
        for (idx in 0..b.body.size - 1) {
            if (!ReplaceCorrectIdealTy(typeManager, b.body[idx], diag: diag)) {
                isWellTyped = false
            }
        }
    }

    if (let Some(lastNode) <- LastNodeForCheck(b)) {
        if (lastNode.IsDecl()) {
            let typeMatched = typeManager.IsSubtype(unitTy, target)
            isWellTyped = ReplaceCorrectIdealTy(typeManager, lastNode, diag: diag) && typeMatched && isWellTyped
            if (isWellTyped) {
                b.SetTy(unitTy)
                return true
            }
            let _ = InvalidBlock(b)
            return false
        }
        if (let Some(lastExpr) <- (lastNode as Expr)) {
            let checked = ChkExprShallow(typeManager, target, lastExpr, diag: diag)
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
