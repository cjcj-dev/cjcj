package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange

private func BoolTy(): Ty {
    return TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
}

private func ToBasicPosition(pos: Position): BasicPosition {
    return BasicPosition(pos.fileID, pos.line, pos.column)
}

private func DiagOld(diag: BasicDiagnosticEngine, node: Node, kind: BasicDiagKind): Unit {
    let _ = diag.Diagnose(ToBasicPosition(node.begin), ToBasicPosition(node.end), kind)
}

private func NodeRange(node: Node): BasicRange {
    var fixedEnd = node.end
    if (node.begin.fileID != node.end.fileID) {
        fixedEnd = node.begin + 1
    }
    return BasicRange(ToBasicPosition(node.begin), ToBasicPosition(fixedEnd))
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

private func JoinCaseTys(typeManager: TypeManager, tys: ArrayList<Ty>, curFile: Option<File>): Ty {
    if (tys.isEmpty()) {
        return TypeManager.GetInvalidTy()
    }
    let tySet = TySet()
    for (ty in tys) {
        tySet.Add(ty)
    }
    return JoinAsVisibleTy(typeManager, tySet, curFile: curFile)
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

private func PatternKindForDiag(ctx: ASTContext, pattern: Pattern): String {
    let kind = PatternKindForOr(ctx, pattern)
    let text = match (kind) {
        case ASTKind.CONST_PATTERN => "constant"
        case ASTKind.WILDCARD_PATTERN => "wildcard"
        case ASTKind.VAR_PATTERN => "binding"
        case ASTKind.TUPLE_PATTERN => "tuple"
        case ASTKind.TYPE_PATTERN => "type"
        case ASTKind.ENUM_PATTERN => "enum"
        case _ => "invalid"
    }
    return text + " pattern"
}

private func FindBindingPattern(ctx: ASTContext, pattern: Pattern): Option<Pattern> {
    if (pattern.astKind == ASTKind.VAR_PATTERN) {
        return Some(pattern)
    }
    if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
        if (!ctx.IsEnumConstructor(varOrEnum.identifier.Val())) {
            return Some(pattern)
        }
    }
    if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
        for (subPattern in tuplePattern.patterns) {
            if (let Some(found) <- FindBindingPattern(ctx, subPattern)) {
                return Some(found)
            }
        }
    }
    if (let Some(enumPattern) <- (pattern as EnumPattern)) {
        for (subPattern in enumPattern.patterns) {
            if (let Some(found) <- FindBindingPattern(ctx, subPattern)) {
                return Some(found)
            }
        }
    }
    if (let Some(typePattern) <- (pattern as TypePattern)) {
        if (let Some(inner) <- typePattern.pattern) {
            return FindBindingPattern(ctx, inner)
        }
    }
    return None
}

public func ChkNoVarPatternInOrPattern(ctx: ASTContext, patterns: ArrayList<Pattern>,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (patterns.size <= 1) {
        return true
    }
    let varPatterns = ArrayList<Pattern>()
    for (pattern in patterns) {
        if (let Some(varPattern) <- FindBindingPattern(ctx, pattern)) {
            varPatterns.add(varPattern)
        }
    }
    if (varPatterns.isEmpty()) {
        return true
    }
    if (let Some(diagValue) <- diag) {
        let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_var_in_or_pattern,
            NodeRange(varPatterns[0]))
        var idx: Int64 = 1
        while (idx < varPatterns.size) {
            builder.AddHint(NodeRange(varPatterns[idx]))
            idx++
        }
    }
    return false
}

public func ChkPatternsSameASTKind(ctx: ASTContext, patterns: ArrayList<Pattern>,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
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
    let frontKind = patterns[0].astKind
    var idx: Int64 = 1
    while (idx < patterns.size) {
        if (patterns[idx].astKind != frontKind) {
            if (let Some(diagValue) <- diag) {
                let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_different_or_pattern,
                    NodeRange(patterns[0]))
                builder.AddMainHintArguments([PatternKindForDiag(ctx, patterns[0])])
                builder.AddHint(NodeRange(patterns[idx]), arguments: [PatternKindForDiag(ctx, patterns[idx])])
            }
            return false
        }
        idx++
    }
    return true
}

