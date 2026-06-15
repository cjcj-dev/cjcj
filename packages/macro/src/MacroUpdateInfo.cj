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

public func UpdateMacroInfo(node: Node, collector: MacroCollector): Unit {
    if (let Some(file) <- (node as File)) {
        updateDeclContainer(file.decls, file, collector)
    } else if (let Some(block) <- (node as Block)) {
        updateNodeContainer(block.body, block, collector)
    } else if (let Some(list) <- (node as FuncParamList)) {
        updateParamContainer(list.params, list, collector)
    } else if (let Some(classDecl) <- (node as ClassDecl)) {
        updateDeclContainer(classDecl.members, classDecl, collector)
    } else if (let Some(structDecl) <- (node as StructDecl)) {
        updateDeclContainer(structDecl.members, structDecl, collector)
    }
}
