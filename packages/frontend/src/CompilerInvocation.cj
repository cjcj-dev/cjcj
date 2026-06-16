package cangjie_compiler::frontend

import std.collection.*

public class CompilerInvocation {
    public let globalOptions: GlobalOptions = GlobalOptions()
    public let frontendOptions: FrontendOptions = FrontendOptions()
    public let optionTable: OptionTable = CreateOptionTable(true)
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
        if (!SetupConditionalCompilationCfg(frontendOptions)) {
            return false
        }
        globalOptions.CopyBaseFrom(frontendOptions)
        return true
    }

    public func ParseArgs(args: ArrayList<String>): Bool {
        return ParseArgs(args.toArray())
    }

    public func GetRuntimeLibPath(relativePath!: String = "../runtime/lib"): String {
        let runtimeLib = "libcangjie-runtime.so"
        let exePath = globalOptions.executablePath
        let hostPathName = globalOptions.GetCangjieLibHostPathName()
        let basePath = JoinPath(GetDirPath(exePath), relativePath)
        return JoinPath(JoinPath(basePath, hostPathName), runtimeLib)
    }
}
