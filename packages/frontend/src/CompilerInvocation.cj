package cangjie_compiler::frontend

import std.collection.*

public class CompilerInvocation {
    public var globalOptions: GlobalOptions = GlobalOptions()
    public let frontendOptions: FrontendOptions = FrontendOptions()
    public let optionTable: OptionTable = CreateOptionTable(frontendMode: true)
    public let argList: ArgList = ArgList()

    public init() {}

    public func ParseArgs(args: Array<String>): Bool {
        if (!optionTable.ParseArgs(args, argList)) {
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
        @When[os == "Windows"]
        let runtimeLib = "libcangjie-runtime.dll"
        @When[os == "macOS"]
        let runtimeLib = "libcangjie-runtime.dylib"
        @When[os != "Windows" && os != "macOS"]
        let runtimeLib = "libcangjie-runtime.so"
        let exePath = globalOptions.executablePath
        let hostPathName = globalOptions.GetCangjieLibHostPathName()
        let basePath = JoinPath(GetDirPath(exePath), relativePath)
        return JoinPath(JoinPath(basePath, hostPathName), runtimeLib)
    }
}
