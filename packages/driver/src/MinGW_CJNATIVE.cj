package cangjie_compiler::driver

import std.collection.*

public class MinGW_CJNATIVE <: Gnu {
    private var mingwSysroot: String = ""
    private var mingwLibPath: String

    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
        mingwLibPath = FileUtil.JoinPath(driver.cangjieHome, "third_party/mingw/lib")
    }

    protected override func GetSharedLibraryExtension(): String { return ".dll" }

    public override func InitializeLibraryPaths(): Unit {
        for (path in driverOptions.toolChainPaths) {
            AddCRuntimeLibraryPath(path)
        }
        InitializeMinGWSysroot()
        AddCRuntimeLibraryPaths()
        AddSystemLibraryPaths()
    }

    private func InitializeMinGWSysroot(): Unit {
        if (driverOptions.customizedSysroot) {
            mingwSysroot = driverOptions.sysroot
            return
        }
        let gccPath = FileUtil.FindProgramByName("x86_64-w64-mingw32-gcc.exe",
            driverOptions.environment.paths.toArray())
        if (!gccPath.isEmpty()) {
            mingwSysroot = FileUtil.GetDirPath(FileUtil.GetDirPath(gccPath))
        }
    }

    protected override func AddCRuntimeLibraryPaths(): Unit {
        let libPath = FileUtil.JoinPath(mingwSysroot, "lib")
        AddCRuntimeLibraryPath(libPath)
        for (directory in FileUtil.GetDirectories(libPath)) {
            if (IsPossibleMatchingTripleName(driverOptions.target, directory.name)) {
                AddCRuntimeLibraryPath(directory.path)
            }
        }
    }

    protected override func AddSystemLibraryPaths(): Unit {
        AddLibraryPaths(ComputeLibPaths())
        super.AddSystemLibraryPaths()
    }

    protected override func ComputeLibPaths(): ArrayList<String> {
        let paths = ArrayList<String>()
        paths.add(FileUtil.JoinPath(mingwSysroot, "lib"))
        paths.add(FileUtil.JoinPath(mingwSysroot, "x86_64-w64-mingw32/lib"))
        return paths
    }

    public override func PrepareDependencyPath(): Bool {
        arPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLVM_AR))
        ldPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLD))
        return !arPath.isEmpty() && !ldPath.isEmpty()
    }

    protected override func GetGccCrtFilePair(): (String, String) {
        return gccExecCrtFilePair
    }

    protected override func GenerateGCCLibPath(gccCrtFilePair: (String, String)): String {
        let _ = gccCrtFilePair
        return mingwLibPath
    }

    protected override func GenerateArchiveTool(objFiles: ArrayList<TempFileInfo>): Unit {
        let tool = Tool(arPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        if (driverOptions.IsCrossCompiling() && FileUtil.GetFileName(arPath).contains("llvm-ar")) {
            tool.SetLdLibraryPath(FileUtil.JoinPath(FileUtil.GetDirPath(arPath), "../lib"))
        }
        tool.AppendArg("crD")
        let outputFile = CreateNewFileInfoWrapper(objFiles, TempFileKind.O_STATICLIB).filePath
        let _ = RemovePath(outputFile)
        tool.AppendArg(outputFile)
        if (objFiles.isEmpty()) {
            for (inputObj in driverOptions.inputObjs) {
                tool.AppendArg(inputObj)
            }
        } else {
            for (objFile in objFiles) {
                tool.AppendArg(objFile.filePath)
            }
        }
        backendCmds.add(MakeSingleToolBatch(tool))
    }

    private func GetMinGWCjldScript(tool: Tool): String {
        var cjldScript = "cjld.lds"
        if (driverOptions.outputMode == OutputMode.SHARED_LIB) {
            tool.AppendArg("-shared")
            cjldScript = "cjld.shared.lds"
        }
        return cjldScript
    }

    protected override func GenerateLinkingTool(
        objFiles: ArrayList<TempFileInfo>,
        gccLibPath: String,
        gccCrtFilePair: (String, String)
    ): Unit {
        let tool = Tool(ldPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        tool.AppendArg("-o")
        tool.AppendArg(GetOutputFileInfo(objFiles).filePath)
        tool.AppendArgIf(driverOptions.stripSymbolTable, "-s")
        tool.AppendArg("--nxcompat")
        tool.AppendArg("--dynamicbase")
        tool.AppendArg("--high-entropy-va")
        tool.AppendArg("-m")
        tool.AppendArg(GetEmulation())
        let cjldScript = GetMinGWCjldScript(tool)
        tool.AppendArg("-Bdynamic")
        if (driverOptions.outputMode == OutputMode.SHARED_LIB) {
            tool.AppendArg("-e")
            tool.AppendArg("DllMainCRTStartup")
            tool.AppendArg("--export-all-symbols")
        }
        if (driverOptions.outputMode == OutputMode.EXECUTABLE ||
            driverOptions.outputMode == OutputMode.SHARED_LIB) {
            let crtObjName = if (driverOptions.outputMode == OutputMode.EXECUTABLE) { "crt2.o" } else { "dllcrt2.o" }
            tool.AppendArg(FileUtil.JoinPath(mingwLibPath, crtObjName))
        }
        tool.AppendArg(GetGccLibFile(gccCrtFilePair[0], gccLibPath))
        if (driverOptions.fastMathMode) {
            let crtfastmathFilepath = GetGccLibFile("crtfastmath.o", gccLibPath)
            if (FileUtil.FileExist(crtfastmathFilepath)) {
                tool.AppendArg(crtfastmathFilepath)
            }
        }
        if (driverOptions.outputMode == OutputMode.EXECUTABLE) {
            tool.AppendArg(FileUtil.JoinPath(mingwLibPath, "CRT_glob.o"))
        }
        HandleLLVMLinkOptions(objFiles, gccLibPath, tool, cjldScript)
        tool.AppendArg(GetGccLibFile(gccCrtFilePair[1], gccLibPath))
        backendCmds.add(MakeSingleToolBatch(tool))
    }

    protected override func HandleLibrarySearchPaths(tool: Tool, cangjieLibPath: String): Unit {
        tool.AppendArg("-L" + mingwLibPath)
        super.HandleLibrarySearchPaths(tool, cangjieLibPath)
    }

    protected override func GenerateLinkOptions(tool: Tool): Unit {
        if (driverOptions.linkStatic) {
            tool.AppendArg("-l:libcangjie-runtime.a")
            tool.AppendArg("-l:libcangjie-thread.a")
            tool.AppendArg("-l:libboundscheck-static.a")
            tool.AppendArg("-l:libc++.a")
            tool.AppendArg("-lclang_rt-builtins")
            tool.AppendArg("-lunwind")
            tool.AppendArg("-lws2_32")
            tool.AppendArg("-ldbghelp")
            tool.AppendArg("-lshlwapi")
        } else {
            tool.AppendArg("-l:libcangjie-runtime.dll")
            tool.AppendArg("-lclang_rt-builtins")
            tool.AppendArg("-lboundscheck")
        }
        tool.AppendArg("-lm")
        tool.AppendArg("-lmsvcrt")
        tool.AppendArg("-lmingw32")
        tool.AppendArg("-lmoldname")
        tool.AppendArg("-lmingwex")
        tool.AppendArg("-lmingw32")
        tool.AppendArg("-lmsvcrt")
        tool.AppendArg("-lpthread")
        tool.AppendArg("-ladvapi32")
        tool.AppendArg("-lshell32")
        tool.AppendArg("-luser32")
        tool.AppendArg("-lkernel32")
        tool.AppendArg("-lmingw32")
        tool.AppendArg("-lmoldname")
        tool.AppendArg("-lmingwex")
        tool.AppendArg("-lmsvcrt")
    }
}
