package cjcj::sema

import std.collection.*
import cjcj::ast.*

// Each tuple projection takes the mode of the tuple. A Nothing branch contributes no value;
// Copyable values constrain the join only when there are no non-Copyable contributors.
public func JoinResultModes(tm: TypeManager, values: ArrayList<Expr>, modeOf: (Expr) -> Option<ASTMode>): ASTMode {
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

public func BindingResultMode(tm: TypeManager, value: Expr, receiver: ASTMode): Option<ASTMode> {
    if (let Some(tuple) <- (value as TupleLit)) {
        return JoinResultModes(tm, tuple.children, { e => BindingResultMode(tm, e, receiver) })
    }
    let results = ResultBranches(value)
    if (!results.isEmpty()) {
        return JoinResultModes(tm, results, { e => BindingResultMode(tm, e, receiver) })
    }
    return CallSiteMode(value, receiver, HashSet<Decl>())
}

public func BindPatternMode(pattern: Pattern, mode: ASTMode): Unit {
    pattern.resolvedMode = mode
    if (let Some(tuple) <- (pattern as TuplePattern)) {
        for (child in tuple.patterns) { BindPatternMode(child, mode) }
    } else if (let Some(typePattern) <- (pattern as TypePattern)) {
        if (let Some(inner) <- typePattern.pattern) { BindPatternMode(inner, mode) }
    } else if (let Some(enumPattern) <- (pattern as EnumPattern)) {
        for (child in enumPattern.patterns) { BindPatternMode(child, mode) }
    } else if (let Some(p) <- (pattern as VarPattern)) {
        if (let Some(decl) <- p.varDecl) { decl.resolvedMode = mode }
    } else if (let Some(p) <- (pattern as VarOrEnumPattern)) {
        if (let Some(inner) <- p.pattern) { BindPatternMode(inner, mode) }
    }
}

// The result of a conditional never comes from its condition, selector, or finally block.
public func ResultBranches(value: Expr): ArrayList<Expr> {
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
