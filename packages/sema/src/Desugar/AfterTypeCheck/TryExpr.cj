package cjcj::sema.Desugar.AfterTypeCheck

import std.collection.*
import cjcj::ast.*
import cjcj::sema.*

private let CLASS_EXCEPTION_NAME: String = "Exception"
private let CORE_PACKAGE: String = "std.core"
private let OPTION_TYPE_NAME: String = "Option"
private let OPTION_NONE: String = "None"
private let OPTION_SOME: String = "Some"
private let FRESH_EXCEPTION_NAME: String = "v-freshExc"
private let V_COMPILER_NAME: String = "v-compiler"
private let CLOSE_NAME: String = "close"
private let IS_CLOSED_NAME: String = "isClosed"

private func IsNamedDecl(decl: Decl, fullPackageName: String, name: String): Bool {
    return decl.identifier.Val() == name && (fullPackageName.isEmpty() || decl.fullPackageName == fullPackageName)
}

private func FindPackageDecl(pkg: Package, fullPackageName: String, name: String,
    context!: Option<ASTContext> = None): Option<Decl> {
    for (decl in pkg.srcImportedNonGenericDecls) {
        if (IsNamedDecl(decl, fullPackageName, name)) {
            return decl
        }
    }
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (IsNamedDecl(decl, fullPackageName, name)) {
                return decl
            }
        }
    }
    if (let Some(ctx) <- context) {
        if (let Some(packageMap) <- ctx.resolvedPackageMemberDeclsMap.get(fullPackageName)) {
            if (let Some(decls) <- packageMap.get(name)) {
                for (decl in decls) {
                    if (IsNamedDecl(decl, fullPackageName, name)) {
                        return decl
                    }
                }
            }
        }
        for (packageDecl in ctx.packageDecls) {
            if (packageDecl.fullPackageName == fullPackageName ||
                packageDecl.srcPackage.fullPackageName == fullPackageName) {
                for (file in packageDecl.srcPackage.files) {
                    for (decl in file.decls) {
                        if (IsNamedDecl(decl, fullPackageName, name)) {
                            return decl
                        }
                    }
                }
            }
        }
    }
    return None
}

private func FindCoreClassDecl(pkg: Package, name: String, context!: Option<ASTContext> = None): Option<ClassDecl> {
    if (let Some(decl) <- FindPackageDecl(pkg, CORE_PACKAGE, name, context: context)) {
        return decl as ClassDecl
    }
    return None
}

private func FindCoreEnumDecl(pkg: Package, name: String, context!: Option<ASTContext> = None): Option<EnumDecl> {
    if (let Some(decl) <- FindPackageDecl(pkg, CORE_PACKAGE, name, context: context)) {
        return decl as EnumDecl
    }
    return None
}

private func FuncRetTy(decl: Decl): Option<Ty> {
    if (let Some(declTy) <- decl.GetTy()) {
        if (let Some(funcTy) <- (declTy as FuncTy)) {
            return funcTy.retTy
        }
    }
    return None
}

private func AsFuncDecl(decl: Option<Decl>): Option<FuncDecl> {
    if (let Some(value) <- decl) {
        return value as FuncDecl
    }
    return None
}

private func RefTargetFunc(refExpr: RefExpr): Option<FuncDecl> {
    return AsFuncDecl(refExpr.ref.target)
}

private func CreateRefSome(someTy: FuncTy): Option<RefExpr> {
    if (let Some(enumTy) <- (someTy.retTy as EnumTy)) {
        if (let Some(enumDecl) <- enumTy.declPtr) {
            if (let Some(decl) <- LookupEnumMember(enumDecl, OPTION_SOME)) {
                let refExpr = CreateRefExpr(decl)
                refExpr.ref.targets.add(decl)
                refExpr.SetTy(someTy)
                for (typeArg in enumTy.typeArgs) {
                    refExpr.instTys.add(typeArg)
                }
                return refExpr
            }
        }
    }
    return None
}

private func CreateRefNone(enumTy: EnumTy): Option<RefExpr> {
    if (let Some(enumDecl) <- enumTy.declPtr) {
        if (let Some(decl) <- LookupEnumMember(enumDecl, OPTION_NONE)) {
            let refExpr = CreateRefExpr(decl)
            refExpr.SetTy(enumTy)
            for (typeArg in enumTy.typeArgs) {
                refExpr.instTys.add(typeArg)
            }
            return refExpr
        }
    }
    return None
}

private func CreateThrowExprFromPattern(pattern: VarPattern): ThrowExpr {
    let ret = ThrowExpr()
    if (let Some(varDecl) <- pattern.varDecl) {
        ret.expr = CreateRefExpr(varDecl)
    }
    ret.SetTy(TypeManager.GetNothingTy())
    return ret
}

