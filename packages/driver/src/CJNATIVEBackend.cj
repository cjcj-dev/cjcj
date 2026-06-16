package cangjie_compiler::driver

import std.collection.*

public class CJNATIVEBackend <: Backend {
    private var optPath: String = ""
    private var llcPath: String = ""

    public init(job: Job, driverOptions: DriverOptions, driver: Driver) {
        super(job, driverOptions, driver)
    }

    protected override func GenerateToolChain(): Bool {
        if (driverOptions.target.os == OSType.LINUX) {
            if (driverOptions.target.env == EnvironmentType.OHOS) {
                TC = Ohos_CJNATIVE(driver, driverOptions, backendCmds)
                return true
            }
            if (driverOptions.target.env == EnvironmentType.ANDROID) {
                TC = Android_CJNATIVE(driver, driverOptions, backendCmds)
                return true
            }
            if (driverOptions.target.env == EnvironmentType.GNU ||
                driverOptions.target.env == EnvironmentType.NOT_AVAILABLE) {
                TC = Linux_CJNATIVE(driver, driverOptions, backendCmds)
                return true
            }
            eprintln("error: Unsupported Environment Type: ${driverOptions.target.EnvironmentToString()}")
            return false
        }
        if (driverOptions.target.os == OSType.WINDOWS) {
            if (driverOptions.target.env == EnvironmentType.GNU) {
                TC = MinGW_CJNATIVE(driver, driverOptions, backendCmds)
                return true
            }
            eprintln("error: Unsupported Environment Type: ${driverOptions.target.EnvironmentToString()}")
            return false
        }
        if (driverOptions.target.os == OSType.DARWIN) {
            TC = Darwin_CJNATIVE(driver, driverOptions, backendCmds)
            return true
        }
        if (driverOptions.target.os == OSType.IOS) {
            TC = IOS_CJNATIVE(driver, driverOptions, backendCmds)
            return true
        }
        eprintln("error: Unsupported OS Type: ${driverOptions.target.OSTypeToString()}")
        return false
    }

    protected override func PrepareDependencyPath(): Bool {
        let cjnativeBinSearchPaths = ArrayList<String>()
        if (let Some(home) <- driverOptions.environment.cangjieHome) {
            cjnativeBinSearchPaths.add(FileUtil.JoinPath(home, "third_party/llvm/bin"))
        }
        cjnativeBinSearchPaths.add(FileUtil.JoinPath(driver.cangjieHome, "third_party/llvm/bin"))
        for (path in driverOptions.toolChainPaths) {
            cjnativeBinSearchPaths.add(path)
        }
        for (path in driverOptions.environment.paths) {
            cjnativeBinSearchPaths.add(path)
        }
        optPath = FileUtil.FindProgramByName(ToolName(ToolID.OPT), cjnativeBinSearchPaths.toArray())
        if (optPath.isEmpty()) {
            eprintln("error: not found `opt` in the Cangjie installation, CANGJIE_HOME")
            return false
        }
        llcPath = FileUtil.FindProgramByName(ToolName(ToolID.LLC), cjnativeBinSearchPaths.toArray())
        if (llcPath.isEmpty()) {
            eprintln("error: not found `llc` in the Cangjie installation, CANGJIE_HOME")
            return false
        }
        if (let Some(toolChain) <- TC) {
            return toolChain.PrepareDependencyPath()
        }
        return false
    }

    protected override func ProcessGeneration(): Bool {
        let bitCodeFiles = GetFrontendOutputs()
        if (driverOptions.incrementalCompileNoChange) {
            return ProcessGenerationOfIncrementalNoChangeCompile(bitCodeFiles)
        }
        return ProcessGenerationOfNormalCompile(bitCodeFiles)
    }

