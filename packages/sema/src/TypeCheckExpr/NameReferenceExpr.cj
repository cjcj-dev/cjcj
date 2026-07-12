package cjcj::sema.TypeCheckExpr

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::modules.SemaImportManager
import cjcj::sema.*
import cjcj::sema.Desugar.*

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

func GetTargetsSameASTKind(targets: ArrayList<Decl>): ASTKind {
    var result = ASTKind.INVALID_DECL
    for (target in targets) {
        if (result == ASTKind.INVALID_DECL && target.astKind != ASTKind.INVALID_DECL) {
            result = target.astKind
        }
        if (result != target.astKind) {
            return ASTKind.INVALID_DECL
        }
    }
    return result
}

func GetTargetsSameASTKind(allTargets: ArrayList<(Ty, ArrayList<Decl>)>): ASTKind {
    var result = ASTKind.INVALID_DECL
    for ((_, targets) in allTargets) {
        let kind = GetTargetsSameASTKind(targets)
        if (kind == ASTKind.INVALID_DECL || (result != ASTKind.INVALID_DECL && result != kind)) {
            return ASTKind.INVALID_DECL
        }
        result = kind
    }
    return result
}

func GetUpperBoundTargetsWithGivenKind(allTargets: ArrayList<(Ty, ArrayList<Decl>)>,
    kinds: ArrayList<ASTKind>): ArrayList<(Decl, ArrayList<Ty>)> {
    let results = ArrayList<(Decl, ArrayList<Ty>)>()
    for ((ty, targets) in allTargets) {
        for (target in targets) {
            if (!kinds.contains(target.astKind)) {
                continue
            }
            var found = false
            for ((resultTarget, upperBounds) in results) {
                if (resultTarget == target) {
                    upperBounds.add(ty)
                    found = true
                    break
                }
            }
            if (!found) {
                let upperBounds = ArrayList<Ty>()
                upperBounds.add(ty)
                results.add((target, upperBounds))
            }
        }
    }
    return results
}

func IsCloserToImpl(source: Decl, target: Decl): Bool {
    let updateAbstract = source.TestAttr(Attribute.ABSTRACT) && !target.TestAttr(Attribute.ABSTRACT)
    let updateNonInterface = !source.TestAttr(Attribute.ABSTRACT) && !target.TestAttr(Attribute.ABSTRACT) &&
        target.outerDecl.isSome() && target.outerDecl.getOrThrow().astKind != ASTKind.INTERFACE_DECL
    return updateAbstract || updateNonInterface
}

func DiagForGenericParamMemberNotFound(diag: BasicDiagnosticEngine, ma: MemberAccess,
    genericParamDecl: GenericParamDecl): Unit {
    if (Ty.IsTyCorrect(genericParamDecl.GetTy()) && genericParamDecl.GetTy().getOrThrow().IsGeneric()) {
        if (let Some(genericTy) <- (genericParamDecl.GetTy().getOrThrow() as GenericsTy)) {
            if (genericTy.isUpperBoundLegal) {
                let baseExpr = ma.baseExpr.getOrThrow()
                let builder = Diagnose(diag, baseExpr, BasicDiagKind.sema_invalid_field_expose_access,
                    args: [BasicDiagArgument(ma.field.Val()), BasicDiagArgument("exposed generic parameter"),
                        BasicDiagArgument(genericParamDecl.identifier.Val())])
                builder.Emit()
            }
        }
    }
}

func DiagAmbiguousUpperBoundTargets(diag: BasicDiagnosticEngine, ma: MemberAccess,
    targets: ArrayList<Decl>): Unit {
    let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_ambiguous_use, ma,
        MakeRange(ma.field.Begin(), ma.field.End()), arguments: [ma.field.Val()])
    for (target in targets) {
        let outerDecl = target.outerDecl.getOrThrow()
        var message = "found "
        if (outerDecl.astKind == ASTKind.EXTEND_DECL) {
            message += "extended "
        }
        message += DeclKindToString(target) + " member of '" + outerDecl.GetTy().getOrThrow().String() + "'"
        AddNote(builder, target, MakeRangeForDeclIdentifier(target), message)
    }
    builder.Emit()
}

