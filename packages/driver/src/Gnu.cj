package cangjie_compiler::driver

import std.collection.*

public open class Gnu <: ToolChain {
    protected var ldPath: String = ""
    protected var arPath: String = ""
    protected var objcopyPath: String = ""

    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
    }

    public open override func InitializeLibraryPaths(): Unit {
        for (path in driverOptions.toolChainPaths) {
            AddCRuntimeLibraryPath(path)
        }
        AddCRuntimeLibraryPaths()
        AddSystemLibraryPaths()
    }

    protected open func AddCRuntimeLibraryPaths(): Unit {
        let archFolderName = GetArchFolderName(driverOptions.target.arch)
        AddCRuntimeLibraryPath(FileUtil.JoinPath(driverOptions.sysroot, archFolderName))
        AddCRuntimeLibraryPath(FileUtil.JoinPath(FileUtil.JoinPath(driverOptions.sysroot, "usr"), archFolderName))
        AddCRuntimeLibraryPath(FileUtil.JoinPath(driverOptions.sysroot, "lib"))
        AddCRuntimeLibraryPath(FileUtil.JoinPath(FileUtil.JoinPath(driverOptions.sysroot, "usr"), "lib"))
    }

    protected open func AddSystemLibraryPaths(): Unit {
        AddLibraryPaths(driverOptions.environment.libraryPaths)
    }

    public open override func PrepareDependencyPath(): Bool {
        let toolPrefix = if (driverOptions.IsCrossCompiling()) { driverOptions.target.GetEffectiveTripleString() + "-" } else { "" }
        arPath = FindUserToolPath(toolPrefix + ToolName(ToolID.AR))
        if (arPath.isEmpty()) {
            eprintln("error: not found `ar` in search paths. You may add search path by `-B` option.")
            return false
        }
        objcopyPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLVM_OBJCOPY))
        if (objcopyPath.isEmpty()) {
            objcopyPath = FindUserToolPath(toolPrefix + ToolName(ToolID.OBJCOPY))
        }
        if (driverOptions.IsLTOEnabled()) {
            ldPath = FindCangjieLLVMToolPath(ToolName(ToolID.LLD))
        } else {
            ldPath = FindUserToolPath(toolPrefix + ToolName(ToolID.LD))
        }
        if (ldPath.isEmpty()) {
            eprintln("error: not found linker in search paths. You may add search path by `-B` option.")
            return false
        }
        return true
    }

    public open override func ProcessGeneration(input: ArrayList<TempFileInfo>): Bool {
        if (driverOptions.outputMode == OutputMode.STATIC_LIB) {
            GenerateArchiveTool(input)
            return true
        }
        if (driverOptions.outputMode == OutputMode.OBJ) {
            GenerateObjTool(input)
            return true
        }
        GenerateLinkingTool(input)
        return true
    }

    protected open func GenerateArchiveTool(objFiles: ArrayList<TempFileInfo>): Unit {
        let tool = Tool(arPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        tool.AppendArg("crD")
        let outputFile = CreateNewFileInfoWrapper(objFiles, TempFileKind.O_STATICLIB).filePath
        let _ = FileUtil.RemovePath(outputFile)
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

    protected open func GenerateLinkingTool(objFiles: ArrayList<TempFileInfo>): Unit {
        let tool = Tool(ldPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        tool.AppendArg("-o")
        tool.AppendArg(GetOutputFileInfo(objFiles).filePath)
        if (driverOptions.outputMode == OutputMode.SHARED_LIB) {
            tool.AppendArg("-shared")
        }
        if (driverOptions.outputMode == OutputMode.EXECUTABLE) {
            tool.AppendArg("-pie")
        }
        tool.AppendArgIf(driverOptions.stripSymbolTable, "-s")
        tool.AppendArg("-m")
        tool.AppendArg(GetEmulation())
        tool.AppendArg("--hash-style=both")
        HandleLibrarySearchPaths(tool)
        SortInputlibraryFileAndAppend(tool, objFiles)
        GenerateLinkOptionsOfBuiltinLibs(tool)
        GenerateLinkOptions(tool)
        GenerateRuntimePath(tool)
        backendCmds.add(MakeSingleToolBatch(tool))
    }

    protected open func HandleLibrarySearchPaths(tool: Tool): Unit {
        for (path in driverOptions.librarySearchPaths) {
            tool.AppendArg("-L" + path)
        }
        tool.AppendArg("-L" + FileUtil.JoinPath(driver.cangjieHome, "lib"))
        tool.AppendArg("-L" + FileUtil.JoinPath(driver.cangjieHome, "runtime/lib"))
        for (path in GetLibraryPaths()) {
            tool.AppendArg("-L" + path)
        }
    }

    protected open func GenerateLinkOptions(tool: Tool): Unit {
        if (driverOptions.linkStatic) {
            tool.AppendArg("-l:libcangjie-runtime.a")
            tool.AppendArg("-l:libcangjie-thread.a")
            tool.AppendArg("-l:libboundscheck-static.a")
            tool.AppendArg("-lstdc++")
            tool.AppendArg("-lpthread")
            tool.AppendArg("-ldl")
            tool.AppendArg("-lm")
            tool.AppendArg("-lc")
        } else {
            tool.AppendArg("-l:libcangjie-runtime.so")
            tool.AppendArg("-lboundscheck")
            tool.AppendArg("-lm")
            tool.AppendArg("-lc")
        }
    }

    protected open func GetEmulation(): String {
        if (driverOptions.target.arch == ArchType.X86_64 && driverOptions.target.os == OSType.LINUX) {
            return "elf_x86_64"
        }
        if (driverOptions.target.arch == ArchType.AARCH64 && driverOptions.target.os == OSType.LINUX) {
            return "aarch64linux"
        }
        if (driverOptions.target.arch == ArchType.ARM32) {
            return "armelf_linux_eabi"
        }
        if (driverOptions.target.os == OSType.WINDOWS) {
            return "i386pep"
        }
        return ""
    }
}
