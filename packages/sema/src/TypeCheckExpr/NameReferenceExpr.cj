package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::modules.SemaImportManager
import cangjie_compiler::sema.*

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

func TcTargetReferenceTy(target: Decl): Option<Ty> {
    if (Ty.IsTyCorrect(target.GetTy())) {
        return target.GetTy()
    }
    if (let Some(propDecl) <- (target as PropDecl)) {
        if (let Some(getter) <- GetUsableGetterForProperty(propDecl)) {
            if (let Some(getterTy) <- getter.GetTy()) {
                if (let Some(funcTy) <- (getterTy as FuncTy)) {
                    if (Ty.IsTyCorrect(funcTy.retTy)) {
                        return Some(funcTy.retTy)
                    }
                }
            }
        }
    }
    return None
}

func TcSetTyFromTarget(typeManager: TypeManager, node: Node, target: Decl): Ty {
    if (let Some(targetTy) <- TcTargetReferenceTy(target)) {
        let substitutedTy = typeManager.SubstituteTypeAliasInTy(targetTy)
        let instTy = if (let Some(expr) <- (node as Expr)) {
            typeManager.ApplySubstPack(substitutedTy, GenerateGenericTypeMapping(typeManager, expr), ignoreUnsolved: true)
        } else {
            substitutedTy
        }
        node.SetTy(instTy)
        return instTy
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
        var ctorTy: Ty = TypeManager.GetInvalidTy()
        if (let Some(ctor) <- enumPattern.constructor) {
            ctorTy = SynExprShallow(typeManager, ctor)
            if (let Some(ctorRef) <- (ctor as NameReferenceExpr)) {
                ctorTy = InstantiateEnumConstructorRefFromTarget(typeManager, target, ctorRef, ctorTy)
            }
            enumOk = Ty.IsTyCorrect(ctorTy) && enumOk
        }
        if (let Some(funcTy) <- (ctorTy as FuncTy)) {
            if (funcTy.paramTys.size == enumPattern.patterns.size) {
                var idx: Int64 = 0
                while (idx < enumPattern.patterns.size) {
                    enumOk = TcPatternCheck(typeManager, funcTy.paramTys[idx], enumPattern.patterns[idx]) && enumOk
                    idx++
                }
            } else {
                for (subPattern in enumPattern.patterns) {
                    enumOk = TcPatternCheck(typeManager, typeManager.GetAnyTy(), subPattern) && enumOk
                }
            }
        } else {
            for (subPattern2 in enumPattern.patterns) {
                enumOk = TcPatternCheck(typeManager, typeManager.GetAnyTy(), subPattern2) && enumOk
            }
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

private func PropagatePatternCtxExpr(pattern: Pattern, initializer: Expr): Unit {
    if (let Some(varPattern) <- (pattern as VarPattern)) {
        varPattern.ctxExpr = initializer
        return
    }
    if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
        for (subPattern in tuplePattern.patterns) {
            PropagatePatternCtxExpr(subPattern, initializer)
        }
        return
    }
    if (let Some(typePattern) <- (pattern as TypePattern)) {
        if (let Some(innerPattern) <- typePattern.pattern) {
            PropagatePatternCtxExpr(innerPattern, initializer)
        }
        return
    }
    if (let Some(enumPattern) <- (pattern as EnumPattern)) {
        for (subPattern2 in enumPattern.patterns) {
            PropagatePatternCtxExpr(subPattern2, initializer)
        }
        return
    }
    if (let Some(varOrEnumPattern) <- (pattern as VarOrEnumPattern)) {
        if (let Some(innerPattern2) <- varOrEnumPattern.pattern) {
            PropagatePatternCtxExpr(innerPattern2, initializer)
        }
        return
    }
    if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
        if (let Some(innerPattern3) <- exceptPattern.pattern) {
            PropagatePatternCtxExpr(innerPattern3, initializer)
        }
        return
    }
    if (let Some(commandPattern) <- (pattern as CommandTypePattern)) {
        if (let Some(innerPattern4) <- commandPattern.pattern) {
            PropagatePatternCtxExpr(innerPattern4, initializer)
        }
    }
}

private func PatternContainsExplicitVarBinding(pattern: Pattern): Bool {
    if (let Some(_) <- (pattern as VarPattern)) {
        return true
    }
    if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
        for (subPattern in tuplePattern.patterns) {
            if (PatternContainsExplicitVarBinding(subPattern)) {
                return true
            }
        }
        return false
    }
    if (let Some(typePattern) <- (pattern as TypePattern)) {
        if (let Some(innerPattern) <- typePattern.pattern) {
            return PatternContainsExplicitVarBinding(innerPattern)
        }
        return false
    }
    if (let Some(enumPattern) <- (pattern as EnumPattern)) {
        for (subPattern2 in enumPattern.patterns) {
            if (PatternContainsExplicitVarBinding(subPattern2)) {
                return true
            }
        }
        return false
    }
    if (let Some(varOrEnumPattern) <- (pattern as VarOrEnumPattern)) {
        if (let Some(innerPattern2) <- varOrEnumPattern.pattern) {
            return PatternContainsExplicitVarBinding(innerPattern2)
        }
        return false
    }
    if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
        if (let Some(innerPattern3) <- exceptPattern.pattern) {
            return PatternContainsExplicitVarBinding(innerPattern3)
        }
        return false
    }
    if (let Some(commandPattern) <- (pattern as CommandTypePattern)) {
        if (let Some(innerPattern4) <- commandPattern.pattern) {
            return PatternContainsExplicitVarBinding(innerPattern4)
        }
    }
    return false
}