private func CreateFreshExceptionMatch(someTy: FuncTy, freshExc: VarDecl, noneBody: Expr): Option<MatchExpr> {
    if (let Some(freshTy) <- freshExc.GetTy()) {
        if (let Some(enumTy) <- (freshTy as EnumTy)) {
            if (enumTy.typeArgs.size != 1) {
                return None
            }
            if (let Some(someRef) <- CreateRefSome(someTy)) {
                if (let Some(noneRef) <- CreateRefNone(enumTy)) {
                    let varPattern = CreateVarPattern(V_COMPILER_NAME, enumTy.typeArgs[0])
                    let somePattern = EnumPattern()
                    somePattern.constructor = someRef
                    somePattern.patterns.add(varPattern)
                    somePattern.SetTy(enumTy)
                    let caseSome = CreateMatchCase(somePattern, CreateThrowExprFromPattern(varPattern))

                    let nonePattern = EnumPattern()
                    nonePattern.constructor = noneRef
                    nonePattern.SetTy(enumTy)
                    let matchTy = noneBody.GetTy() ?? TypeManager.GetInvalidTy()
                    let caseNone = CreateMatchCase(nonePattern, noneBody)

                    let matchCases = ArrayList<MatchCase>()
                    matchCases.add(caseSome)
                    matchCases.add(caseNone)
                    let selector = CreateRefExpr(freshExc)
                    selector.SetTy(enumTy)
                    let matchExpr = CreateMatchExpr(selector, matchCases, matchTy)
                    AddCurFile(matchExpr, file: freshExc.curFile)
                    return matchExpr
                }
            }
        }
    }
    return None
}

private func CreateExceptionPattern(exceptionDecl: ClassDecl, pattern: VarPattern): ExceptTypePattern {
    let exceptTypePattern = ExceptTypePattern()
    exceptTypePattern.pattern = pattern
    let exceptionType = CreateRefType(exceptionDecl)
    exceptTypePattern.types.add(exceptionType)
    if (let Some(exceptionTy) <- exceptionDecl.GetTy()) {
        exceptTypePattern.SetTy(exceptionTy)
    }
    return exceptTypePattern
}

private func SelectZeroArgFunction(typeManager: TypeManager, resource: VarDecl, fieldName: String): Option<FuncDecl> {
    let resourceTy = resource.GetTy()
    let decls = FieldLookup(typeManager, Ty.GetDeclPtrOfTy(resourceTy), fieldName,
        info: LookupInfo(baseTy: resourceTy, file: resource.curFile))
    for (decl in decls) {
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(declTy) <- decl.GetTy()) {
                if (let Some(funcTy) <- (declTy as FuncTy)) {
                    if (funcTy.paramTys.isEmpty()) {
                        return funcDecl
                    }
                }
            }
        }
    }
    return None
}

private func CopyResourceSource(resource: VarDecl, target: Node): Unit {
    if (let Some(initializer) <- resource.initializer) {
        CopyBasicInfo(initializer, target)
    } else {
        CopyBasicInfo(resource, target)
    }
}

private func CreateResourceCall(resource: VarDecl, funcDecl: FuncDecl): CallExpr {
    let baseFunc = CreateMemberAccess(CreateRefExpr(resource), funcDecl)
    baseFunc.targets.add(funcDecl)
    if (let Some(baseExpr) <- baseFunc.baseExpr) {
        CopyResourceSource(resource, baseExpr)
    }
    CopyResourceSource(resource, baseFunc)
    let callExpr = CreateCallExpr(baseFunc, ArrayList<FuncArg>(), Some(funcDecl), FuncRetTy(funcDecl),
        CallKind.CALL_DECLARED_FUNCTION)
    CopyBasicInfo(resource, callExpr)
    if (let Some(retTy) <- FuncRetTy(funcDecl)) {
        callExpr.SetTy(retTy)
    }
    AddCurFile(callExpr, file: resource.curFile)
    return callExpr
}

