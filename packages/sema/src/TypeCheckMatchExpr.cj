package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor

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

private func JoinCaseTys(typeManager: TypeManager, tys: ArrayList<Ty>, curFile: Option<File>): ErrOrTy {
    if (tys.isEmpty()) {
        return ErrOrTy.TY(TypeManager.GetInvalidTy())
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

public func ChkNoVarPatternInOrPattern(ctx: ASTContext, patterns: ArrayList<Pattern>,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (patterns.size <= 1) {
        return true
    }
    let varPatterns = ArrayList<Pattern>()
    for (pattern in patterns) {
        let _ = Walker(pattern, visitPre: { node: Node =>
            let isVarPattern = node.astKind == ASTKind.VAR_PATTERN ||
                (node.astKind == ASTKind.VAR_OR_ENUM_PATTERN &&
                    !ctx.IsEnumConstructor((node as VarOrEnumPattern).getOrThrow().identifier.Val()))
            if (isVarPattern) {
                varPatterns.add((node as Pattern).getOrThrow())
                return VisitAction.SKIP_CHILDREN
            }
            return VisitAction.WALK_CHILDREN
        }).Walk()
    }
    if (varPatterns.isEmpty()) {
        return true
    }
    if (let Some(diagValue) <- diag) {
        let builder = DiagnoseRefactor(
            diagValue, BasicDiagKindRefactor.sema_var_in_or_pattern, varPatterns[0])
        var idx: Int64 = 1
        while (idx < varPatterns.size) {
            AddHint(builder, varPatterns[idx])
            idx++
        }
        builder.Emit()
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
                let builder = DiagnoseRefactor(
                    diagValue, BasicDiagKindRefactor.sema_different_or_pattern, patterns[0])
                builder.AddMainHintArguments([PatternKindForDiag(ctx, patterns[0])])
                AddHint(builder, patterns[idx], arguments: [PatternKindForDiag(ctx, patterns[idx])])
                builder.Emit()
            }
            return false
        }
        idx++
    }
    return true
}

public func ChkMatchCasePatterns(typeManager: TypeManager, ctx: ASTContext, target: Ty, mc: MatchCase,
    diag!: Option<BasicDiagnosticEngine> = None, exprChecker!: Option<ConstPatternExprChecker> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None): Bool {
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
            desugarCallExpr: desugarCallExpr, diag: diag)) {
            ok = false
        }
    }
    return ok
}

public func ChkMatchCasePatGuard(typeManager: TypeManager, ctx: ASTContext, mc: MatchCase,
    exprChecker!: Option<ConstPatternExprChecker> = None): Bool {
    let _ = typeManager
    let _ = ctx
    var ret = true
    if (let Some(guardExpr) <- mc.patternGuard) {
        let boolTy = BoolTy()
        ret = exprChecker.getOrThrow()(boolTy, guardExpr)
    }
    return ret
}

public func ChkMatchCaseActions(typeManager: TypeManager, target: Option<Ty>, mc: MatchCase,
    exprChecker!: Option<ConstPatternExprChecker> = None,
    exprSynthesizer!: Option<(Expr) -> Ty> = None): Bool {
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
    if (let Some(synthesizer) <- exprSynthesizer) {
        block.SetTy(synthesizer(block))
    }
    let blockTy = BlockTy(block)
    mc.SetTy(blockTy)
    return Ty.IsTyCorrect(blockTy)
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
                Diagnose(diagValue, matchCaseOther, BasicDiagKind.sema_match_case_has_no_type).Emit()
            }
        }
        idx++
    }
    if (!foundDefault) {
        ok = false
        if (let Some(diagValue) <- diag) {
            Diagnose(diagValue, me, BasicDiagKind.sema_match_case_must_have_default).Emit()
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
    exprChecker!: Option<ConstPatternExprChecker> = None,
    exprSynthesizer!: Option<(Expr) -> Ty> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None): Ty {
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
            exprChecker: exprChecker, desugarCallExpr: desugarCallExpr)
        let guardOk = ChkMatchCasePatGuard(typeManager, ctx, mc, exprChecker: exprChecker)
        let actionOk = ChkMatchCaseActions(typeManager, None, mc, exprChecker: exprChecker,
            exprSynthesizer: exprSynthesizer)
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
                exprChecker: exprChecker, desugarCallExpr: desugarCallExpr)
        }
    }
    let joinRes = JoinCaseTys(typeManager, caseTys, me.curFile)
    let (optErrs, joinedTy) = SetJoinedType(me.GetTy() ?? TypeManager.GetInvalidTy(), joinRes)
    me.SetTy(joinedTy)
    if (let Some(errMsg) <- optErrs) {
        if (let Some(engine) <- diag) {
            let builder = if (SugarKindEq(me.sugarKind, SugarKind.IF_LET)) {
                Diagnose(engine, me, BasicDiagKind.sema_diag_report_error_message,
                    args: [BasicDiagArgument("types " + Ty.ToString(me.matchCases[0].GetTy()) + " and " +
                        Ty.ToString(me.matchCases[1].GetTy()) +
                        " of the two branches of this 'if' expression mismatch")])
            } else {
                Diagnose(engine, me, BasicDiagKind.sema_type_incompatible,
                    args: [BasicDiagArgument("MatchCase")])
            }
            builder.AddNote(errMsg)
            builder.Emit()
        }
    }
    if (SugarKindEq(me.sugarKind, SugarKind.NO_SUGAR)) {
        if (let Some(engine) <- diag) {
            if (!CheckMatchExprHasSelectorExhaustivenessAndReachability(engine, typeManager, me)) {
                return InvalidMatchTy(me)
            }
        }
    }
    return me.GetTy() ?? TypeManager.GetInvalidTy()
}