public func ChkMatchCasePatterns(typeManager: TypeManager, ctx: ASTContext, target: Ty, mc: MatchCase,
    diag!: Option<BasicDiagnosticEngine> = None, exprChecker!: Option<ConstPatternExprChecker> = None): Bool {
    if (!ChkNoVarPatternInOrPattern(ctx, mc.patterns, diag: diag) ||
        !ChkPatternsSameASTKind(ctx, mc.patterns, diag: diag)) {
        for (pattern in mc.patterns) {
            pattern.SetTy(TypeManager.GetInvalidTy())
        }
        return false
    }
    var ok = true
    for (pattern in mc.patterns) {
        if (!ChkPattern(typeManager, ctx, target, pattern, isPatternInMatch: true, exprChecker: exprChecker,
            diag: diag)) {
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

public func ChkMatchCaseActions(typeManager: TypeManager, target: Option<Ty>, mc: MatchCase,
    exprChecker!: Option<ConstPatternExprChecker> = None): Bool {
    if (let None <- mc.exprOrDecls) {
        mc.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let block = mc.exprOrDecls.getOrThrow()
    if (let Some(targetTy) <- target) {
        if (let Some(checker) <- exprChecker) {
            if (checker(targetTy, block)) {
                mc.SetTy(block.GetTy() ?? targetTy)
                return true
            }
            mc.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        let blockTy = BlockTy(block)
        if (typeManager.CheckTypeCompatibility(targetTy, blockTy) == TypeCompatibility.INCOMPATIBLE) {
            mc.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        mc.SetTy(blockTy)
        return Ty.IsTyCorrect(blockTy)
    }
    let blockTy = BlockTy(block)
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

public func CheckMatchExprNoSelectorExhaustiveness(me: MatchExpr, hasDefault!: Bool = false,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    var ok = true
    var foundDefault = hasDefault
    var defaultCase: Int64 = 0
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
            if (let Some(diagValue) <- diag) {
                DiagOld(diagValue, matchCaseOther, BasicDiagKind.sema_match_case_has_no_type)
            }
        }
        idx++
    }
    if (!foundDefault) {
        ok = false
        if (let Some(diagValue) <- diag) {
            DiagOld(diagValue, me, BasicDiagKind.sema_match_case_must_have_default)
        }
    }
    var unreachableIdx = defaultCase + 1
    while (unreachableIdx < me.matchCaseOthers.size) {
        me.matchCaseOthers[unreachableIdx].EnableAttr(Attribute.UNREACHABLE)
        unreachableIdx++
    }
    return ok
}

public func SynNormalMatchCaseBody(typeManager: TypeManager, ctx: ASTContext,
    diag: Option<BasicDiagnosticEngine>, me: MatchExpr,
    exprChecker!: Option<ConstPatternExprChecker> = None): Ty {
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
        let patternOk = ChkMatchCasePatterns(typeManager, ctx, selectorTy, mc, diag: diag,
            exprChecker: exprChecker)
        let guardOk = ChkMatchCasePatGuard(typeManager, ctx, mc)
        let actionOk = ChkMatchCaseActions(typeManager, None, mc, exprChecker: exprChecker)
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
    if (selector.GetTy().getOrThrow().HasPlaceholder()) {
        selector.SetTy(typeManager.TryGreedySubst(selector.GetTy().getOrThrow()))
        for (mc in me.matchCases) {
            let _ = ChkMatchCasePatterns(typeManager, ctx, selector.GetTy().getOrThrow(), mc, diag: diag,
                exprChecker: exprChecker)
        }
    }
    let joinedTy = JoinCaseTys(typeManager, caseTys, me.curFile)
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

public func SynQuestSugarMatchCaseBody(typeManager: TypeManager, ctx: ASTContext, me: MatchExpr,
    exprChecker!: Option<ConstPatternExprChecker> = None): Ty {
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
    let _ = ChkMatchCasePatterns(typeManager, ctx, selectorTy, firstCase, exprChecker: exprChecker)
    let _ = ChkMatchCaseActions(typeManager, None, firstCase, exprChecker: exprChecker)
    if (let Some(firstTy) <- firstCase.GetTy()) {
        let _ = ChkMatchCasePatterns(typeManager, ctx, selectorTy, secondCase, exprChecker: exprChecker)
        let _ = ChkMatchCaseActions(typeManager, firstTy, secondCase, exprChecker: exprChecker)
        me.SetTy(firstTy)
        return firstTy
    }
    return InvalidMatchTy(me)
}

public func SynMatchExprHasSelector(typeManager: TypeManager, ctx: ASTContext,
    diag: Option<BasicDiagnosticEngine>, me: MatchExpr,
    exprChecker!: Option<ConstPatternExprChecker> = None): Ty {
    if (SugarKindEq(me.sugarKind, SugarKind.QUEST)) {
        return SynQuestSugarMatchCaseBody(typeManager, ctx, me, exprChecker: exprChecker)
    }
    return SynNormalMatchCaseBody(typeManager, ctx, diag, me, exprChecker: exprChecker)
}

public func SynMatchExprNoSelector(typeManager: TypeManager, ctx: ASTContext, me: MatchExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
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
    if (hasInvalidCase || !CheckMatchExprNoSelectorExhaustiveness(me, diag: diag)) {
        return InvalidMatchTy(me)
    }
    let joinedTy = JoinCaseTys(typeManager, caseTys, me.curFile)
    me.SetTy(joinedTy)
    return joinedTy
}

public func SynMatchExpr(typeManager: TypeManager, ctx: ASTContext, me: MatchExpr,
    diag!: Option<BasicDiagnosticEngine> = None, exprChecker!: Option<ConstPatternExprChecker> = None): Ty {
    if (let Some(_) <- me.selector) {
        return SynMatchExprHasSelector(typeManager, ctx, diag, me, exprChecker: exprChecker)
    }
    return SynMatchExprNoSelector(typeManager, ctx, me, diag: diag)
}

public func ChkMatchExprHasSelector(typeManager: TypeManager, ctx: ASTContext,
    diag: Option<BasicDiagnosticEngine>, target: Ty, me: MatchExpr,
    exprChecker!: Option<ConstPatternExprChecker> = None): Bool {
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
        let patternOk = ChkMatchCasePatterns(typeManager, ctx, selectorTy, mc, diag: diag,
            exprChecker: exprChecker)
        let guardOk = ChkMatchCasePatGuard(typeManager, ctx, mc)
        let actionOk = ChkMatchCaseActions(typeManager, target, mc, exprChecker: exprChecker)
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
            me.SetTy(JoinCaseTys(typeManager, caseTys, me.curFile))
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

public func ChkMatchExprNoSelector(typeManager: TypeManager, ctx: ASTContext, target: Ty, me: MatchExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
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
            me.SetTy(JoinCaseTys(typeManager, caseTys, me.curFile))
        }
        ok = CheckMatchExprNoSelectorExhaustiveness(me, diag: diag)
    }
    if (!ok) {
        let _ = InvalidMatchTy(me)
    }
    return ok
}

public func ChkMatchExpr(typeManager: TypeManager, ctx: ASTContext, target: Ty, me: MatchExpr,
    diag!: Option<BasicDiagnosticEngine> = None, exprChecker!: Option<ConstPatternExprChecker> = None): Bool {
    if (let Some(_) <- me.selector) {
        return ChkMatchExprHasSelector(typeManager, ctx, diag, target, me, exprChecker: exprChecker)
    }
    return ChkMatchExprNoSelector(typeManager, ctx, target, me, diag: diag)
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
