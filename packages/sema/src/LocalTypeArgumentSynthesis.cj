package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

public class LocTyArgSynArgPack {
    public let tyVarsToSolve: ArrayList<GenericsTy> = ArrayList<GenericsTy>()
    public let argTys: ArrayList<Ty> = ArrayList<Ty>()
    public let paramTys: ArrayList<Ty> = ArrayList<Ty>()
    public let argBlames: ArrayList<Blame> = ArrayList<Blame>()
    public var funcRetTy: Option<Ty> = None
    public var retTyUB: Option<Ty> = None
    public var retBlame: Blame = Blame(src: None, lb: None, ub: None, style: BlameStyle.ARGUMENT)

    public init() {}
}

private func containsTyVar(values: ArrayList<GenericsTy>, tyVar: GenericsTy): Bool {
    for (value in values) {
        if (SameTy(value, tyVar)) {
            return true
        }
    }
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

private func ToTySet(values: ArrayList<GenericsTy>): TySet {
    let out = TySet()
    for (value in values) {
        out.Add(value)
    }
    return out
}

private func substContainsTyVar(subst: TypeSubst, tyVar: GenericsTy): Bool {
    for (entry in subst.entries) {
        if (entry.ty.Contains(tyVar)) {
            return true
        }
    }
    return false
}

private func typeArgsCanUnify(synthesis: LocalTypeArgumentSynthesis, argTy: Ty, paramTy: Ty): Bool {
    if (argTy.typeArgs.size != paramTy.typeArgs.size) {
        return false
    }
    for (idx in 0..argTy.typeArgs.size) {
        if (!synthesis.UnifyOne(argTy.typeArgs[idx], paramTy.typeArgs[idx])) {
            return false
        }
    }
    return true
}

private func insertOptionIndex(options: ArrayList<Int64>, tys: ArrayList<Ty>, idx: Int64): Unit {
    let level = CountOptionNestedLevel(tys[idx])
    var insertAt = options.size
    var pos: Int64 = 0
    while (pos < options.size) {
        if (CountOptionNestedLevel(tys[options[pos]]) < level) {
            insertAt = pos
            break
        }
        pos++
    }
    options.add(idx)
    var move = options.size - 1
    while (move > insertAt) {
        options[move] = options[move - 1]
        move--
    }
    options[insertAt] = idx
}

private func getOrderedCheckingIndexes(tys: ArrayList<Ty>): ArrayList<Int64> {
    let options = ArrayList<Int64>()
    let others = ArrayList<Int64>()
    let ideals = ArrayList<Int64>()
    for (idx in 0..tys.size) {
        let ty = tys[idx]
        if (Ty.IsTyCorrect(ty)) {
            if (ty.IsIdeal()) {
                ideals.add(idx)
            } else if (ty.IsCoreOptionType()) {
                insertOptionIndex(options, tys, idx)
            } else {
                others.add(idx)
            }
        } else {
            others.add(idx)
        }
    }
    for (idx in others) {
        options.add(idx)
    }
    for (idx in ideals) {
        options.add(idx)
    }
    return options
}

public class LocalTypeArgumentSynthesis {
    private var tyMgr: TypeManager
    private var argPack: LocTyArgSynArgPack
    private var needDiagMsg: Bool
    private var constraints: Constraint = Constraint()
    private var errInfo: SolvingErrInfo = SolvingErrInfo()
    private var curTyVar: Option<GenericsTy> = None
    private var hasNothingTy: Bool = false
    private var hasAnyTy: Bool = false
    private var deterministic: Bool = false
    private let activeBoundChecks: ArrayList<(Ty, Ty)> = ArrayList<(Ty, Ty)>()

    public init(typeManager: TypeManager, argPack: LocTyArgSynArgPack, needDiagMsg!: Bool = false) {
        tyMgr = typeManager
        this.argPack = argPack
        this.needDiagMsg = needDiagMsg
    }

    public func SynthesizeTypeArguments(allowPartial!: Bool = false): Option<TypeSubst> {
        if (argPack.argTys.size != argPack.paramTys.size) {
            errInfo.style = SolvingErrStyle.ARG_MISMATCH
            return None
        }
        CopyUpperbound()
        constraints = InitConstraints(argPack.tyVarsToSolve)
        let orderedIndexes = getOrderedCheckingIndexes(argPack.argTys)
        for (idx in orderedIndexes) {
            if (!Ty.IsTyCorrect(argPack.argTys[idx]) || !Ty.IsTyCorrect(argPack.paramTys[idx])) {
                errInfo.style = SolvingErrStyle.ARG_MISMATCH
                return None
            }
            if (!UnifyOne(argPack.argTys[idx], argPack.paramTys[idx])) {
                errInfo.style = SolvingErrStyle.ARG_MISMATCH
                return None
            }
        }
        if (let Some(funcRetTy) <- argPack.funcRetTy) {
            if (let Some(retTyUB) <- argPack.retTyUB) {
                if (funcRetTy.HasGeneric() && !UnifyOne(funcRetTy, retTyUB)) {
                    errInfo.style = SolvingErrStyle.RET_MISMATCH
                    return None
                }
            }
        }
        return SolveCurrentConstraints(allowPartial: allowPartial)
    }

    public func HasUnsolvedTyVars(subst: TypeSubst): Bool {
        return CountUnsolvedTyVars(subst) > 0
    }

    public func CountUnsolvedTyVars(subst: TypeSubst): Int64 {
        var count: Int64 = 0
        for (tyVar in argPack.tyVarsToSolve) {
            if (let None <- subst.Get(tyVar)) {
                count++
            } else if (substContainsTyVar(subst, tyVar)) {
                count++
            }
        }
        return count
    }

    public func GetErrInfo(): SolvingErrInfo {
        return errInfo
    }

    public static func Unify(typeManager: TypeManager, cst: Constraint, argTy: Ty, paramTy: Ty): Bool {
        let pack = LocTyArgSynArgPack()
        for (entry in cst.entries) {
            pack.tyVarsToSolve.add(entry.tyVar)
        }
        let synthesis = LocalTypeArgumentSynthesis(typeManager, pack)
        synthesis.constraints = cloneConstraint(cst)
        let ok = synthesis.UnifyOne(argTy, paramTy)
        if (ok) {
            cst.Clear()
            for (entry in synthesis.constraints.entries) {
                let bounds = cst.GetOrCreate(entry.tyVar)
                bounds.lbs.AddAll(entry.bounds.lbs)
                bounds.ubs.AddAll(entry.bounds.ubs)
                bounds.sum.AddAll(entry.bounds.sum)
                bounds.eq.AddAll(entry.bounds.eq)
            }
        }
        return ok
    }

    public static func SolveConstraints(typeManager: TypeManager, cst: Constraint): Option<TypeSubst> {
        let pack = LocTyArgSynArgPack()
        for (entry in cst.entries) {
            pack.tyVarsToSolve.add(entry.tyVar)
        }
        let synthesis = LocalTypeArgumentSynthesis(typeManager, pack)
        synthesis.constraints = cloneConstraint(cst)
        synthesis.deterministic = true
        return synthesis.SolveCurrentConstraints(allowPartial: true)
    }

    public func InitConstraints(tyVarsToSolve: ArrayList<GenericsTy>): Constraint {
        let out = Constraint()
        for (tyVar in tyVarsToSolve) {
            let bounds = out.GetOrCreate(tyVar)
            for (upper in tyVar.upperBounds) {
                bounds.ubs.Add(upper)
            }
            if (let Some(lower) <- tyVar.lowerBound) {
                bounds.lbs.Add(lower)
            }
        }
        return out
    }

    private func CopyUpperbound(): Unit {
        let instMapping = tyMgr.GetInstMapping()
        for (entry in instMapping.u2i.entries) {
            if (let Some(instTyVar) <- (entry.ty as GenericsTy)) {
                if (!containsTyVar(argPack.tyVarsToSolve, instTyVar)) {
                    continue
                }
                for (upper in entry.tyVar.upperBounds) {
                    let instUpper = tyMgr.InstOf(upper)
                    if (!containsTy(instTyVar.upperBounds, instUpper)) {
                        instTyVar.upperBounds.add(instUpper)
                    }
                }
            }
        }
    }

    public func UnifyOne(argTy: Ty, paramTy: Ty): Bool {
        if (SameTy(argTy, paramTy) || argTy.IsQuest() || paramTy.IsQuest()) {
            return true
        }
        if (let Some(paramIntersection) <- (paramTy as IntersectionTy)) {
            return UnifyParamIntersectionTy(argTy, paramIntersection)
        }
        if (let Some(argIntersection) <- (argTy as IntersectionTy)) {
            return UnifyArgIntersectionTy(argIntersection, paramTy)
        }
        if (let Some(argUnion) <- (argTy as UnionTy)) {
            return UnifyArgUnionTy(argUnion, paramTy)
        }
        if (let Some(paramUnion) <- (paramTy as UnionTy)) {
            return UnifyParamUnionTy(argTy, paramUnion)
        }
        if (let Some(paramVar) <- (paramTy as GenericsTy)) {
            if (paramVar.isPlaceholder && containsTyVar(argPack.tyVarsToSolve, paramVar)) {
                let lowerBound = normalizeInferredTy(argTy)
                return AddLowerBound(paramVar, lowerBound)
            }
        }
        if (let Some(argVar) <- (argTy as GenericsTy)) {
            if (argVar.isPlaceholder && containsTyVar(argPack.tyVarsToSolve, argVar)) {
                let upperBound = normalizeInferredTy(paramTy)
                return AddUpperBound(argVar, upperBound)
            }
            if (!argVar.isPlaceholder) {
                if (argVar.upperBounds.isEmpty()) {
                    return UnifyOne(tyMgr.GetAnyTy(), paramTy)
                }
                for (upper in argVar.upperBounds) {
                    if (UnifyOne(upper, paramTy)) {
                        return true
                    }
                }
                return false
            }
        }
        if (paramTy.IsCoreOptionType() && paramTy.typeArgs.size == 1 &&
            CountOptionNestedLevel(paramTy) > CountOptionNestedLevel(argTy)) {
            if (argTy.IsCoreOptionType() && argTy.typeArgs.size == 1) {
                return UnifyOne(argTy.typeArgs[0], paramTy.typeArgs[0])
            }
            return UnifyOne(argTy, paramTy.typeArgs[0])
        }
        if (let Some(argFunc) <- (argTy as FuncTy)) {
            if (let Some(paramFunc) <- (paramTy as FuncTy)) {
                return UnifyFuncTy(argFunc, paramFunc)
            }
        }
        if (let Some(argTuple) <- (argTy as TupleTy)) {
            if (let Some(paramTuple) <- (paramTy as TupleTy)) {
                return typeArgsCanUnify(this, argTuple, paramTuple)
            }
        }
        if ((argTy.IsArray() && paramTy.IsArray()) || (argTy.IsPointer() && paramTy.IsPointer())) {
            return UnifyBuiltInTy(argTy, paramTy)
        }
        if (argTy.IsNominal() && paramTy.IsNominal()) {
            return UnifyNominal(argTy, paramTy)
        }
        if (argTy.IsBuiltin() && paramTy.IsInterface()) {
            return UnifyNominal(argTy, paramTy)
        }
        if (argTy.IsPrimitive() && paramTy.IsPrimitive()) {
            if (!tyMgr.IsSubtype(argTy, paramTy)) {
                return false
            }
            if (argTy.IsIdeal() && !paramTy.IsIdeal()) {
                UpdateIdealTysInCurrentConstraint(paramTy)
            } else if (paramTy.IsIdeal() && !argTy.IsIdeal()) {
                UpdateIdealTysInCurrentConstraint(argTy)
            }
            return true
        }
        return tyMgr.IsSubtype(argTy, paramTy)
    }

    private func AddLowerBound(tyVar: GenericsTy, lowerBound: Ty): Bool {
        curTyVar = Some(tyVar)
        NoteSpecialBound(lowerBound)
        let bounds = constraints.GetOrCreate(tyVar)
        let addedLower = bounds.lbs.Add(lowerBound)
        var addedGreedyUpper = false
        if (deterministic && IsGreedySolution(tyVar, lowerBound, false)) {
            if (bounds.eq.IsEmpty()) {
                bounds.eq.Add(lowerBound)
            }
            addedGreedyUpper = bounds.ubs.Add(lowerBound)
        }
        if (addedLower) {
            let upperBounds = bounds.ubs.Clone()
            for (upperBound in upperBounds.values) {
                if (Ty.IsTyCorrect(upperBound) && !UnifyBoundPair(lowerBound, upperBound)) {
                    return false
                }
            }
            if (deterministic && !CheckKnownSumLowerBound(tyVar, bounds, lowerBound)) {
                return false
            }
        }
        if (addedGreedyUpper) {
            let lowerBounds = bounds.lbs.Clone()
            for (existingLower in lowerBounds.values) {
                if (Ty.IsTyCorrect(existingLower) && !UnifyBoundPair(existingLower, lowerBound)) {
                    return false
                }
            }
        }
        if (!CheckKnownSumEqBound(tyVar, bounds)) {
            return false
        }
        return true
    }

    private func AddUpperBound(tyVar: GenericsTy, upperBound: Ty): Bool {
        curTyVar = Some(tyVar)
        NoteSpecialBound(upperBound)
        let bounds = constraints.GetOrCreate(tyVar)
        let addedUpper = bounds.ubs.Add(upperBound)
        var addedGreedyLower = false
        if (deterministic && IsGreedySolution(tyVar, upperBound, true)) {
            if (bounds.eq.IsEmpty()) {
                bounds.eq.Add(upperBound)
            }
            addedGreedyLower = bounds.lbs.Add(upperBound)
        }
        if (addedUpper) {
            let lowerBounds = bounds.lbs.Clone()
            for (lowerBound in lowerBounds.values) {
                if (Ty.IsTyCorrect(lowerBound) && !UnifyBoundPair(lowerBound, upperBound)) {
                    return false
                }
            }
        }
        if (addedGreedyLower) {
            let upperBounds = bounds.ubs.Clone()
            for (existingUpper in upperBounds.values) {
                if (Ty.IsTyCorrect(existingUpper) && !UnifyBoundPair(upperBound, existingUpper)) {
                    return false
                }
            }
            if (deterministic && !CheckKnownSumLowerBound(tyVar, bounds, upperBound)) {
                return false
            }
        }
        if (!CheckKnownSumEqBound(tyVar, bounds)) {
            return false
        }
        return true
    }

    private func CheckKnownSumLowerBound(tyVar: GenericsTy, bounds: TyVarBounds, lowerBound: Ty): Bool {
        if (!deterministic || tyMgr.TyVarHasNoSum(tyVar)) {
            return true
        }
        if (lowerBound.IsNothing()) {
            return true
        }
        return bounds.sum.Contains(lowerBound)
    }

    private func CheckKnownSumEqBound(tyVar: GenericsTy, bounds: TyVarBounds): Bool {
        if (!deterministic || tyMgr.TyVarHasNoSum(tyVar) || bounds.eq.IsEmpty()) {
            return true
        }
        let eqTy = bounds.eq.values[0]
        if (eqTy.IsNothing()) {
            return true
        }
        return bounds.sum.Contains(eqTy)
    }

    private func IsGreedySolution(tyVar: GenericsTy, bound: Ty, isUpperbound: Bool): Bool {
        let tyParam = bound.IsGeneric() && !bound.IsPlaceholder()
        var outerTyVar = false
        if (let Some(boundVar) <- (bound as GenericsTy)) {
            outerTyVar = boundVar.isPlaceholder &&
                tyMgr.ScopeDepthOfTyVar(boundVar) <= tyMgr.ScopeDepthOfTyVar(tyVar)
        }
        var finalClass = false
        if (isUpperbound) {
            if (let Some(classTy) <- (bound as ClassTy)) {
                if (let Some(classDecl) <- classTy.declPtr) {
                    finalClass = !IsInheritableClass(classDecl)
                }
            }
        }
        let finalType = finalClass ||
            (!bound.IsGeneric() && !bound.IsClassLike() && !bound.IsAny() && !bound.IsNothing())
        let anyOrNothing = (bound.IsAny() && !isUpperbound) || (bound.IsNothing() && isUpperbound)
        return tyParam || outerTyVar || finalType || anyOrNothing
    }

    private func HasActiveBoundCheck(argTy: Ty, paramTy: Ty): Bool {
        for (entry in activeBoundChecks) {
            if (SameTy(entry[0], argTy) && SameTy(entry[1], paramTy)) {
                return true
            }
        }
        return false
    }

    private func UnifyBoundPair(argTy: Ty, paramTy: Ty): Bool {
        if (HasActiveBoundCheck(argTy, paramTy)) {
            return true
        }
        activeBoundChecks.add((argTy, paramTy))
        let ok = UnifyOne(argTy, paramTy)
        activeBoundChecks.remove(at: activeBoundChecks.size - 1)
        return ok
    }

    private func NoteSpecialBound(ty: Ty): Unit {
        if (ty.IsNothing()) {
            hasNothingTy = true
        } else if (ty.IsAny()) {
            hasAnyTy = true
        }
    }

    private func UpdateIdealTysInCurrentConstraint(targetTy: Ty): Unit {
        if (let Some(tyVar) <- curTyVar) {
            let bounds = constraints.GetOrCreate(tyVar)
            ReplaceIdealTyInSet(bounds.lbs, targetTy)
            ReplaceIdealTyInSet(bounds.ubs, targetTy)
        }
    }

    private func ReplaceIdealTyInSet(tys: TySet, targetTy: Ty): Unit {
        var idx: Int64 = 0
        while (idx < tys.values.size) {
            if ((tys.values[idx].kind == TypeKind.TYPE_IDEAL_INT && targetTy.IsInteger()) ||
                (tys.values[idx].kind == TypeKind.TYPE_IDEAL_FLOAT && targetTy.IsFloating())) {
                tys.values[idx] = targetTy
            }
            idx++
        }
    }

    private func UnifyParamIntersectionTy(argTy: Ty, paramTy: IntersectionTy): Bool {
        for (candidate in paramTy.tys) {
            if (!UnifyOne(argTy, candidate)) {
                return false
            }
        }
        return true
    }

    private func UnifyArgIntersectionTy(argTy: IntersectionTy, paramTy: Ty): Bool {
        if (argTy.tys.isEmpty()) {
            return UnifyOne(tyMgr.GetAnyTy(), paramTy)
        }
        if (argTy.tys.size == 1) {
            return UnifyOne(argTy.tys[0], paramTy)
        }
        let saved = cloneConstraint(constraints)
        for (candidate in argTy.tys) {
            constraints = cloneConstraint(saved)
            if (UnifyOne(candidate, paramTy)) {
                return true
            }
        }
        constraints = saved
        return false
    }

    private func UnifyParamUnionTy(argTy: Ty, paramTy: UnionTy): Bool {
        if (paramTy.tys.isEmpty()) {
            return argTy.IsNothing()
        }
        if (paramTy.tys.size == 1) {
            return UnifyOne(argTy, paramTy.tys[0])
        }
        let saved = cloneConstraint(constraints)
        for (candidate in paramTy.tys) {
            constraints = cloneConstraint(saved)
            if (UnifyOne(argTy, candidate)) {
                return true
            }
        }
        constraints = saved
        return false
    }

    private func UnifyArgUnionTy(argTy: UnionTy, paramTy: Ty): Bool {
        for (candidate in argTy.tys) {
            if (!UnifyOne(candidate, paramTy)) {
                return false
            }
        }
        return true
    }

    private func UnifyFuncTy(argTy: FuncTy, paramTy: FuncTy): Bool {
        if (argTy.paramTys.size != paramTy.paramTys.size) {
            return false
        }
        for (idx in 0..argTy.paramTys.size) {
            if (!UnifyOne(paramTy.paramTys[idx], argTy.paramTys[idx])) {
                return false
            }
        }
        return UnifyOne(argTy.retTy, paramTy.retTy)
    }

    private func UnifyBuiltInTy(argTy: Ty, paramTy: Ty): Bool {
        if (argTy.typeArgs.size != 1 || paramTy.typeArgs.size != 1) {
            return false
        }
        return UnifyOne(argTy.typeArgs[0], paramTy.typeArgs[0]) &&
            UnifyOne(paramTy.typeArgs[0], argTy.typeArgs[0])
    }

    private func UnifyNominal(argTy: Ty, paramTy: Ty): Bool {
        let promoted = Promotion(tyMgr).Promote(argTy, paramTy)
        if (promoted.IsEmpty()) {
            return false
        }
        let saved = cloneConstraint(constraints)
        for (candidate in promoted.values) {
            if (candidate.typeArgs.size != paramTy.typeArgs.size) {
                continue
            }
            constraints = cloneConstraint(saved)
            var localOk = true
            for (idx in 0..candidate.typeArgs.size) {
                if (!UnifyOne(candidate.typeArgs[idx], paramTy.typeArgs[idx]) ||
                    !UnifyOne(paramTy.typeArgs[idx], candidate.typeArgs[idx])) {
                    localOk = false
                    break
                }
            }
            if (localOk) {
                return true
            }
        }
        constraints = saved
        return false
    }

    private func SolveCurrentConstraints(allowPartial!: Bool = false): Option<TypeSubst> {
        let subst = TypeSubst()
        let graph = TyVarConstraintGraph(constraints, argPack.tyVarsToSolve, tyMgr)
        while (true) {
            let nextConstraints = graph.TopoOnce(constraints)
            if (nextConstraints.entries.isEmpty()) {
                break
            }
            let substitutedConstraints = ApplyTypeSubstForConstraint(subst, nextConstraints)
            let solved = SolveConstraintGroup(substitutedConstraints)
            if (!solved.entries.isEmpty()) {
                MergeTypeSubst(subst, solved)
                graph.ApplyTypeSubst(solved)
            }
        }
        if (allowPartial || !HasUnsolvedTyVars(subst)) {
            return subst
        }
        if (let Some(unsolved) <- FirstUnsolvedTyVar(subst)) {
            errInfo.style = SolvingErrStyle.NO_CONSTRAINT
            errInfo.tyVar = unsolved
        }
        return None
    }

    private func SolveConstraintGroup(group: Constraint): TypeSubst {
        let subst = TypeSubst()
        var remaining = cloneConstraint(group)
        var newInfo = true
        while (newInfo) {
            newInfo = false
            var idx: Int64 = 0
            while (idx < remaining.entries.size) {
                let entry = remaining.entries[idx]
                if (let Some(solution) <- FindSolution(entry.tyVar, entry.bounds)) {
                    subst.Put(entry.tyVar, solution)
                    remaining.entries.remove(at: idx)
                    newInfo = true
                    continue
                }
                idx++
            }
            if (newInfo) {
                remaining = ApplyTypeSubstForConstraint(subst, remaining)
            }
        }
        return subst
    }

    private func FindSolution(tyVar: GenericsTy, bounds: TyVarBounds): Option<Ty> {
        for (eqTy in bounds.eq.values) {
            let normalizedEq = NormalizeSolution(eqTy)
            if (IsValidSolution(normalizedEq, bounds)) {
                return normalizedEq
            }
        }
        if (let Some(joinedLb) <- JoinLowerBounds(bounds.lbs)) {
            let normalizedJoined = NormalizeSolution(joinedLb)
            if (IsValidSolution(normalizedJoined, bounds)) {
                return normalizedJoined
            }
        }
        if (let Some(metUb) <- MeetUpperBounds(tyVar, bounds.ubs)) {
            let normalizedMet = NormalizeSolution(metUb)
            if (IsValidSolution(normalizedMet, bounds)) {
                return normalizedMet
            }
        }
        for (lb in bounds.lbs.values) {
            let normalizedLb = NormalizeSolution(lb)
            if (IsValidSolution(normalizedLb, bounds)) {
                return normalizedLb
            }
        }
        for (ub in bounds.ubs.values) {
            let normalizedUb = NormalizeSolution(ub)
            if (IsValidSolution(normalizedUb, bounds)) {
                return normalizedUb
            }
        }
        return None
    }

    private func MergeTypeSubst(target: TypeSubst, source: TypeSubst): Unit {
        for (entry in source.entries) {
            target.Put(entry.tyVar, entry.ty)
        }
    }

    private func FirstUnsolvedTyVar(subst: TypeSubst): Option<GenericsTy> {
        for (tyVar in argPack.tyVarsToSolve) {
            if (let None <- subst.Get(tyVar)) {
                return tyVar
            }
            if (substContainsTyVar(subst, tyVar)) {
                return tyVar
            }
        }
        return None
    }

    private func ApplyTypeSubstForConstraint(typeMapping: TypeSubst, input: Constraint): Constraint {
        if (typeMapping.IsEmpty()) {
            return cloneConstraint(input)
        }
        let out = Constraint()
        for (entry in input.entries) {
            let bounds = TyVarBounds()
            for (lower in entry.bounds.lbs.values) {
                bounds.lbs.Add(tyMgr.GetInstantiatedTy(lower, typeMapping))
            }
            for (upper in entry.bounds.ubs.values) {
                bounds.ubs.Add(tyMgr.GetInstantiatedTy(upper, typeMapping))
            }
            for (sumTy in entry.bounds.sum.values) {
                bounds.sum.Add(tyMgr.GetInstantiatedTy(sumTy, typeMapping))
            }
            for (eqTy in entry.bounds.eq.values) {
                bounds.eq.Add(tyMgr.GetInstantiatedTy(eqTy, typeMapping))
            }
            out.entries.add(ConstraintEntry(entry.tyVar, bounds: bounds))
        }
        return out
    }

    private func JoinLowerBounds(lbs: TySet): Option<Ty> {
        if (lbs.values.isEmpty()) {
            return None
        }
        return JoinAsVisibleTy(tyMgr, lbs, ignoredTyVars: ToTySet(argPack.tyVarsToSolve))
    }

    private func MeetUpperBounds(tyVar: GenericsTy, ubs: TySet): Option<Ty> {
        if (ubs.values.isEmpty()) {
            return None
        }
        let tysWithoutTyVar = TySet()
        let tysWithTyVar = TySet()
        for (upper in ubs.values) {
            if (upper.Contains(tyVar)) {
                tysWithTyVar.Add(upper)
            } else {
                tysWithoutTyVar.Add(upper)
            }
        }
        var resultOpt = MeetTypes(tysWithoutTyVar)
        if (tysWithTyVar.IsEmpty()) {
            return resultOpt
        }
        if (let Some(result) <- resultOpt) {
            let subst = TypeSubst()
            subst.Put(tyVar, result)
            let instantiated = TySet()
            instantiated.Add(result)
            for (upperWithTyVar in tysWithTyVar.values) {
                instantiated.Add(tyMgr.GetInstantiatedTy(upperWithTyVar, subst))
            }
            resultOpt = MeetTypes(instantiated)
        }
        return resultOpt
    }

    private func MeetTypes(values: TySet): Option<Ty> {
        if (values.values.isEmpty()) {
            return None
        }
        return MeetAsVisibleTy(tyMgr, values, ignoredTyVars: ToTySet(argPack.tyVarsToSolve))
    }

    private func NormalizeSolution(ty: Ty): Ty {
        let inferred = normalizeInferredTy(ty)
        if (inferred.HasIdealTy()) {
            return ReplaceIdealTyInSolution(inferred)
        }
        return inferred
    }

    private func ReplaceIdealTyInSolution(ty: Ty): Ty {
        if (!ty.HasIdealTy()) {
            return ty
        }
        if (ty.IsIdeal()) {
            return tyMgr.ReplaceIdealTy(ty)
        }
        if (let Some(arrayTy) <- (ty as ArrayTy)) {
            if (arrayTy.typeArgs.size == 1) {
                return tyMgr.GetArrayTy(ReplaceIdealTyInSolution(arrayTy.typeArgs[0]), arrayTy.dims)
            }
        }
        if (let Some(varrayTy) <- (ty as VArrayTy)) {
            if (varrayTy.typeArgs.size == 1) {
                return tyMgr.GetVArrayTy(ReplaceIdealTyInSolution(varrayTy.typeArgs[0]), varrayTy.size)
            }
        }
        if (let Some(pointerTy) <- (ty as PointerTy)) {
            if (pointerTy.typeArgs.size == 1) {
                return tyMgr.GetPointerTy(ReplaceIdealTyInSolution(pointerTy.typeArgs[0]))
            }
        }
        if (let Some(tupleTy) <- (ty as TupleTy)) {
            return tyMgr.GetTupleTy(replaceIdealArgs(tupleTy.typeArgs), isClosureTy: tupleTy.isClosureTy)
        }
        if (let Some(funcTy) <- (ty as FuncTy)) {
            let cfg = FuncTyConfig()
            cfg.isC = funcTy.isC
            cfg.isClosureTy = funcTy.isClosureTy
            cfg.hasVariableLenArg = funcTy.hasVariableLenArg
            cfg.noCast = funcTy.noCast
            return tyMgr.GetFunctionTy(replaceIdealArgs(funcTy.paramTys),
                ReplaceIdealTyInSolution(funcTy.retTy), cfg: cfg)
        }
        if (let Some(classThisTy) <- (ty as ClassThisTy)) {
            if (let Some(decl) <- classThisTy.declPtr) {
                return tyMgr.GetClassThisTy(decl, replaceIdealArgs(classThisTy.typeArgs))
            }
        }
        if (let Some(classTy) <- (ty as ClassTy)) {
            if (let Some(decl) <- classTy.declPtr) {
                return tyMgr.GetClassTy(decl, replaceIdealArgs(classTy.typeArgs))
            }
        }
        if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
            if (let Some(decl) <- interfaceTy.declPtr) {
                return tyMgr.GetInterfaceTy(decl, replaceIdealArgs(interfaceTy.typeArgs))
            }
        }
        if (let Some(structTy) <- (ty as StructTy)) {
            if (let Some(decl) <- structTy.declPtr) {
                return tyMgr.GetStructTy(decl, replaceIdealArgs(structTy.typeArgs))
            }
        }
        if (let Some(refEnumTy) <- (ty as RefEnumTy)) {
            if (let Some(decl) <- refEnumTy.declPtr) {
                return tyMgr.GetRefEnumTy(decl, replaceIdealArgs(refEnumTy.typeArgs))
            }
        }
        if (let Some(enumTy) <- (ty as EnumTy)) {
            if (let Some(decl) <- enumTy.declPtr) {
                return tyMgr.GetEnumTy(decl, typeArgs: replaceIdealArgs(enumTy.typeArgs))
            }
        }
        if (let Some(aliasTy) <- (ty as TypeAliasTy)) {
            if (let Some(decl) <- aliasTy.declPtr) {
                return tyMgr.GetTypeAliasTy(decl, replaceIdealArgs(aliasTy.typeArgs))
            }
        }
        if (let Some(unionTy) <- (ty as UnionTy)) {
            return tyMgr.GetUnionTy(replaceIdealArgs(unionTy.tys))
        }
        if (let Some(intersectionTy) <- (ty as IntersectionTy)) {
            return tyMgr.GetIntersectionTy(replaceIdealArgs(intersectionTy.tys))
        }
        return ty
    }

    private func replaceIdealArgs(values: ArrayList<Ty>): Array<Ty> {
        let out = ArrayList<Ty>()
        for (value in values) {
            out.add(ReplaceIdealTyInSolution(value))
        }
        return out.toArray()
    }

    private func IsValidSolution(candidate: Ty, bounds: TyVarBounds): Bool {
        if (candidate.HasInvalidTy() || candidate.HasIdealTy() || candidate.IsCType()) {
            return false
        }
        if (candidate.IsNothing() && !hasNothingTy) {
            return false
        }
        if (candidate.IsAny() && !hasAnyTy) {
            return false
        }
        for (lb in bounds.lbs.values) {
            if (!tyMgr.IsSubtype(lb, candidate)) {
                return false
            }
        }
        for (ub in bounds.ubs.values) {
            if (!tyMgr.IsSubtype(candidate, ub)) {
                return false
            }
        }
        return true
    }

    private func normalizeInferredTy(ty: Ty): Ty {
        if (let Some(thisTy) <- (ty as ClassThisTy)) {
            if (let Some(decl) <- thisTy.declPtr) {
                return tyMgr.GetClassTy(decl, CopyTypeArgs(thisTy.typeArgs))
            }
        }
        return ty
    }
}

private func cloneTyBlameEntries(entries: ArrayList<TyBlameEntry>): ArrayList<TyBlameEntry> {
    let out = ArrayList<TyBlameEntry>()
    for (entry in entries) {
        out.add(TyBlameEntry(entry.ty, blames: entry.blames.Clone()))
    }
    return out
}

private func cloneTyVarBounds(bounds: TyVarBounds): TyVarBounds {
    let out = TyVarBounds()
    out.lbs = bounds.lbs.Clone()
    out.ubs = bounds.ubs.Clone()
    out.sum = bounds.sum.Clone()
    out.eq = bounds.eq.Clone()
    for (entry in cloneTyBlameEntries(bounds.lb2Blames)) {
        out.lb2Blames.add(entry)
    }
    for (entry in cloneTyBlameEntries(bounds.ub2Blames)) {
        out.ub2Blames.add(entry)
    }
    return out
}

private func cloneConstraint(cst: Constraint): Constraint {
    let out = Constraint()
    for (entry in cst.entries) {
        out.entries.add(ConstraintEntry(entry.tyVar, bounds: cloneTyVarBounds(entry.bounds)))
    }
    return out
}
