package cangjie_compiler::macro_pkg

import std.collection.*

private let MACRO_COMMON_ARGS: Int64 = 1
private let MACRO_ATTR_ARGS: Int64 = 2
private let MACRO_DEF_NUM: Int64 = 2

public func GetMacroFuncName(fullPackageName: String, isAttr: Bool, ident: String): String {
    let prefix = if (isAttr) { "macroCall_a_" } else { "macroCall_c_" }
    return (prefix + ident + "_" + fullPackageName).replace(".", "_").replace(":", "_")
}

private func declMatchesMacroName(decl: Decl, macroName: String, identifier: String): Bool {
    if (macroName.contains(".")) {
        return decl.identifier == identifier && (decl.fullPackageName + "." + decl.identifier == macroName ||
            decl.fullPackageName.endsWith(macroName[0..(macroName.size - identifier.size - 1)]))
    }
    return decl.identifier == macroName || decl.identifier == identifier
}

private func collectDeclsFromDecl(decl: Decl, macroName: String, identifier: String, out: ArrayList<Decl>): Unit {
    if (declMatchesMacroName(decl, macroName, identifier)) {
        out.add(decl)
    }
    for (member in decl.GetMemberDecls()) {
        collectDeclsFromDecl(member, macroName, identifier, out)
    }
}

private func collectDeclsFromPackage(pkg: Package, macroName: String, identifier: String, out: ArrayList<Decl>): Unit {
    for (file in pkg.files) {
        for (decl in file.decls) {
            collectDeclsFromDecl(decl, macroName, identifier, out)
        }
    }
}

private func getAllDeclsForMacroName(macCall: MacroCall, macroName: String, out: ArrayList<Decl>): Bool {
    if (let Some(instance) <- macCall.ci) {
        let identifier = macCall.GetIdentifier()
        if (let Some(node) <- macCall.GetNode()) {
            if (let Some(file) <- node.curFile) {
                if (let Some(pkg) <- file.curPackage) {
                    collectDeclsFromPackage(pkg, macroName, identifier, out)
                }
            }
        }
        for (pkg in instance.importManager.importedMacroPackages) {
            collectDeclsFromPackage(pkg, macroName, identifier, out)
        }
    }
    return true
}

private func firstParamCount(fd: FuncDecl): Int64 {
    if (fd.funcBody.paramLists.isEmpty()) {
        return 0
    }
    return fd.funcBody.paramLists[0].params.size
}

private func isMacroFuncDecl(decl: Decl): Bool {
    return decl.astKind == ASTKind.FUNC_DECL && decl.TestAttr(Attribute.MACRO_FUNC)
}

private func getValidFuncDecl(macCall: MacroCall, decls: ArrayList<Decl>): Bool {
    let fds = ArrayList<FuncDecl>()
    for (decl in decls) {
        if (!isMacroFuncDecl(decl)) {
            if (macCall.RequireInvocation().hasParenthesis) {
                if (let Some(instance) <- macCall.ci) {
                    instance.diag.Diagnose(macCall.GetBeginPos(),
                        "expect macro definition '" + macCall.GetIdentifier() + "', but found another declaration")
                }
                return false
            }
            continue
        }
        if (let Some(fd) <- (decl as FuncDecl)) {
            fds.add(fd)
        }
    }
    if (fds.isEmpty()) {
        if (macCall.RequireInvocation().hasParenthesis && !macCall.RequireInvocation().IsIfAvailable()) {
            if (let Some(instance) <- macCall.ci) {
                instance.diag.Diagnose(macCall.GetBeginPos(), "undeclared macro identifier '" +
                    macCall.GetIdentifier() + "'")
            }
        }
        return false
    }
    if (fds.size == 1) {
        let argsSize = firstParamCount(fds[0])
        if (macCall.HasAttribute()) {
            if (argsSize != MACRO_ATTR_ARGS) {
                if (let Some(instance) <- macCall.ci) {
                    instance.diag.Diagnose(macCall.GetBeginPos(),
                        "expect an attributed macro '" + macCall.GetIdentifier() + "', but find a plain one")
                }
                return false
            }
        } else if (argsSize != MACRO_COMMON_ARGS) {
            if (let Some(instance) <- macCall.ci) {
                instance.diag.Diagnose(macCall.GetBeginPos(),
                    "expect a plain macro '" + macCall.GetIdentifier() + "', but find an attributed one")
            }
            return false
        }
        macCall.BindDefinition(fds[0])
        return true
    }
    if (fds.size == MACRO_DEF_NUM) {
        let argsSize1 = firstParamCount(fds[0])
        let argsSize2 = firstParamCount(fds[1])
        if (argsSize1 == argsSize2) {
            if (let Some(instance) <- macCall.ci) {
                instance.diag.Diagnose(macCall.GetBeginPos(), "ambiguous match for macro call " + macCall.GetIdentifier())
            }
            return false
        }
        if (macCall.HasAttribute()) {
            macCall.BindDefinition(if (argsSize1 == MACRO_ATTR_ARGS) { fds[0] } else { fds[1] })
        } else {
            macCall.BindDefinition(if (argsSize1 == MACRO_COMMON_ARGS) { fds[0] } else { fds[1] })
        }
        return true
    }
    if (let Some(instance) <- macCall.ci) {
        instance.diag.Diagnose(macCall.GetBeginPos(), "ambiguous match for macro call " + macCall.GetIdentifier())
    }
    return false
}

private func bindDefinitionByName(macCall: MacroCall, macroName: String): Bool {
    if (macCall.GetDefinition().isSome()) {
        return true
    }
    let decls = ArrayList<Decl>()
    if (!getAllDeclsForMacroName(macCall, macroName, decls)) {
        return false
    }
    if (!getValidFuncDecl(macCall, decls)) {
        return false
    }
    return macCall.GetDefinition().isSome()
}

private func bindInvokeFunc(macCall: MacroCall): Bool {
    if (let Some(fd) <- macCall.GetDefinition()) {
        macCall.methodName = GetMacroFuncName(fd.fullPackageName, macCall.HasAttribute(), fd.identifier)
        macCall.packageName = fd.fullPackageName
        if (macCall.libPath.isEmpty()) {
            macCall.libPath = "lib-macro_" + fd.fullPackageName.replace(".", "_") + LIB_SUFFIX
        }
        return macCall.FindMacroDefMethod()
    }
    return false
}

extend MacroCall {
    public func ResolveMacroCall(instance: CompilerInstance): Bool {
        ci = Some(instance)
        let macCallFullName = GetFullName()
        if (IsBuiltInMacro(macCallFullName)) {
            return true
        }
        if (let Some(value) <- GetNode()) {
            if (let Some(decl) <- (value as MacroExpandDecl)) {
                if (let Some(innerDecl) <- decl.invocation.decl) {
                    if (innerDecl.astKind == ASTKind.TYPE_ALIAS_DECL) {
                        return false
                    }
                }
            }
            if (let Some(expr) <- (value as MacroExpandExpr)) {
                if (expr.invocation.IsIfAvailable()) {
                    return false
                }
            }
        }
        if (!bindDefinitionByName(this, macCallFullName)) {
            return false
        }
        if (!bindInvokeFunc(this)) {
            status = MacroEvalStatus.FAIL
            if (let Some(current) <- ci) {
                current.diag.Diagnose(GetBeginPos(), "Cannot find method from dynamic libs for macro call '" +
                    GetFullName() + "'")
            }
            return false
        }
        return true
    }
}
