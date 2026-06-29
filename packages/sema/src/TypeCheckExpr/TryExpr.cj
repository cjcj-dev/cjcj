package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.MakeRange as BasicMakeRange
import cangjie_compiler::sema.*

private let EFFECT_PACKAGE_NAME: String = "stdx.effect"
private let CORE_PACKAGE_NAME: String = "std.core"
private let COMMAND_TYPE_NAME: String = "Command"
private let RESOURCE_TYPE_NAME: String = "Resource"
private let CLASS_EXCEPTION_NAME: String = "Exception"
private let CLASS_ERROR_NAME: String = "Error"

private func TryInvalid(te: TryExpr): Ty {
    return TcInvalid(te)
}

private func JoinTryTy(typeManager: TypeManager, currentTy: Ty, branchTy: Ty, curFile: Option<File>): Ty {
    if (!Ty.IsTyCorrect(currentTy) || !Ty.IsTyCorrect(branchTy)) {
        return TypeManager.GetInvalidTy()
    }
    if (currentTy.IsNothing()) {
        return branchTy
    }
    if (branchTy.IsNothing()) {
        return currentTy
    }
    let tys = TySet()
    tys.Add(currentTy)
    tys.Add(branchTy)
    return JoinAsVisibleTy(typeManager, tys, curFile: curFile)
}

private func IsCommandTy(ty: Ty): Bool {
    if (ty.typeArgs.size != 1) {
        return false
    }
    if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
        if (!decl.fullPackageName.isEmpty()) {
            return decl.fullPackageName == EFFECT_PACKAGE_NAME && decl.identifier.Val() == COMMAND_TYPE_NAME
        }
    }
    return ty.name == COMMAND_TYPE_NAME
}

private func PromotedCommandTy(typeManager: TypeManager, ty: Ty): Option<Ty> {
    if (!Ty.IsTyCorrect(ty) || ty.IsNothing()) {
        return None
    }
    if (IsCommandTy(ty)) {
        return Some(ty)
    }
    if (let Some(genericTy) <- (ty as GenericsTy)) {
        for (upperTy in genericTy.upperBounds) {
            if (let Some(promotedUpper) <- PromotedCommandTy(typeManager, upperTy)) {
                return Some(promotedUpper)
            }
        }
    }
    for (superTy in typeManager.GetAllSuperTys(ty).values) {
        if (IsCommandTy(superTy)) {
            return Some(superTy)
        }
    }
    return None
}

private func CommandPayloadTy(typeManager: TypeManager, ty: Ty): Option<Ty> {
    if (let Some(commandTy) <- PromotedCommandTy(typeManager, ty)) {
        return Some(commandTy.typeArgs[0])
    }
    return None
}

private func IsCoreNamedTy(ty: Ty, name: String): Bool {
    if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
        if (!decl.fullPackageName.isEmpty()) {
            return decl.fullPackageName == CORE_PACKAGE_NAME && decl.identifier.Val() == name
        }
    }
    return ty.name == name
}

private func IsResourceTy(typeManager: TypeManager, ty: Ty): Bool {
    if (!Ty.IsTyCorrect(ty) || ty.IsNothing()) {
        return false
    }
    if (IsCoreNamedTy(ty, RESOURCE_TYPE_NAME)) {
        return true
    }
    if (let Some(genericTy) <- (ty as GenericsTy)) {
        for (upperTy in genericTy.upperBounds) {
            if (IsResourceTy(typeManager, upperTy)) {
                return true
            }
        }
    }
    for (superTy in typeManager.GetAllSuperTys(ty).values) {
        if (IsCoreNamedTy(superTy, RESOURCE_TYPE_NAME)) {
            return true
        }
    }
    return false
}

private func IsIncludedType(typeManager: TypeManager, included: ArrayList<Ty>, candidate: Ty): Bool {
    for (includedTy in included) {
        if (SameTy(candidate, includedTy) || typeManager.IsSubtype(candidate, includedTy)) {
            return true
        }
    }
    return false
}

private func AddIncludedType(typeManager: TypeManager, included: ArrayList<Ty>, candidate: Ty): Bool {
    if (IsIncludedType(typeManager, included, candidate)) {
        return true
    }
    included.add(candidate)
    return true
}

