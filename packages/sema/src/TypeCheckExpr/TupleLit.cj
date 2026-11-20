package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.MakeRange as BasicMakeRange
import cjcj::sema.*

private func invalidTupleLit(tl: TupleLit): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    tl.SetTy(invalidTy)
    return invalidTy
}

private func unboxOptionType(ty: Ty): Ty {
    var currentTy = ty
    while (!currentTy.HasInvalidTy() && currentTy.IsCoreOptionType()) {
        if (currentTy.typeArgs.size != 1) {
            return TypeManager.GetInvalidTy()
        }
        currentTy = currentTy.typeArgs[0]
    }
    return currentTy
}

private func replaceIdealChildTy(typeManager: TypeManager, expr: Expr): Option<Ty> {
    if (let Some(exprTy) <- expr.GetTy()) {
        if (exprTy.IsIdeal()) {
            let concreteTy = typeManager.ReplaceIdealTy(exprTy)
            expr.SetTy(concreteTy)
            return concreteTy
        }
        return exprTy
    }
    return None
}

private func diagMismatchedTypesWithFoundTy(
    diag: Option<BasicDiagnosticEngine>,
    node: Node,
    expected: String,
    found: String
): Unit {
    if (!node.ShouldDiagnose(allowCompilerAdd: true)) {
        return
    }
    if (let Some(diagValue) <- diag) {
        let builder = DiagnoseRefactor(diagValue,
            BasicDiagKindRefactor.sema_mismatched_types,
            node)
        builder.AddMainHintArguments([expected, found])
        builder.Emit()
    }
}

private func diagMismatchedTypes(
    diag: Option<BasicDiagnosticEngine>,
    node: Node,
    target: Ty
): Unit {
    if (!Ty.IsTyCorrect(node.GetTy()) || !Ty.IsTyCorrect(target)) {
        return
    }
    diagMismatchedTypesWithFoundTy(diag, node, target.String(), (node.GetTy() ?? TypeManager.GetInvalidTy()).String())
}

public func SynTupleLit(typeManager: TypeManager, tl: TupleLit): Ty {
    let elementTys = ArrayList<Ty>()
    for (child in tl.children) {
        if (let Some(elementTy) <- replaceIdealChildTy(typeManager, child)) {
            elementTys.add(elementTy)
        } else {
            return invalidTupleLit(tl)
        }
    }
    let tupleTy = typeManager.GetTupleTy(elementTys.toArray())
    tl.SetTy(tupleTy)
    return tupleTy
}

public func ChkTupleLit(typeManager: TypeManager, target: Ty, tl: TupleLit, synthesizer: (TupleLit) -> Ty,
    check!: Option<(Ty, Expr) -> Bool> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (target.IsAny()) {
        tl.SetTy(synthesizer(tl))
        let _ = ReplaceIdealTy(typeManager, tl, diag: diag)
        return Ty.IsTyCorrect(tl.GetTy())
    }

    let targetTy = unboxOptionType(target)
    if (targetTy.HasInvalidTy() || !targetTy.IsTuple()) {
        diagMismatchedTypesWithFoundTy(diag, tl, targetTy.String(), "Tuple")
        tl.SetTy(TypeManager.GetNonNullTy(tl.GetTy() ?? TypeManager.GetInvalidTy()))
        return false
    }
    if (let Some(targetTuple) <- (targetTy as TupleTy)) {
        if (targetTuple.typeArgs.size != tl.children.size) {
            tl.SetTy(synthesizer(tl))
            let _ = ReplaceIdealTy(typeManager, tl, diag: diag)
            diagMismatchedTypes(diag, tl, targetTy)
            return false
        }
        for (idx in 0..targetTuple.typeArgs.size) {
            let child = tl.children[idx]
            if (let Some(checkFunc) <- check) {
                if (!checkFunc(targetTuple.typeArgs[idx], child)) {
                    diagMismatchedTypes(diag, child, targetTuple.typeArgs[idx])
                    tl.SetTy(synthesizer(tl))
                    let _ = ReplaceIdealTy(typeManager, tl, diag: diag)
                    return false
                }
                continue
            }
            if (let Some(childTy) <- replaceIdealChildTy(typeManager, child)) {
                // C++ Check(ctx, typeArgs[i], child) => child <: elem (TupleLit.cpp)
                if (childTy.HasInvalidTy() ||
                    !typeManager.IsSubtype(childTy, targetTuple.typeArgs[idx])) {
                    let _ = SynTupleLit(typeManager, tl)
                    return false
                }
            } else {
                let _ = invalidTupleLit(tl)
                return false
            }
        }
        tl.SetTy(targetTy)
        return true
    }
    let _ = invalidTupleLit(tl)
    return false
}

