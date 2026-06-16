package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public func SelfhostPortStatus_TypeCheckExpr_TryExpr(): Bool {
    return true
}

private func TryInvalid(te: TryExpr): Ty {
    return TcInvalid(te)
}

private func JoinTryTy(typeManager: TypeManager, currentTy: Ty, branchTy: Ty): Ty {
    if (currentTy.IsNothing()) {
        return branchTy
    }
    if (branchTy.IsNothing()) {
        return currentTy
    }
    if (typeManager.CheckTypeCompatibility(currentTy, branchTy) != TypeCompatibility.INCOMPATIBLE) {
        return currentTy
    }
    if (typeManager.CheckTypeCompatibility(branchTy, currentTy) != TypeCompatibility.INCOMPATIBLE) {
        return branchTy
    }
    let tySet = TySet()
    tySet.Add(currentTy)
    tySet.Add(branchTy)
    let common = typeManager.GetAllCommonSuperTys(tySet)
    if (!common.values.isEmpty()) {
        return common.values[0]
    }
    return TypeManager.GetInvalidTy()
}

private func ChkTryExprCatchPatterns(typeManager: TypeManager, te: TryExpr): Bool {
    var ok = true
    for (pattern in te.catchPatterns) {
        ok = TcPatternCheck(typeManager, typeManager.GetAnyTy(), pattern) && ok
    }
    for (handler in te.handlers) {
        if (let Some(commandPattern) <- handler.commandPattern) {
            ok = TcPatternCheck(typeManager, typeManager.GetAnyTy(), commandPattern) && ok
        } else {
            ok = false
        }
    }
    return ok
}

