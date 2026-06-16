package cangjie_compiler::macro_pkg

import std.collection.*

private func hasNoMacros(mc: MacroCollector): Bool {
    return mc.macroDefFuncs.isEmpty() && mc.macCalls.isEmpty()
}

private func hasDefAndCallInSamePkg(macroCollector: MacroCollector, diag: DiagnosticEngine): Bool {
    var ret = false
    for (fd in macroCollector.macroDefFuncs) {
        for (call in macroCollector.macCalls) {
            if (fd.identifier == call.GetFullName()) {
                ret = true
                diag.Diagnose(call.GetBeginPos(), "macro's call and definition can not in one package")
            }
        }
    }
    return ret
}

private func walkNode(node: Node, visit: (Node) -> Bool): Unit {
    if (!visit(node)) {
        return
    }
    for (child in node.Children()) {
        walkNode(child, visit)
    }
    if (let Some(decl) <- (node as Decl)) {
        for (anno in decl.annotations) {
            walkNode(anno, visit)
        }
        for (modifier in decl.modifiers) {
            walkNode(modifier, visit)
        }
        for (member in decl.GetMemberDecls()) {
            walkNode(member, visit)
        }
    }
    if (let Some(funcDecl) <- (node as FuncDecl)) {
        for (list in funcDecl.funcBody.paramLists) {
            walkNode(list, visit)
        }
        if (let Some(body) <- funcDecl.funcBody.body) {
            walkNode(body, visit)
        }
    }
}

private func collectMacroEachFile(file: File, collector: MacroCollector): Unit {
    walkNode(file, { curNode: Node =>
        if (let Some(macroDecl) <- (curNode as MacroDecl)) {
            collector.macroDefFuncs.add(macroDecl)
        }
        UpdateMacroInfo(curNode, collector)
        return !curNode.IsMacroCallNode()
    })
}

private func hasMacroCallInNode(node: Node, diag: DiagnosticEngine): Bool {
    let hasMacroCall = Box<Bool>(false)
    walkNode(node, { curNode: Node =>
        if (curNode.IsMacroCallNode()) {
            hasMacroCall.value = true
            if (let Some(invocation) <- curNode.GetInvocation()) {
                diag.Diagnose(invocation.macroCallDiagInfo.identifierPos,
                    "undeclared macro identifier '" + invocation.macroCallDiagInfo.identifier + "'")
            }
            return false
        }
        return true
    })
    return hasMacroCall.value
}

private func checkUnhandledMacroCall(pkg: Package, diag: DiagnosticEngine): Unit {
    if (diag.GetErrorCount() > 0) {
        return
    }
    for (file in pkg.files) {
        if (!file.hasMacro) {
            continue
        }
        let _ = hasMacroCallInNode(file, diag)
    }
}

private func parseGeneratedNodes(tokens: ArrayList<Token>, macroNode: MacroCall): ArrayList<Node> {
    let out = ArrayList<Node>()
    if (tokens.isEmpty()) {
        return out
    }
    // The isolated Macro package has no manifest dependency on Parse, so it recovers the replacement shape here.
    let first = tokens[0]
    if (macroNode.RequireNode().astKind == ASTKind.MACRO_EXPAND_PARAM) {
        let param = FuncParam()
        param.identifier = if (tokens.size > 0) { tokens[0].Value() } else { "" }
        param.begin = first.Begin()
        param.end = tokens[tokens.size - 1].End()
        param.curFile = macroNode.RequireNode().curFile
        out.add(param)
        return out
    }
    if (macroNode.RequireNode().astKind == ASTKind.MACRO_EXPAND_DECL) {
        if (first.kind == TokenKind.FUNC || first.kind == TokenKind.MACRO) {
            let fd = FuncDecl()
            fd.identifier = findFollowingIdentifier(tokens, 1)
            fd.begin = first.Begin()
            fd.end = tokens[tokens.size - 1].End()
            fd.curFile = macroNode.RequireNode().curFile
            out.add(fd)
            return out
        }
        if (first.kind == TokenKind.VAR || first.kind == TokenKind.LET || first.kind == TokenKind.CONST) {
            let varDecl = VarDecl()
            varDecl.identifier = findFollowingIdentifier(tokens, 1)
            varDecl.begin = first.Begin()
            varDecl.end = tokens[tokens.size - 1].End()
            varDecl.curFile = macroNode.RequireNode().curFile
            out.add(varDecl)
            return out
        }
        let decl = Decl(ASTKind.UNKNOWN)
        decl.identifier = findFollowingIdentifier(tokens, 0)
        decl.begin = first.Begin()
        decl.end = tokens[tokens.size - 1].End()
        decl.curFile = macroNode.RequireNode().curFile
        out.add(decl)
        return out
    }
    let tokenPart = TokenPart(tokens)
    tokenPart.begin = first.Begin()
    tokenPart.end = tokens[tokens.size - 1].End()
    tokenPart.curFile = macroNode.RequireNode().curFile
    out.add(tokenPart)
    return out
}

