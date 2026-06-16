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

public class LocalTypeArgumentSynthesis {
    private var tyMgr: TypeManager
    private var argPack: LocTyArgSynArgPack
    private var needDiagMsg: Bool
    private var constraints: Constraint = Constraint()
    private var errInfo: SolvingErrInfo = SolvingErrInfo()

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
        constraints = InitConstraints(argPack.tyVarsToSolve)
        for (idx in 0..argPack.argTys.size) {
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
        return synthesis.SolveCurrentConstraints(allowPartial: false)
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

    public func UnifyOne(argTy: Ty, paramTy: Ty): Bool {
        if (SameTy(argTy, paramTy) || argTy.IsQuest() || paramTy.IsQuest()) {
            return true
        }
        if (let Some(paramVar) <- (paramTy as GenericsTy)) {
            if (paramVar.isPlaceholder && containsTyVar(argPack.tyVarsToSolve, paramVar)) {
                constraints.GetOrCreate(paramVar).lbs.Add(normalizeInferredTy(argTy))
                return true
            }
        }
        if (let Some(argVar) <- (argTy as GenericsTy)) {
            if (argVar.isPlaceholder && containsTyVar(argPack.tyVarsToSolve, argVar)) {
                constraints.GetOrCreate(argVar).ubs.Add(normalizeInferredTy(paramTy))
                return true
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
            return typeArgsCanUnify(this, argTy, paramTy)
        }
        if (argTy.IsNominal() && paramTy.IsNominal()) {
            return UnifyNominal(argTy, paramTy)
        }
        if (argTy.IsPrimitive() && paramTy.IsPrimitive()) {
            return tyMgr.IsSubtype(argTy, paramTy)
        }
        return tyMgr.IsSubtype(argTy, paramTy)
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

    private func UnifyNominal(argTy: Ty, paramTy: Ty): Bool {
        let promoted = Promotion(tyMgr).Promote(argTy, paramTy)
        if (promoted.IsEmpty()) {
            return false
        }
        var accepted = false
        for (candidate in promoted.values) {
            if (candidate.typeArgs.size == paramTy.typeArgs.size) {
                var localOk = true
                for (idx in 0..candidate.typeArgs.size) {
                    if (!UnifyOne(candidate.typeArgs[idx], paramTy.typeArgs[idx])) {
                        localOk = false
                        break
                    }
                }
                accepted = accepted || localOk
            } else {
                accepted = true
            }
        }
        return accepted
    }

    private func SolveCurrentConstraints(allowPartial!: Bool = false): Option<TypeSubst> {
        let subst = TypeSubst()
        for (tyVar in argPack.tyVarsToSolve) {
            if (let Some(solution) <- FindSolution(tyVar)) {
                subst.Put(tyVar, solution)
            } else if (!allowPartial) {
                errInfo.style = SolvingErrStyle.NO_CONSTRAINT
                errInfo.tyVar = tyVar
                return None
            }
        }
        return subst
    }

    private func FindSolution(tyVar: GenericsTy): Option<Ty> {
        let bounds = constraints.GetOrCreate(tyVar)
        for (eqTy in bounds.eq.values) {
            if (IsValidSolution(eqTy, bounds)) {
                return eqTy
            }
        }
        for (lb in bounds.lbs.values) {
            if (IsValidSolution(lb, bounds)) {
                return lb
            }
        }
        for (ub in bounds.ubs.values) {
            if (IsValidSolution(ub, bounds)) {
                return ub
            }
        }
        return None
    }

    private func IsValidSolution(candidate: Ty, bounds: TyVarBounds): Bool {
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

private func cloneConstraint(cst: Constraint): Constraint {
    let out = Constraint()
    for (entry in cst.entries) {
        let bounds = out.GetOrCreate(entry.tyVar)
        bounds.lbs.AddAll(entry.bounds.lbs)
        bounds.ubs.AddAll(entry.bounds.ubs)
        bounds.sum.AddAll(entry.bounds.sum)
        bounds.eq.AddAll(entry.bounds.eq)
    }
    return out
}