private func ChkTryExprFinallyBlock(typeManager: TypeManager, te: TryExpr): Bool {
    if (let Some(finallyBlock) <- te.finallyBlock) {
        let finallyTy = SynBlock(typeManager, finallyBlock)
        if (Ty.IsTyCorrect(finallyTy)) {
            finallyBlock.SetTy(TcUnitTy())
            if (let Some(finallyLambda) <- te.finallyLambda) {
                let finallyLamTy = typeManager.GetFunctionTy(Array<Ty>(), TcUnitTy())
                return ChkLamExpr(typeManager, finallyLamTy, finallyLambda)
            }
            return true
        }
        finallyBlock.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    return true
}

private func SynTryWithResourcesExpr(typeManager: TypeManager, te: TryExpr): Ty {
    var ok = true
    for (resource in te.resourceSpec) {
        if (let Some(typeNode) <- resource.typeNode) {
            if (let Some(typeTy) <- typeNode.GetTy()) {
                resource.SetTy(typeTy)
            }
        }
        if (let Some(initializer) <- resource.initializer) {
            let initTy = SynExprShallow(typeManager, initializer)
            if (Ty.IsTyCorrect(initTy)) {
                if (let None <- resource.GetTy()) {
                    resource.SetTy(initTy)
                }
            } else {
                resource.SetTy(TypeManager.GetInvalidTy())
                ok = false
            }
        }
        if (!Ty.IsTyCorrect(resource.GetTy())) {
            ok = false
        }
    }
    if (let Some(tryBlock) <- te.tryBlock) {
        ok = Ty.IsTyCorrect(SynBlock(typeManager, tryBlock)) && ok
    } else {
        ok = false
    }
    ok = ChkTryExprCatchPatterns(typeManager, te) && ok
    for (catchBlock in te.catchBlocks) {
        ok = Ty.IsTyCorrect(SynBlock(typeManager, catchBlock)) && ok
    }
    ok = ChkTryExprFinallyBlock(typeManager, te) && ok
    if (ok) {
        let unitTy = TcUnitTy()
        te.SetTy(unitTy)
        return unitTy
    }
    return TryInvalid(te)
}

private func SynTryExprCatchesAndHandles(typeManager: TypeManager, te: TryExpr, baseTy: Ty): Option<Ty> {
    var ok = ChkTryExprCatchPatterns(typeManager, te)
    var joinedTy = baseTy
    for (catchBlock in te.catchBlocks) {
        let catchTy = SynBlock(typeManager, catchBlock)
        if (Ty.IsTyCorrect(catchTy)) {
            joinedTy = JoinTryTy(typeManager, joinedTy, catchTy)
            ok = Ty.IsTyCorrect(joinedTy) && ok
        } else {
            ok = false
        }
    }
    for (handler in te.handlers) {
        if (let Some(block) <- handler.block) {
            let handlerTy = SynBlock(typeManager, block)
            if (Ty.IsTyCorrect(handlerTy)) {
                joinedTy = JoinTryTy(typeManager, joinedTy, handlerTy)
                ok = Ty.IsTyCorrect(joinedTy) && ok
            } else {
                ok = false
            }
        } else {
            ok = false
        }
        if (let Some(lambda) <- handler.desugaredLambda) {
            let commandTy = typeManager.GetAnyTy()
            let handleTy = typeManager.GetFunctionTy([commandTy], joinedTy)
            ok = ChkLamExpr(typeManager, handleTy, lambda) && ok
        }
    }
    if (ok) {
        return Some(joinedTy)
    }
    return None
}

public func SynTryExpr(typeManager: TypeManager, te: TryExpr): Ty {
    if (!te.resourceSpec.isEmpty()) {
        return SynTryWithResourcesExpr(typeManager, te)
    }
    var ok = true
    var baseTy: Ty = TypeManager.GetNothingTy()
    if (!te.handlers.isEmpty() && (let Some(lambda) <- te.tryLambda)) {
        let lambdaTy = SynLamExpr(typeManager, lambda)
        if (let Some(funcTy) <- (lambdaTy as FuncTy)) {
            baseTy = funcTy.retTy
        } else {
            ok = false
        }
    } else if (let Some(tryBlock) <- te.tryBlock) {
        baseTy = SynBlock(typeManager, tryBlock)
        ok = Ty.IsTyCorrect(baseTy) && ok
    } else {
        ok = false
    }
    if (let Some(joinedTy) <- SynTryExprCatchesAndHandles(typeManager, te, baseTy)) {
        ok = ChkTryExprFinallyBlock(typeManager, te) && ok
        if (ok) {
            te.SetTy(joinedTy)
            return joinedTy
        }
    }
    return TryInvalid(te)
}

private func ChkTryExprCatchesAndHandles(typeManager: TypeManager, target: Ty, te: TryExpr): Bool {
    var ok = ChkTryExprCatchPatterns(typeManager, te)
    for (catchBlock in te.catchBlocks) {
        ok = ChkBlock(typeManager, target, catchBlock) && ok
    }
    for (handler in te.handlers) {
        if (let Some(block) <- handler.block) {
            ok = ChkBlock(typeManager, target, block) && ok
        } else {
            ok = false
        }
        if (let Some(lambda) <- handler.desugaredLambda) {
            let handleTy = typeManager.GetFunctionTy([typeManager.GetAnyTy()], target)
            ok = ChkLamExpr(typeManager, handleTy, lambda) && ok
        }
    }
    return ok
}

public func ChkTryExpr(typeManager: TypeManager, target: Ty, te: TryExpr): Bool {
    if (!te.resourceSpec.isEmpty()) {
        let actualTy = SynTryWithResourcesExpr(typeManager, te)
        if (Ty.IsTyCorrect(actualTy) &&
            typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
            return true
        }
        let _ = TryInvalid(te)
        return false
    }
    var ok = true
    if (!te.handlers.isEmpty()) {
        let tryLambdaTy = typeManager.GetFunctionTy(Array<Ty>(), target)
        if (let Some(lambda) <- te.tryLambda) {
            ok = ChkLamExpr(typeManager, tryLambdaTy, lambda) && ok
        } else if (let Some(tryBlock) <- te.tryBlock) {
            ok = ChkBlock(typeManager, target, tryBlock) && ok
        } else {
            ok = false
        }
    } else if (let Some(tryBlock) <- te.tryBlock) {
        ok = ChkBlock(typeManager, target, tryBlock) && ok
    } else {
        ok = false
    }
    ok = ChkTryExprCatchesAndHandles(typeManager, target, te) && ok
    ok = ChkTryExprFinallyBlock(typeManager, te) && ok
    if (ok) {
        te.SetTy(target)
        return true
    }
    let _ = TryInvalid(te)
    return false
}