private func LetPatternHasExplicitVarBinding(letDestructor: LetPatternDestructor): Bool {
    for (pattern in letDestructor.patterns) {
        if (PatternContainsExplicitVarBinding(pattern)) {
            return true
        }
    }
    return false
}

private func ExprHasExplicitVarBindingInCondition(expr: Expr): Bool {
    if (let Some(letDestructor) <- (expr as LetPatternDestructor)) {
        return LetPatternHasExplicitVarBinding(letDestructor)
    }
    if (let Some(parenExpr) <- (expr as ParenExpr)) {
        if (let Some(innerExpr) <- parenExpr.expr) {
            return ExprHasExplicitVarBindingInCondition(innerExpr)
        }
        return false
    }
    if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
        if (let Some(leftExpr) <- binaryExpr.leftExpr) {
            if (ExprHasExplicitVarBindingInCondition(leftExpr)) {
                return true
            }
        }
        if (let Some(rightExpr) <- binaryExpr.rightExpr) {
            if (ExprHasExplicitVarBindingInCondition(rightExpr)) {
                return true
            }
        }
    }
    return false
}

private func PatternsHaveCompatibleKinds(patterns: ArrayList<Pattern>): Bool {
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
    let firstKind = patterns[0].astKind
    for (idx in 1..patterns.size) {
        if (patterns[idx].astKind != firstKind) {
            return false
        }
    }
    return true
}

private func SynLetPatternDestructorCondition(typeManager: TypeManager, letDestructor: LetPatternDestructor,
    suppressIntroducingVariableError: Bool): Bool {
    if (let Some(initializer) <- letDestructor.initializer) {
        let selectorTy = SynExprShallow(typeManager, initializer)
        var ok = Ty.IsTyCorrect(selectorTy)
        let concreteSelectorTy = if (ok) { TcReplaceIdeal(typeManager, initializer) } else { selectorTy }
        if (!PatternsHaveCompatibleKinds(letDestructor.patterns)) {
            ok = false
        }
        if (!suppressIntroducingVariableError && letDestructor.patterns.size > 1 &&
            LetPatternHasExplicitVarBinding(letDestructor)) {
            ok = false
        }
        for (pattern in letDestructor.patterns) {
            pattern.ctxExpr = initializer
            PropagatePatternCtxExpr(pattern, initializer)
            ok = TcPatternCheck(typeManager, concreteSelectorTy, pattern) && ok
        }
        if (ok) {
            letDestructor.SetTy(TcBoolTy())
            return true
        }
    }
    let _ = TcInvalid(letDestructor)
    return false
}

