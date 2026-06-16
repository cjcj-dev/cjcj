package cangjie_compiler::driver

import std.collection.*

public open class MachO <: ToolChain {
    protected var ldPath: String = ""
    protected var arPath: String = ""
    protected var dsymutilPath: String = ""
    protected var stripPath: String = ""

    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        super(driver, driverOptions, backendCmds)
    }

    protected override func GetSharedLibraryExtension(): String { return ".dylib" }

    public open override func InitializeLibraryPaths(): Unit {
        for (path in driverOptions.toolChainPaths) {
            AddCRuntimeLibraryPath(path)
        }
        AddLibraryPaths(driverOptions.environment.libraryPaths)
    }

    public open override func PrepareDependencyPath(): Bool {
        arPath = FindUserToolPath(ToolName(ToolID.AR))
        ldPath = FindCangjieLLVMToolPath(ToolName(ToolID.LD64_LLD))
        dsymutilPath = FindUserToolPath(ToolName(ToolID.DSYMUTIL))
        stripPath = FindUserToolPath(ToolName(ToolID.STRIP))
        return !arPath.isEmpty() && !ldPath.isEmpty()
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
        let output = GenerateLinkingTool(input)
        if (driverOptions.enableCompileDebug && !dsymutilPath.isEmpty()) {
            GenerateDebugSymbolFile(output)
        }
        if (driverOptions.stripSymbolTable && !stripPath.isEmpty()) {
            GenerateStripSymbolFile(output)
        }
        return true
    }

    protected open func GenerateArchiveTool(objFiles: ArrayList<TempFileInfo>): Unit {
        let tool = Tool(arPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        tool.AppendArg("cr")
        let outputFile = CreateNewFileInfoWrapper(objFiles, TempFileKind.O_STATICLIB).filePath
        let _ = FileUtil.RemovePath(outputFile)
        tool.AppendArg(outputFile)
        for (objFile in objFiles) {
            tool.AppendArg(objFile.filePath)
        }
        for (inputObj in driverOptions.inputObjs) {
            tool.AppendArg(inputObj)
        }
        backendCmds.add(MakeSingleToolBatch(tool))
    }

    protected open func GenerateLinkingTool(objFiles: ArrayList<TempFileInfo>): TempFileInfo {
        let output = GetOutputFileInfo(objFiles)
        let tool = Tool(ldPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        tool.AppendArg("-o")
        tool.AppendArg(output.filePath)
        tool.AppendArgIf(driverOptions.outputMode == OutputMode.SHARED_LIB, "-dylib")
        tool.AppendArg("-arch")
        tool.AppendArg(GetTargetArchString())
        tool.AppendArg("-syslibroot")
        tool.AppendArg(if (driverOptions.sysroot.isEmpty()) { "/" } else { driverOptions.sysroot })
        HandleLibrarySearchPaths(tool)
        SortInputlibraryFileAndAppend(tool, objFiles)
        GenerateLinkOptionsOfBuiltinLibs(tool)
        GenerateLinkOptions(tool)
        GenerateRuntimePath(tool)
        backendCmds.add(MakeSingleToolBatch(tool))
        return output
    }

    protected open func GetTargetArchString(): String {
        if (driverOptions.target.arch == ArchType.AARCH64) { return "arm64" }
        if (driverOptions.target.arch == ArchType.X86_64) { return "x86_64" }
        return ""
    }

    protected open func HandleLibrarySearchPaths(tool: Tool): Unit {
        for (path in driverOptions.librarySearchPaths) {
            tool.AppendArg("-L" + path)
        }
        tool.AppendArg("-L" + FileUtil.JoinPath(driver.cangjieHome, "runtime/lib"))
        tool.AppendArg("-L" + FileUtil.JoinPath(driver.cangjieHome, "lib"))
        for (path in GetLibraryPaths()) {
            tool.AppendArg("-L" + path)
        }
    }

    protected open func GenerateLinkOptions(tool: Tool): Unit {
        if (driverOptions.linkStatic) {
            tool.AppendArg(FileUtil.JoinPath(driver.cangjieHome, "lib/libcangjie-runtime.a"))
            tool.AppendArg(FileUtil.JoinPath(driver.cangjieHome, "lib/libcangjie-thread.a"))
            tool.AppendArg(FileUtil.JoinPath(driver.cangjieHome, "lib/libboundscheck-static.a"))
            tool.AppendArg("-lc++")
        } else {
            tool.AppendArg("-lcangjie-runtime")
            tool.AppendArg("-lboundscheck")
        }
        tool.AppendArg("-lSystem")
    }

    protected open func GenerateDebugSymbolFile(binaryFile: TempFileInfo): Unit {
        let tool = Tool(dsymutilPath, ToolType.OTHER, driverOptions.environment.allVariables)
        tool.AppendArg(binaryFile.filePath)
        tool.AppendArg("-o")
        tool.AppendArg(binaryFile.filePath + ".dSYM")
        backendCmds.add(MakeSingleToolBatch(tool))
    }

    protected func GenerateStripSymbolFile(binaryFile: TempFileInfo): Unit {
        let tool = Tool(stripPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        tool.AppendArg(binaryFile.filePath)
        backendCmds.add(MakeSingleToolBatch(tool))
    }
}
