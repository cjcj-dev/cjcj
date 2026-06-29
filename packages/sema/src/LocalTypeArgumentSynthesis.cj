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

private class MemoForUnifiedTys {
    public let values: ArrayList<(Ty, Ty)> = ArrayList<(Ty, Ty)>()

    public init() {}

    public func Contains(argTy: Ty, paramTy: Ty): Bool {
        for (entry in values) {
            if (refEq(entry[0], argTy) && refEq(entry[1], paramTy)) {
                return true
            }
        }
        return false
    }

    public func Add(argTy: Ty, paramTy: Ty): Unit {
        if (!Contains(argTy, paramTy)) {
            values.add((argTy, paramTy))
        }
    }

    public func Clone(): MemoForUnifiedTys {
        let out = MemoForUnifiedTys()
        for (entry in values) {
            out.values.add((entry[0], entry[1]))
        }
        return out
    }
}

private class ConstraintWithMemo {
    public var constraint: Constraint
    public var memo: MemoForUnifiedTys
    public var hasNothingTy: Bool
    public var hasAnyTy: Bool

    public init(constraint!: Constraint = Constraint(), memo!: MemoForUnifiedTys = MemoForUnifiedTys(),
        hasNothingTy!: Bool = false, hasAnyTy!: Bool = false) {
        this.constraint = constraint
        this.memo = memo
        this.hasNothingTy = hasNothingTy
        this.hasAnyTy = hasAnyTy
    }

    public func Clone(): ConstraintWithMemo {
        return ConstraintWithMemo(constraint: cloneConstraint(constraint), memo: memo.Clone(),
            hasNothingTy: hasNothingTy, hasAnyTy: hasAnyTy)
    }
}

private class ConstraintWithMemos {
    public let values: ArrayList<ConstraintWithMemo> = ArrayList<ConstraintWithMemo>()

    public init() {}

    public func Add(value: ConstraintWithMemo): Unit {
        values.add(value)
    }

    public func AddAll(other: ConstraintWithMemos): Unit {
        for (value in other.values) {
            values.add(value.Clone())
        }
    }

    public func IsEmpty(): Bool {
        return values.isEmpty()
    }

    public func Size(): Int64 {
        return values.size
    }

    public func Clone(): ConstraintWithMemos {
        let out = ConstraintWithMemos()
        out.AddAll(this)
        return out
    }
}

private class Tracked {
    public var ty: Ty
    public var blames: BlameSet

    public init(ty: Ty, blames!: BlameSet = BlameSet()) {
        this.ty = ty
        this.blames = blames
    }
}

private class TypeSubsts {
    public let values: ArrayList<TypeSubst> = ArrayList<TypeSubst>()

    public init() {}

    public func Insert(subst: TypeSubst): Unit {
        for (value in values) {
            if (value.entries.size != subst.entries.size) {
                continue
            }
            var allSame = true
            for (entry in value.entries) {
                var found = false
                for (other in subst.entries) {
                    if (refEq(entry.tyVar, other.tyVar) && refEq(entry.ty, other.ty)) {
                        found = true
                        break
                    }
                }
                if (!found) {
                    allSame = false
                    break
                }
            }
            if (allSame) {
                return
            }
        }
        values.add(subst.Clone())
    }

    public func IsEmpty(): Bool {
        return values.isEmpty()
    }
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
    private var cms: ConstraintWithMemos = ConstraintWithMemos()
    private var errMsg: SolvingErrInfo = SolvingErrInfo()
    private var curTyVar: Option<GenericsTy> = None
    private var deterministic: Bool = false

    public init(typeManager: TypeManager, argPack: LocTyArgSynArgPack, needDiagMsg!: Bool = false) {
        tyMgr = typeManager
        this.argPack = LocTyArgSynArgPack()
        for (tyVar in argPack.tyVarsToSolve) {
            this.argPack.tyVarsToSolve.add(tyVar)
        }
        for (argTy in argPack.argTys) {
            this.argPack.argTys.add(argTy)
        }
        for (paramTy in argPack.paramTys) {
            this.argPack.paramTys.add(paramTy)
        }
        for (argBlame in argPack.argBlames) {
            this.argPack.argBlames.add(argBlame)
        }
        this.argPack.funcRetTy = argPack.funcRetTy
        this.argPack.retTyUB = argPack.retTyUB
        this.argPack.retBlame = argPack.retBlame
        this.needDiagMsg = needDiagMsg
        if (!needDiagMsg) {
            this.argPack.argBlames.clear()
            for (_ in this.argPack.argTys) {
                this.argPack.argBlames.add(Blame(src: None, lb: None, ub: None, style: BlameStyle.ARGUMENT))
            }
        }
    }