private func TcCheckConditionInternal(typeManager: TypeManager, expr: Expr,
    suppressIntroducingVariableError: Bool, ctx!: Option<ASTContext> = None): Bool {
    if (let Some(parenExpr) <- (expr as ParenExpr)) {
        if (let Some(innerExpr) <- parenExpr.expr) {
            let ok = TcCheckConditionInternal(typeManager, innerExpr, suppressIntroducingVariableError, ctx: ctx)
            parenExpr.SetTy(TcTyOrInvalid(innerExpr))
            return ok
        }
        let _ = TcInvalid(parenExpr)
        return false
    }
    if (let Some(letDestructor) <- (expr as LetPatternDestructor)) {
        return SynLetPatternDestructorCondition(typeManager, letDestructor, suppressIntroducingVariableError)
    }
    if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
        if (binaryExpr.op == TokenKind.AND || binaryExpr.op == TokenKind.OR) {
            var suppressChildren = suppressIntroducingVariableError
            if (!suppressChildren && binaryExpr.op == TokenKind.OR &&
                ExprHasExplicitVarBindingInCondition(binaryExpr)) {
                suppressChildren = true
            }
            var ok = true
            if (let Some(leftExpr) <- binaryExpr.leftExpr) {
                ok = TcCheckConditionInternal(typeManager, leftExpr, suppressChildren, ctx: ctx) && ok
            } else {
                ok = false
            }
            if (let Some(rightExpr) <- binaryExpr.rightExpr) {
                ok = TcCheckConditionInternal(typeManager, rightExpr, suppressChildren, ctx: ctx) && ok
            } else {
                ok = false
            }
            if (ok && !suppressChildren) {
                binaryExpr.SetTy(TcBoolTy())
                return true
            }
            let _ = TcInvalid(binaryExpr)
            return false
        }
    }
    return ChkExprShallow(typeManager, TcBoolTy(), expr, ctx: ctx)
}

func TcCheckCondition(typeManager: TypeManager, expr: Expr, ctx!: Option<ASTContext> = None): Bool {
    return TcCheckConditionInternal(typeManager, expr, false, ctx: ctx)
}

private func SynCallArg(typeManager: TypeManager, arg: FuncArg): Bool {
    if (let Some(expr) <- arg.expr) {
        if (Ty.IsTyCorrect(expr.GetTy())) {
            let concreteExistingTy = TcReplaceIdeal(typeManager, expr)
            arg.SetTy(concreteExistingTy)
            return true
        }
        let exprTy = SynExprShallow(typeManager, expr)
        if (Ty.IsTyCorrect(exprTy)) {
            let concreteTy = TcReplaceIdeal(typeManager, expr)
            arg.SetTy(concreteTy)
            return true
        }
    }
    arg.SetTy(TypeManager.GetInvalidTy())
    return false
}

private func SynCallChildren(typeManager: TypeManager, ce: CallExpr): Bool {
    var ok = true
    if (let Some(baseFunc) <- ce.baseFunc) {
        SetIsNotAlone(baseFunc)
        let baseTy = SynExprShallow(typeManager, baseFunc)
        ok = (Ty.IsTyCorrect(baseTy) || (baseTy.IsQuest() && !GetFuncTargets(baseFunc).isEmpty())) && ok
    }
    for (arg in ce.args) {
        ok = SynCallArg(typeManager, arg) && ok
    }
    return ok
}

private func SynCallExprShallow(typeManager: TypeManager, ce: CallExpr, ctx!: Option<ASTContext> = None): Ty {
    if (!SynCallChildren(typeManager, ce)) {
        return TcInvalid(ce)
    }
    let callTy = SynCallExpr(typeManager, ce, ctx: ctx)
    if (Ty.IsTyCorrect(callTy)) {
        return callTy
    }
    return TcInvalid(ce)
}

private func ChkCallExprShallow(typeManager: TypeManager, target: Ty, ce: CallExpr, ctx!: Option<ASTContext> = None): Bool {
    if (!SynCallChildren(typeManager, ce)) {
        let _ = TcInvalid(ce)
        return false
    }
    if (ChkCallExpr(typeManager, None, Some(target), ce, ctx: ctx)) {
        return true
    }
    if (Ty.IsTyCorrect(ce.GetTy())) {
        return false
    }
    let _ = TcInvalid(ce)
    return false
}

private func AddTargetIfMissing(targets: ArrayList<Decl>, candidate: Decl): Unit {
    for (target in targets) {
        if (sameImportedAwareDecl(target, candidate)) {
            return
        }
    }
    targets.add(candidate)
}

private func sameImportedAwareDecl(left: Decl, right: Decl): Bool {
    if (left.TestAttr(Attribute.IMPORTED) && right.TestAttr(Attribute.IMPORTED)) {
        if (!left.rawMangleName.isEmpty() || !right.rawMangleName.isEmpty()) {
            return left.rawMangleName == right.rawMangleName
        }
        if (!left.mangledName.isEmpty() || !right.mangledName.isEmpty()) {
            return left.mangledName == right.mangledName
        }
    }
    return SameDecl(left, right)
}