private func findFollowingIdentifier(tokens: ArrayList<Token>, start: Int64): String {
    var idx = start
    while (idx < tokens.size) {
        if (IsIdentifierOrContextualKeyword(tokens[idx].kind)) {
            return tokens[idx].Value()
        }
        idx++
    }
    return ""
}

private func replaceNodeVector(container: ArrayList<Node>, loc: Int64, newNodes: ArrayList<Node>): Unit {
    let rebuilt = ArrayList<Node>()
    var idx: Int64 = 0
    while (idx < container.size) {
        if (idx == loc) {
            for (node in newNodes) {
                rebuilt.add(node)
            }
        } else {
            rebuilt.add(container[idx])
        }
        idx++
    }
    container.clear()
    for (node in rebuilt) {
        container.add(node)
    }
}

private func replaceDeclVector(container: ArrayList<Decl>, loc: Int64, newNodes: ArrayList<Node>, diag: DiagnosticEngine): Unit {
    let rebuilt = ArrayList<Decl>()
    var idx: Int64 = 0
    while (idx < container.size) {
        if (idx == loc) {
            for (node in newNodes) {
                if (let Some(decl) <- (node as Decl)) {
                    rebuilt.add(decl)
                } else {
                    diag.Diagnose(node.begin, "expect declaration from macro expansion")
                }
            }
        } else {
            rebuilt.add(container[idx])
        }
        idx++
    }
    container.clear()
    for (decl in rebuilt) {
        container.add(decl)
    }
}

private func replaceParamVector(container: ArrayList<FuncParam>, loc: Int64, newNodes: ArrayList<Node>, diag: DiagnosticEngine): Unit {
    if (newNodes.isEmpty()) {
        diag.Diagnose(DEFAULT_POSITION, "unexpected empty tokens after the macro expansion for the func parameters.")
        return
    }
    let rebuilt = ArrayList<FuncParam>()
    var idx: Int64 = 0
    while (idx < container.size) {
        if (idx == loc) {
            for (node in newNodes) {
                if (let Some(param) <- (node as FuncParam)) {
                    rebuilt.add(param)
                } else {
                    diag.Diagnose(node.begin, "expect function parameter from macro expansion")
                }
            }
        } else {
            rebuilt.add(container[idx])
        }
        idx++
    }
    container.clear()
    for (param in rebuilt) {
        container.add(param)
    }
}

public class MacroExpansion {
    var curPackage: Option<Package> = None
    var ci: CompilerInstance
    var macroCollector: MacroCollector = MacroCollector()
    public let tokensEvalInMacro: ArrayList<String> = ArrayList<String>()

    public init(ci: CompilerInstance) {
        this.ci = ci
    }

    public func Execute(pkg: Package): Unit {
        curPackage = Some(pkg)
        CollectMacros(pkg)
        if (hasNoMacros(macroCollector) || macroCollector.macCalls.isEmpty() ||
            hasDefAndCallInSamePkg(macroCollector, ci.diag) || ci.diag.GetErrorCount() > 0) {
            return
        }
        EvaluateMacros()
        ProcessPackageMacros(this, pkg)
        ReplaceAST(pkg)
    }

    public func Execute(packages: ArrayList<Package>): Unit {
        if (ci.invocation.globalOptions.enableCompileTest) {
            TestEntryConstructor(ci.diag).CheckTestSuite(packages)
        }
        for (pkg in packages) {
            Execute(pkg)
        }
        if (ci.invocation.globalOptions.enableCompileTest && ci.invocation.globalOptions.CompileExecutable()) {
            TestEntryConstructor.ConstructTestSuite(ci.invocation.globalOptions.moduleName, packages,
                ci.importManager.GetAllImportedPackages(), ci.invocation.globalOptions.compileTestsOnly,
                ci.invocation.globalOptions.mock == MockMode.ON)
        }
        for (pkg in packages) {
            AddCurFile(pkg)
            checkUnhandledMacroCall(pkg, ci.diag)
        }
    }

    public func ExpandDecl(decl: Decl): ArrayList<Decl> {
        let result = ArrayList<Decl>()
        if (decl.IsMemberDecl()) {
            return result
        }
        let currentDecls = ArrayList<Decl>()
        currentDecls.add(decl)
        let localCollector = MacroCollector()
        CollectMacroCallsInDecls(currentDecls, localCollector)
        if (localCollector.macCalls.isEmpty()) {
            return currentDecls
        }
        let evaluator = MacroEvaluation(ci, localCollector, ci.invocation.globalOptions.enableMacroInLSP)
        evaluator.Evaluate()
        ProcessMacroCallList(this, localCollector.macCalls)
        ReplaceMacroCallsInDecls(localCollector.macCalls)
        for (currentDecl in currentDecls) {
            result.add(currentDecl)
        }
        return result
    }

