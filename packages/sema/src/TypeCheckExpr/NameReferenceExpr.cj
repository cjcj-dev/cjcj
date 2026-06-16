package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public func SelfhostPortStatus_TypeCheckExpr_NameReferenceExpr(): Bool {
    return true
}

func TcUnitTy(): Ty {
    return TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
}

func TcBoolTy(): Ty {
    return TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
}

func TcInvalid(node: Node): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    node.SetTy(invalidTy)
    return invalidTy
}

func TcTyOrInvalid(node: Node): Ty {
    if (let Some(ty) <- node.GetTy()) {
        return ty
    }
    return TypeManager.GetInvalidTy()
}

func TcReplaceIdeal(typeManager: TypeManager, expr: Expr): Ty {
    if (let Some(exprTy) <- expr.GetTy()) {
        if (exprTy.IsIdeal()) {
            let replacedTy = typeManager.ReplaceIdealTy(exprTy)
            expr.SetTy(replacedTy)
            return replacedTy
        }
        return exprTy
    }
    return TypeManager.GetInvalidTy()
}

func TcSetTyFromTarget(node: Node, target: Decl): Ty {
    if (let Some(targetTy) <- target.GetTy()) {
        node.SetTy(targetTy)
        return targetTy
    }
    return TcInvalid(node)
}

func TcPatternCheck(typeManager: TypeManager, target: Ty, pattern: Pattern): Bool {
    pattern.SetTy(target)
    if (let Some(_) <- (pattern as WildcardPattern)) {
        return Ty.IsTyCorrect(target)
    }
    if (let Some(varPattern) <- (pattern as VarPattern)) {
        if (let Some(varDecl) <- varPattern.varDecl) {
            varDecl.SetTy(target)
        }
        return true
    }
    if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
        if (let Some(tupleTy) <- (target as TupleTy)) {
            if (tuplePattern.patterns.size != tupleTy.typeArgs.size) {
                pattern.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            var ok = true
            for (idx in 0..tuplePattern.patterns.size) {
                ok = TcPatternCheck(typeManager, tupleTy.typeArgs[idx], tuplePattern.patterns[idx]) && ok
            }
            if (!ok) {
                pattern.SetTy(TypeManager.GetInvalidTy())
            }
            return ok
        }
        pattern.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (let Some(typePattern) <- (pattern as TypePattern)) {
        var typeOk = true
        if (let Some(typeNode) <- typePattern.typeNode) {
            if (let Some(typeTy) <- typeNode.GetTy()) {
                typeOk = typeManager.CheckTypeCompatibility(typeTy, target) != TypeCompatibility.INCOMPATIBLE ||
                    typeManager.CheckTypeCompatibility(target, typeTy) != TypeCompatibility.INCOMPATIBLE
                pattern.SetTy(typeTy)
            } else {
                typeOk = false
            }
        }
        if (let Some(innerPattern) <- typePattern.pattern) {
            let innerTarget = if (let Some(patternTy) <- pattern.GetTy()) { patternTy } else { target }
            typeOk = TcPatternCheck(typeManager, innerTarget, innerPattern) && typeOk
        }
        if (!typeOk) {
            pattern.SetTy(TypeManager.GetInvalidTy())
        }
        return typeOk
    }
    if (let Some(constPattern) <- (pattern as ConstPattern)) {
        if (let Some(literal) <- constPattern.literal) {
            return ChkExprShallow(typeManager, target, literal)
        }
        return true
    }
    if (let Some(enumPattern) <- (pattern as EnumPattern)) {
        var enumOk = true
        if (let Some(ctor) <- enumPattern.constructor) {
            enumOk = Ty.IsTyCorrect(SynExprShallow(typeManager, ctor)) && enumOk
        }
        for (subPattern in enumPattern.patterns) {
            enumOk = TcPatternCheck(typeManager, typeManager.GetAnyTy(), subPattern) && enumOk
        }
        if (!enumOk) {
            pattern.SetTy(TypeManager.GetInvalidTy())
        }
        return enumOk
    }
    if (let Some(varOrEnumPattern) <- (pattern as VarOrEnumPattern)) {
        if (let Some(inner) <- varOrEnumPattern.pattern) {
            return TcPatternCheck(typeManager, target, inner)
        }
        return true
    }
    if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
        var exceptOk = true
        for (typeNode in exceptPattern.types) {
            if (let None <- typeNode.GetTy()) {
                exceptOk = false
            }
        }
        if (let Some(inner) <- exceptPattern.pattern) {
            exceptOk = TcPatternCheck(typeManager, target, inner) && exceptOk
        }
        if (!exceptOk) {
            pattern.SetTy(TypeManager.GetInvalidTy())
        }
        return exceptOk
    }
    if (let Some(commandPattern) <- (pattern as CommandTypePattern)) {
        var commandOk = true
        for (typeNode in commandPattern.types) {
            if (let None <- typeNode.GetTy()) {
                commandOk = false
            }
        }
        if (let Some(inner) <- commandPattern.pattern) {
            commandOk = TcPatternCheck(typeManager, target, inner) && commandOk
        }
        if (!commandOk) {
            pattern.SetTy(TypeManager.GetInvalidTy())
        }
        return commandOk
    }
    return Ty.IsTyCorrect(pattern.GetTy())
}