private func CheckCommandPattern(typeManager: TypeManager, handler: Handler, commandPattern: CommandTypePattern,
    included: ArrayList<Ty>): Bool {
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
    var ok = AddIncludedType(typeManager, included, commandTy)
    if (let Some(payloadTy) <- CommandPayloadTy(typeManager, commandTy)) {
        handler.commandResultTy = payloadTy
    } else {
        ok = false
    }
    if (let Some(innerPattern) <- commandPattern.pattern) {
        ok = TcPatternCheck(typeManager, commandTy, innerPattern) && ok
    }
    if (!ok) {
        commandPattern.SetTy(TypeManager.GetInvalidTy())
    }
    return ok
}

private func CheckWildcardCatchPattern(typeManager: TypeManager, pattern: WildcardPattern,
    included: ArrayList<Ty>): Bool {
    let wildcardTy = typeManager.GetAnyTy()
    pattern.SetTy(wildcardTy)
    if (!AddIncludedType(typeManager, included, wildcardTy)) {
        pattern.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    return true
}

private func IsThrowableCatchTy(typeManager: TypeManager, ty: Ty): Bool {
    if (!Ty.IsTyCorrect(ty) || ty.IsNothing()) {
        return false
    }
    if (IsCoreNamedTy(ty, CLASS_EXCEPTION_NAME) || IsCoreNamedTy(ty, CLASS_ERROR_NAME)) {
        return true
    }
    if (let Some(genericTy) <- (ty as GenericsTy)) {
        for (upperTy in genericTy.upperBounds) {
            if (IsThrowableCatchTy(typeManager, upperTy)) {
                return true
            }
        }
    }
    for (superTy in typeManager.GetAllSuperTys(ty).values) {
        if (IsCoreNamedTy(superTy, CLASS_EXCEPTION_NAME) || IsCoreNamedTy(superTy, CLASS_ERROR_NAME)) {
            return true
        }
    }
    return false
}

private func CheckExceptTypePattern(typeManager: TypeManager, exceptPattern: ExceptTypePattern,
    included: ArrayList<Ty>): Bool {
    var ok = true
    var joinedTy: Ty = TypeManager.GetNothingTy()
    for (typeNode in exceptPattern.types) {
        if (let Some(typeTy) <- typeNode.GetTy()) {
            if (IsThrowableCatchTy(typeManager, typeTy)) {
                if (AddIncludedType(typeManager, included, typeTy)) {
                    joinedTy = JoinTryTy(typeManager, joinedTy, typeTy, typeNode.curFile)
                    ok = Ty.IsTyCorrect(joinedTy) && ok
                } else {
                    ok = false
                }
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
    let includedCatchTys = ArrayList<Ty>()
    for (pattern in te.catchPatterns) {
        if (let Some(wildcardPattern) <- (pattern as WildcardPattern)) {
            ok = CheckWildcardCatchPattern(typeManager, wildcardPattern, includedCatchTys) && ok
        } else if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
            ok = CheckExceptTypePattern(typeManager, exceptPattern, includedCatchTys) && ok
        } else {
            pattern.SetTy(TypeManager.GetInvalidTy())
            ok = false
        }
    }
    let includedCommandTys = ArrayList<Ty>()
    for (handler in te.handlers) {
        if (let Some(commandPattern) <- handler.commandPattern) {
            if (let Some(commandTypePattern) <- (commandPattern as CommandTypePattern)) {
                ok = CheckCommandPattern(typeManager, handler, commandTypePattern, includedCommandTys) && ok
            } else {
                ok = false
            }
        } else {
            ok = false
        }
    }
    return ok
}

private func ValidateBlockInTryHandle(block: Block, diag!: Option<BasicDiagnosticEngine> = None): Bool {
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
            if (let Some(diagValue) <- diag) {
                let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_return_in_try_handle_block,
                    BasicMakeRange(node.begin, node.end))
                builder.Emit()
            }
            return VisitAction.STOP_NOW
        }
        VisitAction.WALK_CHILDREN
    })
    return walker.Walk() != VisitAction.STOP_NOW
}

