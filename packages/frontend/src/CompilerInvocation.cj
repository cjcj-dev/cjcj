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
        if (!optionTable.ParseArgs(realArgs, argList)) {
            return false
        }
        frontendOptions.SetFrontendMode()
        if (!frontendOptions.ParseFromArgs(argList)) {
            return false
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
