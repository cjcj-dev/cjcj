package cjcj::macro_pkg

import std.collection.*

private func markInvocationParent(macroNode: Node, parent: Node): Unit {
    if (let Some(invocation) <- macroNode.GetInvocation()) {
        if (invocation.newTokens.isEmpty()) {
            invocation.parent = Some(parent)
            invocation.newTokens.add(Token(TokenKind.ILLEGAL, ""))
        }
    }
}

private func updateExprField(exprValue: Option<Expr>, parent: Node, field: ExprFieldKind, collector: MacroCollector): Unit {
    if (let Some(exprNode) <- exprValue) {
        if (exprNode.IsMacroCallNode()) {
            let call = MacroCall(exprNode)
            call.replaceLoc.kind = ReplaceTargetKind.EXPR_BOX
            call.replaceLoc.exprBox = Some(ExprBox(exprNode))
            call.replaceLoc.exprParent = Some(parent)
            call.replaceLoc.exprField = field
            call.isOuterMost = true
            collector.macCalls.add(call)
            markInvocationParent(exprNode, parent)
        }
    }
}

private func updateExprContainer(container: ArrayList<Expr>, parent: Node, collector: MacroCollector): Unit {
    var idx: Int64 = 0
    while (idx < container.size) {
        if (container[idx].IsMacroCallNode()) {
            let macroNode = container[idx]
            let call = MacroCall(macroNode)
            call.replaceLoc.kind = ReplaceTargetKind.EXPR_VECTOR
            call.replaceLoc.loc = idx
            call.replaceLoc.exprs = Some(container)
            call.isOuterMost = true
            collector.macCalls.add(call)
            markInvocationParent(macroNode, parent)
        }
        idx++
    }
}

private func updateDeclContainer(container: ArrayList<Decl>, parent: Node, collector: MacroCollector): Unit {
    var idx: Int64 = 0
    while (idx < container.size) {
        if (container[idx].IsMacroCallNode()) {
            let macroNode = container[idx]
            let call = MacroCall(macroNode)
            call.replaceLoc.kind = ReplaceTargetKind.DECL_VECTOR
            call.replaceLoc.loc = idx
            call.replaceLoc.decls = Some(container)
            call.isOuterMost = true
            collector.macCalls.add(call)
            markInvocationParent(macroNode, parent)
        }
        idx++
    }
}

private func updateNodeContainer(container: ArrayList<Node>, parent: Node, collector: MacroCollector): Unit {
    var idx: Int64 = 0
    while (idx < container.size) {
        if (container[idx].IsMacroCallNode()) {
            let macroNode = container[idx]
            let call = MacroCall(macroNode)
            call.replaceLoc.kind = ReplaceTargetKind.NODE_VECTOR
            call.replaceLoc.loc = idx
            call.replaceLoc.nodes = Some(container)
            call.isOuterMost = true
            collector.macCalls.add(call)
            markInvocationParent(macroNode, parent)
        }
        idx++
    }
}

private func updateParamContainer(container: ArrayList<FuncParam>, parent: Node, collector: MacroCollector): Unit {
    var idx: Int64 = 0
    while (idx < container.size) {
        if (container[idx].IsMacroCallNode()) {
            let macroNode = container[idx]
            let call = MacroCall(macroNode)
            call.replaceLoc.kind = ReplaceTargetKind.PARAM_VECTOR
            call.replaceLoc.loc = idx
            call.replaceLoc.params = Some(container)
            call.isOuterMost = true
            collector.macCalls.add(call)
            markInvocationParent(macroNode, parent)
        }
        idx++
    }
}