private func PopulateMemberAccessTargets(typeManager: TypeManager, ma: MemberAccess, baseTy: Ty,
    diag!: Option<BasicDiagnosticEngine> = None): Unit {
    if ((let Some(_) <- ma.target) || !ma.targets.isEmpty() || !Ty.IsTyCorrect(baseTy)) {
        return
    }
    if (let Some(genericTy) <- (baseTy as GenericsTy)) {
        PopulateMemberAccessTargetsFromUpperBounds(typeManager, ma, genericTy)
        return
    }
    if (baseTy.IsIdeal()) {
        PopulateIdealMemberAccessTargets(typeManager, ma, baseTy, diag: diag)
        return
    }
    let info = LookupInfo(baseTy: Some(baseTy), file: ma.curFile)
    let foundFields = FieldLookup(typeManager, Ty.GetDeclPtrOfTy(Some(baseTy)), ma.field.Val(), info: info)
    for (decl in foundFields) {
        AddTargetIfMissing(ma.targets, decl)
    }
    if (let Some(file) <- ma.curFile) {
        for (decl in ExtendFieldLookup(typeManager, file, Some(baseTy), ma.field.Val())) {
            AddTargetIfMissing(ma.targets, decl)
        }
    }
}

private func PopulateIdealMemberAccessTargets(typeManager: TypeManager, ma: MemberAccess, baseTy: Ty,
    diag!: Option<BasicDiagnosticEngine> = None): Unit {
    let candidates = ArrayList<Decl>()
    let targetTys = ArrayList<Ty>()
    if (let Some(file) <- ma.curFile) {
        for (tyKind in GetIdealTypesByKind(baseTy.kind)) {
            let concreteTy = TypeManager.GetPrimitiveTy(tyKind)
            for (decl in ExtendFieldLookup(typeManager, file, Some(concreteTy), ma.field.Val())) {
                if (!decl.TestAttr(Attribute.STATIC)) {
                    AddTargetIfMissing(candidates, decl)
                    targetTys.add(concreteTy)
                }
            }
        }
    }
    if (candidates.size > 1) {
        if (let Some(baseExpr) <- ma.baseExpr) {
            let _ = ReplaceIdealTy(typeManager, baseExpr, diag: diag)
            if (let Some(replacedTy) <- baseExpr.GetTy()) {
                PopulateMemberAccessTargets(typeManager, ma, replacedTy, diag: diag)
            }
        }
        return
    }
    if (candidates.size == 1) {
        if (let Some(baseExpr) <- ma.baseExpr) {
            baseExpr.SetTy(targetTys[targetTys.size - 1])
        }
        AddTargetIfMissing(ma.targets, candidates[0])
    }
}

private func PopulateMemberAccessTargetsFromUpperBounds(typeManager: TypeManager, ma: MemberAccess,
    genericTy: GenericsTy): Unit {
    ma.isExposedAccess = true
    if (!genericTy.isUpperBoundLegal) {
        return
    }
    for (upperBound in genericTy.upperBounds) {
        if (!Ty.IsTyCorrect(upperBound)) {
            continue
        }
        let targets = GetUpperBoundTargets(typeManager, ma, upperBound, false)
        if (!targets.isEmpty() && ma.matchedParentTy.isNone()) {
            ma.matchedParentTy = Some(upperBound)
        }
        for (decl in targets) {
            AddTargetIfMissing(ma.targets, decl)
            AddUpperBoundTargetMap(ma, decl, upperBound)
        }
    }
}

private func GetUpperBoundTargets(typeManager: TypeManager, ma: MemberAccess, upperBound: Ty,
    isStaticAccess: Bool): ArrayList<Decl> {
    let targets = ArrayList<Decl>()
    if (upperBound.IsClassLike() || upperBound.IsStruct() || upperBound.IsEnum()) {
        let info = LookupInfo(baseTy: Some(upperBound), file: ma.curFile)
        for (decl in FieldLookup(typeManager, Ty.GetDeclPtrOfTy(Some(upperBound)), ma.field.Val(), info: info)) {
            if (IsUpperBoundTargetValidForAccess(decl, isStaticAccess)) {
                AddTargetIfMissing(targets, decl)
            }
        }
        return targets
    }
    if (let Some(file) <- ma.curFile) {
        for (decl in ExtendFieldLookup(typeManager, file, Some(upperBound), ma.field.Val())) {
            if (IsUpperBoundTargetValidForAccess(decl, isStaticAccess)) {
                AddTargetIfMissing(targets, decl)
            }
        }
    }
    return targets
}

