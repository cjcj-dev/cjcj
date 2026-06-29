package cangjie_compiler::sema.Desugar

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.Plugin.*
import cangjie_compiler::utils.CJC_ASSERT

private let V_COMPILER: String = "v-compiler"
private let OPTION_VALUE_CTOR: String = "Some"
private let OPTION_NONE_CTOR: String = "None"
private let STD_LIB_OPTION: String = "Option"

private func CloneExpr(expr: Expr): Option<Expr> {
    return ASTCloner.Clone(expr) as Expr
}

private func CloneType(typeNode: Type): Option<Type> {
    return ASTCloner.Clone(typeNode) as Type
}

private func IsUnitExpr(node: Node): Bool {
    if (let Some(lit) <- (node as LitConstExpr)) {
        return lit.kind == LitConstKind.UNIT
    }
    return false
}

private func IsNothingExpr(node: Node): Bool {
    return node.astKind == ASTKind.JUMP_EXPR || node.astKind == ASTKind.THROW_EXPR ||
        node.astKind == ASTKind.RETURN_EXPR
}

private func UnitifyBlock(block: Block): Unit {
    if (block.body.isEmpty()) {
        block.body.add(CreateUnitExpr())
        return
    }
    let last = block.body[block.body.size - 1]
    if (!IsUnitExpr(last) && !IsNothingExpr(last)) {
        block.body.add(CreateUnitExpr())
    }
}

private func UnitifyBranchExpr(node: Node): Unit {
    if (let Some(ifExpr) <- (node as IfExpr)) {
        if (let Some(elseExpr) <- ifExpr.elseBody) {
            if (let Some(thenBody) <- ifExpr.thenBody) {
                UnitifyBlock(thenBody)
                if (let Some(elseBlock) <- (elseExpr as Block)) {
                    UnitifyBlock(elseBlock)
                }
            }
        }
    } else if (let Some(tryExpr) <- (node as TryExpr)) {
        if (let Some(tryLambda) <- tryExpr.tryLambda) {
            if (let Some(funcBody) <- tryLambda.funcBody) {
                if (let Some(body) <- funcBody.body) {
                    UnitifyBlock(body)
                }
            }
        } else if (let Some(tryBlock) <- tryExpr.tryBlock) {
            UnitifyBlock(tryBlock)
        }
        for (catchBlock in tryExpr.catchBlocks) {
            UnitifyBlock(catchBlock)
        }
        for (handler in tryExpr.handlers) {
            if (let Some(block) <- handler.block) {
                UnitifyBlock(block)
            }
            if (let Some(lambda) <- handler.desugaredLambda) {
                if (let Some(funcBody) <- lambda.funcBody) {
                    if (let Some(body) <- funcBody.body) {
                        UnitifyBlock(body)
                    }
                }
            }
        }
    } else if (let Some(matchExpr) <- (node as MatchExpr)) {
        for (matchCase in matchExpr.matchCases) {
            if (let Some(block) <- matchCase.exprOrDecls) {
                UnitifyBlock(block)
            }
        }
        for (matchCaseOther in matchExpr.matchCaseOthers) {
            if (let Some(block) <- matchCaseOther.exprOrDecls) {
                UnitifyBlock(block)
            }
        }
    }
}

private let LEVEL_IDENTIFIER: String = "level"
private let SYSCAP_IDENTIFIER: String = "syscap"
private let DEVICE_INFO: String = "DeviceInfo"
private let SDK_API_VERSION: String = "sdkApiVersion"
private let API_AVAILABLE: String = "apiAvailable"
private let CANIUSE_IDENTIFIER: String = "canIUse"
private let IFAVAILABLE_RUNTIME_APILEVEL_MAJOR: UInt32 = 26u32

private func ParseCompatibleSDKVersion(value: String): APILevelVersion {
    if (let Some(version) <- APILevelVersion.ParseChecked(value, APILevelParseRule.MAJOR_OR_TRIPLE)) {
        return version
    }
    return APILevelVersion()
}