    private func GenerateCJNativeBaseTool(toolPath: String): Tool {
        let tool = Tool(toolPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        tool.SetLdLibraryPath(FileUtil.JoinPath(FileUtil.GetDirPath(toolPath), "../lib"))
        return tool
    }

    private func GetFrontendOutputs(): ArrayList<TempFileInfo> {
        let bitCodeFiles = ArrayList<TempFileInfo>()
        for (frontendOutput in driverOptions.frontendOutputFiles) {
            bitCodeFiles.add(frontendOutput)
        }
        for (bcFile in driverOptions.bcInputFiles) {
            let filename = FileUtil.GetFileNameWithoutExtension(bcFile)
            bitCodeFiles.add(TempFileInfo(fileName: filename, filePath: bcFile, rawPath: bcFile, isForeignInput: true))
        }
        return bitCodeFiles
    }

    private func GenerateCacheCopyTool(files: ArrayList<TempFileInfo>, extension: String): Unit {
        let batch = ArrayList<Tool>()
        for (file in files) {
            if (file.isForeignInput) {
                continue
            }
            let srcFile = file.filePath
            let destFile = driverOptions.GetHashedObjFileName(FileUtil.GetFileNameWithoutExtension(srcFile)) + extension
            let tool = Tool("CacheCopy", ToolType.INTERNAL_IMPLEMENTED, driverOptions.environment.allVariables)
            tool.AppendArg(srcFile)
            tool.AppendArg(destFile)
            batch.add(tool)
        }
        backendCmds.add(batch)
    }

    private func ProcessGenerationOfNormalCompile(bitCodeFiles: ArrayList<TempFileInfo>): Bool {
        if (driverOptions.IsLTOEnabled() && driverOptions.enIncrementalCompilation) {
            GenerateCacheCopyTool(bitCodeFiles, ".bc")
        }
        if (driverOptions.IsLTOEnabled()) {
            let frontendOutputFiles = ArrayList<TempFileInfo>()
            let preprocessedFiles = ArrayList<TempFileInfo>()
            for (fileInfo in bitCodeFiles) {
                if (fileInfo.isFrontendOutput) {
                    frontendOutputFiles.add(fileInfo)
                } else {
                    preprocessedFiles.add(fileInfo)
                }
            }
            let processedFrontendFiles = GeneratePreprocessTools(frontendOutputFiles)
            for (fileInfo in processedFrontendFiles) {
                preprocessedFiles.add(fileInfo)
            }
            if (driverOptions.outputMode == OutputMode.STATIC_LIB) {
                return true
            }
            if (let Some(toolChain) <- TC) {
                return toolChain.ProcessGeneration(preprocessedFiles)
            }
            return false
        }
        let preprocessedFiles = GeneratePreprocessTools(bitCodeFiles)
        if (driverOptions.saveTemps) {
            let _ = GenerateCompileTool(preprocessedFiles, emitAssembly: true)
        }
        let objFiles = GenerateCompileTool(preprocessedFiles)
        let batch = ArrayList<Tool>()
        for (objFile in objFiles) {
            let srcFile = objFile.filePath
            let destFile = driverOptions.GetHashedObjFileName(FileUtil.GetFileNameWithoutExtension(srcFile)) + ObjSuffix(driverOptions.target.os)
            if ((driverOptions.aggressiveParallelCompile ?? 1) > 1 && IsParallelCompileObjFile(srcFile)) {
                continue
            }
            let tool = Tool("CacheCopy", ToolType.INTERNAL_IMPLEMENTED, driverOptions.environment.allVariables)
            tool.AppendArg(srcFile)
            tool.AppendArg(destFile)
            batch.add(tool)
        }
        backendCmds.add(batch)
        if (let Some(toolChain) <- TC) {
            return toolChain.ProcessGeneration(objFiles)
        }
        return false
    }

    private func ProcessGenerationOfIncrementalNoChangeCompile(bitCodeFiles: ArrayList<TempFileInfo>): Bool {
        let tempBitCodeFiles = ArrayList<TempFileInfo>()
        for (file in bitCodeFiles) {
            tempBitCodeFiles.add(TempFileInfo(fileName: file.fileName, filePath: file.filePath, rawPath: file.rawPath,
                isFrontendOutput: file.isFrontendOutput, isForeignInput: file.isForeignInput))
        }
        if (driverOptions.IsLTOEnabled()) {
            let inputs = ArrayList<TempFileInfo>()
            for (file in tempBitCodeFiles) {
                let tempFile = TempFileInfo(fileName: file.fileName, filePath: file.filePath, rawPath: file.rawPath,
                    isFrontendOutput: file.isFrontendOutput, isForeignInput: file.isForeignInput)
                if (!file.isForeignInput) {
                    let cachedFile = driverOptions.GetHashedObjFileName(FileUtil.GetFileNameWithoutExtension(file.fileName)) + ".bc"
                    tempFile.filePath = cachedFile
                    tempFile.rawPath = cachedFile
                }
                inputs.add(tempFile)
            }
            let preprocessedFiles = GeneratePreprocessTools(inputs)
            if (driverOptions.outputMode == OutputMode.STATIC_LIB) {
                return true
            }
            if (let Some(toolChain) <- TC) {
                return toolChain.ProcessGeneration(preprocessedFiles)
            }
            return false
        }
        for (file in tempBitCodeFiles) {
            let objFile = driverOptions.GetHashedObjFileName(file.fileName) + ObjSuffix(driverOptions.target.os)
            if (!FileUtil.FileExist(objFile)) {
                eprintln("error: The cache directory is incomplete.")
                return false
            }
            file.filePath = objFile
        }
        if (let Some(toolChain) <- TC) {
            return toolChain.ProcessGeneration(tempBitCodeFiles)
        }
        return false
    }

    private func PreprocessOfNewPassManager(tool: Tool): Unit {
        var passesCollector = "-passes="
        let passItems = ArrayList<String>()
        OPTSetOptimizationLevelOptions({ option: String => passItems.add(option) }, driverOptions)
        OPTSetNewPassManagerOptions({ option: String =>
            if (option.startsWith("-")) { passItems.add(option[1..]) } else { passItems.add(option) }
        }, driverOptions)
        var idx: Int64 = 0
        while (idx < passItems.size) {
            if (idx > 0) {
                passesCollector += ","
            }
            passesCollector += passItems[idx]
            idx++
        }
        tool.AppendArg(passesCollector)
    }

    private func GeneratePreprocessTools(bitCodeFiles: ArrayList<TempFileInfo>): ArrayList<TempFileInfo> {
        let outputFiles = ArrayList<TempFileInfo>()
        let batch = ArrayList<Tool>()
        for (bitCodeFile in bitCodeFiles) {
            let tool = GenerateCJNativeBaseTool(optPath)
            tool.AppendArg(bitCodeFile.filePath)
            PreprocessOfNewPassManager(tool)
            OPTSetOptions({ option: String => tool.AppendArg(option) }, driverOptions)
            OPTSetVerifyOptions({ option: String => tool.AppendArg(option) }, driverOptions)
            OPTSetTripleOptions({ option: String => tool.AppendArg(option) }, driverOptions)
            OPTSetCodeObfuscationOptions({ option: String => tool.AppendArg(option) }, driverOptions)
            OPTSetLTOOptions({ option: String => tool.AppendArg(option) }, driverOptions)
            OPTSetPgoOptions({ option: String => tool.AppendArg(option) }, driverOptions)
            OPTSetTransparentOptions({ option: String => tool.AppendArg(option) }, driverOptions)
            let kind = if (driverOptions.IsLTOEnabled() && driverOptions.outputMode == OutputMode.STATIC_LIB) {
                TempFileKind.O_OPT_BC
            } else {
                TempFileKind.T_OPT_BC
            }
            let optBcFileInfo = TempFileManager.Instance().CreateNewFileInfo(bitCodeFile, kind)
            tool.AppendArg("-o")
            tool.AppendArg(optBcFileInfo.filePath)
            outputFiles.add(optBcFileInfo)
            batch.add(tool)
        }
        backendCmds.add(batch)
        return outputFiles
    }

    private func GenerateCompileTool(bitCodeFiles: ArrayList<TempFileInfo>, emitAssembly!: Bool = false): ArrayList<TempFileInfo> {
        let outputFiles = ArrayList<TempFileInfo>()
        let batch = ArrayList<Tool>()
        for (bitCodeFile in bitCodeFiles) {
            let tool = GenerateCJNativeBaseTool(llcPath)
            tool.AppendArg(bitCodeFile.filePath)
            LLCSetOptions({ option: String => tool.AppendArg(option) }, driverOptions)
            LLCSetTripleOptions({ option: String => tool.AppendArg(option) }, driverOptions)
            LLCSetOptimizationLevelOptions({ option: String => tool.AppendArg(option) }, driverOptions)
            LLCSetTransparentOptions({ option: String => tool.AppendArg(option) }, driverOptions)
            tool.AppendArg(if (emitAssembly) { "--filetype=asm" } else { "--filetype=obj" })
            let fileKind = if (emitAssembly) { TempFileKind.T_ASM } else { TempFileKind.T_OBJ }
            let fileInfo = TempFileManager.Instance().CreateNewFileInfo(bitCodeFile, fileKind)
            tool.AppendArg("-o")
            tool.AppendArg(fileInfo.filePath)
            outputFiles.add(fileInfo)
            batch.add(tool)
        }
        backendCmds.add(batch)
        return outputFiles
    }
}

private func IsParallelCompileObjFile(srcFile: String): Bool {
    let fileName = FileUtil.GetFileNameWithoutExtension(srcFile)
    let extension = FileUtil.GetFileExtension(srcFile)
    if (extension != "o" && extension != "obj") {
        return false
    }
    if (let Some(pos) <- fileName.indexOf("-")) {
        let parallelId = fileName[0..pos]
        if (parallelId.isEmpty()) {
            return false
        }
        for (byte in parallelId.toArray()) {
            if (byte < b'0' || byte > b'9') {
                return false
            }
        }
        return true
    }
    return false
}