private func IsUpperBoundTargetValidForAccess(decl: Decl, isStaticAccess: Bool): Bool {
    return if (isStaticAccess) { decl.TestAttr(Attribute.STATIC) } else { !decl.TestAttr(Attribute.STATIC) }
}

private func AddUpperBoundTargetMap(ma: MemberAccess, target: Decl, upperBound: Ty): Unit {
    let uppers = ArrayList<Ty>()
    uppers.add(upperBound)
    ma.foundUpperBoundMap.add((target, uppers))
}

public func SynExprShallow(typeManager: TypeManager, expr: Expr,
    diag!: Option<BasicDiagnosticEngine> = None, ctx!: Option<ASTContext> = None,
    importManager!: Option<SemaImportManager> = None): Ty {
    if (let Some(desugar) <- expr.desugarExpr) {
        if (let Some(desugarTy) <- desugar.GetTy()) {
            expr.SetTy(desugarTy)
            return desugarTy
        }
    }
    if (let Some(value) <- (expr as PrimitiveTypeExpr)) {
        let ty = TypeManager.GetPrimitiveTy(value.typeKind)
        expr.SetTy(ty)
        return ty
    }
    if (let Some(value) <- (expr as LitConstExpr)) { return SynLitConstExpr(value, diag: diag) }
    if (let Some(value) <- (expr as ParenExpr)) { return SynParenExpr(typeManager, value) }
    if (let Some(value) <- (expr as TupleLit)) { return SynTupleLit(typeManager, value) }
    if (let Some(value) <- (expr as CallExpr)) { return SynCallExprShallow(typeManager, value, ctx: ctx) }
    if (let Some(value) <- (expr as Block)) { return SynBlock(typeManager, value, diag: diag) }
    if (let Some(value) <- (expr as UnaryExpr)) { return SynUnaryExpr(typeManager, value) }
    if (let Some(value) <- (expr as BinaryExpr)) {
        return SynBinaryExpr(typeManager, value, ctx: ctx,
            synthesizer: Some({ operand: Expr => SynExprShallow(typeManager, operand, ctx: ctx) }), diag: diag)
    }
    if (let Some(value) <- (expr as AssignExpr)) { return SynAssignExpr(typeManager, value, ctx: ctx) }
    if (let Some(value) <- (expr as IfExpr)) { return SynIfExpr(typeManager, value) }
    if (let Some(value) <- (expr as WhileExpr)) { return SynWhileExpr(typeManager, value, ctx: ctx) }
    if (let Some(value) <- (expr as DoWhileExpr)) { return SynDoWhileExpr(typeManager, value, ctx: ctx) }
    if (let Some(value) <- (expr as ForInExpr)) {
        if (let Some(realCtx) <- ctx) {
            return SynForInExpr(typeManager, value, realCtx, diag: diag, importManager: importManager)
        }
        return TcInvalid(value)
    }
    if (let Some(value) <- (expr as LambdaExpr)) { return SynLamExpr(typeManager, value, ctx: ctx) }
    if (let Some(value) <- (expr as TryExpr)) { return SynTryExpr(typeManager, value) }
    if (let Some(value) <- (expr as IfAvailableExpr)) { return SynIfAvailableExpr(typeManager, value) }
    if (let Some(value) <- (expr as SubscriptExpr)) { return SynSubscriptExpr(typeManager, value) }
    if (let Some(value) <- (expr as RangeExpr)) { return SynRangeExpr(typeManager, value) }
    if (let Some(value) <- (expr as IsExpr)) { return SynIsExpr(typeManager, value) }
    if (let Some(value) <- (expr as AsExpr)) {
        if (let Some(manager) <- importManager) {
            return SynAsExpr(typeManager, value, manager.GetCoreDecl<EnumDecl>("Option"), diag: diag)
        } else if (let Some(realCtx) <- ctx) {
            return SynAsExpr(typeManager, value, GetCoreDecl(realCtx, "Option") as EnumDecl, diag: diag)
        }
        return SynAsExpr(typeManager, value, None, diag: diag)
    }
    if (let Some(value) <- (expr as IncOrDecExpr)) {
        return SynIncOrDecExpr(value,
            { operand: Expr => SynExprShallow(typeManager, operand, diag: diag) },
            { desugar: Expr => SynExprShallow(typeManager, desugar, diag: diag) },
            diag: diag)
    }
    if (let Some(value) <- (expr as OptionalChainExpr)) { return SynOptionalChainExpr(typeManager, value) }
    if (let Some(value) <- (expr as ReturnExpr)) { return SynReturnExpr(typeManager, value) }
    if (let Some(value) <- (expr as JumpExpr)) { return SynLoopControlExpr(value) }
    if (let Some(value) <- (expr as ThrowExpr)) { return SynThrowExpr(typeManager, value, diag: diag) }
    if (let Some(value) <- (expr as PerformExpr)) { return SynPerformExpr(typeManager, value) }
    if (let Some(value) <- (expr as ResumeExpr)) { return SynResumeExpr(typeManager, value) }
    if (let Some(value) <- (expr as QuoteExpr)) { return SynQuoteExpr(value) }
    if (let Some(value) <- (expr as TypeConvExpr)) { return SynTypeConvExpr(typeManager, value) }
    if (let Some(value) <- (expr as SpawnExpr)) { return SynSpawnExpr(typeManager, value) }
    if (let Some(value) <- (expr as SynchronizedExpr)) { return SynSyncExpr(typeManager, value) }
    if (let Some(value) <- (expr as NameReferenceExpr)) { return SynNameReferenceExpr(typeManager, value, diag: diag) }
    if (let Some(existingTy) <- expr.GetTy()) {
        if (Ty.IsTyCorrect(existingTy)) {
            return existingTy
        }
    }
    return TcInvalid(expr)
}

