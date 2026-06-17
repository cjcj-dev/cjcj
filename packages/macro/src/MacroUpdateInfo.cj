package cangjie_compiler::macro_pkg

import std.collection.*

private func markInvocationParent(macroNode: Node, parent: Node): Unit {
    if (let Some(invocation) <- macroNode.GetInvocation()) {
        invocation.parent = Some(parent)
        if (invocation.newTokens.isEmpty()) {
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
    } else if (let Some(binary) <- (node as BinaryExpr)) {
        updateExprField(binary.leftExpr, binary, ExprFieldKind.BINARY_LEFT_EXPR, collector)
        updateExprField(binary.rightExpr, binary, ExprFieldKind.BINARY_RIGHT_EXPR, collector)
    } else if (let Some(varDecl) <- (node as VarDecl)) {
        updateExprField(varDecl.initializer, varDecl, ExprFieldKind.VAR_DECL_INITIALIZER, collector)
    } else if (let Some(classDecl) <- (node as ClassDecl)) {
        updateDeclContainer(classDecl.members, classDecl, collector)
    } else if (let Some(structDecl) <- (node as StructDecl)) {
        updateDeclContainer(structDecl.members, structDecl, collector)
    } else if (let Some(interfaceDecl) <- (node as InterfaceDecl)) {
        updateDeclContainer(interfaceDecl.members, interfaceDecl, collector)
    } else if (let Some(enumDecl) <- (node as EnumDecl)) {
        updateDeclContainer(enumDecl.members, enumDecl, collector)
        updateDeclContainer(enumDecl.constructors, enumDecl, collector)
    } else if (let Some(extendDecl) <- (node as ExtendDecl)) {
        updateDeclContainer(extendDecl.members, extendDecl, collector)
    }
}
