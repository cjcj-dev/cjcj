package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.*

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

private func SynthesizeAndReplaceIdealTy(typeManager: TypeManager, pos: SynPos, node: Node,
    synthesizer: Option<(SynPos, Node) -> Ty>, diag: Option<BasicDiagnosticEngine>): Bool {
    if (let Some(synthesize) <- synthesizer) {
        var valid = false
        try (ds = DiagSuppressor(diag)) {
            valid = Ty.IsTyCorrect(synthesize(pos, node)) && ReplaceIdealTy(typeManager, node, diag: diag) && !ds.HasError()
            ds.ReportDiag()
        }
        return valid
    }
    return Ty.IsTyCorrect(node.GetTy()) && ReplaceIdealTy(typeManager, node, diag: diag)
}

public func SynBlock(typeManager: TypeManager, b: Block, pos!: SynPos = SynPos.NONE,
    synthesizer!: Option<(SynPos, Node) -> Ty> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (b.body.isEmpty()) {
        let unitTy = UnitTy()
        b.SetTy(unitTy)
        return unitTy
    }
    var existInvalid = false
    for (idx in 0..b.body.size) {
        let node = b.body[idx]
        let exprPos = if (idx == b.body.size - 1 && pos != SynPos.UNUSED) {
            SynPos.IMPLICIT_RETURN
        } else {
            SynPos.UNUSED
        }
        if (!SynthesizeAndReplaceIdealTy(typeManager, exprPos, node, synthesizer, diag)) {
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
    synthesizer!: Option<(SynPos, Node) -> Ty> = None, checker!: Option<(Ty, Expr) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let unitTy = UnitTy()
    if (b.body.isEmpty()) {
        b.SetTy(unitTy)
        let ret = typeManager.IsSubtype(unitTy, target)
        if (!ret && b.TestAttr(Attribute.UNSAFE)) {
            if (let Some(diagValue) <- diag) {
                let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_mismatched_types, b.begin,
                    arguments: [target.String(), unitTy.String()])
                builder.Emit()
            }
        }
        return ret
    }

    var isWellTyped = true
    if (b.body.size > 1) {
        for (idx in 0..b.body.size - 1) {
            if (!SynthesizeAndReplaceIdealTy(typeManager, SynPos.UNUSED, b.body[idx], synthesizer, diag)) {
                isWellTyped = false
            }
        }
    }

    if (let Some(lastNode) <- LastNodeForCheck(b)) {
        if (lastNode.IsDecl()) {
            let typeMatched = typeManager.IsSubtype(unitTy, target)
            isWellTyped = SynthesizeAndReplaceIdealTy(typeManager, SynPos.IMPLICIT_RETURN, lastNode, synthesizer, diag) &&
                typeMatched && isWellTyped
            if (isWellTyped) {
                b.SetTy(unitTy)
                return true
            }
            if (!typeMatched) {
                if (let Some(diagValue2) <- diag) {
                    DiagMismatchedTypesWithFoundTy(diagValue2, lastNode, target, unitTy,
                        note: "definitions and declarations are always of type 'Unit'")
                }
            }
            let _ = InvalidBlock(b)
            return false
        }
        if (let Some(lastExpr) <- (lastNode as Expr)) {
            let checked = if (let Some(check) <- checker) {
                check(target, lastExpr)
            } else {
                ChkExprShallow(typeManager, target, lastExpr, diag: diag)
            }
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
