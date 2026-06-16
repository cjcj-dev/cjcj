package cangjie_compiler::driver

import std.collection.*

public class Android_CJNATIVE <: Linux_CJNATIVE {
    private var androidSysroot: String = ""

    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
        androidSysroot = driverOptions.sysroot
    }

    protected override func AddCRuntimeLibraryPaths(): Unit {
        let suffix = if (driverOptions.target.arch == ArchType.ARM32) { "-linux-androideabi" } else { "-linux-android" }
        let tripleDir = driverOptions.target.ArchToString() + suffix
        AddCRuntimeLibraryPath(FileUtil.JoinPath(androidSysroot, "usr/lib/" + tripleDir + "/" + driverOptions.target.apiLevel))
        AddCRuntimeLibraryPath(FileUtil.JoinPath(androidSysroot, "usr/lib/" + tripleDir))
    }

    public override func PrepareDependencyPath(): Bool {
        arPath = FindUserToolPath(ToolName(ToolID.LLVM_AR))
        if (arPath.isEmpty()) {
            arPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLVM_AR))
        }
        ldPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLD))
        objcopyPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLVM_OBJCOPY))
        return !arPath.isEmpty() && !ldPath.isEmpty()
    }

    protected override func GenerateLinkOptions(tool: Tool): Unit {
        tool.AppendArg("-lclang_rt.builtins-" + driverOptions.target.ArchToString() + "-android")
        tool.AppendArg("-l:libcangjie-runtime.so")
        tool.AppendArg("-lboundscheck")
        tool.AppendArg("-ldl")
    }
}
