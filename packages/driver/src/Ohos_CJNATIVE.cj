package cjcj::driver

import std.collection.*

public class Ohos_CJNATIVE <: Linux_CJNATIVE {
    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
    }

    protected override func AddCRuntimeLibraryPaths(): Unit {
        for (path in driverOptions.toolChainPaths) {
            AddCRuntimeLibraryPath(path)
        }
        AddCRuntimeLibraryPath(FileUtil.JoinPath(driver.cangjieHome, "lib/" + driverOptions.GetCangjieLibTargetPathName()))
    }

    public override func PrepareDependencyPath(): Bool {
        objcopyPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLVM_OBJCOPY))
        if (objcopyPath.isEmpty()) {
            return false
        }
        arPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLVM_AR))
        if (arPath.isEmpty()) {
            return false
        }
        ldPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLD))
        return !ldPath.isEmpty()
    }

    protected override func GenerateLinking(objFiles: ArrayList<TempFileInfo>): Bool {
        GenerateLinkingTool(objFiles, "", ("", ""))
        return true
    }

    private func GetOhosCjldScript(tool: Tool): String {
        var cjldScript = "cjld.lds"
        if (driverOptions.outputMode == OutputMode.SHARED_LIB) {
            tool.AppendArg("-shared")
            cjldScript = "cjld.shared.lds"
        }
        if (driverOptions.outputMode == OutputMode.EXECUTABLE ||
            driverOptions.outputMode == OutputMode.SHARED_LIB) {
            tool.AppendArg("-dynamic-linker")
            tool.AppendArg(GetDynamicLinkerPath(driverOptions.target))
        }
        return cjldScript
    }

    protected override func GenerateLinkingTool(
        objFiles: ArrayList<TempFileInfo>,
        gccLibPath: String,
        gccCrtFilePair: (String, String)
    ): Unit {
        let _ = gccCrtFilePair
        let tool = Tool(ldPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        tool.SetLdLibraryPath(FileUtil.JoinPath(FileUtil.GetDirPath(ldPath), "../lib"))
        tool.AppendArg("-o")
        tool.AppendArg(GetOutputFileInfo(objFiles).filePath)
        if (driverOptions.IsLTOEnabled()) {
            GenerateLinkOptionsForLTO(tool)
        } else if (driverOptions.EnableHwAsan()) {
            tool.AppendArg("-z")
            tool.AppendArg("notext")
        } else {
            tool.AppendArg("-z")
            tool.AppendArg("noexecstack")
        }
        tool.AppendArg("-z")
        tool.AppendArg("max-page-size=4096")
        tool.AppendArgIf(driverOptions.stripSymbolTable, "-s")
        tool.AppendArg("--hash-style=both")
        tool.AppendArg("-m")
        tool.AppendArg(GetEmulation())
        let cjldScript = GetOhosCjldScript(tool)
        if (driverOptions.outputMode == OutputMode.EXECUTABLE) {
            tool.AppendArg("-pie")
            if (let Some(crt1) <- FileUtil.FindFileByName("Scrt1.o", GetCRuntimeLibraryPath().toArray())) {
                tool.AppendArg(crt1)
            } else {
                tool.AppendArg("Scrt1.o")
            }
        }
        if (let Some(crti) <- FileUtil.FindFileByName("crti.o", GetCRuntimeLibraryPath().toArray())) {
            tool.AppendArg(crti)
        } else {
            tool.AppendArg("crti.o")
        }
        HandleLLVMLinkOptions(objFiles, gccLibPath, tool, cjldScript)
        GenerateRuntimePath(tool)
        if (let Some(crtn) <- FileUtil.FindFileByName("crtn.o", GetCRuntimeLibraryPath().toArray())) {
            tool.AppendArg(crtn)
        } else {
            tool.AppendArg("crtn.o")
        }
        backendCmds.add(MakeSingleToolBatch(tool))
    }

    protected override func GenerateLinkOptions(tool: Tool): Unit {
        tool.AppendArg("-l:libcangjie-runtime.so")
        tool.AppendArg("-L" + FileUtil.JoinPath(driver.cangjieHome, "lib/" + driverOptions.GetCangjieLibTargetPathName()))
        tool.AppendArg("-lboundscheck")
        tool.AppendArg("-lm")
        tool.AppendArg("-lc")
        tool.AppendArg("-lclang_rt.builtins")
        tool.AppendArg("-lunwind")
    }

    protected override func HandleSanitizerDependencies(tool: Tool): Unit {
        tool.AppendArg("-lpthread")
        tool.AppendArg("-lrt")
        tool.AppendArg("-lm")
        tool.AppendArg("-ldl")
        tool.AppendArg("-lresolv")
    }

    protected override func GetClangRTProfileLibraryName(): String {
        return "libclang_rt.profile.a"
    }
}