func FoundSameSignatureMember(typeManager: TypeManager, decl: Decl, funcTy: FuncTy,
    methodSigs: ArrayList<(String, ArrayList<Ty>, Decl)>): Option<Int64> {
    for (idx in 0..methodSigs.size) {
        var sameParams = methodSigs[idx][1].size == funcTy.paramTys.size
        if (sameParams) {
            for (paramIdx in 0..funcTy.paramTys.size) {
                if (!(methodSigs[idx][1][paramIdx] == funcTy.paramTys[paramIdx])) {
                    sameParams = false
                    break
                }
            }
        }
        if (methodSigs[idx][0] == decl.identifier.Val() && sameParams) {
            return Some(idx)
        }
    }
    if (!decl.TestAttr(Attribute.GENERIC)) {
        return None
    }
    for ((_, _, method) in methodSigs) {
        if (!method.TestAttr(Attribute.GENERIC)) {
            continue
        }
        let typeMapping = typeManager.GenerateGenericMappingFromGeneric(decl, method)
        if (let Some(instTy) <- (typeManager.GetInstantiatedTy(funcTy, typeMapping) as FuncTy)) {
            for (idx in 0..methodSigs.size) {
                var sameParams = methodSigs[idx][1].size == instTy.paramTys.size
                if (sameParams) {
                    for (paramIdx in 0..instTy.paramTys.size) {
                        if (!(methodSigs[idx][1][paramIdx] == instTy.paramTys[paramIdx])) {
                            sameParams = false
                            break
                        }
                    }
                }
                if (methodSigs[idx][0] == decl.identifier.Val() && sameParams) {
                    return Some(idx)
                }
            }
        }
    }
    return None
}

func FoundSameSignatureMember(typeManager: TypeManager, decl: Decl, funcTy: FuncTy,
    methodSigs: ArrayList<(FuncTy, Decl)>): Option<Int64> {
    for (idx in 0..methodSigs.size) {
        if (methodSigs[idx][0] == funcTy) {
            return Some(idx)
        }
    }
    if (!decl.TestAttr(Attribute.GENERIC)) {
        return None
    }
    for ((_, method) in methodSigs) {
        if (!method.TestAttr(Attribute.GENERIC)) {
            continue
        }
        let typeMapping = typeManager.GenerateGenericMappingFromGeneric(decl, method)
        if (let Some(instTy) <- (typeManager.GetInstantiatedTy(funcTy, typeMapping) as FuncTy)) {
            for (idx in 0..methodSigs.size) {
                if (methodSigs[idx][0] == instTy) {
                    return Some(idx)
                }
            }
        }
    }
    return None
}

func CompNodeByPos(left: Decl, right: Decl): Bool {
    return left.begin.fileID < right.begin.fileID ||
        (left.begin.fileID == right.begin.fileID && left.begin < right.begin) ||
        (left.begin.fileID == right.begin.fileID && left.begin == right.begin && left.objectId < right.objectId)
}

func MergeFuncTargetsInUpperBounds(typeManager: TypeManager, ma: MemberAccess): ArrayList<Decl> {
    let methodSigs = ArrayList<(String, ArrayList<Ty>, Decl)>()
    let upperDecls = ArrayList<Decl>()
    for ((decl, _) in ma.foundUpperBoundMap) {
        var found = false
        for (existing in upperDecls) {
            if (existing == decl) {
                found = true
                break
            }
        }
        if (!found) {
            upperDecls.add(decl)
        }
    }
    sort(upperDecls, by: { left: Decl, right: Decl =>
        if (CompNodeByPos(left, right)) { Ordering.LT } else if (CompNodeByPos(right, left)) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    })
    for (decl in upperDecls) {
        if (decl.astKind != ASTKind.FUNC_DECL || !Ty.IsTyCorrect(decl.GetTy())) {
            continue
        }
        let mappings = MultiTypeSubst()
        typeManager.GenerateTypeMappingForUpperBounds(mappings, ma, decl)
        for (ty in typeManager.GetInstantiatedTys(decl.GetTy().getOrThrow(), mappings).values) {
            if (let Some(funcTy) <- (ty as FuncTy)) {
                if (!Ty.IsTyCorrect(funcTy)) {
                    continue
                }
                if (let Some(found) <- FoundSameSignatureMember(typeManager, decl, funcTy, methodSigs)) {
                    if (IsCloserToImpl(methodSigs[found][2], decl)) {
                        methodSigs.remove(at: found)
                        methodSigs.add((decl.identifier.Val(), funcTy.paramTys, decl))
                    }
                } else {
                    methodSigs.add((decl.identifier.Val(), funcTy.paramTys, decl))
                }
            }
        }
    }
    let targets = ArrayList<Decl>()
    for ((_, _, target) in methodSigs) {
        var found = false
        for (existing in targets) {
            if (existing == target) {
                found = true
                break
            }
        }
        if (!found) {
            targets.add(target)
        }
    }
    return targets
}