private func CreateSDKApiVersionCheck(iae: IfAvailableExpr, levelExpr: Expr, levelExprBase: Expr): Expr {
    let memberAccess = CreateMemberAccess(CreateRefExpr(DEVICE_INFO), SDK_API_VERSION)
    if (let Some(baseExpr) <- memberAccess.baseExpr) {
        CopyBasicInfo(iae, baseExpr)
    }
    let condition = CreateBinaryExpr(memberAccess, levelExpr, TokenKind.GE)
    if (let Some(rightExpr) <- condition.rightExpr) {
        CopyBasicInfo(levelExprBase, rightExpr)
    }
    if (let Some(leftExpr) <- condition.leftExpr) {
        CopyBasicInfo(iae, leftExpr)
    }
    AddCurFile(condition, file: iae.curFile)
    CopyBasicInfo(iae, condition)
    return condition
}

private func CreateApiAvailableCheck(iae: IfAvailableExpr, levelExpr: Expr): Expr {
    let apiAvailableRef = CreateRefExpr(API_AVAILABLE)
    CopyBasicInfo(iae, apiAvailableRef)
    let args = ArrayList<FuncArg>()
    args.add(CreateFuncArg(levelExpr))
    let condition = CreateCallExpr(apiAvailableRef, args)
    AddCurFile(condition, file: iae.curFile)
    CopyBasicInfo(iae, condition)
    return condition
}

private func DesugarIfAvailableLevelCondition(iae: IfAvailableExpr, compatibleSDKVersion: String): Expr {
    let compatibleLevel = ParseCompatibleSDKVersion(compatibleSDKVersion)
    let runtimeLevel = APILevelVersion(IFAVAILABLE_RUNTIME_APILEVEL_MAJOR)
    if (let Some(arg) <- iae.GetArg()) {
        if (let Some(argExpr) <- arg.expr) {
            if (let Some(lit) <- (argExpr as LitConstExpr)) {
                if (lit.kind == LitConstKind.INTEGER) {
                    if (compatibleLevel >= runtimeLevel) {
                        if (let Some(cloned) <- CloneExpr(argExpr)) {
                            return CreateApiAvailableCheck(iae, cloned)
                        }
                    } else if (let Some(clonedLevel) <- CloneExpr(argExpr)) {
                        return CreateSDKApiVersionCheck(iae, clonedLevel, lit)
                    }
                } else if (lit.kind == LitConstKind.STRING) {
                    if (compatibleLevel >= runtimeLevel) {
                        if (let Some(clonedString) <- CloneExpr(argExpr)) {
                            return CreateApiAvailableCheck(iae, clonedString)
                        }
                    } else if (let Some(parsedLevel) <-
                        APILevelVersion.ParseChecked(lit.stringValue, APILevelParseRule.TRIPLE_ONLY)) {
                        if (parsedLevel.major < IFAVAILABLE_RUNTIME_APILEVEL_MAJOR) {
                            let majorExpr = CreateLitConstExpr(LitConstKind.INTEGER,
                                "${parsedLevel.major}", Ty.GetInitialTy())
                            CopyBasicInfo(lit, majorExpr)
                            return CreateSDKApiVersionCheck(iae, majorExpr, lit)
                        }
                        let majorGate = CreateLitConstExpr(LitConstKind.INTEGER,
                            "${IFAVAILABLE_RUNTIME_APILEVEL_MAJOR}", Ty.GetInitialTy())
                        CopyBasicInfo(lit, majorGate)
                        let majorCondition = CreateSDKApiVersionCheck(iae, majorGate, lit)
                        if (let Some(runtimeArg) <- CloneExpr(argExpr)) {
                            let runtimeCondition = CreateApiAvailableCheck(iae, runtimeArg)
                            let condition = CreateBinaryExpr(majorCondition, runtimeCondition, TokenKind.AND)
                            AddCurFile(condition, file: iae.curFile)
                            CopyBasicInfo(iae, condition)
                            return condition
                        }
                    }
                }
            }
            if (let Some(clonedRaw) <- CloneExpr(argExpr)) {
                return clonedRaw
            }
        }
    }
    return InvalidExpr()
}

private func DesugarIfAvailableSyscapCondition(iae: IfAvailableExpr): Expr {
    let canIUseRef = CreateRefExpr(CANIUSE_IDENTIFIER)
    CopyBasicInfo(iae, canIUseRef)
    let args = ArrayList<FuncArg>()
    CJC_ASSERT(iae.GetArg().isSome())
    let arg = iae.GetArg().getOrThrow()
    CJC_ASSERT(arg.expr.isSome())
    let argExpr = arg.expr.getOrThrow()
    arg.expr = None
    args.add(CreateFuncArg(argExpr))
    let condition = CreateCallExpr(canIUseRef, args)
    AddCurFile(condition, file: iae.curFile)
    CopyBasicInfo(iae, condition)
    return condition
}

