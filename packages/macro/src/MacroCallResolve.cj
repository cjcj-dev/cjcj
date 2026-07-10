package cjcj::macro_pkg

import std.collection.*
import std.fs.exists

private let MACRO_COMMON_ARGS: Int64 = 1
private let MACRO_ATTR_ARGS: Int64 = 2
private let MACRO_DEF_NUM: Int64 = 2
private let DIR_SEPARATOR: String = "/"

private let STANDARD_LIBS: Array<(String, String)> = [
    ("std.core", "core"), ("std.binary", "binary"), ("std.io", "io"), ("std.math", "math"),
    ("std.overflow", "overflow"), ("std.runtime", "runtime"), ("std.convert", "convert"),
    ("std.random", "random"), ("std.collection", "collection"), ("std.unicode", "unicode"),
    ("std.sort", "sort"), ("std.argopt", "argopt"), ("std.time", "time"), ("std.sync", "sync"),
    ("std.collection.concurrent", "collection.concurrent"), ("std.net", "net"), ("std.regex", "regex"),
    ("std.unittest.common", "unittest.common"), ("std.unittest.prop_test", "unittest.prop_test"),
    ("std.unittest.diff", "unittest.diff"), ("std.math.numeric", "math.numeric"), ("std.fs", "fs"),
    ("std.unittest.mock.internal", "unittest.mock.internal"), ("std.unittest.mock", "unittest.mock"),
    ("std.reflect", "reflect"), ("std.ref", "ref"), ("std.crypto", "crypto"),
    ("std.crypto.digest", "crypto.digest"), ("std.crypto.cipher", "crypto.cipher"),
    ("std.console", "console"), ("std.database", "database"), ("std.database.sql", "database.sql"),
    ("std.posix", "posix"), ("std.process", "process"), ("std.env", "env"),
    ("std.objectpool", "objectpool"), ("std.unittest", "unittest"), ("std", "std"),
    ("std.ffi.python", "ffi.python"), ("fuzz.fuzz", "fuzz")
]

public func GetMacroFuncName(fullPackageName: String, isAttr: Bool, ident: String): String {
    let prefix = if (isAttr) { "macroCall_a_" } else { "macroCall_c_" }
    return (prefix + ident + "_" + fullPackageName).replace(".", "_").replace(":", "_")
}

private func splitQualifiedName(name: String): ArrayList<String> {
    let parts = ArrayList<String>()
    var start: Int64 = 0
    var idx: Int64 = 0
    while (idx < name.size) {
        if (name[idx] == b'.') {
            parts.add(name[start..idx])
            start = idx + 1
        }
        idx++
    }
    parts.add(name[start..])
    return parts
}

private func getDirPath(path: String): String {
    if (path.isEmpty()) {
        return "."
    }
    if (let Some(pos) <- path.lastIndexOf(DIR_SEPARATOR)) {
        if (pos == 0) {
            return DIR_SEPARATOR
        }
        return path[0..pos]
    }
    return "."
}

private func joinPath(base: String, append: String): String {
    if (base.isEmpty() || base == ".") {
        return append
    }
    if (base[base.size - 1] == b'/') {
        return base + append
    }
    return base + DIR_SEPARATOR + append
}

private func fileExists(path: String): Bool {
    try {
        return exists(path)
    } catch (e: Exception) {
        return false
    }
}

private func findFileByName(fileName: String, searchPaths: ArrayList<String>): String {
    if (fileName.isEmpty()) {
        return ""
    }
    for (path in searchPaths) {
        if (path.isEmpty()) {
            continue
        }
        let candidate = joinPath(path, fileName)
        if (fileExists(candidate)) {
            return candidate
        }
    }
    if (fileExists(fileName)) {
        return fileName
    }
    return ""
}

private func standardLibName(fullPackageName: String): Option<String> {
    for ((name, mapped) in STANDARD_LIBS) {
        if (name == fullPackageName) {
            return Some(mapped)
        }
    }
    return None
}

private func toCjoFileName(fullPackageName: String): String {
    if (let Some(pos) <- fullPackageName.indexOf("::")) {
        return fullPackageName[(pos + 2)..] + "_" + fullPackageName[0..pos]
    }
    return fullPackageName
}

private func convertPackageNameToLibCangjieBaseFormat(fullPackageName: String): String {
    if (let Some(mapped) <- standardLibName(fullPackageName)) {
        let names = splitQualifiedName(fullPackageName)
        if (names.size == 1) {
            return "cangjie-" + mapped
        }
        return "cangjie-" + names[0] + "-" + mapped
    }
    return ""
}

