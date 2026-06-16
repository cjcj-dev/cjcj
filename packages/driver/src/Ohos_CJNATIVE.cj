package cangjie_compiler::driver

import std.collection.*

public class Ohos_CJNATIVE <: Linux_CJNATIVE {
    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
    }

    protected override func AddCRuntimeLibraryPaths(): Unit {
        for (path in driverOptions.toolChainPaths) {
            AddCRuntimeLibraryPath(path)
        }
        AddCRuntimeLibraryPath(FileUtil.JoinPath(driver.cangjieHome, "lib/" + driverOptions.target.GetEffectiveTripleString()))
    }

    public override func PrepareDependencyPath(): Bool {
        arPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLVM_AR))
        ldPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLD))
        objcopyPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLVM_OBJCOPY))
        return !arPath.isEmpty() && !ldPath.isEmpty()
    }

    protected override func GenerateLinkOptions(tool: Tool): Unit {
        tool.AppendArg("-l:libcangjie-runtime.so")
        tool.AppendArg("-lboundscheck")
        tool.AppendArg("-lunwind")
    }
}
