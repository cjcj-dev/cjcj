package cangjie_compiler::driver

import std.collection.*

public class MinGW_CJNATIVE <: Gnu {
    private let mingwLibPath: String

    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
        mingwLibPath = FileUtil.JoinPath(driver.cangjieHome, "third_party/mingw/lib")
    }

    protected override func GetSharedLibraryExtension(): String { return ".dll" }

    public override func PrepareDependencyPath(): Bool {
        arPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLVM_AR))
        ldPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLD))
        return !arPath.isEmpty() && !ldPath.isEmpty()
    }

    protected override func HandleLibrarySearchPaths(tool: Tool): Unit {
        tool.AppendArg("-L" + mingwLibPath)
        super.HandleLibrarySearchPaths(tool)
    }

    protected override func GenerateLinkOptions(tool: Tool): Unit {
        if (driverOptions.linkStatic) {
            tool.AppendArg("-l:libcangjie-runtime.a")
            tool.AppendArg("-l:libcangjie-thread.a")
            tool.AppendArg("-l:libboundscheck-static.a")
        } else {
            tool.AppendArg("-l:libcangjie-runtime.dll")
            tool.AppendArg("-lboundscheck")
        }
        tool.AppendArg("-lmsvcrt")
        tool.AppendArg("-lmingw32")
        tool.AppendArg("-lpthread")
    }
}