private func collectParentMacroName(macCall: MacroCall): Unit {
    if (let Some(parent) <- macCall.parentMacroCall) {
        for (name in parent.parentNames) {
            macCall.parentNames.add(name)
        }
        macCall.parentNames.add(parent.GetFullName())
    }
}

private func getAllDeclsForMacroName(macCall: MacroCall, macroName: String, out: ArrayList<Decl>): Bool {
    if (let Some(instance) <- macCall.ci) {
        let identifier = macCall.GetIdentifier()
        if (let Some(node) <- macCall.GetNode()) {
            if (let Some(file) <- node.curFile) {
                if (macroName.contains(".")) {
                    // The package name may be an alias: import p0.* as p1.*, p1 is the alias for p0.
                    let pkgNameMaybeAlias = macroName[0..(macroName.lastIndexOf(".") ?? 0)]
                    let (packageDeclOpt, isConflicted) = instance.importManager.GetImportedPackageDecl(node,
                        pkgNameMaybeAlias)
                    if (let Some(packageDecl) <- packageDeclOpt) {
                        if (isConflicted) {
                            instance.GetDiag().Diagnose(macCall.GetBeginPos(), DiagKind.sema_package_name_conflict,
                                args: [DiagArgument(pkgNameMaybeAlias)]).Emit()
                            return false
                        }
                        for (foundDecl in instance.importManager.GetPackageMembersByName(packageDecl.srcPackage,
                            identifier)) {
                            out.add(foundDecl)
                        }
                    } else {
                        instance.GetDiag().Diagnose(macCall.GetBeginPos(), DiagKind.macro_undefined_pkg_name,
                            args: [DiagArgument(pkgNameMaybeAlias)]).Emit()
                        return false
                    }
                } else {
                    for (importedDecl in instance.importManager.GetImportedDeclsByName(file, identifier)) {
                        out.add(importedDecl)
                    }
                }
            }
        }
    }
    return true
}

private func firstParamCount(fd: FuncDecl): Int64 {
    if (fd.funcBody.getOrThrow().paramLists.isEmpty()) {
        return 0
    }
    return fd.funcBody.getOrThrow().paramLists[0].params.size
}

private func isMacroFuncDecl(decl: Decl): Bool {
    return ASTKindEquals(decl.astKind, ASTKind.FUNC_DECL) && decl.TestAttr(Attribute.MACRO_FUNC)
}

private func isDeclInMacroPackage(decl: Decl): Bool {
    if (let Some(file) <- decl.curFile) {
        if (let Some(pkg) <- file.curPackage) {
            return pkg.isMacroPackage
        }
    }
    return true
}