func TcCheckCondition(typeManager: TypeManager, expr: Expr): Bool {
    if (let Some(parenExpr) <- (expr as ParenExpr)) {
        if (let Some(innerExpr) <- parenExpr.expr) {
            let ok = TcCheckCondition(typeManager, innerExpr)
            parenExpr.SetTy(TcTyOrInvalid(innerExpr))
            return ok
        }
        let _ = TcInvalid(parenExpr)
        return false
    }
    if (let Some(letDestructor) <- (expr as LetPatternDestructor)) {
        if (let Some(initializer) <- letDestructor.initializer) {
            let selectorTy = SynExprShallow(typeManager, initializer)
            var ok = Ty.IsTyCorrect(selectorTy)
            for (pattern in letDestructor.patterns) {
                pattern.ctxExpr = initializer
                ok = TcPatternCheck(typeManager, selectorTy, pattern) && ok
            }
            if (ok) {
                letDestructor.SetTy(TcBoolTy())
                return true
            }
        }
        let _ = TcInvalid(letDestructor)
        return false
    }
    if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
        if (binaryExpr.op == TokenKind.AND || binaryExpr.op == TokenKind.OR) {
            var ok = true
            if (let Some(leftExpr) <- binaryExpr.leftExpr) {
                ok = TcCheckCondition(typeManager, leftExpr) && ok
            } else {
                ok = false
            }
            if (let Some(rightExpr) <- binaryExpr.rightExpr) {
                ok = TcCheckCondition(typeManager, rightExpr) && ok
            } else {
                ok = false
            }
            if (ok) {
                binaryExpr.SetTy(TcBoolTy())
                return true
            }
            let _ = TcInvalid(binaryExpr)
            return false
        }
    }
    return ChkExprShallow(typeManager, TcBoolTy(), expr)
}

