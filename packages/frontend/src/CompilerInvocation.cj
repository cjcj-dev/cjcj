package cangjie_compiler::frontend

import std.collection.*

@When[os == "Windows"]
private func FrontendRuntimeLibraryName(): String {
    return "libcangjie-runtime.dll"
}

@When[os == "macOS"]
private func FrontendRuntimeLibraryName(): String {
    return "libcangjie-runtime.dylib"
}

@When[os != "Windows" && os != "macOS"]
private func FrontendRuntimeLibraryName(): String {
    return "libcangjie-runtime.so"
}

public class CompilerInvocation {
    public var globalOptions: GlobalOptions = GlobalOptions()
    public let frontendOptions: FrontendOptions = FrontendOptions()
    public let optionTable: OptionTable = CreateOptionTable(frontendMode: true)
    public let argList: ArgList = ArgList()

    public init() {}

    public func ParseArgs(args: Array<String>): Bool {
        let realArgs = normalizeFrontendArgs(args)
        let filtered = StripModuleSrcPathArgs(realArgs)
        if (!filtered.ok) {
            return false
        }
        if (!optionTable.ParseArgs(filtered.args, argList)) {
            return false
        }
        frontendOptions.SetFrontendMode()
        if (!frontendOptions.ParseFromArgs(argList)) {
            return false
        }
        if (!filtered.moduleSrcPath.isEmpty()) {
            frontendOptions.moduleSrcPath = filtered.moduleSrcPath
            if (frontendOptions.compilePackage && frontendOptions.packagePaths.isEmpty()) {
                frontendOptions.packagePaths.add(filtered.moduleSrcPath)
            }
        }
        frontendOptions.SetCompilationCachedPath()
        globalOptions = frontendOptions
        return true
    }

    public func ParseArgs(args: ArrayList<String>): Bool {
        return ParseArgs(args.toArray())
    }

    public func GetRuntimeLibPath(relativePath!: String = "../runtime/lib"): String {
        let runtimeLib = FrontendRuntimeLibraryName()
        let exePath = globalOptions.executablePath
        let hostPathName = globalOptions.GetCangjieLibHostPathName()
        let basePath = JoinPath(GetDirPath(exePath), relativePath)
        return JoinPath(JoinPath(basePath, hostPathName), runtimeLib)
    }
}

private func normalizeFrontendArgs(args: Array<String>): Array<String> {
    if (!args.isEmpty() && isToolInvocationName(args[0])) {
        return args
    }
    let normalized = ArrayList<String>()
    normalized.add("cjc-frontend")
    for (arg in args) {
        normalized.add(arg)
    }
    return normalized.toArray()
}

private func isToolInvocationName(value: String): Bool {
    let name = GetFileName(value)
    return name == "cjc-frontend" || name == "cjc-frontend.exe" || name == "cjc" || name == "cjc.exe"
}

private class FrontendArgFilterResult {
    public let ok: Bool
    public let args: Array<String>
    public let moduleSrcPath: String

    public init(ok: Bool, args: Array<String>, moduleSrcPath: String) {
        this.ok = ok
        this.args = args
        this.moduleSrcPath = moduleSrcPath
    }
}

private func StripModuleSrcPathArgs(args: Array<String>): FrontendArgFilterResult {
    let filtered = ArrayList<String>()
    var moduleSrcPath = ""
    var idx: Int64 = 0
    while (idx < args.size) {
        let current = args[idx]
        if (current == "--module-src-path") {
            if (idx + 1 >= args.size) {
                return FrontendArgFilterResult(false, filtered.toArray(), "")
            }
            moduleSrcPath = args[idx + 1]
            idx += 2
            continue
        }
        if (current.startsWith("--module-src-path=")) {
            moduleSrcPath = current["--module-src-path=".size..]
            idx++
            continue
        }
        filtered.add(current)
        idx++
    }
    if (!moduleSrcPath.isEmpty()) {
        filtered.add(moduleSrcPath)
    }
    return FrontendArgFilterResult(true, filtered.toArray(), moduleSrcPath)
}
