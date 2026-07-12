package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.MakeRange as BasicMakeRange
import cjcj::sema.*

private let CORE_PACKAGE_NAME: String = "std.core"
private let RESOURCE_TYPE_NAME: String = "Resource"

private func TryInvalid(te: TryExpr): Ty {
    return TcInvalid(te)
}
private func JoinTryTy(typeManager: TypeManager, currentTy: Ty, branchTy: Ty, curFile: Option<File>): ErrOrTy {
    if (!Ty.IsTyCorrect(currentTy) || !Ty.IsTyCorrect(branchTy)) {
        return ErrOrTy.TY(TypeManager.GetInvalidTy())
    }
    if (currentTy.IsNothing()) {
        return ErrOrTy.TY(branchTy)
    }
    if (branchTy.IsNothing()) {
        return ErrOrTy.TY(currentTy)
    }
    let tys = TySet()
    tys.Add(currentTy)
    tys.Add(branchTy)
    return JoinAsVisibleTy(typeManager, tys, curFile: curFile)
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

private func ChkTryWildcardPattern(target: Ty, pattern: WildcardPattern, included: ArrayList<Ty>,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    pattern.SetTy(target)
    if ((target as ClassTy).isSome()) {
        for (includedTy in included) {
            if (refEq(includedTy, target)) {
                if (let Some(diagValue) <- diag) {
                    let builder = diagValue.Diagnose(pattern.begin, pattern.end,
                        BasicDiagKind.sema_useless_exception_type)
                    builder.Emit()
                }
                break
            }
        }
    }
    return true
}

private func ChkExceptTypePattern(typeManager: TypeManager, exceptPattern: ExceptTypePattern,
    included: ArrayList<Ty>, exceptionTy: Option<Ty>, errorTy: Option<Ty>,
    diag!: Option<BasicDiagnosticEngine> = None,
    patternChecker!: Option<(Ty, Pattern) -> Bool> = None): Bool {
    var result = true
    let typeTys = ArrayList<Ty>()
    let foundClass = exceptionTy.isSome() && errorTy.isSome()
    for (typeNode in exceptPattern.types) {
        let typeTy = typeNode.GetTy() ?? TypeManager.GetInvalidTy()
        if (!foundClass || typeTy.IsNothing() ||
            !((if (let Some(coreExceptionTy) <- exceptionTy) {
                typeManager.IsSubtype(typeTy, coreExceptionTy)
            } else {
                false
            }) || (if (let Some(coreErrorTy) <- errorTy) {
                typeManager.IsSubtype(typeTy, coreErrorTy)
            } else {
                false
            }))) {
            if (let Some(diagValue) <- diag) {
                let builder = diagValue.Diagnose(typeNode.begin, typeNode.end,
                    BasicDiagKind.sema_except_catch_type_error)
                builder.Emit()
            }
            result = false
            continue
        }
        var includedBySubtype = false
        for (includedTy in included) {
            if (typeManager.IsSubtype(typeTy, includedTy)) {
                includedBySubtype = true
                break
            }
        }
        if (includedBySubtype) {
            if (let Some(diagValue2) <- diag) {
                let builder2 = diagValue2.Diagnose(typeNode.begin, typeNode.end,
                    BasicDiagKind.sema_useless_exception_type)
                builder2.Emit()
            }
        } else {
            included.add(typeTy)
        }
        var alreadyInTypeTys = false
        for (existingTy in typeTys) {
            if (refEq(existingTy, typeTy)) {
                alreadyInTypeTys = true
                break
            }
        }
        if (!alreadyInTypeTys) {
            typeTys.add(typeTy)
        }
    }
    if (!result || typeTys.isEmpty()) {
        exceptPattern.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    let typeTySet = TySet()
    for (typeTy2 in typeTys) {
        typeTySet.Add(typeTy2)
    }
    let joinRes = JoinAsVisibleTy(typeManager, typeTySet, curFile: exceptPattern.curFile)
    let (optErrs, joinedTy) = SetJoinedType(exceptPattern.GetTy().getOrThrow(), joinRes)
    exceptPattern.SetTy(joinedTy)
    if (let Some(errMsg) <- optErrs) {
        if (let Some(diagValue3) <- diag) {
            let builder3 = Diagnose(diagValue3, exceptPattern,
                BasicDiagKind.sema_type_incompatible, args: [BasicDiagArgument("pattern")])
            builder3.AddNote(errMsg)
            builder3.Emit()
        }
        return false
    }
    if (let Some(innerPattern) <- exceptPattern.pattern) {
        return patternChecker.getOrThrow()(joinedTy, innerPattern)
    }
    return true
}

private func ChkCommandTypePattern(typeManager: TypeManager, commandPattern: CommandTypePattern,
    included: ArrayList<Ty>, commandTy: Option<Ty>,
    diag!: Option<BasicDiagnosticEngine> = None): Option<Ty> {
    if (commandPattern.types.size != 1) {
        commandPattern.SetTy(TypeManager.GetInvalidTy())
        return None
    }
    if (let None <- commandTy) {
        if (let Some(diagValue) <- diag) {
            let builder = DiagnoseRefactor(diagValue, BasicDiagKindRefactor.sema_command_handle_type_error,
                commandPattern.types[0])
            builder.Emit()
        }
        return None
    }
    let cmdTypePat = commandPattern.types[0]
    let cmdTypePatTy = cmdTypePat.GetTy() ?? TypeManager.GetInvalidTy()
    let promotedTys = Promotion(typeManager).Promote(cmdTypePatTy, commandTy.getOrThrow())
    if (cmdTypePatTy.IsNothing() || promotedTys.IsEmpty()) {
        if (let Some(diagValue2) <- diag) {
            let builder2 = DiagnoseRefactor(diagValue2, BasicDiagKindRefactor.sema_command_handle_type_error,
                cmdTypePat)
            builder2.Emit()
        }
        commandPattern.SetTy(TypeManager.GetInvalidTy())
        return None
    }
    for (includedTy in included) {
        if (typeManager.IsSubtype(cmdTypePatTy, includedTy)) {
            if (let Some(diagValue3) <- diag) {
                let builder3 = DiagnoseRefactor(diagValue3, BasicDiagKindRefactor.sema_useless_command_type,
                    cmdTypePat)
                builder3.Emit()
            }
            commandPattern.SetTy(cmdTypePatTy)
            return Some(promotedTys.values[0])
        }
    }
    included.add(cmdTypePatTy)
    commandPattern.SetTy(cmdTypePatTy)
    return Some(promotedTys.values[0])
}

private func ChkHandlePatterns(typeManager: TypeManager, handler: Handler, included: ArrayList<Ty>,
    commandTy: Option<Ty>, diag!: Option<BasicDiagnosticEngine> = None,
    patternChecker!: Option<(Ty, Pattern) -> Bool> = None): Bool {
    if (let None <- handler.commandPattern) {
        return false
    }
    let commandPattern = handler.commandPattern.getOrThrow()
    if (let None <- (commandPattern as CommandTypePattern)) {
        return false
    }
    let commandTypePattern = (commandPattern as CommandTypePattern).getOrThrow()
    let maybeCommandTyAsCommand = ChkCommandTypePattern(typeManager, commandTypePattern, included, commandTy, diag: diag)
    if (let None <- maybeCommandTyAsCommand) {
        return false
    }
    let commandTyAsCommand = maybeCommandTyAsCommand.getOrThrow()
    if (commandTyAsCommand.typeArgs.isEmpty()) {
        return false
    }
    handler.commandResultTy = commandTyAsCommand.typeArgs[0]
    if (let Some(innerPattern) <- commandTypePattern.pattern) {
        let targetTy = commandTypePattern.GetTy() ?? TypeManager.GetInvalidTy()
        return patternChecker.getOrThrow()(targetTy, innerPattern)
    }
    return true
}

private func ChkTryExprCatchPatterns(typeManager: TypeManager, te: TryExpr,
    exceptionTy!: Option<Ty> = None, errorTy!: Option<Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None,
    patternChecker!: Option<(Ty, Pattern) -> Bool> = None): Bool {
    let includedCatchTys = ArrayList<Ty>()
    for (pattern in te.catchPatterns) {
        if (let Some(wildcardPattern) <- (pattern as WildcardPattern)) {
            if (let None <- exceptionTy) {
                return false
            }
            if (!ChkTryWildcardPattern(exceptionTy.getOrThrow(), wildcardPattern, includedCatchTys, diag: diag)) {
                return false
            }
            includedCatchTys.add(exceptionTy.getOrThrow())
        } else if (let Some(exceptPattern) <- (pattern as ExceptTypePattern)) {
            if (!ChkExceptTypePattern(typeManager, exceptPattern, includedCatchTys, exceptionTy, errorTy,
                diag: diag, patternChecker: patternChecker)) {
                return false
            }
        } else {
            pattern.SetTy(TypeManager.GetInvalidTy())
            return false
        }
    }
    return true
}

private func ChkTryExprHandlePatterns(typeManager: TypeManager, te: TryExpr, commandTy!: Option<Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None,
    patternChecker!: Option<(Ty, Pattern) -> Bool> = None): Bool {
    let includedCommandTys = ArrayList<Ty>()
    for (handler in te.handlers) {
        if (let Some(commandPattern) <- handler.commandPattern) {
            if (let Some(_) <- (commandPattern as CommandTypePattern)) {
                if (handler.desugaredLambda.isNone()) {
                    continue
                }
                if (!ChkHandlePatterns(typeManager, handler, includedCommandTys, commandTy,
                    diag: diag, patternChecker: patternChecker)) {
                    return false
                }
            } else {
                continue
            }
        } else {
            continue
        }
    }
    return true
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
                let builder = DiagnoseRefactor(diagValue, BasicDiagKindRefactor.sema_return_in_try_handle_block,
                    node)
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
    diag!: Option<BasicDiagnosticEngine> = None,
    synthesizer!: Option<(SynPos, Expr) -> Ty> = None,
    checker!: Option<(Ty, Expr) -> Bool> = None): Bool {
    if (let Some(finallyBlock) <- te.finallyBlock) {
        var isWellTyped = true
        if (te.isDesugaredFromSyncBlock) {
            try (ds = DiagSuppressor(diag)) {
                if (Ty.IsTyCorrect(synthesizer.getOrThrow()(SynPos.UNUSED, finallyBlock))) {
                    ds.ReportDiag()
                } else {
                    isWellTyped = false
                }
            }
        } else {
            isWellTyped = Ty.IsTyCorrect(synthesizer.getOrThrow()(SynPos.UNUSED, finallyBlock)) &&
                isWellTyped
            if (!te.handlers.isEmpty()) {
                if (let Some(finallyLambda) <- te.finallyLambda) {
                    let finallyLamTy = typeManager.GetFunctionTy(Array<Ty>(), TcUnitTy())
                    isWellTyped = checker.getOrThrow()(finallyLamTy, finallyLambda) && isWellTyped
                }
            }
        }
        finallyBlock.SetTy(if (isWellTyped) { TcUnitTy() } else { TypeManager.GetInvalidTy() })
        return isWellTyped
    }
    return true
}

private func SynthesizeAndReplaceIdealTy(typeManager: TypeManager, resource: VarDecl,
    synthesizer: (Expr) -> Ty): Bool {
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
                synthesizer(initializer)
            }
        } else {
            synthesizer(initializer)
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
    exceptionTy!: Option<Ty> = None, errorTy!: Option<Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None,
    patternChecker!: Option<(Ty, Pattern) -> Bool> = None,
    synthesizer!: Option<(SynPos, Expr) -> Ty> = None,
    checker!: Option<(Ty, Expr) -> Bool> = None): Ty {
    var ok = true
    for (resource in te.resourceSpec) {
        ok = SynthesizeAndReplaceIdealTy(typeManager, resource,
            { expr: Expr => synthesizer.getOrThrow()(SynPos.EXPR_ARG, expr) }) && ok
    }
    if (let Some(tryBlock) <- te.tryBlock) {
        ok = Ty.IsTyCorrect(synthesizer.getOrThrow()(SynPos.EXPR_ARG, tryBlock)) && ok
    } else {
        ok = false
    }
    ok = ChkTryExprCatchPatterns(typeManager, te, exceptionTy: exceptionTy, errorTy: errorTy,
        diag: diag, patternChecker: patternChecker) && ok
    for (catchBlock in te.catchBlocks) {
        ok = Ty.IsTyCorrect(synthesizer.getOrThrow()(SynPos.EXPR_ARG, catchBlock)) && ok
    }
    ok = ChkTryExprFinallyBlock(typeManager, te, diag: diag, synthesizer: synthesizer, checker: checker) && ok
    if (ok) {
        let unitTy = TcUnitTy()
        te.SetTy(unitTy)
        return unitTy
    }
    return TryInvalid(te)
}

private func SynTryExprCatchesAndHandles(typeManager: TypeManager, te: TryExpr, baseTy: Ty,
    exceptionTy!: Option<Ty> = None, errorTy!: Option<Ty> = None, commandTy!: Option<Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None,
    patternChecker!: Option<(Ty, Pattern) -> Bool> = None,
    synthesizer!: Option<(SynPos, Expr) -> Ty> = None,
    checker!: Option<(Ty, Expr) -> Bool> = None): Option<Ty> {
    var ok = ChkTryExprCatchPatterns(typeManager, te, exceptionTy: exceptionTy, errorTy: errorTy,
        diag: diag, patternChecker: patternChecker) &&
        ChkTryExprHandlePatterns(typeManager, te, commandTy: commandTy, diag: diag, patternChecker: patternChecker)
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
        let catchTy = synthesizer.getOrThrow()(SynPos.EXPR_ARG, catchBlock)
        if (Ty.IsTyCorrect(catchTy)) {
            let joinRes = JoinTryTy(typeManager, joinedTy, catchTy, te.curFile)
            let (optErrs, tmpJoinedTy) = SetJoinedType(joinedTy, joinRes)
            if (let Some(errMsg) <- optErrs) {
                ok = false
                if (te.ShouldDiagnose()) {
                    if (let Some(diagValue) <- diag) {
                        let builder = Diagnose(diagValue, catchBlock,
                            BasicDiagKind.sema_diag_report_error_message,
                            args: [BasicDiagArgument("The type of this catch block is '" +
                                Ty.ToString(Some(catchTy)) +
                                "', which mismatches the smallest common supertype '" + joinedTy.String() +
                                "' of previous branches.")])
                        AddNote(builder, te, errMsg)
                        builder.Emit()
                    }
                }
            } else {
                joinedTy = tmpJoinedTy
            }
        } else {
            ok = false
        }
    }
    for (handler in te.handlers) {
        if (!ValidateHandler(handler, diag: diag)) {
            ok = false
        } else if (let Some(block) <- handler.block) {
            let handlerTy = synthesizer.getOrThrow()(SynPos.EXPR_ARG, block)
            if (Ty.IsTyCorrect(handlerTy)) {
                let joinRes = JoinTryTy(typeManager, joinedTy, handlerTy, te.curFile)
                let (optErrs, tmpJoinedTy) = SetJoinedType(joinedTy, joinRes)
                if (let Some(errMsg) <- optErrs) {
                    ok = false
                    if (te.ShouldDiagnose()) {
                        if (let Some(diagValue) <- diag) {
                            let builder = DiagnoseRefactor(diagValue,
                                BasicDiagKindRefactor.sema_mismatching_handle_block, block,
                                Ty.ToString(Some(handlerTy)), joinedTy.String())
                            AddNote(builder, te, errMsg)
                            builder.Emit()
                        }
                    }
                } else {
                    joinedTy = tmpJoinedTy
                }
            } else {
                ok = false
            }
        } else {
            ok = false
        }
        if (let Some(lambda) <- handler.desugaredLambda) {
            let patternTy = HandlerPatternTy(typeManager, handler)
            let handleTy = typeManager.GetFunctionTy([patternTy], joinedTy)
            ok = checker.getOrThrow()(handleTy, lambda) && ok
        }
    }
    if (ok) {
        return Some(joinedTy)
    }
    return None
}