public func SynExprShallow(typeManager: TypeManager, expr: Expr): Ty {
    if (let Some(desugar) <- expr.desugarExpr) {
        if (let Some(desugarTy) <- desugar.GetTy()) {
            expr.SetTy(desugarTy)
            return desugarTy
        }
    }
    if (let Some(value) <- (expr as LitConstExpr)) { return SynLitConstExpr(value) }
    if (let Some(value) <- (expr as ParenExpr)) { return SynParenExpr(typeManager, value) }
    if (let Some(value) <- (expr as TupleLit)) { return SynTupleLit(typeManager, value) }
    if (let Some(value) <- (expr as Block)) { return SynBlock(typeManager, value) }
    if (let Some(value) <- (expr as UnaryExpr)) { return SynUnaryExpr(typeManager, value) }
    if (let Some(value) <- (expr as BinaryExpr)) { return SynBinaryExpr(typeManager, value) }
    if (let Some(value) <- (expr as AssignExpr)) { return SynAssignExpr(typeManager, value) }
    if (let Some(value) <- (expr as IfExpr)) { return SynIfExpr(typeManager, value) }
    if (let Some(value) <- (expr as WhileExpr)) { return SynWhileExpr(typeManager, value) }
    if (let Some(value) <- (expr as DoWhileExpr)) { return SynDoWhileExpr(typeManager, value) }
    if (let Some(value) <- (expr as ForInExpr)) { return SynForInExpr(typeManager, value) }
    if (let Some(value) <- (expr as LambdaExpr)) { return SynLamExpr(typeManager, value) }
    if (let Some(value) <- (expr as TryExpr)) { return SynTryExpr(typeManager, value) }
    if (let Some(value) <- (expr as IfAvailableExpr)) { return SynIfAvailableExpr(typeManager, value) }
    if (let Some(value) <- (expr as SubscriptExpr)) { return SynSubscriptExpr(typeManager, value) }
    if (let Some(value) <- (expr as RangeExpr)) { return SynRangeExpr(typeManager, value) }
    if (let Some(value) <- (expr as IsExpr)) { return SynIsExpr(typeManager, value) }
    if (let Some(value) <- (expr as AsExpr)) { return SynAsExpr(typeManager, value, None) }
    if (let Some(value) <- (expr as IncOrDecExpr)) { return SynIncOrDecExpr(value) }
    if (let Some(value) <- (expr as OptionalChainExpr)) { return SynOptionalChainExpr(typeManager, value) }
    if (let Some(value) <- (expr as ReturnExpr)) { return SynReturnExpr(typeManager, value) }
    if (let Some(value) <- (expr as JumpExpr)) { return SynLoopControlExpr(value) }
    if (let Some(value) <- (expr as ThrowExpr)) { return SynThrowExpr(typeManager, value) }
    if (let Some(value) <- (expr as PerformExpr)) { return SynPerformExpr(typeManager, value) }
    if (let Some(value) <- (expr as ResumeExpr)) { return SynResumeExpr(typeManager, value) }
    if (let Some(value) <- (expr as QuoteExpr)) { return SynQuoteExpr(value) }
    if (let Some(value) <- (expr as TypeConvExpr)) { return SynTypeConvExpr(typeManager, value) }
    if (let Some(value) <- (expr as SpawnExpr)) { return SynSpawnExpr(typeManager, value) }
    if (let Some(value) <- (expr as SynchronizedExpr)) { return SynSyncExpr(typeManager, value) }
    if (let Some(value) <- (expr as NameReferenceExpr)) { return SynNameReferenceExpr(typeManager, value) }
    if (let Some(existingTy) <- expr.GetTy()) {
        if (Ty.IsTyCorrect(existingTy)) {
            return existingTy
        }
    }
    return TcInvalid(expr)
}

public func ChkExprShallow(typeManager: TypeManager, target: Ty, expr: Expr): Bool {
    if (let Some(value) <- (expr as LitConstExpr)) { return ChkLitConstExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as ParenExpr)) { return ChkParenExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as TupleLit)) { return ChkTupleLit(typeManager, target, value) }
    if (let Some(value) <- (expr as Block)) { return ChkBlock(typeManager, target, value) }
    if (let Some(value) <- (expr as UnaryExpr)) { return ChkUnaryExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as BinaryExpr)) { return ChkBinaryExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as AssignExpr)) { return ChkAssignExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as IfExpr)) { return ChkIfExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as WhileExpr)) { return ChkWhileExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as DoWhileExpr)) { return ChkDoWhileExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as ForInExpr)) { return ChkForInExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as LambdaExpr)) { return ChkLamExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as TryExpr)) { return ChkTryExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as IfAvailableExpr)) { return ChkIfAvailableExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as SubscriptExpr)) { return ChkSubscriptExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as RangeExpr)) { return ChkRangeExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as IsExpr)) { return ChkIsExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as AsExpr)) { return ChkAsExpr(typeManager, target, value, None) }
    if (let Some(value) <- (expr as IncOrDecExpr)) { return ChkIncOrDecExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as OptionalChainExpr)) { return ChkOptionalChainExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as ReturnExpr)) { return ChkReturnExpr(typeManager, value) }
    if (let Some(value) <- (expr as JumpExpr)) { return ChkLoopControlExpr(value) }
    if (let Some(value) <- (expr as QuoteExpr)) { return ChkQuoteExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as TypeConvExpr)) { return ChkTypeConvExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as SpawnExpr)) { return ChkSpawnExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as SynchronizedExpr)) {
        let syncTy = SynSyncExpr(typeManager, value)
        return Ty.IsTyCorrect(syncTy) &&
            typeManager.CheckTypeCompatibility(target, syncTy) != TypeCompatibility.INCOMPATIBLE
    }
    if (let Some(value) <- (expr as NameReferenceExpr)) { return ChkNameReferenceExpr(typeManager, target, value) }
    let actualTy = SynExprShallow(typeManager, expr)
    if (Ty.IsTyCorrect(actualTy) && typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = TcInvalid(expr)
    return false
}

