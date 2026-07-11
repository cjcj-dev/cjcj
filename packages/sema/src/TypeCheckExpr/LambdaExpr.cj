package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::sema.*

private func LambdaInvalid(le: LambdaExpr): Ty {
    return TcInvalid(le)
}

private class LambdaParamInference {
    public let placeholders: ArrayList<GenericsTy> = ArrayList<GenericsTy>()

    public init() {}
}

private func LambdaParamList(le: LambdaExpr): Option<FuncParamList> {
    if (let Some(funcBody) <- le.funcBody) {
        if (!funcBody.paramLists.isEmpty()) {
            return Some(funcBody.paramLists[0])
        }
    }
    return None
}

private func ClearLambdaBodyForReCheck(le: LambdaExpr): Unit {
    if (let Some(funcBody) <- le.funcBody) {
        if (let Some(body) <- funcBody.body) {
            let walker = Walker(body, visitPre: { node: Node =>
                if (let Some(_) <- (node as Type)) {
                    return VisitAction.SKIP_CHILDREN
                }
                if (let Some(_) <- (node as Generic)) {
                    return VisitAction.SKIP_CHILDREN
                }
                if (let Some(funcParam) <- (node as FuncParam)) {
                    if (funcParam.TestAttr(Attribute.HAS_INITIAL)) {
                        return VisitAction.SKIP_CHILDREN
                    }
                }
                node.Clear()
                VisitAction.WALK_CHILDREN
            })
            let _ = walker.Walk()
        }
    }
}

private func InferParamTyFromNode(typeManager: TypeManager, param: FuncParam,
    placeholders: ArrayList<GenericsTy>, allowPlaceholder: Bool): Ty {
    if (let Some(typeNode) <- param.typeNode) {
        if (let Some(typeTy) <- typeNode.GetTy()) {
            param.SetTy(typeTy)
            return typeTy
        }
    }
    if (let Some(paramTy) <- param.GetTy()) {
        if (Ty.IsTyCorrect(paramTy)) {
            if (paramTy.IsPlaceholder() || paramTy.IsAny()) {
                if (allowPlaceholder) {
                    let freshTyVar = typeManager.AllocTyVar(srcId: "T-Lam", needSolving: true)
                    param.SetTy(freshTyVar)
                    placeholders.add(freshTyVar)
                    return freshTyVar
                }
                return TypeManager.GetInvalidTy()
            }
            return paramTy
        }
    }
    if (allowPlaceholder) {
        let freshTyVar2 = typeManager.AllocTyVar(srcId: "T-Lam", needSolving: true)
        param.SetTy(freshTyVar2)
        placeholders.add(freshTyVar2)
        return freshTyVar2
    }
    return TypeManager.GetInvalidTy()
}

private func CanInferLambdaParamBody(ctx: Option<ASTContext>, le: LambdaExpr): Bool {
    if (let Some(ctxValue) <- ctx) {
        return !ctxValue.funcArgReachable.contains(le)
    }
    return true
}

private func CollectLambdaParamTys(typeManager: TypeManager, le: LambdaExpr,
    allowPlaceholder!: Bool = false, ctx!: Option<ASTContext> = None): Option<LambdaParamInference> {
    if (let Some(paramList) <- LambdaParamList(le)) {
        let inference = LambdaParamInference()
        for (param in paramList.params) {
            let paramTy = InferParamTyFromNode(typeManager, param, inference.placeholders,
                allowPlaceholder && CanInferLambdaParamBody(ctx, le))
            if (!Ty.IsTyCorrect(paramTy)) {
                return None
            }
        }
        return Some(inference)
    }
    return None
}

private func CopyConstraintForTyVar(source: Constraint, target: Constraint, tyVar: GenericsTy): Bool {
    for (entry in source.entries) {
        if (SameTy(entry.tyVar, tyVar)) {
            let bounds = target.GetOrCreate(tyVar)
            bounds.lbs.AddAll(entry.bounds.lbs)
            bounds.ubs.AddAll(entry.bounds.ubs)
            bounds.sum.AddAll(entry.bounds.sum)
            bounds.eq.AddAll(entry.bounds.eq)
            return true
        }
    }
    return false
}