    private func CollectMacros(pkg: Package): Unit {
        macroCollector.clear()
        macroCollector.curPkg = Some(pkg)
        for (file in pkg.files) {
            if (!file.hasMacro) {
                continue
            }
            collectMacroEachFile(file, macroCollector)
        }
        for (pkg in ci.importManager.GetImportedPkgsForMacro()) {
            macroCollector.importedMacroPkgs.add(pkg)
        }
    }

    public func CollectMacroCallsInDecls(currentDecls: ArrayList<Decl>, collector: MacroCollector): Unit {
        var idx: Int64 = 0
        while (idx < currentDecls.size) {
            let currentDecl = currentDecls[idx]
            if (currentDecl.IsMacroCallNode()) {
                let call = MacroCall(currentDecl)
                call.replaceLoc.kind = ReplaceTargetKind.DECL_VECTOR
                call.replaceLoc.loc = idx
                call.replaceLoc.decls = Some(currentDecls)
                call.isOuterMost = true
                collector.macCalls.add(call)
            } else {
                walkNode(currentDecl, { curNode: Node =>
                    UpdateMacroInfo(curNode, collector)
                    return true
                })
            }
            idx++
        }
    }

    public func ReplaceMacroCallsInDecls(macroCalls: ArrayList<MacroCall>): Unit {
        var idx = macroCalls.size - 1
        while (idx >= 0) {
            ReplaceEachMacro(macroCalls[idx])
            if (idx == 0) {
                break
            }
            idx--
        }
    }

    private func EvaluateMacros(): Unit {
        let evaluator = MacroEvaluation(ci, macroCollector, ci.invocation.globalOptions.enableMacroInLSP)
        evaluator.Evaluate()
        tokensEvalInMacro.clear()
        for (code in evaluator.GetVecOfGeneratedCodes()) {
            tokensEvalInMacro.add(code)
        }
    }

    public func ReplaceAST(pkg: Package): Unit {
        let _ = pkg
        var idx = macroCollector.macCalls.size - 1
        while (idx >= 0) {
            ReplaceEachMacro(macroCollector.macCalls[idx])
            if (idx == 0) {
                break
            }
            idx--
        }
    }

    public func ReplaceEachMacro(macCall: MacroCall): Unit {
        let invocation = macCall.RequireInvocation()
        if (MacroExpandFailed(invocation.newTokens) || macCall.status == MacroEvalStatus.FAIL) {
            return
        }
        let nodes = parseGeneratedNodes(invocation.newTokens, macCall)
        for (node in nodes) {
            if (node.IsInvalid()) {
                return
            }
            if (hasMacroCallInNode(node, ci.diag)) {
                return
            }
        }
        ReplaceEachMacroHelper(macCall, nodes)
    }

    public func ReplaceEachMacroHelper(macroNode: MacroCall, newNodes: ArrayList<Node>): Unit {
        let target = macroNode.replaceLoc
        if (target.kind == ReplaceTargetKind.EXPR_BOX) {
            if (newNodes.size == 1) {
                if (let Some(replacementExpr) <- (newNodes[0] as Expr)) {
                    if (AssignExprReplacement(target, replacementExpr)) {
                        if (let Some(file) <- macroNode.RequireNode().curFile) {
                            file.originalMacroCallNodes.add(macroNode.RequireNode())
                        }
                    }
                } else {
                    ci.diag.Diagnose(newNodes[0].begin, "expect one expression from macro expansion")
                }
            } else {
                ci.diag.Diagnose(macroNode.GetBeginPos(), "expect one expression from macro expansion")
            }
        } else if (target.kind == ReplaceTargetKind.NODE_VECTOR) {
            if (let Some(nodes) <- target.nodes) {
                replaceNodeVector(nodes, target.loc, newNodes)
            }
        } else if (target.kind == ReplaceTargetKind.DECL_VECTOR) {
            if (let Some(decls) <- target.decls) {
                replaceDeclVector(decls, target.loc, newNodes, ci.diag)
            }
        } else if (target.kind == ReplaceTargetKind.PARAM_VECTOR) {
            if (let Some(params) <- target.params) {
                replaceParamVector(params, target.loc, newNodes, ci.diag)
            }
        } else {
            ci.diag.Diagnose(macroNode.GetBeginPos(), "invalid node expanded in macro call's father node")
        }
    }
}
