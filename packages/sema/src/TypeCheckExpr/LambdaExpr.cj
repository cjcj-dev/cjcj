package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public func SelfhostPortStatus_TypeCheckExpr_LambdaExpr(): Bool {
    return true
}

private func LambdaInvalid(le: LambdaExpr): Ty {
    return TcInvalid(le)
}

private func LambdaParamList(le: LambdaExpr): Option<FuncParamList> {
    if (let Some(funcBody) <- le.funcBody) {
        if (!funcBody.paramLists.isEmpty()) {
            return Some(funcBody.paramLists[0])
        }
    }
    return None
}

private func InferParamTyFromNode(typeManager: TypeManager, param: FuncParam): Ty {
    if (let Some(typeNode) <- param.typeNode) {
        if (let Some(typeTy) <- typeNode.GetTy()) {
            param.SetTy(typeTy)
            return typeTy
        }
    }
    if (let Some(paramTy) <- param.GetTy()) {
        if (Ty.IsTyCorrect(paramTy)) {
            return paramTy
        }
    }
    let anyTy = typeManager.GetAnyTy()
    param.SetTy(anyTy)
    return anyTy
}

private func CollectLambdaParamTys(typeManager: TypeManager, le: LambdaExpr): Option<ArrayList<Ty>> {
    if (let Some(paramList) <- LambdaParamList(le)) {
        let paramTys = ArrayList<Ty>()
        for (param in paramList.params) {
            let paramTy = InferParamTyFromNode(typeManager, param)
            if (!Ty.IsTyCorrect(paramTy)) {
                return None
            }
            paramTys.add(paramTy)
        }
        return Some(paramTys)
    }
    return None
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

public func SynLamExpr(typeManager: TypeManager, le: LambdaExpr): Ty {
    if (let None <- le.funcBody) {
        return LambdaInvalid(le)
    }
    if (let None <- LambdaParamList(le)) {
        return LambdaInvalid(le)
    }
    if (let None <- CollectLambdaParamTys(typeManager, le)) {
        return LambdaInvalid(le)
    }
    let funcBody = le.funcBody.getOrThrow()
    let funcTy = SynFuncBodyForLambda(typeManager, funcBody)
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
            } else if (let Some(existingTy) <- param.GetTy()) {
                if (Ty.IsTyCorrect(existingTy) && !existingTy.IsAny()) {
                    paramTy = existingTy
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

public func ChkLamExpr(typeManager: TypeManager, target: Ty, le: LambdaExpr): Bool {
    if (target.IsAny() || (le.TestAttr(Attribute.C) && target.IsCType())) {
        return Ty.IsTyCorrect(SynLamExpr(typeManager, le))
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
    let synTy = SynLamExpr(typeManager, le)
    if (Ty.IsTyCorrect(synTy) && typeManager.CheckTypeCompatibility(target, synTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = LambdaInvalid(le)
    return false
}