extend TypeChecker {
}

// Each tuple projection takes the mode of the tuple. A Nothing branch contributes no value;
// Copyable values constrain the join only when there are no non-Copyable contributors.
func JoinResultModes(tm: TypeManager, values: ArrayList<Expr>, modeOf: (Expr) -> Option<ASTMode>): ASTMode {
    var nonCopy: Option<ASTMode> = None
    var copy: Option<ASTMode> = None
    for (value in values) {
        if (value.GetTy().isNone()) { continue }
        let ty = value.GetTy().getOrThrow()
        if (ty.IsNothing()) { continue }
        let actual = modeOf(value)
        if (actual.isNone()) { continue }
        let mode = actual.getOrThrow()
        if (tm.IsModalCopyType(ty)) {
            copy = if ((let Some(prior) <- copy) && prior != mode) { Some(ASTMode.HALF) } else { Some(mode) }
        } else {
            nonCopy = if ((let Some(prior) <- nonCopy) && prior != mode) { Some(ASTMode.HALF) } else { Some(mode) }
        }
    }
    return nonCopy ?? (copy ?? ASTMode.NOT)
}

func BindingResultMode(tm: TypeManager, value: Expr, receiver: ASTMode): Option<ASTMode> {
    if (let Some(tuple) <- (value as TupleLit)) {
        return JoinResultModes(tm, tuple.children, { e => BindingResultMode(tm, e, receiver) })
    }
    let results = ResultBranches(value)
    if (!results.isEmpty()) {
        return JoinResultModes(tm, results, { e => BindingResultMode(tm, e, receiver) })
    }
    return CallSiteMode(value, receiver, HashSet<Decl>())
}

func BindTuplePatternMode(pattern: Pattern, mode: ASTMode): Unit {
    pattern.resolvedMode = mode
    if (let Some(tuple) <- (pattern as TuplePattern)) {
        for (child in tuple.patterns) { BindTuplePatternMode(child, mode) }
    } else if (let Some(p) <- (pattern as VarPattern)) {
        if (let Some(decl) <- p.varDecl) { decl.resolvedMode = mode }
    } else if (let Some(p) <- (pattern as VarOrEnumPattern)) {
        if (let Some(inner) <- p.pattern) { BindTuplePatternMode(inner, mode) }
    }
}

// The result of a conditional never comes from its condition, selector, or finally block.
func ResultBranches(value: Expr): ArrayList<Expr> {
    let out = ArrayList<Expr>()
    if (let Some(paren) <- (value as ParenExpr)) {
        if (let Some(inner) <- paren.expr) { out.add(inner) }
    } else if (let Some(block) <- (value as Block)) {
        if ((let Some(last) <- block.GetLastExprOrDecl()) && (let Some(e) <- (last as Expr))) { out.add(e) }
    } else if (let Some(ie) <- (value as IfExpr)) {
        if (let Some(b) <- ie.thenBody) { out.add(b) }
        if (let Some(b) <- ie.elseBody) { out.add(b) }
    } else if (let Some(me) <- (value as MatchExpr)) {
        for (c in me.matchCases) { if (let Some(b) <- c.exprOrDecls) { out.add(b) } }
        for (c in me.matchCaseOthers) { if (let Some(b) <- c.exprOrDecls) { out.add(b) } }
    } else if (let Some(te) <- (value as TryExpr)) {
        if (let Some(b) <- te.tryBlock) { out.add(b) }
        for (b in te.catchBlocks) { out.add(b) }
        for (h in te.handlers) { if (let Some(b) <- h.block) { out.add(b) } }
    }
    return out
}