private func getValidFuncDecl(macCall: MacroCall, decls: ArrayList<Decl>): Bool {
    let fds = ArrayList<FuncDecl>()
    for (decl in decls) {
        if (!isMacroFuncDecl(decl)) {
            if (macCall.RequireInvocation().hasParenthesis) {
                if (let Some(instance) <- macCall.ci) {
                    instance.GetDiag().Diagnose(macCall.GetBeginPos(),
                        "expect macro definition '" + macCall.GetIdentifier() + "', but found another declaration")
                }
                return false
            }
            continue
        }
        if (!isDeclInMacroPackage(decl)) {
            continue
        }
        if (let Some(fd) <- (decl as FuncDecl)) {
            fds.add(fd)
        }
    }
    if (fds.isEmpty()) {
        if (macCall.RequireInvocation().hasParenthesis && !macCall.RequireInvocation().IsIfAvailable()) {
            if (let Some(instance) <- macCall.ci) {
                instance.GetDiag().Diagnose(macCall.GetBeginPos(), "undeclared macro identifier '" +
                    macCall.GetIdentifier() + "'")
            }
        }
        return false
    }
    if (fds.size == 1 && !fds[0].funcBody.getOrThrow().paramLists.isEmpty()) {
        let argsSize = firstParamCount(fds[0])
        if (macCall.HasAttribute()) {
            if (argsSize != MACRO_ATTR_ARGS) {
                if (let Some(instance) <- macCall.ci) {
                    instance.GetDiag().Diagnose(macCall.GetBeginPos(),
                        "expect an attributed macro '" + macCall.GetIdentifier() + "', but find a plain one")
                }
                return false
            }
        } else if (argsSize != MACRO_COMMON_ARGS) {
            if (let Some(instance) <- macCall.ci) {
                instance.GetDiag().Diagnose(macCall.GetBeginPos(),
                    "expect a plain macro '" + macCall.GetIdentifier() + "', but find an attributed one")
            }
            return false
        }
        macCall.BindDefinition(fds[0])
        return true
    }
    if (fds.size == MACRO_DEF_NUM && !fds[0].funcBody.getOrThrow().paramLists.isEmpty() &&
        !fds[1].funcBody.getOrThrow().paramLists.isEmpty()) {
        let argsSize1 = firstParamCount(fds[0])
        let argsSize2 = firstParamCount(fds[1])
        if (argsSize1 == argsSize2) {
            if (let Some(instance) <- macCall.ci) {
                instance.GetDiag().Diagnose(macCall.GetBeginPos(), "ambiguous match for macro call " + macCall.GetIdentifier())
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
    return true
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
    if (macCall.GetDefinition().isSome()) {
        return true
    }
    if (let Some(instance) <- macCall.ci) {
        instance.GetDiag().Diagnose(macCall.GetBeginPos(), "ambiguous match for macro call " + macCall.GetIdentifier())
    }
    return false
}

private func findStdMacroLibPath(packageName: String, instance: MacroHost): String {
    let baseName = convertPackageNameToLibCangjieBaseFormat(packageName)
    if (baseName.isEmpty()) {
        return ""
    }
    let libName = "lib" + baseName + LIB_SUFFIX
    let executablePath = instance.GetGlobalOptions().executablePath
    if (!executablePath.isEmpty()) {
        let candidate = joinPath(joinPath(getDirPath(executablePath), "../runtime/lib"), libName)
        if (fileExists(candidate)) {
            return candidate
        }
    }
    let foundInSearch = findFileByName(libName, instance.importManager.GetSearchPath())
    if (!foundInSearch.isEmpty()) {
        return foundInSearch
    }
    return ""
}

private func findMacroDefPkg(macCall: MacroCall, instance: MacroHost, fd: FuncDecl): Unit {
    for (packageName in instance.importManager.GetImportedStdMacroPackages()) {
        if (packageName == fd.fullPackageName) {
            macCall.libPath = findStdMacroLibPath(packageName, instance)
            return
        }
    }
    let libName = "lib-macro_" + toCjoFileName(fd.fullPackageName) + LIB_SUFFIX
    let names = splitQualifiedName(fd.fullPackageName)
    if (!names.isEmpty()) {
        let nestedName = toCjoFileName(names[0]) + DIR_SEPARATOR + libName
        let nestedPath = findFileByName(nestedName, instance.importManager.GetSearchPath())
        if (!nestedPath.isEmpty()) {
            macCall.libPath = nestedPath
            return
        }
    }
    macCall.libPath = findFileByName(libName, instance.importManager.GetSearchPath())
}

private func bindInvokeFunc(macCall: MacroCall): Bool {
    if (let Some(fd) <- macCall.GetDefinition()) {
        macCall.methodName = GetMacroFuncName(fd.fullPackageName, macCall.HasAttribute(), fd.identifier.GetRawText())
        macCall.packageName = fd.fullPackageName
        if (let Some(instance) <- macCall.ci) {
            if (instance.GetGlobalOptions().enableMacroInLSP) {
                collectParentMacroName(macCall)
            }
            if (instance.GetGlobalOptions().macroLib.isEmpty()) {
                findMacroDefPkg(macCall, instance, fd)
            }
        } else if (macCall.libPath.isEmpty()) {
            macCall.libPath = "lib-macro_" + toCjoFileName(fd.fullPackageName) + LIB_SUFFIX
        }
        return macCall.FindMacroDefMethod()
    }
    return false
}

extend MacroCall {
    public func ResolveMacroCall(instance: MacroHost): Bool {
        ci = Some(instance)
        let macCallFullName = GetFullName()
        if (IsBuiltInMacro(macCallFullName)) {
            return true
        }
        if (let Some(value) <- GetNode()) {
            if (let Some(decl) <- (value as MacroExpandDecl)) {
                if (let Some(innerDecl) <- decl.invocation.decl) {
                    if (ASTKindEquals(innerDecl.astKind, ASTKind.TYPE_ALIAS_DECL)) {
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
                current.GetDiag().Diagnose(GetBeginPos(), "Cannot find method from dynamic libs for macro call '" +
                    GetFullName() + "'")
            }
            return false
        }
        return true
    }
}