private func CreateTryInFinally(typeManager: TypeManager, exceptionDecl: ClassDecl, someTy: FuncTy,
    resource: VarDecl, freshExc: VarDecl): Option<TryExpr> {
    if (let Some(freshTy) <- freshExc.GetTy()) {
        if (freshTy.typeArgs.size != 1) {
            return None
        }
        if (let Some(closeFunc) <- SelectZeroArgFunction(typeManager, resource, CLOSE_NAME)) {
            if (let Some(isClosedFunc) <- SelectZeroArgFunction(typeManager, resource, IS_CLOSED_NAME)) {
                let catchPattern = CreateVarPattern(V_COMPILER_NAME, freshTy.typeArgs[0])
                let closeNodes = ArrayList<Node>()
                closeNodes.add(CreateResourceCall(resource, closeFunc))
                let thenBlock = CreateBlock(closeNodes, Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
                let notClosed = CreateUnaryExpr(CreateResourceCall(resource, isClosedFunc), TokenKind.NOT)
                notClosed.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN))
                let ifExpr = CreateIfExpr(notClosed, thenBlock)
                ifExpr.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))

                if (let Some(matchExpr) <- CreateFreshExceptionMatch(someTy, freshExc,
                    CreateThrowExprFromPattern(catchPattern))) {
                    let tryNodes = ArrayList<Node>()
                    tryNodes.add(ifExpr)
                    let catchNodes = ArrayList<Node>()
                    catchNodes.add(matchExpr)
                    let tryExpr = TryExpr()
                    tryExpr.tryBlock = CreateBlock(tryNodes, Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
                    tryExpr.catchPatterns.add(CreateExceptionPattern(exceptionDecl, catchPattern))
                    tryExpr.catchBlocks.add(CreateBlock(catchNodes, Some(TypeManager.GetNothingTy())))
                    tryExpr.isDesugaredFromTryWithResources = true
                    CopyBasicInfo(resource, tryExpr)
                    tryExpr.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
                    AddCurFile(tryExpr, file: resource.curFile)
                    return tryExpr
                }
            }
        }
    }
    return None
}

private func CreateTryCatchFinally(typeManager: TypeManager, exceptionDecl: ClassDecl, someTy: FuncTy,
    resource: VarDecl, freshExc: VarDecl, tryBlock: Block): Option<TryExpr> {
    if (let Some(freshTy) <- freshExc.GetTy()) {
        if (freshTy.typeArgs.size != 1) {
            return None
        }
        let catchPattern = CreateVarPattern(V_COMPILER_NAME, freshTy.typeArgs[0])
        if (let Some(catchVar) <- catchPattern.varDecl) {
            if (let Some(someRef) <- CreateRefSome(someTy)) {
                let args = ArrayList<FuncArg>()
                args.add(CreateFuncArg(CreateRefExpr(catchVar)))
                let someCall = CreateCallExpr(someRef, args, RefTargetFunc(someRef), Some(someTy.retTy),
                    CallKind.CALL_DECLARED_FUNCTION)
                someCall.SetTy(someTy.retTy)
                let assignExpr = CreateAssignExpr(CreateRefExpr(freshExc), someCall,
                    Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
                assignExpr.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))

                if (let Some(tryInFinally) <- CreateTryInFinally(typeManager, exceptionDecl, someTy,
                    resource, freshExc)) {
                    if (let Some(matchExpr) <- CreateFreshExceptionMatch(someTy, freshExc,
                        CreateUnitExpr(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))) {
                        let catchNodes = ArrayList<Node>()
                        catchNodes.add(assignExpr)
                        let finallyNodes = ArrayList<Node>()
                        finallyNodes.add(tryInFinally)
                        finallyNodes.add(matchExpr)
                        let tryExpr = TryExpr()
                        CopyBasicInfo(tryBlock, tryExpr)
                        tryExpr.tryBlock = tryBlock
                        tryExpr.catchPatterns.add(CreateExceptionPattern(exceptionDecl, catchPattern))
                        tryExpr.catchBlocks.add(CreateBlock(catchNodes, Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))))
                        tryExpr.finallyBlock = CreateBlock(finallyNodes, Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
                        tryExpr.isDesugaredFromTryWithResources = true
                        tryExpr.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
                        AddCurFile(tryExpr, file: resource.curFile)
                        return tryExpr
                    }
                }
            }
        }
    }
    return None
}

private func CreateFreshExceptionVar(resource: VarDecl, noneTy: EnumTy): Option<VarDecl> {
    if (let Some(noneRef) <- CreateRefNone(noneTy)) {
        let freshExc = CreateVarDecl(FRESH_EXCEPTION_NAME, noneRef, None)
        CopyBasicInfo(resource, freshExc)
        freshExc.isVar = true
        freshExc.curFile = resource.curFile
        freshExc.SetTy(noneTy)
        return freshExc
    }
    return None
}