private func DesugarIfAvailableCondition(iae: IfAvailableExpr, compatibleSDKVersion: String): Expr {
    if (let Some(arg) <- iae.GetArg()) {
        let name = arg.name.Val()
        if (name == LEVEL_IDENTIFIER) {
            return DesugarIfAvailableLevelCondition(iae, compatibleSDKVersion)
        }
        if (name == SYSCAP_IDENTIFIER) {
            return DesugarIfAvailableSyscapCondition(iae)
        }
    }
    return InvalidExpr()
}

private func CloneLambdaBody(lambda: LambdaExpr): Option<Block> {
    if (let Some(funcBody) <- lambda.funcBody) {
        if (let Some(body) <- funcBody.body) {
            return ASTCloner.Clone(body) as Block
        }
    }
    return None
}

private func DesugarIfAvailableExpr(iae: IfAvailableExpr, compatibleSDKVersion: String): Unit {
    if (let Some(_) <- iae.desugarExpr) {
        return
    }
    if (let Some(lambda1) <- iae.GetLambda1()) {
        if (let Some(lambda2) <- iae.GetLambda2()) {
            if (let Some(ifBlock) <- CloneLambdaBody(lambda1)) {
                if (let Some(elseBlock) <- CloneLambdaBody(lambda2)) {
                    let condition = DesugarIfAvailableCondition(iae, compatibleSDKVersion)
                    let ifExpr = CreateIfExpr(condition, ifBlock, elseBlock, iae.GetTy())
                    ifExpr.sourceExpr = iae
                    CopyBasicInfo(iae, ifExpr)
                    iae.desugarExpr = ifExpr
                }
            }
        }
    }
}

private func DesugarSynchronizedExpr(expr: SynchronizedExpr): Unit {
    if (expr.TestAttr(Attribute.IS_BROKEN)) {
        return
    }
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(mutex) <- expr.mutex) {
        if (mutex.IsInvalid()) {
            return
        }
        if (let Some(mutexClone) <- CloneExpr(mutex)) {
            let nodes = ArrayList<Node>()
            let mtxVar = CreateVarDecl(".mtx", mutexClone, None)
            nodes.add(mtxVar)
            let mtxRef = CreateRefExpr(".mtx")
            mtxRef.EnableAttr(Attribute.COMPILER_ADD)
            let lockAccess = CreateMemberAccess(mtxRef, "lock")
            CopyBasicInfo(mutex, lockAccess)
            nodes.add(CreateCallExpr(lockAccess, ArrayList<FuncArg>()))
            let tryExpr = TryExpr()
            tryExpr.tryPos = expr.begin
            tryExpr.begin = expr.begin
            if (let Some(body) <- expr.body) {
                tryExpr.tryBlock = body
            } else {
                tryExpr.tryBlock = Block()
            }
            tryExpr.finallyPos = expr.end
            let mtxRef2 = CreateRefExpr(".mtx")
            mtxRef2.EnableAttr(Attribute.COMPILER_ADD)
            let unlockAccess = CreateMemberAccess(mtxRef2, "unlock")
            CopyBasicInfo(mutex, unlockAccess)
            let finallyNodes = ArrayList<Node>()
            finallyNodes.add(CreateCallExpr(unlockAccess, ArrayList<FuncArg>()))
            tryExpr.finallyBlock = CreateBlock(finallyNodes)
            tryExpr.isDesugaredFromSyncBlock = true
            nodes.add(tryExpr)
            let block = CreateBlock(nodes)
            AddCurFile(block, file: expr.curFile)
            expr.desugarExpr = block
            expr.body = None
        }
    }
}