private func BuildLambdaConstraint(typeManager: TypeManager, placeholders: ArrayList<GenericsTy>): Option<Constraint> {
    let constraint = Constraint()
    for (tyVar in placeholders) {
        if (!CopyConstraintForTyVar(typeManager.constraints, constraint, tyVar)) {
            return None
        }
    }
    return Some(constraint)
}

private func LambdaSubstSolvesAll(placeholders: ArrayList<GenericsTy>, subst: TypeSubst): Bool {
    for (tyVar in placeholders) {
        if (let None <- subst.Get(tyVar)) {
            return false
        }
    }
    return true
}

private func ApplyLambdaParamSubst(typeManager: TypeManager, funcBody: FuncBody, subst: TypeSubst): Unit {
    if (funcBody.paramLists.isEmpty()) {
        return
    }
    for (param in funcBody.paramLists[0].params) {
        if (let Some(paramTy) <- param.GetTy()) {
            param.SetTy(typeManager.GetInstantiatedTy(paramTy, subst))
        }
    }
}

private func SolveLambdaParamPlaceholders(typeManager: TypeManager, le: LambdaExpr,
    inference: LambdaParamInference, funcTy: Ty): Ty {
    if (inference.placeholders.isEmpty()) {
        return funcTy
    }
    if (let Some(lambdaConstraint) <- BuildLambdaConstraint(typeManager, inference.placeholders)) {
        if (let Some(subst) <- LocalTypeArgumentSynthesis.SolveConstraints(typeManager, lambdaConstraint)) {
            if (LambdaSubstSolvesAll(inference.placeholders, subst)) {
                if (let Some(funcBody) <- le.funcBody) {
                    ApplyLambdaParamSubst(typeManager, funcBody, subst)
                    ClearLambdaBodyForReCheck(le)
                    return SynFuncBodyForLambda(typeManager, funcBody)
                }
            }
        }
    }
    return TypeManager.GetInvalidTy()
}

private func SynFuncBodyForLambda(typeManager: TypeManager, funcBody: FuncBody): Ty {
    var retTy: Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
    if (let Some(retTypeNode) <- funcBody.retType) {
        if (let Some(declaredRetTy) <- retTypeNode.GetTy()) {
            retTy = declaredRetTy
        }
    }
    if (let Some(body) <- funcBody.body) {
        if (let Some(_) <- funcBody.retType) {
            if (!ChkBlock(typeManager, retTy, body)) {
                funcBody.SetTy(TypeManager.GetInvalidTy())
                return TypeManager.GetInvalidTy()
            }
        } else {
            retTy = SynBlock(typeManager, body)
            if (!Ty.IsTyCorrect(retTy)) {
                funcBody.SetTy(TypeManager.GetInvalidTy())
                return TypeManager.GetInvalidTy()
            }
        }
    }
    let paramTys = GetFuncBodyParamTys(funcBody)
    let funcTy = typeManager.GetFunctionTy(paramTys.toArray(), retTy)
    funcBody.SetTy(funcTy)
    return funcTy
}

private func CloneFuncTyConfig(funcTy: FuncTy): FuncTyConfig {
    let cfg = FuncTyConfig()
    cfg.isC = funcTy.isC
    cfg.isClosureTy = funcTy.isClosureTy
    cfg.hasVariableLenArg = funcTy.hasVariableLenArg
    cfg.noCast = funcTy.noCast
    return cfg
}