private func ValidateHandler(handler: Handler, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let None <- handler.block) {
        return false
    }
    let block = handler.block.getOrThrow()
    if (!ValidateBlockInTryHandle(block, diag: diag)) {
        return false
    }
    if (let None <- handler.desugaredLambda) {
        return false
    }
    let bind = { node: Node =>
        if (let Some(resumeExpr) <- (node as ResumeExpr)) {
            resumeExpr.enclosing = handler
            return VisitAction.WALK_CHILDREN
        }
        if (let Some(_) <- (node as FuncBody)) {
            return VisitAction.SKIP_CHILDREN
        }
        VisitAction.WALK_CHILDREN
    }
    if (let Some(lambda) <- handler.desugaredLambda) {
        if (let Some(funcBody) <- lambda.funcBody) {
            if (let Some(body) <- funcBody.body) {
                let lambdaWalker = Walker(body, visitPre: bind)
                let _ = lambdaWalker.Walk()
            }
        }
    }
    if (let Some(blockValue) <- handler.block) {
        let blockWalker = Walker(blockValue, visitPre: bind)
        let _ = blockWalker.Walk()
    }
    return true
}

private func HandlerPatternTy(typeManager: TypeManager, handler: Handler): Ty {
    if (let Some(commandPattern) <- handler.commandPattern) {
        if (let Some(commandTypePattern) <- (commandPattern as CommandTypePattern)) {
            if (let Some(innerPattern) <- commandTypePattern.pattern) {
                if (let Some(patternTy) <- innerPattern.GetTy()) {
                    return patternTy
                }
            }
        }
        if (let Some(patternTy) <- commandPattern.GetTy()) {
            return patternTy
        }
    }
    return typeManager.GetAnyTy()
}

private func ChkTryExprFinallyBlock(typeManager: TypeManager, te: TryExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (let Some(finallyBlock) <- te.finallyBlock) {
        var isWellTyped = true
        if (te.isDesugaredFromSyncBlock) {
            try (ds = DiagSuppressor(diag)) {
                if (Ty.IsTyCorrect(SynBlock(typeManager, finallyBlock, pos: SynPos.UNUSED))) {
                    ds.ReportDiag()
                } else {
                    isWellTyped = false
                }
            }
        } else {
            isWellTyped = Ty.IsTyCorrect(SynBlock(typeManager, finallyBlock, pos: SynPos.UNUSED, diag: diag)) &&
                isWellTyped
            if (!te.handlers.isEmpty()) {
                if (let Some(finallyLambda) <- te.finallyLambda) {
                    let finallyLamTy = typeManager.GetFunctionTy(Array<Ty>(), TcUnitTy())
                    isWellTyped = ChkLamExpr(typeManager, finallyLamTy, finallyLambda) && isWellTyped
                }
            }
        }
        finallyBlock.SetTy(if (isWellTyped) { TcUnitTy() } else { TypeManager.GetInvalidTy() })
        return isWellTyped
    }
    return true
}

private func ChkResourceSpec(typeManager: TypeManager, resource: VarDecl): Bool {
    var ok = true
    var declaredTy: Option<Ty> = None
    if (let Some(typeNode) <- resource.typeNode) {
        if (let Some(typeTy) <- typeNode.GetTy()) {
            declaredTy = Some(typeTy)
            resource.SetTy(typeTy)
        } else {
            ok = false
        }
    }
    if (let Some(initializer) <- resource.initializer) {
        let initTy = if (let Some(existingTy) <- initializer.GetTy()) {
            if (Ty.IsTyCorrect(existingTy)) {
                existingTy
            } else {
                SynExprShallow(typeManager, initializer)
            }
        } else {
            SynExprShallow(typeManager, initializer)
        }
        if (Ty.IsTyCorrect(initTy)) {
            let concreteInitTy = TcReplaceIdeal(typeManager, initializer)
            if (let Some(targetTy) <- declaredTy) {
                if (typeManager.CheckTypeCompatibility(targetTy, concreteInitTy) == TypeCompatibility.INCOMPATIBLE) {
                    ok = false
                }
            } else {
                resource.SetTy(concreteInitTy)
            }
        } else {
            ok = false
        }
    }
    if (!Ty.IsTyCorrect(resource.GetTy())) {
        ok = false
    }
    if (ok) {
        if (let Some(resourceTy) <- resource.GetTy()) {
            ok = IsResourceTy(typeManager, resourceTy)
        } else {
            ok = false
        }
    }
    if (!ok) {
        resource.SetTy(TypeManager.GetInvalidTy())
    }
    return ok
}