private func GetOptionalExpr(expr: Expr): Option<OptionalExpr> {
    if (let Some(optionalExpr) <- (expr as OptionalExpr)) {
        return optionalExpr
    }
    if (let Some(memberAccess) <- (expr as MemberAccess)) {
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            return GetOptionalExpr(baseExpr)
        }
    } else if (let Some(callExpr) <- (expr as CallExpr)) {
        if (let Some(baseFunc) <- callExpr.baseFunc) {
            return GetOptionalExpr(baseFunc)
        }
    } else if (let Some(trailing) <- (expr as TrailingClosureExpr)) {
        if (let Some(baseExpr) <- trailing.expr) {
            return GetOptionalExpr(baseExpr)
        }
    } else if (let Some(subscriptExpr) <- (expr as SubscriptExpr)) {
        if (let Some(baseExpr) <- subscriptExpr.baseExpr) {
            return GetOptionalExpr(baseExpr)
        }
    } else if (let Some(assignExpr) <- (expr as AssignExpr)) {
        if (let Some(leftValue) <- assignExpr.leftValue) {
            return GetOptionalExpr(leftValue)
        }
    } else if (let Some(incOrDecExpr) <- (expr as IncOrDecExpr)) {
        if (let Some(innerExpr) <- incOrDecExpr.expr) {
            return GetOptionalExpr(innerExpr)
        }
    }
    return None
}

private func CreateSelector(expr: Expr): Expr {
    if (let Some(optionalExpr) <- (expr as OptionalExpr)) {
        let refExpr = CreateRefExpr(V_COMPILER)
        if (let Some(baseExpr) <- optionalExpr.baseExpr) {
            CopyBasicInfo(baseExpr, refExpr)
        } else {
            CopyBasicInfo(optionalExpr, refExpr)
        }
        refExpr.begin = optionalExpr.questPos
        refExpr.end = optionalExpr.questPos + 1
        return refExpr
    }
    if (let Some(memberAccess) <- (expr as MemberAccess)) {
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            memberAccess.baseExpr = CreateSelector(baseExpr)
        }
    } else if (let Some(callExpr) <- (expr as CallExpr)) {
        if (let Some(baseFunc) <- callExpr.baseFunc) {
            callExpr.baseFunc = CreateSelector(baseFunc)
        }
    } else if (let Some(trailing) <- (expr as TrailingClosureExpr)) {
        if (let Some(baseExpr) <- trailing.expr) {
            trailing.expr = CreateSelector(baseExpr)
        }
    } else if (let Some(subscriptExpr) <- (expr as SubscriptExpr)) {
        if (let Some(baseExpr) <- subscriptExpr.baseExpr) {
            subscriptExpr.baseExpr = CreateSelector(baseExpr)
        }
    } else if (let Some(assignExpr) <- (expr as AssignExpr)) {
        if (let Some(leftValue) <- assignExpr.leftValue) {
            assignExpr.leftValue = CreateSelector(leftValue)
        }
    } else if (let Some(incOrDecExpr) <- (expr as IncOrDecExpr)) {
        if (let Some(innerExpr) <- incOrDecExpr.expr) {
            incOrDecExpr.expr = CreateSelector(innerExpr)
        }
    }
    return expr
}

private func DesugarOptionalChainWithMatchCase(expr: Expr, caseExpr: Expr, isAssign: Bool): Expr {
    if (let Some(optionalExpr) <- GetOptionalExpr(expr)) {
        if (let Some(baseExpr) <- optionalExpr.baseExpr) {
            if (let Some(selectorBase) <- CloneExpr(baseExpr)) {
                let matchCases = ArrayList<MatchCase>()
                let varPattern = CreateVarPattern(V_COMPILER)
                if (let Some(varDecl) <- varPattern.varDecl) {
                    CopyBasicInfo(baseExpr, varDecl)
                }
                let somePattern = EnumPattern()
                somePattern.constructor = CreateRefExprInCore(OPTION_VALUE_CTOR)
                somePattern.patterns.add(varPattern)
                matchCases.add(CreateMatchCase(somePattern, caseExpr))
                let nonePattern = EnumPattern()
                nonePattern.constructor = CreateRefExprInCore(OPTION_NONE_CTOR)
                let noneCaseExpr = if (isAssign) { CreateUnitExpr() } else { CreateRefExprInCore(OPTION_NONE_CTOR) }
                matchCases.add(CreateMatchCase(nonePattern, noneCaseExpr))
                let matchExpr = CreateMatchExpr(CreateSelector(selectorBase), matchCases, Ty.GetInitialTy(), SugarKind.QUEST)
                CopyBasicInfo(baseExpr, matchExpr)
                matchExpr.EnableAttr(Attribute.IS_CLONED_SOURCE_CODE)
                return DesugarOptionalChainWithMatchCase(baseExpr, matchExpr, isAssign)
            }
        }
    }
    return caseExpr
}