private func SynRefExpr(typeManager: TypeManager, re: RefExpr): Ty {
    if (re.isThis || re.isSuper) {
        if (Ty.IsTyCorrect(re.GetTy())) {
            return TcTyOrInvalid(re)
        }
    }
    var targetOpt = re.ref.target
    if ((let None <- targetOpt) && !re.ref.targets.isEmpty()) {
        targetOpt = Some(GetRealTarget(re.ref.targets[0]))
    }
    if (let Some(target) <- targetOpt) {
        ModifyTargetOfRef(re, target, re.ref.targets)
        if (!target.IsFunc() || re.isAlone || re.ref.targets.size <= 1) {
            return TcSetTyFromTarget(re, target)
        }
        re.SetTy(TypeManager.GetQuestTy())
        return TypeManager.GetQuestTy()
    }
    if (Ty.IsTyCorrect(re.GetTy())) {
        return TcTyOrInvalid(re)
    }
    let _ = typeManager
    return TcInvalid(re)
}

private func SynMemberAccess(typeManager: TypeManager, ma: MemberAccess): Ty {
    if (let Some(baseExpr) <- ma.baseExpr) {
        SetIsNotAlone(baseExpr)
        let _ = SynExprShallow(typeManager, baseExpr)
        if (let Some(baseTy) <- baseExpr.GetTy()) {
            if (let Some(varrayTy) <- (baseTy as VArrayTy)) {
                if (ma.field.Val() == "size") {
                    let sizeTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
                    ma.SetTy(sizeTy)
                    let _ = varrayTy
                    return sizeTy
                }
            }
        }
    }
    var targetOpt = ma.target
    if ((let None <- targetOpt) && !ma.targets.isEmpty()) {
        targetOpt = Some(GetRealTarget(ma.targets[0]))
    }
    if (let Some(target) <- targetOpt) {
        ReplaceTarget(ma, Some(target))
        AddFuncTargetsForMemberAccess(ma, ma.targets)
        if (!target.IsFunc() || ma.isAlone || ma.targets.size <= 1) {
            return TcSetTyFromTarget(ma, target)
        }
        ma.SetTy(TypeManager.GetQuestTy())
        return TypeManager.GetQuestTy()
    }
    if (Ty.IsTyCorrect(ma.GetTy())) {
        return TcTyOrInvalid(ma)
    }
    return TcInvalid(ma)
}

public func SynNameReferenceExpr(typeManager: TypeManager, nre: NameReferenceExpr): Ty {
    for (typeArg in nre.GetTypeArgs()) {
        if (let Some(typeArgTy) <- typeArg.GetTy()) {
            if (!containsTy(nre.instTys, typeArgTy)) {
                nre.instTys.add(typeArgTy)
            }
        }
    }
    if (let Some(refExpr) <- (nre as RefExpr)) {
        return SynRefExpr(typeManager, refExpr)
    }
    if (let Some(memberAccess) <- (nre as MemberAccess)) {
        return SynMemberAccess(typeManager, memberAccess)
    }
    if (Ty.IsTyCorrect(nre.GetTy())) {
        return TcTyOrInvalid(nre)
    }
    return TcInvalid(nre)
}

public func ChkNameReferenceExpr(typeManager: TypeManager, target: Ty, nre: NameReferenceExpr): Bool {
    let actualTy = SynNameReferenceExpr(typeManager, nre)
    if (!Ty.IsTyCorrect(actualTy)) {
        return false
    }
    if (actualTy.IsQuest()) {
        let funcs = GetFuncTargets(nre)
        for (funcDecl in funcs) {
            if (let Some(funcTy) <- funcDecl.GetTy()) {
                if (typeManager.CheckTypeCompatibility(target, funcTy) != TypeCompatibility.INCOMPATIBLE) {
                    ReplaceTarget(nre, Some(funcDecl))
                    nre.SetTy(funcTy)
                    return true
                }
            }
        }
        let _ = TcInvalid(nre)
        return false
    }
    if (typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = TcInvalid(nre)
    return false
}

private func containsTy(values: ArrayList<Ty>, ty: Ty): Bool {
    for (value in values) {
        if (SameTy(value, ty)) {
            return true
        }
    }
    return false
}