public func ChkExprShallow(typeManager: TypeManager, target: Ty, expr: Expr,
    ctx!: Option<ASTContext> = None, diag!: Option<BasicDiagnosticEngine> = None,
    importManager!: Option<SemaImportManager> = None): Bool {
    if (let Some(realCtx) <- ctx) {
        typeCheckExprPutTargetType(realCtx, expr, target)
    }
    if (let Some(value) <- (expr as LitConstExpr)) { return ChkLitConstExpr(typeManager, target, value, diag: diag) }
    if (let Some(value) <- (expr as ParenExpr)) { return ChkParenExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as TupleLit)) { return ChkTupleLit(typeManager, target, value, diag: diag) }
    if (let Some(value) <- (expr as CallExpr)) { return ChkCallExprShallow(typeManager, target, value, ctx: ctx) }
    if (let Some(value) <- (expr as Block)) { return ChkBlock(typeManager, target, value, diag: diag) }
    if (let Some(value) <- (expr as UnaryExpr)) { return ChkUnaryExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as BinaryExpr)) {
        return ChkBinaryExpr(typeManager, target, value, ctx: ctx,
            synthesizer: Some({ operand: Expr => SynExprShallow(typeManager, operand, ctx: ctx) }), diag: diag)
    }
    if (let Some(value) <- (expr as AssignExpr)) { return ChkAssignExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as IfExpr)) { return ChkIfExpr(typeManager, target, value, ctx: ctx, diag: diag) }
    if (let Some(value) <- (expr as WhileExpr)) { return ChkWhileExpr(typeManager, target, value, ctx: ctx) }
    if (let Some(value) <- (expr as DoWhileExpr)) { return ChkDoWhileExpr(typeManager, target, value, ctx: ctx) }
    if (let Some(value) <- (expr as ForInExpr)) {
        if (let Some(realCtx) <- ctx) {
            return ChkForInExpr(typeManager, target, value, realCtx, diag: diag, importManager: importManager)
        }
        let _ = TcInvalid(value)
        return false
    }
    if (let Some(value) <- (expr as LambdaExpr)) { return ChkLamExpr(typeManager, target, value, ctx: ctx) }
    if (let Some(value) <- (expr as TryExpr)) { return ChkTryExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as IfAvailableExpr)) { return ChkIfAvailableExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as SubscriptExpr)) { return ChkSubscriptExpr(typeManager, target, value, ctx: ctx) }
    if (let Some(value) <- (expr as RangeExpr)) { return ChkRangeExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as IsExpr)) { return ChkIsExpr(typeManager, target, value, diag: diag) }
    if (let Some(value) <- (expr as AsExpr)) {
        if (let Some(manager) <- importManager) {
            return ChkAsExpr(typeManager, target, value, manager.GetCoreDecl<EnumDecl>("Option"), diag: diag)
        } else if (let Some(realCtx) <- ctx) {
            return ChkAsExpr(typeManager, target, value, GetCoreDecl(realCtx, "Option") as EnumDecl, diag: diag)
        }
        return ChkAsExpr(typeManager, target, value, None, diag: diag)
    }
    if (let Some(value) <- (expr as IncOrDecExpr)) {
        return ChkIncOrDecExpr(typeManager, target, value,
            { operand: Expr => SynExprShallow(typeManager, operand, diag: diag) },
            { desugar: Expr => SynExprShallow(typeManager, desugar, diag: diag) },
            diag: diag)
    }
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
    if (let Some(value) <- (expr as NameReferenceExpr)) {
        return ChkNameReferenceExpr(typeManager, target, value, diag: diag)
    }
    let actualTy = SynExprShallow(typeManager, expr, diag: diag)
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
            return TcSetTyFromTarget(typeManager, re, target)
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