private func CreateOptionalChainCallSome(expr: Expr): CallExpr {
    let someRef = CreateRefExprInCore(OPTION_VALUE_CTOR)
    CopyBasicInfo(expr, someRef)
    let args = ArrayList<FuncArg>()
    args.add(CreateFuncArg(CreateSelector(expr)))
    let callSome = CreateCallExpr(someRef, args)
    CopyBasicInfo(callSome.args[0], callSome)
    return callSome
}

private func DesugarOptionalChainExpr(expr: OptionalChainExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(innerExpr) <- expr.expr) {
        if (let Some(clonedExpr) <- CloneExpr(innerExpr)) {
            let result = if (clonedExpr.astKind == ASTKind.ASSIGN_EXPR || clonedExpr.astKind == ASTKind.INC_OR_DEC_EXPR) {
                DesugarOptionalChainWithMatchCase(clonedExpr, CreateSelector(innerExpr), true)
            } else {
                DesugarOptionalChainWithMatchCase(clonedExpr, CreateOptionalChainCallSome(innerExpr), false)
            }
            CopyBasicInfo(clonedExpr, result)
            AddCurFile(result, file: expr.curFile)
            expr.desugarExpr = result
            expr.expr = None
        }
    }
}

private func DesugarIncOrDecExpr(expr: IncOrDecExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(innerExpr) <- expr.expr) {
        let one = CreateLitConstExpr(LitConstKind.INTEGER, "1", Ty.GetInitialTy())
        CopyBasicInfo(expr, one)
        let assignExpr = CreateAssignExpr(innerExpr, one)
        assignExpr.op = if (expr.op == TokenKind.INCR) { TokenKind.ADD_ASSIGN } else { TokenKind.SUB_ASSIGN }
        assignExpr.isCompound = true
        CopyBasicInfo(expr, assignExpr)
        expr.desugarExpr = assignExpr
        expr.expr = None
    }
}

private func CreateTupleSubscript(baseName: String, source: Expr, index: Int64): SubscriptExpr {
    let tempRefExpr = CreateRefExpr(baseName)
    tempRefExpr.EnableAttr(Attribute.COMPILER_ADD)
    let rightExpr = SubscriptExpr()
    rightExpr.baseExpr = tempRefExpr
    rightExpr.indexExprs.add(CreateLitConstExpr(LitConstKind.INTEGER, "${index}", Ty.GetInitialTy()))
    rightExpr.begin = source.begin
    rightExpr.end = source.end
    rightExpr.EnableAttr(Attribute.COMPILER_ADD)
    rightExpr.EnableAttr(Attribute.IMPLICIT_ADD)
    rightExpr.sourceExpr = source
    return rightExpr
}

private func GetOptionalChainExprForLeftValue(leftValue: Expr): Option<OptionalChainExpr> {
    var current = leftValue
    while (let Some(paren) <- (current as ParenExpr)) {
        if (let Some(innerExpr) <- paren.expr) {
            current = innerExpr
        } else {
            break
        }
    }
    return current as OptionalChainExpr
}

private func DesugarAssignExprRecursively(leftValues: TupleLit, rightExprs: Expr, nodes: ArrayList<Node>): Unit {
    let tempVar = CreateTmpVarDecl(None, rightExprs)
    let identifier = tempVar.identifier.Val()
    nodes.add(tempVar)
    var indexOfRightExpr: Int64 = 0
    for (leftValue in leftValues.children) {
        let rightExpr = CreateTupleSubscript(identifier, rightExprs, indexOfRightExpr)
        if (let Some(leftTuple) <- (leftValue as TupleLit)) {
            DesugarAssignExprRecursively(leftTuple, rightExpr, nodes)
        } else if (let Some(optionalChain) <- GetOptionalChainExprForLeftValue(leftValue)) {
            if (let Some(optionalExpr) <- optionalChain.expr) {
                if (let Some(clonedOptionalExpr) <- CloneExpr(optionalExpr)) {
                    let optionalChainExpr = OptionalChainExpr()
                    optionalChainExpr.EnableAttr(Attribute.COMPILER_ADD)
                    optionalChainExpr.expr = CreateAssignExpr(clonedOptionalExpr, rightExpr)
                    if (let Some(desugarInner) <- optionalChainExpr.expr) {
                        CopyBasicInfo(optionalChain, desugarInner)
                    }
                    nodes.add(optionalChainExpr)
                }
            }
        } else if (let Some(clonedLeft) <- CloneExpr(leftValue)) {
            let tmpAssignExpr = CreateAssignExpr(clonedLeft, rightExpr)
            tmpAssignExpr.begin = leftValue.begin
            tmpAssignExpr.end = leftValue.end
            nodes.add(tmpAssignExpr)
        }
        indexOfRightExpr++
    }
}