    public func SynthesizeTypeArguments(allowPartial!: Bool = false): Option<TypeSubst> {
        if (argPack.argTys.size != argPack.argBlames.size || argPack.argTys.size != argPack.paramTys.size) {
            return None
        }
        for (tyVar in argPack.tyVarsToSolve) {
            if (!tyVar.isPlaceholder) {
                return None
            }
        }
        CopyUpperbound()
        cms = ConstraintWithMemos()
        cms.Add(ConstraintWithMemo(constraint: InitConstraints(argPack.tyVarsToSolve)))
        let orderedIndexes = getOrderedCheckingIndexes(argPack.argTys)
        for (idx in orderedIndexes) {
            if (!Ty.IsTyCorrect(argPack.argTys[idx]) || !Ty.IsTyCorrect(argPack.paramTys[idx])) {
                return None
            }
            let argBlames = BlameSet()
            argBlames.Add(argPack.argBlames[idx])
            let paramBlames = BlameSet()
            paramBlames.Add(argPack.argBlames[idx])
            let needArgDiag = needDiagMsg && match (errMsg.style) {
                case SolvingErrStyle.DEFAULT => true
                case _ => false
            }
            if (needArgDiag) {
                let unified = LocalTypeArgumentSynthesis.Unify(this, cms,
                    Tracked(argPack.argTys[idx], blames: argBlames),
                    Tracked(argPack.paramTys[idx], blames: paramBlames))
                cms = unified[0]
                errMsg = unified[1]
            } else {
                cms = LocalTypeArgumentSynthesis.Unify(this, cms,
                    Tracked(argPack.argTys[idx], blames: argBlames),
                    Tracked(argPack.paramTys[idx], blames: paramBlames))[0]
            }
            if (cms.IsEmpty()) {
                MaybeSetErrMsg(MakeMsgMismatchedArg(argPack.argBlames[idx]))
                return None
            }
        }
        if (let Some(funcRetTy) <- argPack.funcRetTy) {
            if (let Some(retTyUB) <- argPack.retTyUB) {
                if (Ty.IsTyCorrect(funcRetTy) && funcRetTy.HasGeneric() && Ty.IsTyCorrect(retTyUB)) {
                    let retBlames = BlameSet()
                    retBlames.Add(argPack.retBlame)
                    let needRetDiag = needDiagMsg && match (errMsg.style) {
                        case SolvingErrStyle.DEFAULT => true
                        case _ => false
                    }
                    if (needRetDiag) {
                        let unified = LocalTypeArgumentSynthesis.Unify(this, cms, Tracked(funcRetTy, blames: retBlames),
                            Tracked(retTyUB, blames: retBlames))
                        cms = unified[0]
                        errMsg = unified[1]
                    } else {
                        cms = LocalTypeArgumentSynthesis.Unify(this, cms, Tracked(funcRetTy, blames: retBlames),
                            Tracked(retTyUB, blames: retBlames))[0]
                    }
                }
            }
        }
        if (cms.IsEmpty()) {
            MaybeSetErrMsg(MakeMsgMismatchedRet(argPack.retBlame))
            return None
        }
        if (!allowPartial && !needDiagMsg) {
            var cmsIdx: Int64 = 0
            while (cmsIdx < cms.values.size) {
                if (!DoesCSCoverAllTyVars(cms.values[cmsIdx].constraint)) {
                    cms.values.remove(at: cmsIdx)
                    continue
                }
                cmsIdx++
            }
        }
        if (let Some(subst) <- SolveCurrentConstraints(allowPartial: allowPartial)) {
            return ResetIdealTypesInSubst(subst)
        }
        return None
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
        if (let Some(tyVar) <- errMsg.tyVar) {
            if (let Some(recovered) <- (tyMgr.RecoverUnivTyVar(tyVar) as GenericsTy)) {
                errMsg.tyVar = Some(recovered)
            }
        }
        var lbIdx: Int64 = 0
        while (lbIdx < errMsg.lbs.size) {
            errMsg.lbs[lbIdx] = tyMgr.RecoverUnivTyVar(errMsg.lbs[lbIdx])
            lbIdx++
        }
        var ubIdx: Int64 = 0
        while (ubIdx < errMsg.ubs.size) {
            errMsg.ubs[ubIdx] = tyMgr.RecoverUnivTyVar(errMsg.ubs[ubIdx])
            ubIdx++
        }
        return errMsg
    }

    public static func Unify(typeManager: TypeManager, cst: Constraint, argTy: Ty, paramTy: Ty): Bool {
        let pack = LocTyArgSynArgPack()
        for (entry in cst.entries) {
            pack.tyVarsToSolve.add(entry.tyVar)
        }
        let synthesis = LocalTypeArgumentSynthesis(typeManager, pack)
        synthesis.cms = ConstraintWithMemos()
        synthesis.cms.Add(ConstraintWithMemo(constraint: cloneConstraint(cst)))
        synthesis.deterministic = true
        let ok = synthesis.UnifyOne(Tracked(argTy), Tracked(paramTy))
        if (ok) {
            cst.Clear()
            if (!synthesis.cms.IsEmpty()) {
                for (entry in synthesis.cms.values[0].constraint.entries) {
                    let bounds = cst.GetOrCreate(entry.tyVar)
                    bounds.lbs.AddAll(entry.bounds.lbs)
                    bounds.ubs.AddAll(entry.bounds.ubs)
                    bounds.sum.AddAll(entry.bounds.sum)
                    bounds.eq.AddAll(entry.bounds.eq)
                }
            }
        }
        return ok
    }