private func SynMemberAccess(typeManager: TypeManager, ma: MemberAccess,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(baseExpr) <- ma.baseExpr) {
        SetIsNotAlone(baseExpr)
        if (!Ty.IsTyCorrect(baseExpr.GetTy())) {
            let _ = SynExprShallow(typeManager, baseExpr, diag: diag)
        }
        if (let Some(baseTy) <- baseExpr.GetTy()) {
            if (let Some(varrayTy) <- (baseTy as VArrayTy)) {
                if (ma.field.Val() == "size") {
                    let sizeTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
                    ma.SetTy(sizeTy)
                    let literalExpr = CreateLitConstExpr(LitConstKind.INTEGER, "${varrayTy.size}", sizeTy)
                    literalExpr.SetTy(sizeTy)
                    ma.desugarExpr = literalExpr
                    return sizeTy
                }
            }
            PopulateMemberAccessTargets(typeManager, ma, baseTy, diag: diag)
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
            return TcSetTyFromTarget(typeManager, ma, target)
        }
        ma.SetTy(TypeManager.GetQuestTy())
        return TypeManager.GetQuestTy()
    }
    if (Ty.IsTyCorrect(ma.GetTy())) {
        return TcTyOrInvalid(ma)
    }
    return TcInvalid(ma)
}

private func ApplyExplicitGenericArgs(typeManager: TypeManager, nre: NameReferenceExpr, fallback: Ty): Ty {
    if (nre.GetTypeArgs().isEmpty()) {
        return fallback
    }
    if (let Some(target) <- nre.GetTarget()) {
        var genericTarget = GetRealTarget(target)
        if (genericTarget.TestAttr(Attribute.CONSTRUCTOR)) {
            if (let Some(outer) <- genericTarget.outerDecl) {
                genericTarget = outer
            }
        }
        let genericTy = GetGenericType(typeManager, genericTarget, nre.GetTypeArgs())
        nre.SetTy(genericTy)
        return genericTy
    }
    return fallback
}

public func SynNameReferenceExpr(typeManager: TypeManager, nre: NameReferenceExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    for (typeArg in nre.GetTypeArgs()) {
        if (let Some(typeArgTy) <- typeArg.GetTy()) {
            if (!containsTy(nre.instTys, typeArgTy)) {
                nre.instTys.add(typeArgTy)
            }
        }
    }
    if (let Some(refExpr) <- (nre as RefExpr)) {
        return ApplyExplicitGenericArgs(typeManager, nre, SynRefExpr(typeManager, refExpr))
    }
    if (let Some(memberAccess) <- (nre as MemberAccess)) {
        return ApplyExplicitGenericArgs(typeManager, nre, SynMemberAccess(typeManager, memberAccess, diag: diag))
    }
    if (Ty.IsTyCorrect(nre.GetTy())) {
        return TcTyOrInvalid(nre)
    }
    return TcInvalid(nre)
}

func IsEnumNeedSynthesis(expr: Expr, target: Decl): Bool {
    if (!target.TestAttr(Attribute.ENUM_CONSTRUCTOR) || target.GetGeneric().isNone()) {
        return false
    }
    var ref = expr
    if (let Some(memberAccess) <- (expr as MemberAccess)) {
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            ref = baseExpr
        }
    }
    return NeedFurtherInstantiation(ref.GetTypeArgs())
}