private func DesugarAssignExpr(expr: AssignExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(leftValue) <- expr.leftValue) {
        if (let Some(tupleLit) <- (leftValue as TupleLit)) {
            if (let Some(rightExpr) <- expr.rightExpr) {
                let nodes = ArrayList<Node>()
                DesugarAssignExprRecursively(tupleLit, rightExpr, nodes)
                let block = CreateBlock(nodes)
                CopyBasicInfo(expr, block)
                expr.desugarExpr = block
                expr.leftValue = None
                expr.rightExpr = None
            }
        }
    }
}

private func DesugarOptionType(typeNode: OptionType): Unit {
    if (let Some(componentType) <- typeNode.componentType) {
        var refType = CreateRefTypeInCore(STD_LIB_OPTION)
        if (let Some(typeArg) <- CloneType(componentType)) {
            refType.typeArguments.add(typeArg)
        }
        var idx: UInt64 = 1u64
        while (idx < typeNode.questNum) {
            let nested = CreateRefTypeInCore(STD_LIB_OPTION)
            if (let Some(innerArg) <- (ASTCloner.Clone(refType) as Type)) {
                nested.typeArguments.add(innerArg)
            }
            refType = nested
            idx++
        }
        CopyBasicInfo(typeNode, refType)
        typeNode.desugarType = refType
    }
}

private func DesugarMainDecl(mainDecl: MainDecl): Unit {
    if (let Some(_) <- mainDecl.desugarDecl) {
        return
    }
    let funcDecl = FuncDecl()
    CopyBasicInfo(mainDecl, funcDecl)
    funcDecl.curFile = mainDecl.curFile
    funcDecl.begin = mainDecl.begin
    funcDecl.keywordPos = mainDecl.keywordPos
    funcDecl.identifier = mainDecl.identifier
    funcDecl.CloneAttrs(mainDecl)
    funcDecl.overflowStrategy = mainDecl.overflowStrategy
    funcDecl.funcBody = mainDecl.funcBody
    if (let Some(body) <- funcDecl.funcBody) {
        body.funcDecl = funcDecl
        funcDecl.end = body.end
    }
    funcDecl.toBeCompiled = mainDecl.toBeCompiled
    funcDecl.rawMangleName = mainDecl.rawMangleName
    funcDecl.hash = mainDecl.hash
    funcDecl.EnableAttr(Attribute.MAIN_ENTRY)
    for (annotation in mainDecl.annotations) {
        if (let Some(cloned) <- (ASTCloner.Clone(annotation) as Annotation)) {
            funcDecl.annotations.add(cloned)
        }
    }
    mainDecl.desugarDecl = funcDecl
    mainDecl.funcBody = None
}

private func DesugarTrailingClosureExpr(expr: TrailingClosureExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(lambdaExpr) <- expr.lambda) {
        if (let Some(baseExpr) <- expr.expr) {
            if (let Some(arrayExpr) <- (baseExpr as ArrayExpr)) {
                arrayExpr.args.add(CreateFuncArg(lambdaExpr))
                expr.desugarExpr = arrayExpr
            } else if (let Some(callExpr) <- (baseExpr as CallExpr)) {
                let arg = CreateFuncArg(lambdaExpr)
                arg.EnableAttr(Attribute.IMPLICIT_ADD)
                callExpr.args.add(arg)
                expr.desugarExpr = callExpr
            } else {
                let args = ArrayList<FuncArg>()
                let arg = CreateFuncArg(lambdaExpr)
                arg.EnableAttr(Attribute.IMPLICIT_ADD)
                args.add(arg)
                expr.desugarExpr = CreateCallExpr(baseExpr, args)
            }
            if (let Some(desugar) <- expr.desugarExpr) {
                CopyBasicInfo(expr, desugar)
            }
            expr.expr = None
            expr.lambda = None
        }
    }
}