    public static func SolveConstraints(typeManager: TypeManager, cst: Constraint): Option<TypeSubst> {
        let pack = LocTyArgSynArgPack()
        for (tyVar in typeManager.GetUnsolvedTyVars()) {
            pack.tyVarsToSolve.add(tyVar)
        }
        let synthesis = LocalTypeArgumentSynthesis(typeManager, pack)
        synthesis.cms = ConstraintWithMemos()
        synthesis.cms.Add(ConstraintWithMemo(constraint: cloneConstraint(cst)))
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

    private func InsertConstraint(c: Constraint, tyVar: GenericsTy, tvb: TyVarBounds): Unit {
        let old = c.GetOrCreate(tyVar)
        for (lb in tvb.lbs.values) {
            let _ = old.lbs.Add(lb)
            for (blameEntry in tvb.lb2Blames) {
                if (!refEq(blameEntry.ty, lb)) {
                    continue
                }
                var found = false
                for (oldEntry in old.lb2Blames) {
                    if (refEq(oldEntry.ty, lb)) {
                        for (blame in blameEntry.blames.values) {
                            oldEntry.blames.Add(blame)
                        }
                        found = true
                        break
                    }
                }
                if (!found) {
                    old.lb2Blames.add(TyBlameEntry(lb, blames: blameEntry.blames.Clone()))
                }
            }
        }
        for (ub in tvb.ubs.values) {
            let _ = old.ubs.Add(ub)
            for (blameEntry in tvb.ub2Blames) {
                if (!refEq(blameEntry.ty, ub)) {
                    continue
                }
                var found = false
                for (oldEntry in old.ub2Blames) {
                    if (refEq(oldEntry.ty, ub)) {
                        for (blame in blameEntry.blames.values) {
                            oldEntry.blames.Add(blame)
                        }
                        found = true
                        break
                    }
                }
                if (!found) {
                    old.ub2Blames.add(TyBlameEntry(ub, blames: blameEntry.blames.Clone()))
                }
            }
        }
    }

    private static func Unify(syn: LocalTypeArgumentSynthesis, newCMS: ConstraintWithMemos, argTTy: Tracked,
        paramTTy: Tracked):
        (ConstraintWithMemos, SolvingErrInfo) {
        let dummyArgPack = LocTyArgSynArgPack()
        for (tyVar in syn.argPack.tyVarsToSolve) {
            dummyArgPack.tyVarsToSolve.add(tyVar)
        }
        let res = ConstraintWithMemos()
        var msg = SolvingErrInfo()
        for (cm in newCMS.values) {
            let newSynIns = LocalTypeArgumentSynthesis(syn.tyMgr, dummyArgPack, needDiagMsg: syn.needDiagMsg)
            newSynIns.cms = ConstraintWithMemos()
            newSynIns.cms.Add(cm.Clone())
            newSynIns.deterministic = syn.deterministic
            if (newSynIns.UnifyOne(argTTy, paramTTy)) {
                res.AddAll(newSynIns.cms)
            } else {
                match (msg.style) {
                    case SolvingErrStyle.DEFAULT => msg = newSynIns.errMsg
                    case _ => ()
                }
            }
        }
        return (res, msg)
    }

    private func UnifyAndTrim(curCMS: ConstraintWithMemos, argTTy: Tracked, paramTTy: Tracked): Bool {
        let unified = LocalTypeArgumentSynthesis.Unify(this, curCMS, argTTy, paramTTy)
        MaybeSetErrMsg(unified[1])
        return VerifyAndSetCMS(unified[0])
    }

    private func VerifyAndSetCMS(newCMS: ConstraintWithMemos): Bool {
        if (!cms.IsEmpty() && newCMS.IsEmpty()) {
            cms = ConstraintWithMemos()
            return false
        }
        cms = newCMS
        return true
    }

    private func UnifyOne(argTTy: Tracked, paramTTy: Tracked): Bool {
        let argTy = argTTy.ty
        let paramTy = paramTTy.ty
        if (cms.Size() != 1) {
            return false
        }
        if (refEq(argTy, paramTy)) {
            return true
        }
        if (argTy.IsQuest() || paramTy.IsQuest()) {
            return true
        }
        if ((paramTy as IntersectionTy).isSome()) {
            return UnifyParamIntersectionTy(argTTy, paramTTy)
        } else if ((argTy as IntersectionTy).isSome()) {
            return UnifyArgIntersectionTy(argTTy, paramTTy)
        } else if ((argTy as UnionTy).isSome()) {
            return UnifyArgUnionTy(argTTy, paramTTy)
        } else if ((paramTy as UnionTy).isSome()) {
            return UnifyParamUnionTy(argTTy, paramTTy)
        }

        let memo = cms.values[0].memo
        if (memo.Contains(argTy, paramTy)) {
            return true
        }
        var hasPlaceholder = false
        if (let Some(paramVar) <- (paramTy as GenericsTy)) {
            if (paramVar.isPlaceholder) {
                hasPlaceholder = true
            }
        }
        if (let Some(argVar) <- (argTy as GenericsTy)) {
            if (argVar.isPlaceholder) {
                hasPlaceholder = true
            }
        }
        if (hasPlaceholder) {
            memo.Add(argTy, paramTy)
            return UnifyTyVar(argTTy, paramTTy)
        }
        if (CountOptionNestedLevel(paramTy) > CountOptionNestedLevel(argTy)) {
            if (paramTy.typeArgs.size != 1) {
                return false
            }
            if (argTy.IsCoreOptionType() && paramTy.IsCoreOptionType()) {
                memo.Add(argTy, paramTy)
                if (argTy.typeArgs.size != 1) {
                    return false
                }
                return UnifyOne(Tracked(argTy.typeArgs[0], blames: argTTy.blames),
                    Tracked(paramTy.typeArgs[0], blames: paramTTy.blames))
            }
            memo.Add(argTy, paramTy)
            return UnifyOne(argTTy, Tracked(paramTy.typeArgs[0], blames: paramTTy.blames))
        }
        if (argTy.IsGeneric() || paramTy.IsGeneric()) {
            return UnifyContextTyVar(argTTy, paramTTy)
        } else if (paramTy.IsNominal() && argTy.IsNominal()) {
            return UnifyNominal(argTTy, paramTTy)
        } else if (argTy.IsBuiltin() && paramTy.IsInterface()) {
            return UnifyBuiltInExtension(argTTy, paramTTy)
        } else if (paramTy.IsPrimitive() && argTy.IsPrimitive()) {
            if (let Some(argPrimitive) <- (argTy as PrimitiveTy)) {
                if (let Some(paramPrimitive) <- (paramTy as PrimitiveTy)) {
                    return UnifyPrimitiveTy(argPrimitive, paramPrimitive)
                }
            }
            return false
        } else if ((argTy.IsArray() && paramTy.IsArray()) || (argTy.IsPointer() && paramTy.IsPointer())) {
            return UnifyBuiltInTy(argTTy, paramTTy)
        } else if (argTy.IsFunc() && paramTy.IsFunc()) {
            return UnifyFuncTy(argTTy, paramTTy)
        } else if (argTy.IsTuple() && paramTy.IsTuple()) {
            return UnifyTupleTy(argTTy, paramTTy)
        }
        return tyMgr.IsSubtype(argTy, paramTy)
    }

    private func UnifyTyVar(argTTy: Tracked, paramTTy: Tracked): Bool {
        if (cms.Size() != 1) {
            return false
        }
        let argTy = argTTy.ty
        let paramTy = paramTTy.ty
        if (let Some(paramVar) <- (paramTy as GenericsTy)) {
            if (paramVar.isPlaceholder) {
                var lb = normalizeInferredTy(argTy)
                var ub: Ty = TypeManager.GetInvalidTy()
                if (lb.IsNothing()) {
                    cms.values[0].hasNothingTy = true
                } else if (lb.IsAny()) {
                    cms.values[0].hasAnyTy = true
                }
                if (deterministic && IsGreedySolution(paramVar, lb, false)) {
                    ub = lb
                    let eq = cms.values[0].constraint.GetOrCreate(paramVar).eq
                    if (eq.IsEmpty()) {
                        eq.Add(lb)
                    }
                }
                curTyVar = Some(paramVar)
                return UnifyTyVarCollectConstraints(paramVar, Tracked(lb, blames: argTTy.blames), Tracked(ub))
            }
        }
        if (let Some(argVar) <- (argTy as GenericsTy)) {
            if (argVar.isPlaceholder) {
                var ub = normalizeInferredTy(paramTy)
                var lb: Ty = TypeManager.GetInvalidTy()
                if (ub.IsNothing()) {
                    cms.values[0].hasNothingTy = true
                } else if (ub.IsAny()) {
                    cms.values[0].hasAnyTy = true
                }
                if (deterministic && IsGreedySolution(argVar, ub, true)) {
                    lb = ub
                    let eq = cms.values[0].constraint.GetOrCreate(argVar).eq
                    if (eq.IsEmpty()) {
                        eq.Add(ub)
                    }
                }
                curTyVar = Some(argVar)
                return UnifyTyVarCollectConstraints(argVar, Tracked(lb), Tracked(ub, blames: paramTTy.blames))
            }
        }
        return false
    }

    private func UnifyTyVarCollectConstraints(tyVar: GenericsTy, lbTTy: Tracked, ubTTy: Tracked): Bool {
        if (cms.Size() != 1) {
            return false
        }
        let lb = lbTTy.ty
        let ub = ubTTy.ty
        let c = cms.values[0].constraint
        if (Ty.IsTyCorrect(lb)) {
            let bounds = TyVarBounds()
            bounds.lbs.Add(lb)
            bounds.lb2Blames.add(TyBlameEntry(lb, blames: lbTTy.blames.Clone()))
            InsertConstraint(c, tyVar, bounds)
        }
        if (Ty.IsTyCorrect(ub)) {
            let bounds = TyVarBounds()
            bounds.ubs.Add(ub)
            bounds.ub2Blames.add(TyBlameEntry(ub, blames: ubTTy.blames.Clone()))
            InsertConstraint(c, tyVar, bounds)
        }

        if (Ty.IsTyCorrect(lb)) {
            let tyVarBounds = c.GetOrCreate(tyVar)
            let ubs = tyVarBounds.ubs.Clone()
            let ub2Blames = cloneTyBlameEntries(tyVarBounds.ub2Blames)
            var lbTy = lb
            if (!deterministic) {
                let joinedLb = JoinAsVisibleTy(tyMgr, tyVarBounds.lbs, ignoredTyVars: ToTySet(argPack.tyVarsToSolve))
                if (!joinedLb.IsAny()) {
                    lbTy = joinedLb
                }
            }
            for (ub0 in ubs.values) {
                var blames = BlameSet()
                for (entry in ub2Blames) {
                    if (refEq(entry.ty, ub0)) {
                        blames = entry.blames.Clone()
                        break
                    }
                }
                if (!UnifyAndTrim(cms, Tracked(lbTy, blames: lbTTy.blames), Tracked(ub0, blames: blames))) {
                    let lbs = ArrayList<Tracked>()
                    lbs.add(lbTTy)
                    let upperBounds = ArrayList<Tracked>()
                    upperBounds.add(Tracked(ub0, blames: blames))
                    MaybeSetErrMsg(MakeMsgConflictingConstraints(tyVar, lbs, upperBounds))
                    return false
                }
            }
            if (deterministic && !tyMgr.TyVarHasNoSum(tyVar)) {
                if (!lb.IsNothing() && !tyVarBounds.sum.Contains(lb)) {
                    return false
                }
            }
        }
        if (Ty.IsTyCorrect(ub)) {
            let tyVarBounds = c.GetOrCreate(tyVar)
            let lbs = tyVarBounds.lbs.Clone()
            let lb2Blames = cloneTyBlameEntries(tyVarBounds.lb2Blames)
            for (lb0 in lbs.values) {
                var blames = BlameSet()
                for (entry in lb2Blames) {
                    if (refEq(entry.ty, lb0)) {
                        blames = entry.blames.Clone()
                        break
                    }
                }
                if (!UnifyAndTrim(cms, Tracked(lb0, blames: blames), ubTTy)) {
                    let lowerBounds = ArrayList<Tracked>()
                    lowerBounds.add(Tracked(lb0, blames: blames))
                    let ubs = ArrayList<Tracked>()
                    ubs.add(ubTTy)
                    MaybeSetErrMsg(MakeMsgConflictingConstraints(tyVar, lowerBounds, ubs))
                    return false
                }
            }
        }
        if (deterministic && !tyMgr.TyVarHasNoSum(tyVar)) {
            let bounds = c.GetOrCreate(tyVar)
            if (!bounds.eq.IsEmpty() && !bounds.eq.values[0].IsNothing() && !bounds.sum.Contains(bounds.eq.values[0])) {
                return false
            }
        }
        return true
    }

    private func UnifyContextTyVar(argTTy: Tracked, paramTTy: Tracked): Bool {
        let argTy = argTTy.ty
        let paramTy = paramTTy.ty
        if (refEq(argTy, paramTy)) {
            return true
        }
        if (let Some(argVar) <- (argTy as GenericsTy)) {
            if (!argVar.isPlaceholder) {
                if (argVar.upperBounds.isEmpty()) {
                    return UnifyOne(Tracked(tyMgr.GetAnyTy()), paramTTy)
                }
                let ubTy = if (argVar.upperBounds.size == 1) {
                    argVar.upperBounds[0]
                } else {
                    tyMgr.GetIntersectionTy(argVar.upperBounds.toArray())
                }
                return UnifyOne(Tracked(ubTy, blames: argTTy.blames), paramTTy)
            }
        }
        if (let Some(paramVar) <- (paramTy as GenericsTy)) {
            if (!paramVar.isPlaceholder) {
                return false
            }
        }
        return false
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

    private func UpdateIdealTysInConstraints(targetTy: Ty): Unit {
        if (cms.Size() != 1) {
            return
        }
        if (let Some(tyVar) <- curTyVar) {
            let bounds = cms.values[0].constraint.GetOrCreate(tyVar)
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

    private func UnifyParamIntersectionTy(argTTy: Tracked, paramTTy: Tracked): Bool {
        if (let Some(paramTy) <- (paramTTy.ty as IntersectionTy)) {
            for (candidate in paramTy.tys) {
                if (!UnifyAndTrim(cms, argTTy, Tracked(candidate, blames: paramTTy.blames))) {
                    return false
                }
            }
            return true
        }
        return false
    }

    private func UnifyArgIntersectionTy(argTTy: Tracked, paramTTy: Tracked): Bool {
        if (let Some(argTy) <- (argTTy.ty as IntersectionTy)) {
            if (argTy.tys.isEmpty()) {
                return UnifyOne(Tracked(tyMgr.GetAnyTy()), paramTTy)
            } else if (argTy.tys.size == 1) {
                return UnifyOne(Tracked(argTy.tys[0], blames: argTTy.blames), paramTTy)
            }
            let res = ConstraintWithMemos()
            for (candidate in argTy.tys) {
                let unified = LocalTypeArgumentSynthesis.Unify(this, cms,
                    Tracked(candidate, blames: argTTy.blames), paramTTy)
                MaybeSetErrMsg(unified[1])
                res.AddAll(unified[0])
                if (deterministic && !res.IsEmpty()) {
                    break
                }
            }
            return VerifyAndSetCMS(res)
        }
        return false
    }

    private func UnifyParamUnionTy(argTTy: Tracked, paramTTy: Tracked): Bool {
        if (let Some(paramTy) <- (paramTTy.ty as UnionTy)) {
            if (paramTy.tys.isEmpty()) {
                return argTTy.ty.IsNothing()
            } else if (paramTy.tys.size == 1) {
                return UnifyOne(argTTy, Tracked(paramTy.tys[0], blames: paramTTy.blames))
            }
            let res = ConstraintWithMemos()
            for (candidate in paramTy.tys) {
                let unified = LocalTypeArgumentSynthesis.Unify(this, cms, argTTy,
                    Tracked(candidate, blames: paramTTy.blames))
                MaybeSetErrMsg(unified[1])
                res.AddAll(unified[0])
                if (deterministic && !res.IsEmpty()) {
                    break
                }
            }
            return VerifyAndSetCMS(res)
        }
        return false
    }

    private func UnifyArgUnionTy(argTTy: Tracked, paramTTy: Tracked): Bool {
        if (let Some(argTy) <- (argTTy.ty as UnionTy)) {
            for (candidate in argTy.tys) {
                if (!UnifyAndTrim(cms, Tracked(candidate, blames: argTTy.blames), paramTTy)) {
                    return false
                }
            }
            return true
        }
        return false
    }

    private func UnifyFuncTy(argTTy: Tracked, paramTTy: Tracked): Bool {
        if (let Some(argTy) <- (argTTy.ty as FuncTy)) {
            if (let Some(paramTy) <- (paramTTy.ty as FuncTy)) {
                if (argTy.paramTys.size != paramTy.paramTys.size) {
                    return false
                }
                for (idx in 0..argTy.paramTys.size) {
                    if (!UnifyAndTrim(cms, Tracked(paramTy.paramTys[idx], blames: paramTTy.blames),
                        Tracked(argTy.paramTys[idx], blames: argTTy.blames))) {
                        return false
                    }
                }
                return UnifyAndTrim(cms, Tracked(argTy.retTy, blames: argTTy.blames),
                    Tracked(paramTy.retTy, blames: paramTTy.blames))
            }
        }
        return false
    }

    private func UnifyTupleTy(argTTy: Tracked, paramTTy: Tracked): Bool {
        if (let Some(argTy) <- (argTTy.ty as TupleTy)) {
            if (let Some(paramTy) <- (paramTTy.ty as TupleTy)) {
                if (argTy.typeArgs.size != paramTy.typeArgs.size) {
                    return false
                }
                for (idx in 0..argTy.typeArgs.size) {
                    if (!UnifyOne(Tracked(argTy.typeArgs[idx], blames: argTTy.blames),
                        Tracked(paramTy.typeArgs[idx], blames: paramTTy.blames))) {
                        return false
                    }
                }
                return true
            }
        }
        return false
    }

    private func UnifyBuiltInTy(argTTy: Tracked, paramTTy: Tracked): Bool {
        if (argTTy.ty.typeArgs.size != 1 || paramTTy.ty.typeArgs.size != 1) {
            return false
        }
        return UnifyOne(Tracked(argTTy.ty.typeArgs[0], blames: argTTy.blames),
            Tracked(paramTTy.ty.typeArgs[0], blames: paramTTy.blames)) &&
            UnifyOne(Tracked(paramTTy.ty.typeArgs[0], blames: paramTTy.blames),
                Tracked(argTTy.ty.typeArgs[0], blames: argTTy.blames))
    }

    private func UnifyNominal(argTTy: Tracked, paramTTy: Tracked): Bool {
        let promoted = Promotion(tyMgr).Promote(argTTy.ty, paramTTy.ty)
        if (promoted.IsEmpty()) {
            return false
        }
        let res = ConstraintWithMemos()
        for (candidate in promoted.values) {
            if (!Ty.IsTyCorrect(candidate)) {
                continue
            }
            if (candidate.typeArgs.size != paramTTy.ty.typeArgs.size) {
                continue
            }
            var currentCms = cms.Clone()
            for (idx in 0..candidate.typeArgs.size) {
                let needNominalDiag = needDiagMsg && match (errMsg.style) {
                    case SolvingErrStyle.DEFAULT => true
                    case _ => false
                }
                if (needNominalDiag) {
                    let unified = LocalTypeArgumentSynthesis.Unify(this, currentCms,
                        Tracked(candidate.typeArgs[idx], blames: argTTy.blames),
                        Tracked(paramTTy.ty.typeArgs[idx], blames: paramTTy.blames))
                    errMsg = unified[1]
                    let unifiedBack = LocalTypeArgumentSynthesis.Unify(this, unified[0],
                        Tracked(paramTTy.ty.typeArgs[idx], blames: paramTTy.blames),
                        Tracked(candidate.typeArgs[idx], blames: argTTy.blames))
                    currentCms = unifiedBack[0]
                    MaybeSetErrMsg(unifiedBack[1])
                } else {
                    currentCms = LocalTypeArgumentSynthesis.Unify(this, currentCms,
                        Tracked(candidate.typeArgs[idx], blames: argTTy.blames),
                        Tracked(paramTTy.ty.typeArgs[idx], blames: paramTTy.blames))[0]
                    currentCms = LocalTypeArgumentSynthesis.Unify(this, currentCms,
                        Tracked(paramTTy.ty.typeArgs[idx], blames: paramTTy.blames),
                        Tracked(candidate.typeArgs[idx], blames: argTTy.blames))[0]
                }
            }
            res.AddAll(currentCms)
            if (deterministic && !res.IsEmpty()) {
                break
            }
        }
        if (!res.IsEmpty()) {
            cms = res
            errMsg = SolvingErrInfo()
        }
        return cms.IsEmpty() || !res.IsEmpty()
    }

    private func UnifyBuiltInExtension(argTTy: Tracked, paramTTy: Tracked): Bool {
        return UnifyNominal(argTTy, paramTTy)
    }

    private func UnifyPrimitiveTy(argTy: PrimitiveTy, paramTy: PrimitiveTy): Bool {
        if (!tyMgr.IsSubtype(argTy, paramTy)) {
            return false
        }
        if (argTy.IsIdeal() && !paramTy.IsIdeal()) {
            UpdateIdealTysInConstraints(paramTy)
        } else if (paramTy.IsIdeal() && !argTy.IsIdeal()) {
            UpdateIdealTysInConstraints(argTy)
        }
        return true
    }

    private func SolveCurrentConstraints(allowPartial!: Bool = false): Option<TypeSubst> {
        let substs = TypeSubsts()
        for (cm in cms.values) {
            let subst = TypeSubst()
            let graph = TyVarConstraintGraph(cm.constraint, argPack.tyVarsToSolve, tyMgr)
            var candidateValid = true
            while (true) {
                let nextConstraints = graph.TopoOnce(cm.constraint)
                if (nextConstraints.entries.isEmpty()) {
                    break
                }
                let substitutedConstraints = ApplyTypeSubstForCS(subst, nextConstraints)
                if (let Some(solved) <- FindSolution(substitutedConstraints, cm.hasNothingTy, cm.hasAnyTy)) {
                    graph.ApplyTypeSubst(solved)
                    MergeTypeSubst(subst, solved)
                } else {
                    candidateValid = false
                    break
                }
            }
            if (candidateValid && (allowPartial || !HasUnsolvedTyVars(subst))) {
                substs.Insert(subst)
            }
        }
        if (!substs.IsEmpty()) {
            errMsg = SolvingErrInfo()
        }
        return GetBestSolution(substs, allowPartial: allowPartial)
    }

    private func FindSolution(thisM: Constraint, hasNothingTy: Bool, hasAnyTy: Bool): Option<TypeSubst> {
        let thisSubst = TypeSubst()
        var current = cloneConstraint(thisM)
        var newInfo = true
        var msg = SolvingErrInfo()
        while (newInfo) {
            newInfo = false
            let tyVarsOfThisM = ArrayList<GenericsTy>()
            for (entry in current.entries) {
                tyVarsOfThisM.add(entry.tyVar)
            }
            var idx: Int64 = 0
            while (idx < current.entries.size) {
                let entry = current.entries[idx]
                if (needDiagMsg && entry.bounds.lbs.IsEmpty() && entry.bounds.ubs.IsEmpty()) {
                    msg = MakeMsgNoConstraint(entry.tyVar)
                    break
                }
                var tyJ = JoinAsVisibleTy(tyMgr, entry.bounds.lbs, ignoredTyVars: ToTySet(tyVarsOfThisM))
                var tyM = MeetUpperBounds(entry.tyVar, entry.bounds.ubs, tyVarsOfThisM) ??
                    TypeManager.GetInvalidTy()
                let validAnyTy = hasAnyTy || (deterministic && entry.bounds.ubs.Contains(tyMgr.GetAnyTy()))
                let validNothingTy = hasNothingTy ||
                    (deterministic && entry.bounds.lbs.Contains(TypeManager.GetNothingTy()))
                if (IsValidSolution(tyJ, validNothingTy, validAnyTy)) {
                    thisSubst.Put(entry.tyVar, tyJ)
                    current.entries.remove(at: idx)
                    newInfo = true
                    continue
                } else if (tyJ.HasIdealTy() && !tyM.IsNumeric()) {
                    tyJ = tyMgr.ReplaceIdealTy(tyJ)
                    thisSubst.Put(entry.tyVar, tyJ)
                    current.entries.remove(at: idx)
                    newInfo = true
                    continue
                } else if (IsValidSolution(tyM, validNothingTy, validAnyTy)) {
                    thisSubst.Put(entry.tyVar, tyM)
                    current.entries.remove(at: idx)
                    newInfo = true
                    continue
                } else if (tyM.HasIdealTy()) {
                    tyM = tyMgr.ReplaceIdealTy(tyM)
                    thisSubst.Put(entry.tyVar, tyM)
                    current.entries.remove(at: idx)
                    newInfo = true
                    continue
                } else if (needDiagMsg) {
                    let lbs = ArrayList<Tracked>()
                    for (lb in entry.bounds.lbs.values) {
                        var blames = BlameSet()
                        for (blameEntry in entry.bounds.lb2Blames) {
                            if (refEq(blameEntry.ty, lb)) {
                                blames = blameEntry.blames.Clone()
                                break
                            }
                        }
                        lbs.add(Tracked(lb, blames: blames))
                    }
                    let ubs = ArrayList<Tracked>()
                    for (ub in entry.bounds.ubs.values) {
                        var blames = BlameSet()
                        for (blameEntry in entry.bounds.ub2Blames) {
                            if (refEq(blameEntry.ty, ub)) {
                                blames = blameEntry.blames.Clone()
                                break
                            }
                        }
                        ubs.add(Tracked(ub, blames: blames))
                    }
                    msg = MakeMsgConflictingConstraints(entry.tyVar, lbs, ubs)
                }
                idx++
            }
            current = ApplyTypeSubstForCS(thisSubst, current)
        }
        match (errMsg.style) {
            case SolvingErrStyle.DEFAULT => errMsg = msg
            case _ => ()
        }
        return thisSubst
    }

    private func MergeTypeSubst(target: TypeSubst, source: TypeSubst): Unit {
        for (entry in source.entries) {
            target.Put(entry.tyVar, entry.ty)
        }
    }

    private func DoesCSCoverAllTyVars(m: Constraint): Bool {
        for (tyVar in argPack.tyVarsToSolve) {
            var covered = false
            for (entry in m.entries) {
                if (SameTy(entry.tyVar, tyVar) && (!entry.bounds.lbs.IsEmpty() || !entry.bounds.ubs.IsEmpty())) {
                    covered = true
                    break
                }
            }
            if (!covered) {
                return false
            }
        }
        return true
    }

    private func GetBestSolution(substs: TypeSubsts, allowPartial!: Bool = false): Option<TypeSubst> {
        if (substs.values.isEmpty() || argPack.tyVarsToSolve.isEmpty()) {
            return None
        }
        if (substs.values.size == 1) {
            return substs.values[0].Clone()
        }
        let candidates = ArrayList<TypeSubst>()
        let maximals = ArrayList<Bool>()
        for (subst in substs.values) {
            candidates.add(subst.Clone())
            maximals.add(true)
        }
        if (allowPartial) {
            let unsolvedCount = ArrayList<Int64>()
            for (tySub in candidates) {
                unsolvedCount.add(CountUnsolvedTyVars(tySub))
            }
            var minCount = unsolvedCount[0]
            for (count in unsolvedCount) {
                if (count < minCount) {
                    minCount = count
                }
            }
            for (idx in 0..unsolvedCount.size) {
                if (unsolvedCount[idx] > minCount) {
                    maximals[idx] = false
                }
            }
        }
        for (tyVar in argPack.tyVarsToSolve) {
            CompareCandidates(tyVar, candidates, maximals)
        }
        if (let Some(idx) <- GetBestIndex(maximals)) {
            return candidates[idx].Clone()
        }
        return None
    }

    private func CompareCandidates(tyVar: GenericsTy, candidates: ArrayList<TypeSubst>, maximals: ArrayList<Bool>): Unit {
        for (idx in 0..candidates.size) {
            if (!maximals[idx]) {
                continue
            }
            let tyI = tyMgr.GetInstantiatedTy(tyVar, candidates[idx])
            for (nextIdx in (idx + 1)..candidates.size) {
                if (!maximals[nextIdx]) {
                    continue
                }
                let tyJ = tyMgr.GetInstantiatedTy(tyVar, candidates[nextIdx])
                if (tyI.IsNumeric() && tyJ.IsNumeric()) {
                    let res = CompareIntAndFloat(tyI, tyJ)
                    if (res == ComparisonRes.GT) {
                        maximals[idx] = false
                    } else if (res == ComparisonRes.LT) {
                        maximals[nextIdx] = false
                    }
                } else if (!tyMgr.IsSubtype(tyI, tyJ)) {
                    maximals[idx] = false
                } else if (!tyMgr.IsSubtype(tyJ, tyI)) {
                    maximals[nextIdx] = false
                }
                if (!maximals[idx]) {
                    break
                }
            }
        }
    }

    private func GetBestIndex(maximals: ArrayList<Bool>): Option<Int64> {
        let res = ArrayList<Int64>()
        for (idx in 0..maximals.size) {
            if (maximals[idx]) {
                res.add(idx)
            }
        }
        if (res.size == 1) {
            return res[0]
        }
        return None
    }

    private func ResetIdealTypesInSubst(m: TypeSubst): TypeSubst {
        let res = TypeSubst()
        for (entry in m.entries) {
            res.Put(entry.tyVar, tyMgr.ReplaceIdealTy(entry.ty))
        }
        return res
    }

    private func ApplyTypeSubstForCS(typeMapping: TypeSubst, input: Constraint): Constraint {
        if (typeMapping.IsEmpty()) {
            return cloneConstraint(input)
        }
        let out = Constraint()
        for (entry in input.entries) {
            let bounds = TyVarBounds()
            for (lower in entry.bounds.lbs.values) {
                let newLower = tyMgr.GetInstantiatedTy(lower, typeMapping)
                bounds.lbs.Add(newLower)
                for (blameEntry in entry.bounds.lb2Blames) {
                    if (refEq(blameEntry.ty, lower)) {
                        bounds.lb2Blames.add(TyBlameEntry(newLower, blames: blameEntry.blames.Clone()))
                        break
                    }
                }
            }
            for (upper in entry.bounds.ubs.values) {
                let newUpper = tyMgr.GetInstantiatedTy(upper, typeMapping)
                bounds.ubs.Add(newUpper)
                for (blameEntry in entry.bounds.ub2Blames) {
                    if (refEq(blameEntry.ty, upper)) {
                        bounds.ub2Blames.add(TyBlameEntry(newUpper, blames: blameEntry.blames.Clone()))
                        break
                    }
                }
            }
            out.entries.add(ConstraintEntry(entry.tyVar, bounds: bounds))
        }
        return out
    }

    private func MeetUpperBounds(tyVar: GenericsTy, ubs: TySet, ignoredTyVars: ArrayList<GenericsTy>): Option<Ty> {
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
        var resultOpt = MeetTypes(tysWithoutTyVar, ignoredTyVars)
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
            resultOpt = MeetTypes(instantiated, ignoredTyVars)
        }
        return resultOpt
    }

    private func MeetTypes(values: TySet, ignoredTyVars: ArrayList<GenericsTy>): Option<Ty> {
        if (values.values.isEmpty()) {
            return None
        }
        return MeetAsVisibleTy(tyMgr, values, ignoredTyVars: ToTySet(ignoredTyVars))
    }

    private func IsValidSolution(ty: Ty, hasNothingTy: Bool, hasAnyTy: Bool): Bool {
        // Mirror C++ LocalTypeArgumentSynthesis::IsValidSolution
        // (src/Sema/LocalTypeArgumentSynthesis.cpp:833-839).
        var solution = !ty.HasInvalidTy() && !ty.IsNothing() && !ty.IsAny() && !ty.HasIdealTy() && !ty.IsCType()
        solution = solution || (hasNothingTy && ty.IsNothing())
        solution = solution || (hasAnyTy && ty.IsAny())
        return solution
    }

    private func MakeMsgConflictingConstraints(tyVar: GenericsTy, lbTTys: ArrayList<Tracked>,
        ubTTys: ArrayList<Tracked>): SolvingErrInfo {
        let ret = SolvingErrInfo()
        ret.style = SolvingErrStyle.CONFLICTING_CONSTRAINTS
        ret.tyVar = Some(tyVar)
        for (tty in lbTTys) {
            ret.lbs.add(tty.ty)
            ret.blames.add(tty.blames.Clone())
        }
        for (tty in ubTTys) {
            ret.ubs.add(tty.ty)
            ret.blames.add(tty.blames.Clone())
        }
        return ret
    }

    private func MakeMsgNoConstraint(tyVar: GenericsTy): SolvingErrInfo {
        let ret = SolvingErrInfo()
        ret.style = SolvingErrStyle.NO_CONSTRAINT
        ret.tyVar = Some(tyVar)
        return ret
    }

    private func MakeMsgMismatchedArg(blame: Blame): SolvingErrInfo {
        let ret = SolvingErrInfo()
        ret.style = SolvingErrStyle.ARG_MISMATCH
        let blames = BlameSet()
        blames.Add(blame)
        ret.blames.add(blames)
        return ret
    }

    private func MakeMsgMismatchedRet(blame: Blame): SolvingErrInfo {
        let ret = SolvingErrInfo()
        ret.style = SolvingErrStyle.RET_MISMATCH
        let blames = BlameSet()
        blames.Add(blame)
        ret.blames.add(blames)
        return ret
    }

    private func MaybeSetErrMsg(s: SolvingErrInfo): Unit {
        let shouldSet = needDiagMsg && match (errMsg.style) {
            case SolvingErrStyle.DEFAULT => true
            case _ => false
        }
        if (shouldSet) {
            errMsg = s
        }
    }

    private func normalizeInferredTy(ty: Ty): Ty {
        if (let Some(thisTy) <- (ty as ClassThisTy)) {
            if (let Some(decl) <- thisTy.declPtr) {
                return tyMgr.GetClassTy(decl, thisTy.typeArgs.toArray())
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
