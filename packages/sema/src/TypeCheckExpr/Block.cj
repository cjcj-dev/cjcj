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

extend TypeChecker {
    public func SynthesizeAndReplaceIdealTy(ctx: CheckerContext, node: Node): Bool {
        var valid = false
        try (ds = DiagSuppressor(impl.diag)) {
            valid = Ty.IsTyCorrect(SynthesizeNode(ctx.Ctx(), ctx.SynthPos(), node)) &&
                ReplaceIdealTy(impl.typeManager, node, diag: impl.diag) && !ds.HasError()
            ds.ReportDiag()
        }
        return valid
    }

    public func SynBlock(ctx: CheckerContext, b: Block): Ty {
        if (b.body.isEmpty()) {
            b.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
            return b.GetTy().getOrThrow()
        }
        var existInvalid = false
        for (idx in 0..b.body.size) {
            let exprPos = if (idx == b.body.size - 1 && ctx.SynthPos() != SynPos.UNUSED) {
                SynPos.IMPLICIT_RETURN
            } else { SynPos.UNUSED }
            existInvalid = !SynthesizeAndReplaceIdealTy(ctx.With(exprPos), b.body[idx]) || existInvalid
        }
        let lastNode = b.body[b.body.size - 1]
        if (existInvalid) {
            b.SetTy(TypeManager.GetInvalidTy())
        } else if (lastNode.IsDecl()) {
            b.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        } else {
            b.SetTy(lastNode.GetTy().getOrThrow())
        }
        return b.GetTy().getOrThrow()
    }

    public func ChkBlock(ctx: ASTContext, target: Ty, b: Block): Bool {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        if (b.body.isEmpty()) {
            b.SetTy(unitTy)
            let ret = impl.typeManager.IsSubtype(b.GetTy().getOrThrow(), target)
            if (!ret && b.TestAttr(Attribute.UNSAFE)) {
                if (let Some(diag) <- impl.diag) { DiagMismatchedTypes(diag, b, target) }
            }
            return ret
        }
        var isWellTyped = true
        if (b.body.size > 1) {
            for (idx in 0..b.body.size - 1) {
                isWellTyped = SynthesizeAndReplaceIdealTy(
                    CheckerContext(ctx, SynPos.UNUSED), b.body[idx]) && isWellTyped
            }
        }
        var lastNode = b.body[b.body.size - 1]
        if (!b.TestAttr(Attribute.COMPILER_ADD) && lastNode.TestAttr(Attribute.COMPILER_ADD) &&
            lastNode.astKind == ASTKind.RETURN_EXPR) {
            if ((let Some(returnExpr) <- (lastNode as ReturnExpr)) && (let Some(innerExpr) <- returnExpr.expr)) {
                lastNode = innerExpr
            }
        }
        if (lastNode.IsDecl()) {
            let typeMatched = impl.typeManager.IsSubtype(unitTy, target)
            isWellTyped = SynthesizeAndReplaceIdealTy(
                CheckerContext(ctx, SynPos.IMPLICIT_RETURN), lastNode) && typeMatched && isWellTyped
            if (isWellTyped) {
                b.SetTy(unitTy)
                return true
            }
            b.SetTy(TypeManager.GetInvalidTy())
            if (!typeMatched) {
                if (let Some(diag2) <- impl.diag) {
                    DiagMismatchedTypesWithFoundTy(diag2, lastNode, target, unitTy,
                        note: "definitions and declarations are always of type 'Unit'")
                }
            }
            return false
        }
        if ((let Some(lastExpr) <- (lastNode as Expr)) && Check(ctx, target, lastExpr) && isWellTyped) {
            b.SetTy(lastExpr.GetTy().getOrThrow())
            return true
        }
        b.SetTy(TypeManager.GetInvalidTy())
        return false
    }
}