private func DispatchBeforeTypeCheck(node: Node, desugarMacrocall: Bool, compatibleSDKVersion: String,
    discardedHelper: DiscardedHelper): Unit {
    match (node.astKind) {
        case ASTKind.MAIN_DECL =>
            if (let Some(mainDecl) <- (node as MainDecl)) {
                DesugarMainDecl(mainDecl)
            }
        case ASTKind.FILE =>
            if (let Some(file) <- (node as File)) {
                if (desugarMacrocall) {
                    for (macroCallNode in file.originalMacroCallNodes) {
                        WalkBeforeTypeCheck(macroCallNode, desugarMacrocall, compatibleSDKVersion, discardedHelper)
                    }
                }
                DesugarMacroDecl(file)
            }
        case ASTKind.QUOTE_EXPR =>
            if (let Some(quoteExpr) <- (node as QuoteExpr)) {
                DesugarQuoteExpr(quoteExpr)
            }
        case ASTKind.OPTION_TYPE =>
            if (let Some(optionType) <- (node as OptionType)) {
                DesugarOptionType(optionType)
            }
        case ASTKind.TRAIL_CLOSURE_EXPR =>
            if (let Some(trailingClosure) <- (node as TrailingClosureExpr)) {
                DesugarTrailingClosureExpr(trailingClosure)
            }
        case ASTKind.SYNCHRONIZED_EXPR =>
            if (let Some(syncExpr) <- (node as SynchronizedExpr)) {
                DesugarSynchronizedExpr(syncExpr)
            }
        case ASTKind.OPTIONAL_CHAIN_EXPR =>
            if (let Some(optionalChain) <- (node as OptionalChainExpr)) {
                DesugarOptionalChainExpr(optionalChain)
            }
        case ASTKind.INC_OR_DEC_EXPR =>
            if (let Some(incOrDecExpr) <- (node as IncOrDecExpr)) {
                DesugarIncOrDecExpr(incOrDecExpr)
            }
        case ASTKind.ASSIGN_EXPR =>
            if (let Some(assignExpr) <- (node as AssignExpr)) {
                DesugarAssignExpr(assignExpr)
            }
        case ASTKind.IF_AVAILABLE_EXPR =>
            if (let Some(ifAvailable) <- (node as IfAvailableExpr)) {
                DesugarIfAvailableExpr(ifAvailable, compatibleSDKVersion)
            }
        case _ => ()
    }
}

private class DiscardedHelper {
    private let isDiscardedStack: ArrayList<Bool> = ArrayList<Bool>()
    private let parentStack: ArrayList<Node> = ArrayList<Node>()

    public func PushCtxt(isDiscarded: Bool, parent: Node): Unit {
        isDiscardedStack.add(isDiscarded)
        parentStack.add(parent)
    }

    public func PopCtxt(expected: Node): Unit {
        let _ = expected
        if (!parentStack.isEmpty()) {
            parentStack.remove(at: parentStack.size - 1)
        }
        if (!isDiscardedStack.isEmpty()) {
            isDiscardedStack.remove(at: isDiscardedStack.size - 1)
        }
    }

    public func IsNodeDiscarded(node: Node): Bool {
        if (parentStack.isEmpty() || isDiscardedStack.isEmpty()) {
            return false
        }
        let parent = parentStack[parentStack.size - 1]
        let isParentDiscarded = isDiscardedStack[isDiscardedStack.size - 1]
        return IsDiscarded(node, parent, isParentDiscarded)
    }
}

private func SameNode(left: Node, right: Node): Bool {
    return left.astKind == right.astKind && left.begin == right.begin && left.end == right.end
}

private func IsIfBody(node: Node, parent: Node): Bool {
    if (let Some(ifExpr) <- (parent as IfExpr)) {
        if (let Some(thenBody) <- ifExpr.thenBody) {
            if (SameNode(node, thenBody)) {
                return true
            }
        }
        if (let Some(elseBody) <- ifExpr.elseBody) {
            return SameNode(node, elseBody)
        }
    }
    return false
}