private func CreateOuterTryBlock(typeManager: TypeManager, exceptionDecl: ClassDecl, someTy: FuncTy,
    noneTy: EnumTy, resourceSpec: ArrayList<VarDecl>, block: Block): Option<Block> {
    var tryBlock = block
    var idx = resourceSpec.size - 1
    while (idx >= 0) {
        let resource = resourceSpec[idx]
        if (let Some(freshExc) <- CreateFreshExceptionVar(resource, noneTy)) {
            if (let Some(tryCatchFinally) <- CreateTryCatchFinally(typeManager, exceptionDecl, someTy,
                resource, freshExc, tryBlock)) {
                let tryBlockNodes = ArrayList<Node>()
                tryBlockNodes.add(freshExc)
                tryBlockNodes.add(resource)
                tryBlockNodes.add(tryCatchFinally)
                tryBlock = CreateBlock(tryBlockNodes, Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
                CopyBasicInfo(resource, tryBlock)
                tryBlock.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
            } else {
                return None
            }
        } else {
            return None
        }
        idx--
    }
    return tryBlock
}

private func AddUnitIfNeeded(typeManager: TypeManager, source: Expr, block: Block): Unit {
    let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
    let blockTy = block.GetTy() ?? TypeManager.GetInvalidTy()
    if (!typeManager.IsSubtype(blockTy, unitTy)) {
        UnitifyBlock(source, block, unitTy)
    }
}

public func DesugarTryWithResourcesExpr(typeManager: TypeManager, pkg: Package, tryExpr: TryExpr,
    context!: Option<ASTContext> = None,
    synthesizer!: Option<(ASTContext, SynPos, Node) -> Ty> = None): Unit {
    if (tryExpr.resourceSpec.isEmpty() || !Ty.IsTyCorrect(tryExpr.GetTy())) {
        return
    }
    if (let Some(_) <- tryExpr.desugarExpr) {
        return
    }
    if (let None <- tryExpr.tryBlock) {
        return
    }
    if (let None <- FindCoreClassDecl(pkg, CLASS_EXCEPTION_NAME, context: context)) {
        return
    }
    if (let None <- FindCoreEnumDecl(pkg, OPTION_TYPE_NAME, context: context)) {
        return
    }

    let exceptionDecl = FindCoreClassDecl(pkg, CLASS_EXCEPTION_NAME, context: context).getOrThrow()
    let optionDecl = FindCoreEnumDecl(pkg, OPTION_TYPE_NAME, context: context).getOrThrow()
    if (let None <- exceptionDecl.GetTy()) {
        return
    }
    let exceptionTy = exceptionDecl.GetTy().getOrThrow()
    let noneTy = typeManager.GetEnumTy(optionDecl, typeArgs: [exceptionTy])
    let someTy = typeManager.GetFunctionTy([exceptionTy], noneTy)
    let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
    let originalTryBlock = tryExpr.tryBlock.getOrThrow()
    AddUnitIfNeeded(typeManager, tryExpr, originalTryBlock)
    if (let Some(tryBlock) <- CreateOuterTryBlock(typeManager, exceptionDecl, someTy, noneTy,
        tryExpr.resourceSpec, originalTryBlock)) {
        if (let Some(ctx) <- context) {
            if (let Some(synthesize) <- synthesizer) {
                let synTy = synthesize(ctx, SynPos.EXPR_ARG, tryBlock)
                if (Ty.IsTyCorrect(Some(synTy))) {
                    tryBlock.SetTy(synTy)
                }
            }
        }
        tryBlock.SetTy(unitTy)
        for (catchBlock in tryExpr.catchBlocks) {
            AddUnitIfNeeded(typeManager, tryExpr, catchBlock)
        }
        var hasFinallyBlock = false
        if (let Some(_) <- tryExpr.finallyBlock) {
            hasFinallyBlock = true
        }
        let emptyCatchAndFinally = tryExpr.catchBlocks.isEmpty() && !hasFinallyBlock
        let desugaredTry = TryExpr()
        desugaredTry.tryBlock = tryBlock
        for (catchPattern in tryExpr.catchPatterns) {
            desugaredTry.catchPatterns.add(catchPattern)
        }
        for (catchBlock in tryExpr.catchBlocks) {
            desugaredTry.catchBlocks.add(catchBlock)
        }
        if (emptyCatchAndFinally) {
            desugaredTry.finallyBlock = CreateBlock(ArrayList<Node>(), Some(unitTy))
        } else if (let Some(finallyBlock) <- tryExpr.finallyBlock) {
            desugaredTry.finallyBlock = finallyBlock
        }
        desugaredTry.isDesugaredFromTryWithResources = true
        CopyBasicInfo(tryExpr, desugaredTry)
        desugaredTry.SetTy(unitTy)
        AddCurFile(desugaredTry, file: tryExpr.curFile)
        tryExpr.desugarExpr = desugaredTry
        tryExpr.resourceSpec.clear()
        tryExpr.catchPatterns.clear()
        tryExpr.catchBlocks.clear()
        tryExpr.tryBlock = None
        tryExpr.finallyBlock = None
    }
}
