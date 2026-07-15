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
import cjcj::utils.CJC_ASSERT

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

private func containsTy(values: ArrayList<Ty>, ty: Ty): Bool {
    for (value in values) {
        if (SameTy(value, ty)) {
            return true
        }
    }
    return false
}

extend TypeChecker {
    public func ChkRefExpr(ctx: ASTContext, target: Ty, nre: NameReferenceExpr): Bool {
        let _ = Synthesize(ctx, SynPos.EXPR_ARG, nre)
        let targets = GetFuncTargets(nre)
        if (targets.isEmpty()) {
            return CheckNonFunctionReference(impl.diag, impl.typeManager, target, nre)
        }
        var matched: UInt32 = 0u32
        CJC_ASSERT(nre.IsReferenceExpr())
        RemoveDuplicateElements(targets)
        let funcTargets = ArrayList<FuncDecl>()
        for (candidate in targets) {
            funcTargets.add(candidate.getOrThrow())
        }
        mpImpl.RemoveCommonCandidatesIfHasSpecific(funcTargets)
        let pair = CollectValidFuncTys(impl.typeManager, impl.diag, ctx, funcTargets, nre,
            targetTy: target as FuncTy)
        var resultMapping = TypeSubst()
        var matchedFd: Option<FuncDecl> = None
        var validCandidateTy: Option<Ty> = None
        for ((fd, fdTy, mapping) in pair.candidates) {
            if (!impl.typeManager.IsSubtype(fdTy, target)) {
                if (validCandidateTy.isNone() && Ty.IsTyCorrect(fdTy) &&
                    !(fdTy as FuncTy).getOrThrow().retTy.IsQuest()) {
                    validCandidateTy = Some(fdTy)
                }
                continue
            }
            if (matched != 0u32) {
                matched++
                break
            }
            matched++
            ReplaceTarget(nre, Some<Decl>(fd))
            matchedFd = Some(fd)
            nre.SetTy(fdTy)
            resultMapping = mapping
        }
        nre.SetTy(TypeManager.GetNonNullTy(nre.GetTy().getOrThrow()))
        if (nre.GetTy().getOrThrow().IsQuest()) {
            nre.SetTy(TypeManager.GetInvalidTy())
        }
        if (matched > 1u32) {
            if (let Some(diag) <- impl.diag) {
                Diagnose(diag, nre, BasicDiagKind.sema_ambiguous_func_ref,
                    args: [BasicDiagArgument(funcTargets[0].identifier.Val())]).Emit()
            }
        } else if (matched == 0u32) {
            if (Ty.IsTyCorrect(nre.GetTy()) && nre.GetTy().getOrThrow().HasQuestTy()) {
                DiagUnableToInferReturnType(impl.diag.getOrThrow(), funcTargets[0], nre)
            } else if (pair.genericIgnored) {
                if (let Some(diag2) <- impl.diag) {
                    Diagnose(diag2, nre, BasicDiagKind.sema_generic_type_without_type_argument).Emit()
                }
            } else if (let Some(candidateTy) <- validCandidateTy) {
                DiagMismatchedTypesWithFoundTy(impl.diag.getOrThrow(), nre, target, candidateTy)
            } else if (let Some(diag3) <- impl.diag) {
                Diagnose(diag3, nre, BasicDiagKind.sema_no_match_function_declaration_for_ref,
                    args: [BasicDiagArgument(funcTargets[0].identifier.Val())]).Emit()
            }
            if (funcTargets.size > 1) {
                ReplaceTarget(nre, None)
            }
        } else {
            let selected = matchedFd.getOrThrow()
            if (IsGenericUpperBoundCall(nre, selected)) {
                nre.matchedParentTy = Some(impl.typeManager.GetInstantiatedTy(
                    selected.outerDecl.getOrThrow().GetTy().getOrThrow(), resultMapping))
            }
            InstantiateReferenceType(ctx, nre, instantiateMap: resultMapping)
        }
        return matched != 0u32
    }
}