public func SynTryExpr(typeManager: TypeManager, te: TryExpr, diag: BasicDiagnosticEngine,
    exceptionTy!: Option<Ty> = None, errorTy!: Option<Ty> = None, commandTy!: Option<Ty> = None,
    patternChecker!: Option<(Ty, Pattern) -> Bool> = None,
    synthesizer!: Option<(SynPos, Expr) -> Ty> = None,
    checker!: Option<(Ty, Expr) -> Bool> = None): Ty {
    if (!te.resourceSpec.isEmpty()) {
        return SynTryWithResourcesExpr(typeManager, te, exceptionTy: exceptionTy, errorTy: errorTy,
            diag: Some(diag), patternChecker: patternChecker, synthesizer: synthesizer, checker: checker)
    }
    var ok = true
    var baseTy: Ty = TypeManager.GetNothingTy()
    if (!te.handlers.isEmpty() && (let Some(lambda) <- te.tryLambda)) {
        let lambdaTy = synthesizer.getOrThrow()(SynPos.EXPR_ARG, lambda)
        if (let Some(funcTy) <- (lambdaTy as FuncTy)) {
            baseTy = funcTy.retTy
        } else {
            ok = false
        }
    } else if (let Some(tryBlock) <- te.tryBlock) {
        baseTy = synthesizer.getOrThrow()(SynPos.EXPR_ARG, tryBlock)
        ok = Ty.IsTyCorrect(baseTy) && ok
    } else {
        ok = false
    }
    if (let Some(joinedTy) <- SynTryExprCatchesAndHandles(typeManager, te, baseTy, exceptionTy: exceptionTy,
        errorTy: errorTy, commandTy: commandTy, diag: Some(diag), patternChecker: patternChecker,
        synthesizer: synthesizer, checker: checker)) {
        ok = ChkTryExprFinallyBlock(typeManager, te, diag: Some(diag), synthesizer: synthesizer,
            checker: checker) && ok
        if (ok) {
            te.SetTy(joinedTy)
            return joinedTy
        }
    }
    return TryInvalid(te)
}

