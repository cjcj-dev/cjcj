package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor

private func BoolTy(): Ty {
    return TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
}

private func SugarKindIndex(kind: SugarKind): Int64 {
    return match (kind) {
        case SugarKind.QUEST => 0
        case SugarKind.IF_LET => 1
        case SugarKind.WHILE_LET => 2
        case SugarKind.FOR_IN_EXPR => 3
        case SugarKind.IS => 4
        case SugarKind.AS => 5
        case SugarKind.TOKEN_CALL => 6
        case SugarKind.NO_SUGAR => 7
    }
}

private func SugarKindEq(lhs: SugarKind, rhs: SugarKind): Bool {
    return SugarKindIndex(lhs) == SugarKindIndex(rhs)
}

private func InvalidMatchTy(me: MatchExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    me.SetTy(invalidTy)
    return invalidTy
}

private func BlockTy(block: Block): Ty {
    if (Ty.IsTyCorrect(block.GetTy())) {
        return block.GetTy().getOrThrow()
    }
    if (let Some(lastNode) <- block.GetLastExprOrDecl()) {
        if (let Some(ty) <- lastNode.GetTy()) {
            block.SetTy(ty)
            return ty
        }
    }
    let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
    if (block.body.isEmpty()) {
        block.SetTy(unitTy)
        return unitTy
    }
    let invalidTy = TypeManager.GetInvalidTy()
    block.SetTy(invalidTy)
    return invalidTy
}

private func JoinCaseTys(typeManager: TypeManager, tys: ArrayList<Ty>): Ty {
    if (tys.isEmpty()) {
        return TypeManager.GetInvalidTy()
    }
    var out = tys[0]
    var idx: Int64 = 1
    while (idx < tys.size) {
        out = Join(typeManager, out, tys[idx])
        idx++
    }
    return out
}

private func PatternKindForOr(ctx: ASTContext, pattern: Pattern): ASTKind {
    if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
        return if (ctx.IsEnumConstructor(varOrEnum.identifier.Val())) {
            ASTKind.ENUM_PATTERN
        } else {
            ASTKind.VAR_PATTERN
        }
    }
    return pattern.astKind
}

private func PatternHasBinding(ctx: ASTContext, pattern: Pattern): Bool {
    if (pattern.astKind == ASTKind.VAR_PATTERN) {
        return true
    }
    if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
        return !ctx.IsEnumConstructor(varOrEnum.identifier.Val())
    }
    if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
        for (subPattern in tuplePattern.patterns) {
            if (PatternHasBinding(ctx, subPattern)) {
                return true
            }
        }
    }
    if (let Some(enumPattern) <- (pattern as EnumPattern)) {
        for (subPattern in enumPattern.patterns) {
            if (PatternHasBinding(ctx, subPattern)) {
                return true
            }
        }
    }
    if (let Some(typePattern) <- (pattern as TypePattern)) {
        if (let Some(inner) <- typePattern.pattern) {
            return PatternHasBinding(ctx, inner)
        }
    }
    return false
}

public func ChkNoVarPatternInOrPattern(ctx: ASTContext, patterns: ArrayList<Pattern>): Bool {
    if (patterns.size <= 1) {
        return true
    }
    for (pattern in patterns) {
        if (PatternHasBinding(ctx, pattern)) {
            return false
        }
    }
    return true
}

public func ChkPatternsSameASTKind(ctx: ASTContext, patterns: ArrayList<Pattern>): Bool {
    if (patterns.size <= 1) {
        return true
    }
    var allEnumLike = true
    for (pattern in patterns) {
        if (pattern.astKind != ASTKind.VAR_OR_ENUM_PATTERN && pattern.astKind != ASTKind.ENUM_PATTERN) {
            allEnumLike = false
            break
        }
    }
    if (allEnumLike) {
        return true
    }
    let frontKind = PatternKindForOr(ctx, patterns[0])
    var idx: Int64 = 1
    while (idx < patterns.size) {
        if (PatternKindForOr(ctx, patterns[idx]) != frontKind) {
            return false
        }
        idx++
    }
    return true
}