private func SynTryWithResourcesExpr(typeManager: TypeManager, te: TryExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    var ok = true
    for (resource in te.resourceSpec) {
        ok = ChkResourceSpec(typeManager, resource) && ok
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
    ok = ChkTryExprFinallyBlock(typeManager, te, diag: diag) && ok
    if (ok) {
        let unitTy = TcUnitTy()
        te.SetTy(unitTy)
        return unitTy
    }
    return TryInvalid(te)
}

private func SynTryExprCatchesAndHandles(typeManager: TypeManager, te: TryExpr, baseTy: Ty,
    diag!: Option<BasicDiagnosticEngine> = None): Option<Ty> {
    var ok = ChkTryExprCatchPatterns(typeManager, te)
    var joinedTy = baseTy
    if (!te.handlers.isEmpty()) {
        if (let Some(tryBlock) <- te.tryBlock) {
            ok = ValidateBlockInTryHandle(tryBlock, diag: diag) && ok
        } else {
            ok = false
        }
    }
    for (catchBlock in te.catchBlocks) {
        if (!te.handlers.isEmpty()) {
            ok = ValidateBlockInTryHandle(catchBlock, diag: diag) && ok
        }
        let catchTy = SynBlock(typeManager, catchBlock)
        if (Ty.IsTyCorrect(catchTy)) {
            joinedTy = JoinTryTy(typeManager, joinedTy, catchTy, te.curFile)
            ok = Ty.IsTyCorrect(joinedTy) && ok
        } else {
            ok = false
        }
    }
    for (handler in te.handlers) {
        if (!ValidateHandler(handler, diag: diag)) {
            ok = false
        } else if (let Some(block) <- handler.block) {
            let handlerTy = SynBlock(typeManager, block)
            if (Ty.IsTyCorrect(handlerTy)) {
                joinedTy = JoinTryTy(typeManager, joinedTy, handlerTy, te.curFile)
                ok = Ty.IsTyCorrect(joinedTy) && ok
            } else {
                ok = false
            }
        } else {
            ok = false
        }
        if (let Some(lambda) <- handler.desugaredLambda) {
            let patternTy = HandlerPatternTy(typeManager, handler)
            let handleTy = typeManager.GetFunctionTy([patternTy], joinedTy)
            ok = ChkLamExpr(typeManager, handleTy, lambda) && ok
        }
    }
    if (ok) {
        return Some(joinedTy)
    }
    return None
}

public func SynTryExpr(typeManager: TypeManager, te: TryExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (!te.resourceSpec.isEmpty()) {
        return SynTryWithResourcesExpr(typeManager, te, diag: diag)
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
    if (let Some(joinedTy) <- SynTryExprCatchesAndHandles(typeManager, te, baseTy, diag: diag)) {
        ok = ChkTryExprFinallyBlock(typeManager, te, diag: diag) && ok
        if (ok) {
            te.SetTy(joinedTy)
            return joinedTy
        }
    }
    return TryInvalid(te)
}

private func ChkTryExprCatchesAndHandles(typeManager: TypeManager, target: Ty, te: TryExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    var ok = ChkTryExprCatchPatterns(typeManager, te)
    for (catchBlock in te.catchBlocks) {
        if (!te.handlers.isEmpty()) {
            ok = ValidateBlockInTryHandle(catchBlock, diag: diag) && ok
        }
        ok = ChkBlock(typeManager, target, catchBlock) && ok
    }
    for (handler in te.handlers) {
        if (!ValidateHandler(handler, diag: diag)) {
            ok = false
        } else if (let Some(block) <- handler.block) {
            ok = ChkBlock(typeManager, target, block) && ok
        } else {
            ok = false
        }
        if (let Some(lambda) <- handler.desugaredLambda) {
            let handleTy = typeManager.GetFunctionTy([HandlerPatternTy(typeManager, handler)], target)
            ok = ChkLamExpr(typeManager, handleTy, lambda) && ok
        }
    }
    return ok
}

public func ChkTryExpr(typeManager: TypeManager, target: Ty, te: TryExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (!te.resourceSpec.isEmpty()) {
        let actualTy = SynTryWithResourcesExpr(typeManager, te, diag: diag)
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
            ok = ValidateBlockInTryHandle(tryBlock, diag: diag) && ok
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
    ok = ChkTryExprCatchesAndHandles(typeManager, target, te, diag: diag) && ok
    ok = ChkTryExprFinallyBlock(typeManager, te, diag: diag) && ok
    if (ok) {
        te.SetTy(target)
        return true
    }
    let _ = TryInvalid(te)
    return false
}
