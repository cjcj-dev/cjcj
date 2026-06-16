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

private func CommandPayloadTy(ty: Ty): Option<Ty> {
    if (ty.name == "Command" && ty.typeArgs.size == 1) {
        return ty.typeArgs[0]
    }
    if (ty.typeArgs.size == 1) {
        return ty.typeArgs[0]
    }
    return None
}

private func CheckCommandPattern(typeManager: TypeManager, handler: Handler, commandPattern: CommandTypePattern): Bool {
    if (commandPattern.types.size != 1) {
        commandPattern.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (let None <- commandPattern.types[0].GetTy()) {
        commandPattern.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let commandTy = commandPattern.types[0].GetTy().getOrThrow()
    commandPattern.SetTy(commandTy)
    if (let Some(payloadTy) <- CommandPayloadTy(commandTy)) {
        handler.commandResultTy = payloadTy
    }
    if (let Some(innerPattern) <- commandPattern.pattern) {
        return TcPatternCheck(typeManager, commandTy, innerPattern)
    }
    return true
}

private func CheckWildcardCatchPattern(typeManager: TypeManager, pattern: WildcardPattern): Bool {
    pattern.SetTy(typeManager.GetAnyTy())
    return true
}

private func IsCatchableExceptionTy(ty: Ty): Bool {
    return !ty.IsNothing() && (ty.IsClassLike() || ty.IsGeneric() || ty.IsAny())
}

private func CheckExceptTypePattern(typeManager: TypeManager, exceptPattern: ExceptTypePattern): Bool {
    var ok = true
    var joinedTy: Ty = TypeManager.GetNothingTy()
    for (typeNode in exceptPattern.types) {
        if (let Some(typeTy) <- typeNode.GetTy()) {
            if (Ty.IsTyCorrect(typeTy) && IsCatchableExceptionTy(typeTy)) {
                joinedTy = JoinTryTy(typeManager, joinedTy, typeTy)
                ok = Ty.IsTyCorrect(joinedTy) && ok
            } else {
                ok = false
            }
        } else {
            ok = false
        }
    }
    if (!ok || exceptPattern.types.isEmpty()) {
        exceptPattern.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    exceptPattern.SetTy(joinedTy)
    if (let Some(innerPattern) <- exceptPattern.pattern) {
        ok = TcPatternCheck(typeManager, joinedTy, innerPattern) && ok
    }
    if (!ok) {
        exceptPattern.SetTy(TypeManager.GetInvalidTy())
    }
    return ok
}

private func ChkTryExprCatchPatterns(typeManager: TypeManager, te: TryExpr): Bool {
    var ok = true
    for (pattern in te.catchPatterns) {
        if (let Some(wildcardPattern) <- (pattern as WildcardPattern)) {
            ok = CheckWildcardCatchPattern(typeManager, wildcardPattern) && ok
        } else if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
            ok = CheckExceptTypePattern(typeManager, exceptPattern) && ok
        } else {
            pattern.SetTy(TypeManager.GetInvalidTy())
            ok = false
        }
    }
    for (handler in te.handlers) {
        if (let Some(commandPattern) <- handler.commandPattern) {
            if (let Some(commandTypePattern) <- (commandPattern as CommandTypePattern)) {
                ok = CheckCommandPattern(typeManager, handler, commandTypePattern) && ok
            } else {
                ok = false
            }
        } else {
            ok = false
        }
    }
    return ok
}

private class TryHandleValidationState {
    public var hasReturn: Bool = false
    public init() {}
}

private class TryHandleResumeBinder {
    private let handler: Handler

    public init(handler: Handler) {
        this.handler = handler
    }

    public func Visit(node: Node): VisitAction {
        if (let Some(resumeExpr) <- (node as ResumeExpr)) {
            resumeExpr.enclosing = handler
            return VisitAction.WALK_CHILDREN
        }
        if (let Some(_) <- (node as FuncBody)) {
            return VisitAction.SKIP_CHILDREN
        }
        return VisitAction.WALK_CHILDREN
    }
}

private func ValidateBlockInTryHandle(block: Block): Bool {
    let state = TryHandleValidationState()
    let walker = Walker(block, visitPre: { node: Node =>
        if (let Some(_) <- (node as FuncBody)) {
            return VisitAction.SKIP_CHILDREN
        }
        if (let Some(tryExpr) <- (node as TryExpr)) {
            return if (tryExpr.handlers.isEmpty()) {
                VisitAction.WALK_CHILDREN
            } else {
                VisitAction.SKIP_CHILDREN
            }
        }
        if (let Some(_) <- (node as ReturnExpr)) {
            state.hasReturn = true
            return VisitAction.STOP_NOW
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
    return !state.hasReturn
}

private func BindResumeInTryHandle(handler: Handler): Unit {
    let binder = TryHandleResumeBinder(handler)
    if (let Some(lambda) <- handler.desugaredLambda) {
        if (let Some(funcBody) <- lambda.funcBody) {
            if (let Some(body) <- funcBody.body) {
                let lambdaWalker = Walker(body, visitPre: { node: Node => binder.Visit(node) })
                let _ = lambdaWalker.Walk()
            }
        }
    }
    if (let Some(block) <- handler.block) {
        let blockWalker = Walker(block, visitPre: { node: Node => binder.Visit(node) })
        let _ = blockWalker.Walk()
    }
}

private func ValidateHandler(handler: Handler): Bool {
    if (let None <- handler.block) {
        return false
    }
    let block = handler.block.getOrThrow()
    if (!ValidateBlockInTryHandle(block)) {
        return false
    }
    if (let None <- handler.desugaredLambda) {
        return false
    }
    BindResumeInTryHandle(handler)
    return true
}

private func HandlerCommandTy(typeManager: TypeManager, handler: Handler): Ty {
    if (let Some(commandPattern) <- handler.commandPattern) {
        if (let Some(commandTy) <- commandPattern.GetTy()) {
            return commandTy
        }
    }
    return typeManager.GetAnyTy()
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
    if (!te.handlers.isEmpty()) {
        if (let Some(tryBlock) <- te.tryBlock) {
            ok = ValidateBlockInTryHandle(tryBlock) && ok
        } else {
            ok = false
        }
    }
    for (catchBlock in te.catchBlocks) {
        if (!te.handlers.isEmpty()) {
            ok = ValidateBlockInTryHandle(catchBlock) && ok
        }
        let catchTy = SynBlock(typeManager, catchBlock)
        if (Ty.IsTyCorrect(catchTy)) {
            joinedTy = JoinTryTy(typeManager, joinedTy, catchTy)
            ok = Ty.IsTyCorrect(joinedTy) && ok
        } else {
            ok = false
        }
    }
    for (handler in te.handlers) {
        if (!ValidateHandler(handler)) {
            ok = false
        } else if (let Some(block) <- handler.block) {
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
            let commandTy = HandlerCommandTy(typeManager, handler)
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
        if (!te.handlers.isEmpty()) {
            ok = ValidateBlockInTryHandle(catchBlock) && ok
        }
        ok = ChkBlock(typeManager, target, catchBlock) && ok
    }
    for (handler in te.handlers) {
        if (!ValidateHandler(handler)) {
            ok = false
        } else if (let Some(block) <- handler.block) {
            ok = ChkBlock(typeManager, target, block) && ok
        } else {
            ok = false
        }
        if (let Some(lambda) <- handler.desugaredLambda) {
            let handleTy = typeManager.GetFunctionTy([HandlerCommandTy(typeManager, handler)], target)
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
        if (let Some(tryBlock) <- te.tryBlock) {
            ok = ValidateBlockInTryHandle(tryBlock) && ok
        }
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