private func IsDiscardTransitive(node: Node, parent: Node): Bool {
    let ifBody = IsIfBody(node, parent)
    let tryBody = parent.astKind == ASTKind.TRY_EXPR && node.astKind == ASTKind.BLOCK
    let matchCase = parent.astKind == ASTKind.MATCH_EXPR &&
        (node.astKind == ASTKind.MATCH_CASE || node.astKind == ASTKind.MATCH_CASE_OTHER)
    let matchCaseBody = (parent.astKind == ASTKind.MATCH_CASE || parent.astKind == ASTKind.MATCH_CASE_OTHER) &&
        node.astKind == ASTKind.BLOCK
    let syncBody = parent.astKind == ASTKind.SYNCHRONIZED_EXPR && node.astKind == ASTKind.BLOCK
    let parentheses = parent.astKind == ASTKind.PAREN_EXPR
    let funcBody = parent.astKind == ASTKind.FUNC_BODY
    return ifBody || tryBody || matchCase || matchCaseBody || syncBody || parentheses || funcBody
}

private func IsFuncBodyWithUnitRet(parent: Node): Bool {
    if (let Some(funcBody) <- (parent as FuncBody)) {
        if (let Some(retType) <- funcBody.retType) {
            if (let Some(primitiveType) <- (retType as PrimitiveType)) {
                return primitiveType.kind == TypeKind.TYPE_UNIT
            }
        }
    }
    return false
}

private func IsConstValBlk(node: Node, parent: Node): Bool {
    let constBlock = parent.astKind == ASTKind.WHILE_EXPR || parent.astKind == ASTKind.DO_WHILE_EXPR ||
        parent.astKind == ASTKind.FOR_IN_EXPR
    var finallyBlock = false
    if (let Some(tryExpr) <- (parent as TryExpr)) {
        if (let Some(finallyBody) <- tryExpr.finallyBlock) {
            finallyBlock = SameNode(node, finallyBody)
        }
    }
    let constructor = node.astKind == ASTKind.FUNC_BODY &&
        parent.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.PRIMARY_CONSTRUCTOR)
    var ifNoElse = false
    if (let Some(ifExpr) <- (parent as IfExpr)) {
        ifNoElse = if (let Some(_) <- ifExpr.elseBody) { false } else { true }
    }
    return constBlock || finallyBlock || IsFuncBodyWithUnitRet(parent) || constructor || ifNoElse
}

private func IsImmediateDiscardedBlockChild(node: Node, parent: Node, isParentDiscarded: Bool): Bool {
    if (let Some(block) <- (parent as Block)) {
        if (block.body.isEmpty()) {
            return false
        }
        let last = block.body[block.body.size - 1]
        return isParentDiscarded || !SameNode(node, last)
    }
    return false
}

private func IsDiscarded(node: Node, parent: Node, isParentDiscarded: Bool): Bool {
    let flagTransitive = isParentDiscarded && IsDiscardTransitive(node, parent)
    let flagConst = (node.astKind == ASTKind.BLOCK || node.astKind == ASTKind.FUNC_BODY) &&
        IsConstValBlk(node, parent)
    let flagBlock = IsImmediateDiscardedBlockChild(node, parent, isParentDiscarded)
    return flagTransitive || flagConst || flagBlock
}

private func WalkBeforeTypeCheck(root: Node, desugarMacrocall: Bool, compatibleSDKVersion: String,
    discardedHelper: DiscardedHelper): Unit {
    let walker = Walker(root, visitPre: { node: Node =>
        if (node.TestAttr(Attribute.IS_BROKEN)) {
            discardedHelper.PushCtxt(false, node)
            return VisitAction.SKIP_CHILDREN
        }
        DispatchBeforeTypeCheck(node, desugarMacrocall, compatibleSDKVersion, discardedHelper)
        if (discardedHelper.IsNodeDiscarded(node)) {
            discardedHelper.PushCtxt(true, node)
            UnitifyBranchExpr(node)
        } else {
            discardedHelper.PushCtxt(false, node)
        }
        VisitAction.WALK_CHILDREN
    }, visitPost: { node: Node =>
        discardedHelper.PopCtxt(node)
        VisitAction.KEEP_DECISION
    })
    let _ = walker.Walk()
}

public func DesugarBeforeTypeCheck(root: Node, desugarMacrocall!: Bool = false,
    compatibleSDKVersion!: String = ""): Unit {
    let discardedHelper = DiscardedHelper()
    WalkBeforeTypeCheck(root, desugarMacrocall, compatibleSDKVersion, discardedHelper)
}