func MergeFuncTargetsInSum(typeManager: TypeManager, ma: MemberAccess): ArrayList<Decl> {
    let methodSigs = ArrayList<(FuncTy, Decl)>()
    let upperDecls = ArrayList<Decl>()
    for ((decl, _) in ma.foundUpperBoundMap) {
        var found = false
        for (existing in upperDecls) {
            if (existing == decl) {
                found = true
                break
            }
        }
        if (!found) {
            upperDecls.add(decl)
        }
    }
    sort(upperDecls, by: { left: Decl, right: Decl =>
        if (CompNodeByPos(left, right)) { Ordering.LT } else if (CompNodeByPos(right, left)) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    })
    for (decl in upperDecls) {
        if (decl.astKind != ASTKind.FUNC_DECL || !Ty.IsTyCorrect(decl.GetTy())) {
            continue
        }
        let mappings = MultiTypeSubst()
        typeManager.GenerateTypeMappingForUpperBounds(mappings, ma, decl)
        for (ty in typeManager.GetInstantiatedTys(decl.GetTy().getOrThrow(), mappings).values) {
            if (let Some(funcTy) <- (ty as FuncTy)) {
                if (!Ty.IsTyCorrect(funcTy)) {
                    continue
                }
                if (let Some(found) <- FoundSameSignatureMember(typeManager, decl, funcTy, methodSigs)) {
                    if (IsCloserToImpl(methodSigs[found][1], decl)) {
                        methodSigs.remove(at: found)
                        methodSigs.add((funcTy, decl))
                    }
                } else {
                    methodSigs.add((funcTy, decl))
                }
            }
        }
    }
    let targets = ArrayList<Decl>()
    for ((_, target) in methodSigs) {
        var found = false
        for (existing in targets) {
            if (existing == target) {
                found = true
                break
            }
        }
        if (!found) {
            targets.add(target)
        }
    }
    return targets
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
    if (let Some(value) <- (expr as Block)) { return SynBlock(typeManager, value, diag: diag) }
    if (let Some(value) <- (expr as UnaryExpr)) { return SynUnaryExpr(typeManager, value) }
    if (let Some(value) <- (expr as BinaryExpr)) {
        return SynBinaryExpr(typeManager, value, ctx: ctx,
            synthesizer: Some({ operand: Expr => SynExprShallow(typeManager, operand, ctx: ctx) }), diag: diag)
    }
    if (let Some(value) <- (expr as IfExpr)) {
        return SynIfExpr(typeManager, value, diag.getOrThrow())
    }
    if (let Some(value) <- (expr as WhileExpr)) { return SynWhileExpr(typeManager, value, ctx: ctx) }
    if (let Some(value) <- (expr as DoWhileExpr)) { return SynDoWhileExpr(typeManager, value, ctx: ctx) }
    if (let Some(value) <- (expr as ForInExpr)) {
        if (let Some(realCtx) <- ctx) {
            return SynForInExpr(typeManager, value, realCtx, diag: diag, importManager: importManager)
        }
        return TcInvalid(value)
    }
    if (let Some(value) <- (expr as LambdaExpr)) { return SynLamExpr(typeManager, value, ctx: ctx) }
    if (let Some(value) <- (expr as TryExpr)) {
        return SynTryExpr(typeManager, value, diag.getOrThrow())
    }
    if (let Some(value) <- (expr as IfAvailableExpr)) {
        return SynIfAvailableExpr(typeManager, value, diag.getOrThrow())
    }
    if (let Some(value) <- (expr as SubscriptExpr)) {
        if ((let Some(realCtx) <- ctx) && (let Some(diagValue) <- diag)) {
            return SynSubscriptExpr(typeManager, realCtx, value,
                { _: SynPos, child: Expr => SynExprShallow(typeManager, child, ctx: ctx,
                    diag: diag, importManager: importManager) },
                { targetTy: Ty, child2: Expr => ChkExprShallow(typeManager, targetTy, child2, ctx: ctx,
                    diag: diag, importManager: importManager) }, diagValue)
        }
        return TcInvalid(value)
    }
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
    if (let Some(value) <- (expr as Block)) { return ChkBlock(typeManager, target, value, diag: diag) }
    if (let Some(value) <- (expr as UnaryExpr)) { return ChkUnaryExpr(typeManager, target, value) }
    if (let Some(value) <- (expr as BinaryExpr)) {
        return ChkBinaryExpr(typeManager, target, value, ctx: ctx,
            synthesizer: Some({ operand: Expr => SynExprShallow(typeManager, operand, ctx: ctx) }), diag: diag)
    }
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
    if (let Some(value) <- (expr as IfAvailableExpr)) {
        return ChkIfAvailableExpr(typeManager, target, value, diag.getOrThrow())
    }
    if (let Some(value) <- (expr as SubscriptExpr)) {
        if ((let Some(realCtx) <- ctx) && (let Some(diagValue) <- diag)) {
            return ChkSubscriptExpr(typeManager, realCtx, Some(target), value,
                { _: SynPos, child: Expr => SynExprShallow(typeManager, child, ctx: ctx,
                    diag: diag, importManager: importManager) },
                { targetTy: Ty, child2: Expr => ChkExprShallow(typeManager, targetTy, child2, ctx: ctx,
                    diag: diag, importManager: importManager) }, diagValue)
        }
        let _ = TcInvalid(value)
        return false
    }
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
    let targets = GetFuncTargets(nre)
    if (targets.isEmpty()) {
        return CheckNonFunctionReference(diag, typeManager, target, nre)
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
        for (funcDeclOpt in funcs) {
            let funcDecl = funcDeclOpt.getOrThrow()
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

extend TypeChecker {
}