public func SynLamExpr(typeManager: TypeManager, le: LambdaExpr, ctx!: Option<ASTContext> = None): Ty {
    if (let None <- le.funcBody) {
        return LambdaInvalid(le)
    }
    if (let None <- LambdaParamList(le)) {
        return LambdaInvalid(le)
    }
    let tyVarScope = BeginTyVarScope(typeManager)
    let inferenceOpt = CollectLambdaParamTys(typeManager, le, allowPlaceholder: true, ctx: ctx)
    if (let None <- inferenceOpt) {
        EndTyVarScope(tyVarScope)
        return LambdaInvalid(le)
    }
    let inference = inferenceOpt.getOrThrow()
    let funcBody = le.funcBody.getOrThrow()
    let rawFuncTy = SynFuncBodyForLambda(typeManager, funcBody)
    var funcTy = rawFuncTy
    if (Ty.IsTyCorrect(rawFuncTy)) {
        funcTy = SolveLambdaParamPlaceholders(typeManager, le, inference, rawFuncTy)
    }
    EndTyVarScope(tyVarScope)
    if (Ty.IsTyCorrect(funcTy)) {
        le.SetTy(funcTy)
        return funcTy
    }
    return LambdaInvalid(le)
}

private func CheckLambdaParamsAgainstTarget(typeManager: TypeManager, le: LambdaExpr, targetFuncTy: FuncTy,
    outParamTys: ArrayList<Ty>): Bool {
    if (let Some(paramList) <- LambdaParamList(le)) {
        if (paramList.params.size != targetFuncTy.paramTys.size) {
            return false
        }
        for (idx in 0..paramList.params.size) {
            let param = paramList.params[idx]
            let targetParamTy = targetFuncTy.paramTys[idx]
            var paramTy = targetParamTy
            if (let Some(typeNode) <- param.typeNode) {
                if (let Some(typeTy) <- typeNode.GetTy()) {
                    paramTy = typeTy
                } else {
                    return false
                }
            }
            param.SetTy(paramTy)
            if (!typeManager.IsSubtype(targetParamTy, paramTy, implicitBoxed: false, allowOptionBox: false)) {
                return false
            }
            outParamTys.add(paramTy)
        }
        return true
    }
    return false
}

private func CheckLambdaBodyAgainstTarget(typeManager: TypeManager, le: LambdaExpr, targetFuncTy: FuncTy): Bool {
    if (let Some(funcBody) <- le.funcBody) {
        if (let Some(body) <- funcBody.body) {
            if (!ChkBlock(typeManager, targetFuncTy.retTy, body)) {
                funcBody.SetTy(TypeManager.GetInvalidTy())
                return false
            }
        }
        let paramTys = GetFuncBodyParamTys(funcBody)
        let funcTy = typeManager.GetFunctionTy(paramTys.toArray(), targetFuncTy.retTy,
            cfg: CloneFuncTyConfig(targetFuncTy))
        funcBody.SetTy(funcTy)
        return true
    }
    return false
}

public func ChkLamExpr(typeManager: TypeManager, target: Ty, le: LambdaExpr, ctx!: Option<ASTContext> = None): Bool {
    if (target.IsAny() || (le.TestAttr(Attribute.C) && target.IsCType())) {
        return Ty.IsTyCorrect(SynLamExpr(typeManager, le, ctx: ctx))
    }
    let targetTy = UnboxOptionType(target)
    if (let Some(targetFuncTy) <- (targetTy as FuncTy)) {
        let paramTys = ArrayList<Ty>()
        if (!CheckLambdaParamsAgainstTarget(typeManager, le, targetFuncTy, paramTys)) {
            let _ = LambdaInvalid(le)
            return false
        }
        if (!CheckLambdaBodyAgainstTarget(typeManager, le, targetFuncTy)) {
            let _ = LambdaInvalid(le)
            return false
        }
        let funcTy = typeManager.GetFunctionTy(paramTys.toArray(), targetFuncTy.retTy,
            cfg: CloneFuncTyConfig(targetFuncTy))
        le.SetTy(funcTy)
        return true
    }
    let synTy = SynLamExpr(typeManager, le, ctx: ctx)
    if (Ty.IsTyCorrect(synTy) && typeManager.CheckTypeCompatibility(target, synTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = LambdaInvalid(le)
    return false
}

extend TypeChecker {
}