private func ChkTryExprCatchesAndHandles(typeManager: TypeManager, target: Ty, te: TryExpr,
    exceptionTy!: Option<Ty> = None, errorTy!: Option<Ty> = None, commandTy!: Option<Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None,
    patternChecker!: Option<(Ty, Pattern) -> Bool> = None,
    checker!: Option<(Ty, Expr) -> Bool> = None): Bool {
    var ok = ChkTryExprCatchPatterns(typeManager, te, exceptionTy: exceptionTy, errorTy: errorTy,
        diag: diag, patternChecker: patternChecker) &&
        ChkTryExprHandlePatterns(typeManager, te, commandTy: commandTy, diag: diag, patternChecker: patternChecker)
    for (catchBlock in te.catchBlocks) {
        if (!te.handlers.isEmpty()) {
            ok = ValidateBlockInTryHandle(catchBlock, diag: diag) && ok
        }
        ok = checker.getOrThrow()(target, catchBlock) && ok
    }
    for (handler in te.handlers) {
        if (!ValidateHandler(handler, diag: diag)) {
            ok = false
        } else if (let Some(block) <- handler.block) {
            ok = checker.getOrThrow()(target, block) && ok
        } else {
            ok = false
        }
        if (let Some(lambda) <- handler.desugaredLambda) {
            let handleTy = typeManager.GetFunctionTy([HandlerPatternTy(typeManager, handler)], target)
            ok = checker.getOrThrow()(handleTy, lambda) && ok
        }
    }
    return ok
}

