package cangjie_compiler::sema.Desugar

import std.collection.*
import cangjie_compiler::ast.*

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

private func UnitifyBlock(block: Block): Unit {
    if (block.body.isEmpty()) {
        block.body.add(CreateUnitExpr())
        return
    }
    let last = block.body[block.body.size - 1]
    if (last.astKind != ASTKind.LIT_CONST_EXPR && last.astKind != ASTKind.JUMP_EXPR &&
        last.astKind != ASTKind.THROW_EXPR && last.astKind != ASTKind.RETURN_EXPR) {
        block.body.add(CreateUnitExpr())
    }
}

private func UnitifyBranchExpr(node: Node): Unit {
    if (let Some(ifExpr) <- (node as IfExpr)) {
        if (let Some(thenBody) <- ifExpr.thenBody) {
            UnitifyBlock(thenBody)
        }
        if (let Some(elseExpr) <- ifExpr.elseBody) {
            if (let Some(elseBlock) <- (elseExpr as Block)) {
                UnitifyBlock(elseBlock)
            }
        }
    } else if (let Some(tryExpr) <- (node as TryExpr)) {
        if (let Some(tryBlock) <- tryExpr.tryBlock) {
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
            let lockAccess = CreateMemberAccess(CreateRefExpr(mtxVar), "lock")
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
            let unlockAccess = CreateMemberAccess(CreateRefExpr(mtxVar), "unlock")
            CopyBasicInfo(mutex, unlockAccess)
            let finallyNodes = ArrayList<Node>()
            finallyNodes.add(CreateCallExpr(unlockAccess, ArrayList<FuncArg>()))
            tryExpr.finallyBlock = CreateBlock(finallyNodes)
            tryExpr.isDesugaredFromSyncBlock = true
            nodes.add(tryExpr)
            let block = CreateBlock(nodes)
            AddCurFile(block, file: expr.curFile)
            expr.desugarExpr = block
            expr.mutex = None
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

private func DesugarAssignExprRecursively(leftValues: TupleLit, rightExprs: Expr, nodes: ArrayList<Node>): Unit {
    let tempVar = CreateTmpVarDecl(None, rightExprs)
    let identifier = tempVar.identifier.Val()
    nodes.add(tempVar)
    var indexOfRightExpr: Int64 = 0
    for (leftValue in leftValues.children) {
        let rightExpr = CreateTupleSubscript(identifier, rightExprs, indexOfRightExpr)
        if (let Some(leftTuple) <- (leftValue as TupleLit)) {
            DesugarAssignExprRecursively(leftTuple, rightExpr, nodes)
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

private func DispatchBeforeTypeCheck(node: Node): Unit {
    match (node.astKind) {
        case ASTKind.MAIN_DECL =>
            if (let Some(mainDecl) <- (node as MainDecl)) {
                DesugarMainDecl(mainDecl)
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
        case _ => ()
    }
}

public func DesugarBeforeTypeCheck(root: Node, desugarMacrocall!: Bool = false,
    compatibleSDKVersion!: String = ""): Unit {
    let _ = desugarMacrocall
    let _ = compatibleSDKVersion
    let walker = Walker(root, visitPre: { node: Node =>
        if (node.TestAttr(Attribute.IS_BROKEN)) {
            return VisitAction.SKIP_CHILDREN
        }
        DispatchBeforeTypeCheck(node)
        VisitAction.WALK_CHILDREN
    }, visitPost: { node: Node =>
        UnitifyBranchExpr(node)
        VisitAction.KEEP_DECISION
    })
    let _ = walker.Walk()
}

public func SelfhostPortStatus_Desugar_DesugarBeforeTypeCheck(): Bool {
    return true
}