public func ChkMatchCasePatterns(typeManager: TypeManager, ctx: ASTContext, target: Ty, mc: MatchCase): Bool {
    if (!ChkNoVarPatternInOrPattern(ctx, mc.patterns) || !ChkPatternsSameASTKind(ctx, mc.patterns)) {
        for (pattern in mc.patterns) {
            pattern.SetTy(TypeManager.GetInvalidTy())
        }
        return false
    }
    var ok = true
    for (pattern in mc.patterns) {
        if (!ChkPattern(typeManager, ctx, target, pattern, isPatternInMatch: true)) {
            ok = false
        }
    }
    return ok
}

public func ChkMatchCasePatGuard(typeManager: TypeManager, ctx: ASTContext, mc: MatchCase): Bool {
    let _ = ctx
    if (let Some(guardExpr) <- mc.patternGuard) {
        if (let Some(guardTy) <- guardExpr.GetTy()) {
            return typeManager.CheckTypeCompatibility(BoolTy(), guardTy) != TypeCompatibility.INCOMPATIBLE
        }
        guardExpr.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    return true
}

public func ChkMatchCaseActions(typeManager: TypeManager, target: Option<Ty>, mc: MatchCase): Bool {
    if (let None <- mc.exprOrDecls) {
        mc.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let block = mc.exprOrDecls.getOrThrow()
    let blockTy = BlockTy(block)
    if (let Some(targetTy) <- target) {
        if (typeManager.CheckTypeCompatibility(targetTy, blockTy) == TypeCompatibility.INCOMPATIBLE) {
            mc.SetTy(TypeManager.GetInvalidTy())
            return false
        }
    }
    mc.SetTy(blockTy)
    return Ty.IsTyCorrect(blockTy)
}

public func SynMatchCaseNoSelector(typeManager: TypeManager, ctx: ASTContext, mco: MatchCaseOther): Ty {
    if (let Some(matchExpr) <- mco.matchExpr) {
        if (let Some(wildcard) <- (matchExpr as WildcardExpr)) {
            wildcard.SetTy(BoolTy())
        } else if (let Some(matchTy) <- matchExpr.GetTy()) {
            if (typeManager.CheckTypeCompatibility(BoolTy(), matchTy) == TypeCompatibility.INCOMPATIBLE) {
                matchExpr.SetTy(TypeManager.GetInvalidTy())
            }
        } else {
            matchExpr.SetTy(TypeManager.GetInvalidTy())
        }
    }
    let _ = ctx
    if (let Some(block) <- mco.exprOrDecls) {
        let ty = BlockTy(block)
        mco.SetTy(ty)
        return ty
    }
    let invalidTy = TypeManager.GetInvalidTy()
    mco.SetTy(invalidTy)
    return invalidTy
}

public func ChkMatchCaseNoSelector(typeManager: TypeManager, ctx: ASTContext, target: Ty,
    mco: MatchCaseOther): Bool {
    var ok = true
    let conditionTy = SynMatchCaseNoSelector(typeManager, ctx, mco)
    let _ = conditionTy
    if (let Some(matchExpr) <- mco.matchExpr) {
        if (let Some(matchTy) <- matchExpr.GetTy()) {
            ok = typeManager.CheckTypeCompatibility(BoolTy(), matchTy) != TypeCompatibility.INCOMPATIBLE
        } else {
            ok = false
        }
    }
    if (let Some(block) <- mco.exprOrDecls) {
        let blockTy = BlockTy(block)
        if (typeManager.CheckTypeCompatibility(target, blockTy) == TypeCompatibility.INCOMPATIBLE) {
            mco.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        mco.SetTy(blockTy)
        return ok
    }
    mco.SetTy(TypeManager.GetInvalidTy())
    return false
}

public func CheckMatchExprNoSelectorExhaustiveness(me: MatchExpr, hasDefault!: Bool = false): Bool {
    var ok = true
    var foundDefault = hasDefault
    var defaultCase: Int64 = -1
    var idx: Int64 = 0
    while (idx < me.matchCaseOthers.size) {
        let matchCaseOther = me.matchCaseOthers[idx]
        if (!foundDefault) {
            if (let Some(matchExpr) <- matchCaseOther.matchExpr) {
                if (let Some(_) <- (matchExpr as WildcardExpr)) {
                    foundDefault = true
                    defaultCase = idx
                }
            }
        }
        if (Ty.IsInitialTy(matchCaseOther.GetTy())) {
            ok = false
        }
        idx++
    }
    if (!foundDefault) {
        ok = false
    }
    if (defaultCase >= 0) {
        var unreachableIdx = defaultCase + 1
        while (unreachableIdx < me.matchCaseOthers.size) {
            me.matchCaseOthers[unreachableIdx].EnableAttr(Attribute.UNREACHABLE)
            unreachableIdx++
        }
    }
    return ok
}

public func SynNormalMatchCaseBody(typeManager: TypeManager, ctx: ASTContext,
    diag: Option<BasicDiagnosticEngine>, me: MatchExpr): Ty {
    if (let None <- me.selector) {
        return InvalidMatchTy(me)
    }
    let selector = me.selector.getOrThrow()
    if (!Ty.IsTyCorrect(selector.GetTy())) {
        return InvalidMatchTy(me)
    }
    let selectorTy = selector.GetTy().getOrThrow()
    let caseTys = ArrayList<Ty>()
    var ok = !me.matchCases.isEmpty()
    for (mc in me.matchCases) {
        mc.SetCtxExprForPatterns(selector)
        let patternOk = ChkMatchCasePatterns(typeManager, ctx, selectorTy, mc)
        let guardOk = ChkMatchCasePatGuard(typeManager, ctx, mc)
        let actionOk = ChkMatchCaseActions(typeManager, None, mc)
        if (patternOk && guardOk && actionOk) {
            if (let Some(caseTy) <- mc.GetTy()) {
                caseTys.add(caseTy)
            }
        } else {
            ok = false
        }
    }
    if (!ok) {
        return InvalidMatchTy(me)
    }
    let joinedTy = JoinCaseTys(typeManager, caseTys)
    me.SetTy(joinedTy)
    if (SugarKindEq(me.sugarKind, SugarKind.NO_SUGAR)) {
        if (let Some(engine) <- diag) {
            if (!CheckMatchExprHasSelectorExhaustivenessAndReachability(engine, typeManager, me)) {
                return InvalidMatchTy(me)
            }
        }
    }
    return me.GetTy() ?? TypeManager.GetInvalidTy()
}

public func SynQuestSugarMatchCaseBody(typeManager: TypeManager, ctx: ASTContext, me: MatchExpr): Ty {
    if (let None <- me.selector) {
        return InvalidMatchTy(me)
    }
    let selector = me.selector.getOrThrow()
    if (!Ty.IsTyCorrect(selector.GetTy())) {
        return InvalidMatchTy(me)
    }
    let selectorTy = selector.GetTy().getOrThrow()
    if (!selectorTy.IsCoreOptionType()) {
        return InvalidMatchTy(me)
    }
    if (me.matchCases.size != 2) {
        return InvalidMatchTy(me)
    }
    let firstCase = me.matchCases[0]
    let secondCase = me.matchCases[1]
    firstCase.SetCtxExprForPatterns(selector)
    secondCase.SetCtxExprForPatterns(selector)
    let _ = ChkMatchCasePatterns(typeManager, ctx, selectorTy, firstCase)
    let _ = ChkMatchCaseActions(typeManager, None, firstCase)
    if (let Some(firstTy) <- firstCase.GetTy()) {
        let _ = ChkMatchCasePatterns(typeManager, ctx, selectorTy, secondCase)
        let _ = ChkMatchCaseActions(typeManager, firstTy, secondCase)
        me.SetTy(firstTy)
        return firstTy
    }
    return InvalidMatchTy(me)
}

public func SynMatchExprHasSelector(typeManager: TypeManager, ctx: ASTContext,
    diag: Option<BasicDiagnosticEngine>, me: MatchExpr): Ty {
    if (SugarKindEq(me.sugarKind, SugarKind.QUEST)) {
        return SynQuestSugarMatchCaseBody(typeManager, ctx, me)
    }
    return SynNormalMatchCaseBody(typeManager, ctx, diag, me)
}

public func SynMatchExprNoSelector(typeManager: TypeManager, ctx: ASTContext, me: MatchExpr): Ty {
    let caseTys = ArrayList<Ty>()
    var hasInvalidCase = false
    for (mco in me.matchCaseOthers) {
        let caseTy = SynMatchCaseNoSelector(typeManager, ctx, mco)
        if (!Ty.IsTyCorrect(caseTy)) {
            hasInvalidCase = true
        } else {
            caseTys.add(caseTy)
        }
    }
    if (hasInvalidCase || !CheckMatchExprNoSelectorExhaustiveness(me)) {
        return InvalidMatchTy(me)
    }
    let joinedTy = JoinCaseTys(typeManager, caseTys)
    me.SetTy(joinedTy)
    return joinedTy
}

public func SynMatchExpr(typeManager: TypeManager, ctx: ASTContext, me: MatchExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(_) <- me.selector) {
        return SynMatchExprHasSelector(typeManager, ctx, diag, me)
    }
    return SynMatchExprNoSelector(typeManager, ctx, me)
}

public func ChkMatchExprHasSelector(typeManager: TypeManager, ctx: ASTContext,
    diag: Option<BasicDiagnosticEngine>, target: Ty, me: MatchExpr): Bool {
    if (let None <- me.selector) {
        let _ = InvalidMatchTy(me)
        return false
    }
    let selector = me.selector.getOrThrow()
    if (!Ty.IsTyCorrect(selector.GetTy())) {
        let _ = InvalidMatchTy(me)
        return false
    }
    let selectorTy = selector.GetTy().getOrThrow()
    let caseTys = ArrayList<Ty>()
    var ok = true
    for (mc in me.matchCases) {
        mc.SetCtxExprForPatterns(selector)
        let patternOk = ChkMatchCasePatterns(typeManager, ctx, selectorTy, mc)
        let guardOk = ChkMatchCasePatGuard(typeManager, ctx, mc)
        let actionOk = ChkMatchCaseActions(typeManager, target, mc)
        if (patternOk && guardOk && actionOk) {
            if (let Some(caseTy) <- mc.GetTy()) {
                caseTys.add(caseTy)
            }
        } else {
            ok = false
        }
    }
    if (ok) {
        if (caseTysContains(typeManager, caseTys, target)) {
            me.SetTy(target)
        } else {
            me.SetTy(JoinCaseTys(typeManager, caseTys))
        }
        if (SugarKindEq(me.sugarKind, SugarKind.NO_SUGAR)) {
            if (let Some(engine) <- diag) {
                ok = CheckMatchExprHasSelectorExhaustivenessAndReachability(engine, typeManager, me)
            }
        }
    }
    if (!ok) {
        let _ = InvalidMatchTy(me)
    }
    return ok
}

public func ChkMatchExprNoSelector(typeManager: TypeManager, ctx: ASTContext, target: Ty, me: MatchExpr): Bool {
    let caseTys = ArrayList<Ty>()
    var ok = true
    for (mco in me.matchCaseOthers) {
        if (ChkMatchCaseNoSelector(typeManager, ctx, target, mco)) {
            if (let Some(caseTy) <- mco.GetTy()) {
                caseTys.add(caseTy)
            }
        } else {
            ok = false
        }
    }
    if (ok) {
        if (caseTysContains(typeManager, caseTys, target)) {
            me.SetTy(target)
        } else {
            me.SetTy(JoinCaseTys(typeManager, caseTys))
        }
        ok = CheckMatchExprNoSelectorExhaustiveness(me)
    }
    if (!ok) {
        let _ = InvalidMatchTy(me)
    }
    return ok
}

public func ChkMatchExpr(typeManager: TypeManager, ctx: ASTContext, target: Ty, me: MatchExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let Some(_) <- me.selector) {
        return ChkMatchExprHasSelector(typeManager, ctx, diag, target, me)
    }
    return ChkMatchExprNoSelector(typeManager, ctx, target, me)
}

private func caseTysContains(typeManager: TypeManager, tys: ArrayList<Ty>, target: Ty): Bool {
    let _ = typeManager
    for (ty in tys) {
        if (SameTy(ty, target)) {
            return true
        }
    }
    return false
}

public func ChkMatchExprWithDiag(diag: BasicDiagnosticEngine, typeManager: TypeManager, ctx: ASTContext,
    target: Ty, me: MatchExpr): Bool {
    let ok = ChkMatchExpr(typeManager, ctx, target, me, diag: diag)
    if (!ok && me.ShouldDiagnose()) {
        SemaDiag(diag, BasicDiagKindRefactor.sema_mismatched_types, me)
    }
    return ok
}

public func SynMatchExprWithDiag(diag: BasicDiagnosticEngine, typeManager: TypeManager,
    ctx: ASTContext, me: MatchExpr): Ty {
    return SynMatchExpr(typeManager, ctx, me, diag: diag)
}

public func SelfhostPortStatus_TypeCheckMatchExpr(): Bool {
    return true
}