public func ChkTryExpr(typeManager: TypeManager, target: Ty, te: TryExpr,
    exceptionTy!: Option<Ty> = None, errorTy!: Option<Ty> = None, commandTy!: Option<Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None,
    patternChecker!: Option<(Ty, Pattern) -> Bool> = None,
    synthesizer!: Option<(SynPos, Expr) -> Ty> = None,
    checker!: Option<(Ty, Expr) -> Bool> = None): Bool {
    if (!te.resourceSpec.isEmpty()) {
        let actualTy = SynTryWithResourcesExpr(typeManager, te, exceptionTy: exceptionTy, errorTy: errorTy,
            diag: diag, patternChecker: patternChecker, synthesizer: synthesizer, checker: checker)
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
            ok = checker.getOrThrow()(tryLambdaTy, lambda) && ok
        } else if (let Some(tryBlock) <- te.tryBlock) {
            ok = checker.getOrThrow()(target, tryBlock) && ok
        } else {
            ok = false
        }
    } else if (let Some(tryBlock) <- te.tryBlock) {
        ok = checker.getOrThrow()(target, tryBlock) && ok
    } else {
        ok = false
    }
    ok = ChkTryExprCatchesAndHandles(typeManager, target, te, exceptionTy: exceptionTy, errorTy: errorTy,
        commandTy: commandTy, diag: diag, patternChecker: patternChecker, checker: checker) && ok
    ok = ChkTryExprFinallyBlock(typeManager, te, diag: diag, synthesizer: synthesizer, checker: checker) && ok
    if (ok) {
        te.SetTy(target)
        return true
    }
    let _ = TryInvalid(te)
    return false
}
