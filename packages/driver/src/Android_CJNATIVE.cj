package cjcj::driver

import std.collection.*

public class Android_CJNATIVE <: Linux_CJNATIVE {
    private var androidSysroot: String = ""

    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
        androidSysroot = driverOptions.sysroot
    }

    public override func InitializeLibraryPaths(): Unit {
        let clangSearchPaths = if (driverOptions.toolChainPaths.isEmpty()) {
            driverOptions.environment.paths.toArray()
        } else {
            driverOptions.toolChainPaths.toArray()
        }
        let clangPath = FileUtil.FindProgramByName(driverOptions.target.GetEffectiveTripleString() + "-clang",
            clangSearchPaths)
        if (!clangPath.isEmpty()) {
            let clangDir = FileUtil.GetDirPath(clangPath)
            DeduceToolchainLibPath(clangDir)
            androidSysroot = FileUtil.JoinPath(FileUtil.GetDirPath(clangDir), "sysroot")
        }
        if (driverOptions.customizedSysroot) {
            androidSysroot = driverOptions.sysroot
        }
        if (!androidSysroot.isEmpty()) {
            let suffix = if (driverOptions.target.arch == ArchType.ARM32) {
                "-linux-androideabi/"
            } else {
                "-linux-android/"
            }
            let tripleDirectory = "usr/lib/" + driverOptions.target.ArchToString() + suffix
            AddLibraryPath(FileUtil.JoinPath(androidSysroot, tripleDirectory + driverOptions.target.apiLevel))
            AddLibraryPath(FileUtil.JoinPath(androidSysroot, tripleDirectory))
            AddLibraryPath(androidSysroot)
        }
        AddCRuntimeLibraryPaths()
    }

    private func DeduceToolchainLibPath(toolchainPath: String): Unit {
        let toolChainRoot = FileUtil.GetDirPath(toolchainPath)
        var clangRtLibRoot = FileUtil.JoinPath(toolChainRoot, "lib64/clang")
        if (!FileUtil.FileExist(clangRtLibRoot)) {
            clangRtLibRoot = FileUtil.JoinPath(toolChainRoot, "lib/clang")
        }
        var selectedClangVersion = GCCVersion()
        var selectedClangPath = ""
        for (directory in FileUtil.GetDirectories(clangRtLibRoot)) {
            if (let Some(version) <- GCCPathScanner.StrToGCCVersion(directory.name)) {
                if (selectedClangVersion < version) {
                    selectedClangPath = directory.path
                    selectedClangVersion = version
                }
            }
        }
        if (!selectedClangPath.isEmpty()) {
            if (driverOptions.target.arch == ArchType.ARM32) {
                AddLibraryPath(FileUtil.JoinPath(selectedClangPath, "lib/linux/arm"))
            } else {
                AddLibraryPath(FileUtil.JoinPath(selectedClangPath, "lib/linux/aarch64"))
            }
            AddLibraryPath(FileUtil.JoinPath(selectedClangPath, "lib/linux"))
        }
    }

    protected override func AddCRuntimeLibraryPaths(): Unit {
        let suffix = if (driverOptions.target.arch == ArchType.ARM32) { "-linux-androideabi" } else { "-linux-android" }
        let tripleDir = driverOptions.target.ArchToString() + suffix
        AddCRuntimeLibraryPath(FileUtil.JoinPath(androidSysroot, "usr/lib/" + tripleDir + "/" + driverOptions.target.apiLevel))
    }

    public override func PrepareDependencyPath(): Bool {
        objcopyPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLVM_OBJCOPY))
        if (objcopyPath.isEmpty()) {
            return false
        }
        arPath = FindUserToolPath(ToolName(ToolID.LLVM_AR))
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

    private func GetAndroidCjldScript(tool: Tool): String {
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
        } else {
            tool.AppendArg("-z")
            tool.AppendArg("noexecstack")
        }
        tool.AppendArgIf(driverOptions.stripSymbolTable, "-s")
        tool.AppendArg("--hash-style=both")
        tool.AppendArg("-EL")
        tool.AppendArg("-m")
        tool.AppendArg(GetEmulation())
        let cjldScript = GetAndroidCjldScript(tool)
        if (driverOptions.outputMode == OutputMode.EXECUTABLE) {
            tool.AppendArg("-pie")
        }
        let crtBeginName = if (driverOptions.outputMode == OutputMode.EXECUTABLE) {
            "crtbegin_dynamic.o"
        } else {
            "crtbegin_so.o"
        }
        if (let Some(crtBegin) <- FileUtil.FindFileByName(crtBeginName, GetCRuntimeLibraryPath().toArray())) {
            tool.AppendArg(crtBegin)
        } else {
            tool.AppendArg(crtBeginName)
        }
        HandleLLVMLinkOptions(objFiles, gccLibPath, tool, cjldScript)
        let crtEndName = if (driverOptions.outputMode == OutputMode.EXECUTABLE) {
            "crtend_android.o"
        } else {
            "crtend_so.o"
        }
        if (let Some(crtEnd) <- FileUtil.FindFileByName(crtEndName, GetCRuntimeLibraryPath().toArray())) {
            tool.AppendArg(crtEnd)
        } else {
            tool.AppendArg(crtEndName)
        }
        backendCmds.add(MakeSingleToolBatch(tool))
    }

    protected override func GenerateLinkOptions(tool: Tool): Unit {
        tool.AppendArg("-lclang_rt.builtins-" + driverOptions.target.ArchToString() + "-android")
        tool.AppendArg("-l:libcangjie-runtime.so")
        tool.AppendArg("-lboundscheck")
        tool.AppendArg("-lm")
        tool.AppendArg("-lc")
        tool.AppendArg("-lclang_rt.builtins-" + driverOptions.target.ArchToString() + "-android")
        tool.AppendArg("-ldl")
        tool.AppendArg("-z")
        if (driverOptions.target.arch == ArchType.ARM32) {
            tool.AppendArg("max-page-size=4096")
        } else {
            tool.AppendArg("max-page-size=16384")
        }
    }

    protected override func HandleSanitizerDependencies(tool: Tool): Unit {
        tool.AppendArg("-lpthread")
        tool.AppendArg("-lrt")
        tool.AppendArg("-lm")
        tool.AppendArg("-ldl")
        tool.AppendArg("-lresolv")
    }
}