func CheckInferrableEnumReference(diag: Option<BasicDiagnosticEngine>, typeManager: TypeManager,
    expr: Expr, target: Ty): Bool {
    let refineResult = EnumSugarTargetsFinder.RefineTargetTy(typeManager, target, expr.GetTarget())
    if (let None <- refineResult) {
        if (let Some(diagValue) <- diag) {
            let builder = diagValue.Diagnose(expr.begin, expr.end, BasicDiagKind.sema_generic_type_without_type_argument)
            builder.Emit()
        }
        return false
    }
    var targetTy = refineResult.getOrThrow()
    if (target.IsInterface()) {
        let candidateTys = Promotion(typeManager).Downgrade(targetTy, target)
        if (candidateTys.values.isEmpty()) {
            if (let Some(diagValue2) <- diag) {
                DiagUnableToInferExpr(diagValue2, expr)
            }
            return false
        }
        targetTy = candidateTys.values[0]
    }
    expr.SetTy(targetTy)
    var ref = expr
    if (let Some(memberAccess2) <- (expr as MemberAccess)) {
        if (let Some(baseExpr2) <- memberAccess2.baseExpr) {
            ref = baseExpr2
            ref.SetTy(targetTy)
        }
    }
    if (let Some(reference) <- (ref as NameReferenceExpr)) {
        reference.instTys.clear()
        for (argTy in targetTy.typeArgs) {
            reference.instTys.add(argTy)
        }
    }
    return true
}

private func CheckNonFunctionReference(diag: Option<BasicDiagnosticEngine>, typeManager: TypeManager, target: Ty,
    refNode: Expr): Bool {
    let refTarget = refNode.GetTarget()
    let checkEnumCtor = if (let Some(targetDecl) <- refTarget) {
        targetDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)
    } else {
        false
    }
    if (checkEnumCtor && IsEnumNeedSynthesis(refNode, refTarget.getOrThrow())) {
        return CheckInferrableEnumReference(diag, typeManager, refNode, target)
    }
    let refTy = refNode.GetTy() ?? TypeManager.GetInvalidTy()
    let isWellTyped = typeManager.IsSubtype(refTy, target)
    if (!isWellTyped) {
        if (let Some(diagValue) <- diag) {
            DiagMismatchedTypes(diagValue, refNode, target)
        }
        refNode.SetTy(TypeManager.GetInvalidTy())
    }
    return isWellTyped
}

private func EnumConstructorOuterDecl(nre: NameReferenceExpr): Option<EnumDecl> {
    if (let Some(target) <- nre.GetTarget()) {
        if (target.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            if (let Some(outer) <- target.outerDecl) {
                return outer as EnumDecl
            }
        }
    }
    return None
}

private func SameEnumDeclAsTarget(enumDecl: EnumDecl, target: Ty): Bool {
    if (let Some(enumTy) <- (target as EnumTy)) {
        if (let Some(targetDecl) <- enumTy.declPtr) {
            return SameDecl(enumDecl, targetDecl)
        }
    }
    return false
}

private func InstantiateEnumConstructorRefFromTarget(
    typeManager: TypeManager,
    target: Ty,
    nre: NameReferenceExpr,
    actualTy: Ty
): Ty {
    if (!actualTy.HasGeneric()) {
        return actualTy
    }
    if (let None <- EnumConstructorOuterDecl(nre)) {
        return actualTy
    }
    let enumDecl = EnumConstructorOuterDecl(nre).getOrThrow()
    if (!SameEnumDeclAsTarget(enumDecl, target)) {
        return actualTy
    }
    let typeMapping = GenerateTypeMapping(enumDecl, target.typeArgs)
    let instTy = typeManager.GetInstantiatedTy(actualTy, typeMapping)
    if (Ty.IsTyCorrect(instTy)) {
        for (argTy in target.typeArgs) {
            if (!containsTy(nre.instTys, argTy)) {
                nre.instTys.add(argTy)
            }
        }
        nre.SetTy(instTy)
        return instTy
    }
    return actualTy
}

public func ChkNameReferenceExpr(typeManager: TypeManager, target: Ty, nre: NameReferenceExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    var actualTy = SynNameReferenceExpr(typeManager, nre, diag: diag)
    if (!Ty.IsTyCorrect(actualTy)) {
        return false
    }
    if (nre.callOrPattern.isNone()) {
        actualTy = InstantiateEnumConstructorRefFromTarget(typeManager, target, nre, actualTy)
    }
    if (nre.callOrPattern.isNone() && (actualTy as FuncTy).isNone() && (let Some(refTarget) <- nre.GetTarget())) {
        if (refTarget.TestAttr(Attribute.ENUM_CONSTRUCTOR) && IsEnumNeedSynthesis(nre, refTarget)) {
            return CheckNonFunctionReference(diag, typeManager, target, nre)
        }
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