public func SynQuestSugarMatchCaseBody(typeManager: TypeManager, ctx: ASTContext,
    diag: Option<BasicDiagnosticEngine>, me: MatchExpr,
    exprChecker!: Option<ConstPatternExprChecker> = None,
    exprSynthesizer!: Option<(Expr) -> Ty> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None): Ty {
    if (let None <- me.selector) {
        return InvalidMatchTy(me)
    }
    let selector = me.selector.getOrThrow()
    if (!Ty.IsTyCorrect(selector.GetTy())) {
        return InvalidMatchTy(me)
    }
    let selectorTy = selector.GetTy().getOrThrow()
    if (!selectorTy.IsCoreOptionType()) {
        if (let Some(engine) <- diag) {
            let builder = DiagnoseRefactor(engine,
                BasicDiagKindRefactor.sema_optional_chain_non_optional, me)
            builder.AddMainHintArguments([selectorTy.String()])
            builder.Emit()
        }
        return InvalidMatchTy(me)
    }
    if (me.matchCases.size != 2) {
        return InvalidMatchTy(me)
    }
    let firstCase = me.matchCases[0]
    let secondCase = me.matchCases[1]
    firstCase.SetCtxExprForPatterns(selector)
    secondCase.SetCtxExprForPatterns(selector)
    let _ = ChkMatchCasePatterns(typeManager, ctx, selectorTy, firstCase, exprChecker: exprChecker,
        desugarCallExpr: desugarCallExpr)
    let _ = ChkMatchCaseActions(typeManager, None, firstCase, exprChecker: exprChecker,
        exprSynthesizer: exprSynthesizer)
    if (let Some(firstTy) <- firstCase.GetTy()) {
        let _ = ChkMatchCasePatterns(typeManager, ctx, selectorTy, secondCase, exprChecker: exprChecker,
            desugarCallExpr: desugarCallExpr)
        let _ = ChkMatchCaseActions(typeManager, firstTy, secondCase, exprChecker: exprChecker)
        me.SetTy(firstTy)
        return firstTy
    }
    return InvalidMatchTy(me)
}

public func SynMatchExprHasSelector(typeManager: TypeManager, ctx: ASTContext,
    diag: Option<BasicDiagnosticEngine>, me: MatchExpr,
    exprChecker!: Option<ConstPatternExprChecker> = None,
    exprSynthesizer!: Option<(Expr) -> Ty> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None): Ty {
    if (SugarKindEq(me.sugarKind, SugarKind.QUEST)) {
        return SynQuestSugarMatchCaseBody(typeManager, ctx, diag, me, exprChecker: exprChecker,
            exprSynthesizer: exprSynthesizer, desugarCallExpr: desugarCallExpr)
    }
    return SynNormalMatchCaseBody(typeManager, ctx, diag, me, exprChecker: exprChecker,
        exprSynthesizer: exprSynthesizer, desugarCallExpr: desugarCallExpr)
}

public func ChkMatchExprHasSelector(typeManager: TypeManager, ctx: ASTContext,
    diag: Option<BasicDiagnosticEngine>, target: Ty, me: MatchExpr,
    exprChecker!: Option<ConstPatternExprChecker> = None,
    desugarCallExpr!: Option<(CallExpr) -> Unit> = None): Bool {
    if (let None <- me.selector) {
        let _ = InvalidMatchTy(me)
        return false
    }
    let selector = me.selector.getOrThrow()
    // C++ TypeCheckMatchExpr.cpp:228-230 concretizes the synthesized selector before checking patterns.
    let _ = ReplaceIdealTy(typeManager, selector, diag: diag)
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
            exprChecker: exprChecker, desugarCallExpr: desugarCallExpr)
        let guardOk = ChkMatchCasePatGuard(typeManager, ctx, mc, exprChecker: exprChecker)
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
            let joinRes = JoinCaseTys(typeManager, caseTys, me.curFile)
            match (joinRes) {
                case ErrOrTy.TY(joinedTy) => me.SetTy(joinedTy)
                case ErrOrTy.ERR(_) => me.SetTy(target)
            }
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

private func caseTysContains(typeManager: TypeManager, tys: ArrayList<Ty>, target: Ty): Bool {
    let _ = typeManager
    for (ty in tys) {
        if (SameTy(ty, target)) {
            return true
        }
    }
    return false
}