public func AssignExprReplacement(target: ReplaceTarget, expr: Expr): Bool {
    if (let Some(parentNode) <- target.exprParent) {
        if (target.exprField == ExprFieldKind.FUNC_PARAM_ASSIGNMENT) {
            if (let Some(parentParam) <- (parentNode as FuncParam)) {
                parentParam.assignment = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.FUNC_ARG_EXPR) {
            if (let Some(parentArg) <- (parentNode as FuncArg)) {
                parentArg.expr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.CALL_BASE_FUNC) {
            if (let Some(parentCall) <- (parentNode as CallExpr)) {
                parentCall.baseFunc = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.MEMBER_BASE_EXPR) {
            if (let Some(parentMember) <- (parentNode as MemberAccess)) {
                parentMember.baseExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.RETURN_EXPR_VALUE) {
            if (let Some(parentReturn) <- (parentNode as ReturnExpr)) {
                parentReturn.expr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.IF_COND_EXPR) {
            if (let Some(parentIf) <- (parentNode as IfExpr)) {
                parentIf.condExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.BINARY_LEFT_EXPR) {
            if (let Some(parentBinary) <- (parentNode as BinaryExpr)) {
                parentBinary.leftExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.BINARY_RIGHT_EXPR) {
            if (let Some(parentBinaryRight) <- (parentNode as BinaryExpr)) {
                parentBinaryRight.rightExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.VAR_DECL_INITIALIZER) {
            if (let Some(parentVarDecl) <- (parentNode as VarDecl)) {
                parentVarDecl.initializer = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.VAR_WITH_PATTERN_INITIALIZER) {
            if (let Some(parentPatternVarDecl) <- (parentNode as VarWithPatternDecl)) {
                parentPatternVarDecl.initializer = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.PAREN_EXPR_VALUE) {
            if (let Some(parentParenExpr) <- (parentNode as ParenExpr)) {
                parentParenExpr.expr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.UNARY_EXPR_VALUE) {
            if (let Some(parentUnaryExpr) <- (parentNode as UnaryExpr)) {
                parentUnaryExpr.expr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.INC_OR_DEC_EXPR_VALUE) {
            if (let Some(parentIncOrDecExpr) <- (parentNode as IncOrDecExpr)) {
                parentIncOrDecExpr.expr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.TYPE_CONV_EXPR_VALUE) {
            if (let Some(parentTypeConvExpr) <- (parentNode as TypeConvExpr)) {
                parentTypeConvExpr.expr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.SUBSCRIPT_BASE_EXPR) {
            if (let Some(parentSubscriptExpr) <- (parentNode as SubscriptExpr)) {
                parentSubscriptExpr.baseExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.OPTIONAL_BASE_EXPR) {
            if (let Some(parentOptionalExpr) <- (parentNode as OptionalExpr)) {
                parentOptionalExpr.baseExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.OPTIONAL_CHAIN_EXPR_VALUE) {
            if (let Some(parentOptionalChainExpr) <- (parentNode as OptionalChainExpr)) {
                parentOptionalChainExpr.expr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.LET_PATTERN_INITIALIZER) {
            if (let Some(parentLetPatternExpr) <- (parentNode as LetPatternDestructor)) {
                parentLetPatternExpr.initializer = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.ASSIGN_RIGHT_EXPR) {
            if (let Some(parentAssignExpr) <- (parentNode as AssignExpr)) {
                parentAssignExpr.rightExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.MATCH_SELECTOR) {
            if (let Some(parentMatchExpr) <- (parentNode as MatchExpr)) {
                parentMatchExpr.selector = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.MATCH_CASE_GUARD) {
            if (let Some(parentMatchCase) <- (parentNode as MatchCase)) {
                parentMatchCase.patternGuard = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.MATCH_CASE_OTHER_EXPR) {
            if (let Some(parentCaseOther) <- (parentNode as MatchCaseOther)) {
                parentCaseOther.matchExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.WHILE_COND_EXPR) {
            if (let Some(parentWhileExpr) <- (parentNode as WhileExpr)) {
                parentWhileExpr.condExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.DO_WHILE_COND_EXPR) {
            if (let Some(parentDoWhileExpr) <- (parentNode as DoWhileExpr)) {
                parentDoWhileExpr.condExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.FOR_IN_EXPR_VALUE) {
            if (let Some(parentForInExpr) <- (parentNode as ForInExpr)) {
                parentForInExpr.inExpression = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.FOR_IN_PATTERN_GUARD) {
            if (let Some(parentForGuardExpr) <- (parentNode as ForInExpr)) {
                parentForGuardExpr.patternGuard = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.THROW_EXPR_VALUE) {
            if (let Some(parentThrowExpr) <- (parentNode as ThrowExpr)) {
                parentThrowExpr.expr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.PERFORM_EXPR_VALUE) {
            if (let Some(parentPerformExpr) <- (parentNode as PerformExpr)) {
                parentPerformExpr.expr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.SPAWN_TASK) {
            if (let Some(parentSpawnExpr) <- (parentNode as SpawnExpr)) {
                parentSpawnExpr.task = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.TRAILING_CLOSURE_EXPR) {
            if (let Some(parentTrailingClosureExpr) <- (parentNode as TrailingClosureExpr)) {
                parentTrailingClosureExpr.expr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.IS_LEFT_EXPR) {
            if (let Some(parentIsExpr) <- (parentNode as IsExpr)) {
                parentIsExpr.leftExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.AS_LEFT_EXPR) {
            if (let Some(parentAsExpr) <- (parentNode as AsExpr)) {
                parentAsExpr.leftExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.RANGE_START_EXPR) {
            if (let Some(parentRangeExpr) <- (parentNode as RangeExpr)) {
                parentRangeExpr.startExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.RANGE_STOP_EXPR) {
            if (let Some(parentRangeStopExpr) <- (parentNode as RangeExpr)) {
                parentRangeStopExpr.stopExpr = Some(expr)
                return true
            }
        } else if (target.exprField == ExprFieldKind.RANGE_STEP_EXPR) {
            if (let Some(parentRangeStepExpr) <- (parentNode as RangeExpr)) {
                parentRangeStepExpr.stepExpr = Some(expr)
                return true
            }
        }
    }
    if (let Some(box) <- target.exprBox) {
        box.value = Some(expr)
        return true
    }
    return false
}

public func UpdateMacroInfo(node: Node, collector: MacroCollector): Unit {
    if (let Some(file) <- (node as File)) {
        updateDeclContainer(file.decls, file, collector)
    } else if (let Some(block) <- (node as Block)) {
        updateNodeContainer(block.body, block, collector)
    } else if (let Some(list) <- (node as FuncParamList)) {
        updateParamContainer(list.params, list, collector)
    } else if (let Some(param) <- (node as FuncParam)) {
        updateExprField(param.assignment, param, ExprFieldKind.FUNC_PARAM_ASSIGNMENT, collector)
    } else if (let Some(arg) <- (node as FuncArg)) {
        updateExprField(arg.expr, arg, ExprFieldKind.FUNC_ARG_EXPR, collector)
    } else if (let Some(call) <- (node as CallExpr)) {
        updateExprField(call.baseFunc, call, ExprFieldKind.CALL_BASE_FUNC, collector)
    } else if (let Some(member) <- (node as MemberAccess)) {
        updateExprField(member.baseExpr, member, ExprFieldKind.MEMBER_BASE_EXPR, collector)
    } else if (let Some(ret) <- (node as ReturnExpr)) {
        updateExprField(ret.expr, ret, ExprFieldKind.RETURN_EXPR_VALUE, collector)
    } else if (let Some(ifExpr) <- (node as IfExpr)) {
        updateExprField(ifExpr.condExpr, ifExpr, ExprFieldKind.IF_COND_EXPR, collector)
    } else if (let Some(parenExpr) <- (node as ParenExpr)) {
        updateExprField(parenExpr.expr, parenExpr, ExprFieldKind.PAREN_EXPR_VALUE, collector)
    } else if (let Some(unaryExpr) <- (node as UnaryExpr)) {
        updateExprField(unaryExpr.expr, unaryExpr, ExprFieldKind.UNARY_EXPR_VALUE, collector)
    } else if (let Some(typeConvExpr) <- (node as TypeConvExpr)) {
        updateExprField(typeConvExpr.expr, typeConvExpr, ExprFieldKind.TYPE_CONV_EXPR_VALUE, collector)
    } else if (let Some(subscriptExpr) <- (node as SubscriptExpr)) {
        updateExprField(subscriptExpr.baseExpr, subscriptExpr, ExprFieldKind.SUBSCRIPT_BASE_EXPR, collector)
        updateExprContainer(subscriptExpr.indexExprs, subscriptExpr, collector)
    } else if (let Some(letPatternExpr) <- (node as LetPatternDestructor)) {
        updateExprField(letPatternExpr.initializer, letPatternExpr, ExprFieldKind.LET_PATTERN_INITIALIZER, collector)
    } else if (let Some(assign) <- (node as AssignExpr)) {
        updateExprField(assign.rightExpr, assign, ExprFieldKind.ASSIGN_RIGHT_EXPR, collector)
    } else if (let Some(binary) <- (node as BinaryExpr)) {
        updateExprField(binary.rightExpr, binary, ExprFieldKind.BINARY_RIGHT_EXPR, collector)
        updateExprField(binary.leftExpr, binary, ExprFieldKind.BINARY_LEFT_EXPR, collector)
    } else if (let Some(arrayLit) <- (node as ArrayLit)) {
        updateExprContainer(arrayLit.children, arrayLit, collector)
    } else if (let Some(tupleLit) <- (node as TupleLit)) {
        updateExprContainer(tupleLit.children, tupleLit, collector)
    } else if (let Some(quoteExpr) <- (node as QuoteExpr)) {
        updateExprContainer(quoteExpr.exprs, quoteExpr, collector)
    } else if (let Some(matchExpr) <- (node as MatchExpr)) {
        updateExprField(matchExpr.selector, matchExpr, ExprFieldKind.MATCH_SELECTOR, collector)
    } else if (let Some(matchCase) <- (node as MatchCase)) {
        updateExprField(matchCase.patternGuard, matchCase, ExprFieldKind.MATCH_CASE_GUARD, collector)
    } else if (let Some(caseOther) <- (node as MatchCaseOther)) {
        updateExprField(caseOther.matchExpr, caseOther, ExprFieldKind.MATCH_CASE_OTHER_EXPR, collector)
    } else if (let Some(whileExpr) <- (node as WhileExpr)) {
        updateExprField(whileExpr.condExpr, whileExpr, ExprFieldKind.WHILE_COND_EXPR, collector)
    } else if (let Some(doWhileExpr) <- (node as DoWhileExpr)) {
        updateExprField(doWhileExpr.condExpr, doWhileExpr, ExprFieldKind.DO_WHILE_COND_EXPR, collector)
    } else if (let Some(forInExpr) <- (node as ForInExpr)) {
        updateExprField(forInExpr.inExpression, forInExpr, ExprFieldKind.FOR_IN_EXPR_VALUE, collector)
        updateExprField(forInExpr.patternGuard, forInExpr, ExprFieldKind.FOR_IN_PATTERN_GUARD, collector)
    } else if (let Some(throwExpr) <- (node as ThrowExpr)) {
        updateExprField(throwExpr.expr, throwExpr, ExprFieldKind.THROW_EXPR_VALUE, collector)
    } else if (let Some(performExpr) <- (node as PerformExpr)) {
        updateExprField(performExpr.expr, performExpr, ExprFieldKind.PERFORM_EXPR_VALUE, collector)
    } else if (let Some(spawnExpr) <- (node as SpawnExpr)) {
        updateExprField(spawnExpr.task, spawnExpr, ExprFieldKind.SPAWN_TASK, collector)
    } else if (let Some(trailingClosureExpr) <- (node as TrailingClosureExpr)) {
        updateExprField(trailingClosureExpr.expr, trailingClosureExpr, ExprFieldKind.TRAILING_CLOSURE_EXPR, collector)
    } else if (let Some(isExpr) <- (node as IsExpr)) {
        updateExprField(isExpr.leftExpr, isExpr, ExprFieldKind.IS_LEFT_EXPR, collector)
    } else if (let Some(asExpr) <- (node as AsExpr)) {
        updateExprField(asExpr.leftExpr, asExpr, ExprFieldKind.AS_LEFT_EXPR, collector)
    } else if (let Some(rangeExpr) <- (node as RangeExpr)) {
        updateExprField(rangeExpr.startExpr, rangeExpr, ExprFieldKind.RANGE_START_EXPR, collector)
        updateExprField(rangeExpr.stopExpr, rangeExpr, ExprFieldKind.RANGE_STOP_EXPR, collector)
        updateExprField(rangeExpr.stepExpr, rangeExpr, ExprFieldKind.RANGE_STEP_EXPR, collector)
    } else if (let Some(patternVarDecl) <- (node as VarWithPatternDecl)) {
        updateExprField(patternVarDecl.initializer, patternVarDecl, ExprFieldKind.VAR_WITH_PATTERN_INITIALIZER, collector)
    } else if (let Some(varDecl) <- (node as VarDecl)) {
        updateExprField(varDecl.initializer, varDecl, ExprFieldKind.VAR_DECL_INITIALIZER, collector)
    } else if (let Some(classDecl) <- (node as ClassDecl)) {
        if (let Some(body) <- classDecl.body) {
            updateDeclContainer(body.decls, classDecl, collector)
        }
    } else if (let Some(structDecl) <- (node as StructDecl)) {
        if (let Some(body) <- structDecl.body) {
            updateDeclContainer(body.decls, structDecl, collector)
        }
    } else if (let Some(interfaceDecl) <- (node as InterfaceDecl)) {
        if (let Some(body) <- interfaceDecl.body) {
            updateDeclContainer(body.decls, interfaceDecl, collector)
        }
    } else if (let Some(enumDecl) <- (node as EnumDecl)) {
        updateDeclContainer(enumDecl.members, enumDecl, collector)
        updateDeclContainer(enumDecl.constructors, enumDecl, collector)
    } else if (let Some(extendDecl) <- (node as ExtendDecl)) {
        updateDeclContainer(extendDecl.members, extendDecl, collector)
    }
}
