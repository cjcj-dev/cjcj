package cangjie_compiler::driver

import std.collection.*

private func LinkStaticLibrary(tool: Tool, lib: String): Unit {
    tool.AppendArg("--whole-archive")
    tool.AppendArg(lib)
    tool.AppendArg("--no-whole-archive")
}

private func RenderSymbolLocalizationFile(symbols: ArrayList<String>): String {
    let builder = StringBuilder()
    for (symbol in symbols) {
        builder.append(symbol)
        builder.append("\n")
    }
    return builder.toString()
}

public open class Gnu <: ToolChain {
    protected var ldPath: String = ""
    protected var arPath: String = ""
    protected var objcopyPath: String = ""
    protected let gccExecCrtFilePair: (String, String) = ("crtbegin.o", "crtend.o")
    protected let gccSharedCrtFilePair: (String, String) = ("crtbeginS.o", "crtendS.o")

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
        let libPath = FileUtil.JoinPath(driverOptions.sysroot, "lib")
        for (directory in FileUtil.GetDirectories(libPath)) {
            if (IsPossibleMatchingTripleName(driverOptions.target, directory.name)) {
                AddCRuntimeLibraryPath(directory.path)
            }
        }
        let usrLibPath = FileUtil.JoinPath(FileUtil.JoinPath(driverOptions.sysroot, "usr"), "lib")
        for (directory in FileUtil.GetDirectories(usrLibPath)) {
            if (IsPossibleMatchingTripleName(driverOptions.target, directory.name)) {
                AddCRuntimeLibraryPath(directory.path)
            }
        }
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
        if (driverOptions.IsLTOEnabled() || driverOptions.EnableHwAsan()) {
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
        var codegenOutputBCNum: Int64 = 0
        for (obj in input) {
            if (!obj.isForeignInput) {
                codegenOutputBCNum++
            }
        }
        if (codegenOutputBCNum > 1) {
            return PerformPartialLinkAndContinue(input)
        }
        return FinishGeneration(input)
    }

    protected func FinishGeneration(objFiles: ArrayList<TempFileInfo>): Bool {
        if (driverOptions.outputMode == OutputMode.STATIC_LIB) {
            GenerateArchiveTool(objFiles)
            return true
        }
        if (driverOptions.outputMode == OutputMode.OBJ) {
            GenerateObjTool(objFiles)
            return true
        }
        return GenerateLinking(objFiles)
    }

    protected func PerformPartialLinkAndContinue(objFiles: ArrayList<TempFileInfo>): Bool {
        let packageNames = ArrayList<String>()
        let packageModules = ArrayList<ArrayList<TempFileInfo>>()
        let foreignInputs = ArrayList<TempFileInfo>()
        for (objFile in objFiles) {
            if (objFile.isForeignInput) {
                foreignInputs.add(objFile)
                continue
            }
            let fileName = FileUtil.GetFileNameWithoutExtension(objFile.filePath)
            let pkgName = if (let Some(pos) <- fileName.indexOf("-")) { fileName[pos + 1..] } else { fileName }
            var groupIndex: Int64 = -1
            var idx: Int64 = 0
            while (idx < packageNames.size) {
                if (packageNames[idx] == pkgName) {
                    groupIndex = idx
                    break
                }
                idx++
            }
            if (groupIndex < 0) {
                packageNames.add(pkgName)
                let group = ArrayList<TempFileInfo>()
                group.add(objFile)
                packageModules.add(group)
            } else {
                packageModules[groupIndex].add(objFile)
            }
        }

        let processedObjFiles = ArrayList<TempFileInfo>()
        var groupIdx: Int64 = 0
        while (groupIdx < packageNames.size) {
            if (!PartialLinkOnePackage(packageNames[groupIdx], packageModules[groupIdx], processedObjFiles)) {
                return false
            }
            groupIdx++
        }
        for (foreignInput in foreignInputs) {
            processedObjFiles.add(foreignInput)
        }
        return FinishGeneration(processedObjFiles)
    }

    protected func PartialLinkOnePackage(
        pkgName: String,
        modules: ArrayList<TempFileInfo>,
        processedObjFiles: ArrayList<TempFileInfo>
    ): Bool {
        if (modules.isEmpty()) {
            return true
        }
        let dirPath = FileUtil.GetDirPath(modules[0].filePath)
        let outputFile = FileUtil.JoinPath(dirPath, pkgName + ObjSuffix(driverOptions.target.os))
        if (!(modules.size == 1 && modules[0].filePath == outputFile)) {
            let tool = Tool(ldPath, ToolType.BACKEND, driverOptions.environment.allVariables)
            tool.AppendArg("-o")
            tool.AppendArg(outputFile)
            tool.AppendArg("-r")
            for (module in modules) {
                tool.AppendArg(module.filePath)
            }
            backendCmds.add(MakeSingleToolBatch(tool))
        }

        let outputDir = FileUtil.GetAbsPath(FileUtil.GetDirPath(outputFile)) ?? FileUtil.GetDirPath(outputFile)
        let symbolFile = FileUtil.JoinPath(outputDir, pkgName + ".__symbols")
        let symbolsToLocalize = if (let Some(perPkgSymbols) <- driverOptions.symbolsNeedLocalizedPerPkg.get(pkgName)) {
            perPkgSymbols
        } else {
            driverOptions.symbolsNeedLocalized
        }
        if (!FileUtil.WriteToFile(symbolFile, RenderSymbolLocalizationFile(symbolsToLocalize))) {
            eprintln("error: failed to write symbol localization list: " + symbolFile)
            return false
        }
        if (!symbolsToLocalize.isEmpty()) {
            if (objcopyPath.isEmpty()) {
                eprintln("error: not found `objcopy` in search paths. You may add search path by `-B` option.")
                return false
            }
            let changeSymVis = Tool(objcopyPath, ToolType.BACKEND, driverOptions.environment.allVariables)
            changeSymVis.AppendArg(outputFile)
            changeSymVis.AppendArg("--localize-symbols=" + symbolFile)
            backendCmds.add(MakeSingleToolBatch(changeSymVis))
        }

        processedObjFiles.add(TempFileInfo(fileName: FileUtil.GetFileNameWithoutExtension(outputFile),
            filePath: outputFile, rawPath: outputFile, isFrontendOutput: true))
        if ((driverOptions.aggressiveParallelCompile ?? 1) > 1) {
            let destFile = driverOptions.GetHashedObjFileNameForPackage(pkgName, pkgName) + ObjSuffix(driverOptions.target.os)
            let cacheCopyTool = Tool("CacheCopy", ToolType.INTERNAL_IMPLEMENTED, driverOptions.environment.allVariables)
            cacheCopyTool.AppendArg(outputFile)
            cacheCopyTool.AppendArg(destFile)
            backendCmds.add(MakeSingleToolBatch(cacheCopyTool))
        }
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

    protected open func GenerateLinking(objFiles: ArrayList<TempFileInfo>): Bool {
        let gccCrtFilePair = GetGccCrtFilePair()
        let gccLibPath = GenerateGCCLibPath(gccCrtFilePair)
        if (driverOptions.enableVerbose) {
            println("selected gcc lib path: " + gccLibPath)
        }
        GenerateLinkingTool(objFiles, gccLibPath, gccCrtFilePair)
        return true
    }

    protected open func GenerateGCCLibPath(gccCrtFilePair: (String, String)): String {
        let files = ArrayList<String>()
        if (!gccCrtFilePair[0].isEmpty()) {
            files.add(gccCrtFilePair[0])
        }
        if (!gccCrtFilePair[1].isEmpty()) {
            files.add(gccCrtFilePair[1])
        }
        if (files.isEmpty()) {
            return ""
        }
        let scanner = GCCPathScanner(driverOptions.target, files, GetCRuntimeLibraryPath())
        if (let Some(gccPath) <- scanner.Scan()) {
            return gccPath.libPath
        }
        return ""
    }

    protected func GetGccLibFile(filename: String, gccLibPath: String): String {
        if (filename.isEmpty()) {
            return ""
        }
        if (let Some(crtFile) <- FileUtil.FindFileByName(filename, GetCRuntimeLibraryPath())) {
            return crtFile
        }
        if (!gccLibPath.isEmpty()) {
            return FileUtil.JoinPath(gccLibPath, filename)
        }
        return filename
    }

    protected open func GetGccCrtFilePair(): (String, String) {
        if (driverOptions.outputMode == OutputMode.EXECUTABLE) {
            return gccExecCrtFilePair
        }
        if (driverOptions.outputMode == OutputMode.SHARED_LIB) {
            return gccSharedCrtFilePair
        }
        return ("", "")
    }

    protected open func GenerateLinkingTool(
        objFiles: ArrayList<TempFileInfo>,
        gccLibPath: String,
        gccCrtFilePair: (String, String)
    ): Unit {
        let _ = gccLibPath
        let _ = gccCrtFilePair
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
        tool.AppendArgIf(driverOptions.enableGcSections, "-gc-sections")
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

    protected open func HandleLibrarySearchPaths(tool: Tool, cangjieLibPath: String): Unit {
        for (path in driverOptions.librarySearchPaths) {
            tool.AppendArg("-L" + path)
        }
        if (driverOptions.EnableSanitizer()) {
            tool.AppendArg("-L" + FileUtil.JoinPath(cangjieLibPath, driverOptions.SanitizerTypeToShortString()))
        }
        tool.AppendArg("-L" + cangjieLibPath)
        let cangjieRuntimeLibPath = FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "runtime/lib"),
            driverOptions.GetCangjieLibTargetPathName())
        if (driverOptions.EnableSanitizer()) {
            tool.AppendArg("-L" + FileUtil.JoinPath(cangjieRuntimeLibPath, driverOptions.SanitizerTypeToShortString()))
        }
        tool.AppendArg("-L" + cangjieRuntimeLibPath)
        for (path in GetLibraryPaths()) {
            tool.AppendArg("-L" + path)
        }
        if (driverOptions.IsCrossCompiling() && !driverOptions.target.IsMinGW()) {
            tool.AppendArg("-rpath-link")
            tool.AppendArg(cangjieRuntimeLibPath)
        }
    }

    protected func SearchClangLibrary(libName: String, libSuffix: String): Option<String> {
        let searchPaths = ArrayList<String>()
        for (path in driverOptions.librarySearchPaths) {
            searchPaths.add(path)
        }
        for (path in GetLibraryPaths()) {
            searchPaths.add(path)
        }
        for (path in GetCRuntimeLibraryPath()) {
            searchPaths.add(path)
        }
        let prefix = "libclang_rt."
        if (let Some(found) <- FileUtil.FindFileByName(prefix + libName + libSuffix, searchPaths)) {
            return found
        }
        return FileUtil.FindFileByName(prefix + libName + "-" + driverOptions.target.ArchToString() + libSuffix,
            searchPaths)
    }

    protected open func HandleSanitizerDependencies(tool: Tool): Unit {
        tool.AppendArg("-lpthread")
        tool.AppendArg("-lrt")
        tool.AppendArg("-lm")
        tool.AppendArg("-ldl")
        tool.AppendArg("-lresolv")
        tool.AppendArg("-lgcc_s")
    }

    private func GenericHandleSanitizerRuntime(
        tool: Tool,
        name: String,
        cangjieLibPath: String,
        finalFallback: () -> Unit
    ): Unit {
        if (driverOptions.outputMode != OutputMode.EXECUTABLE) {
            return
        }
        HandleSanitizerDependencies(tool)
        tool.AppendArg("--export-dynamic")
        let staticName = "libclang_rt-" + name + ".a"
        if (let Some(rtLib) <- FileUtil.FindFileByName(staticName, [cangjieLibPath])) {
            LinkStaticLibrary(tool, rtLib)
            return
        }
        if (let Some(rtLib) <- SearchClangLibrary(name, ".a")) {
            LinkStaticLibrary(tool, rtLib)
            return
        }
        if (let Some(preinitLib) <- SearchClangLibrary(name + "-preinit", ".a")) {
            LinkStaticLibrary(tool, preinitLib)
            tool.AppendArg("-lclang_rt." + name)
            return
        }
        finalFallback()
    }

    private func HandleAsanDependencies(tool: Tool, cangjieLibPath: String, gccLibPath: String): Unit {
        GenericHandleSanitizerRuntime(tool, "asan", cangjieLibPath, { =>
            tool.AppendArg(FileUtil.JoinPath(gccLibPath, "libasan_preinit.o"))
            tool.AppendArg("-lasan")
        })
    }

    private func HandleHwasanDependencies(tool: Tool, cangjieLibPath: String): Unit {
        GenericHandleSanitizerRuntime(tool, "hwasan", cangjieLibPath, { =>
            LinkStaticLibrary(tool, "libclang_rt.hwasan-preinit.a")
            tool.AppendArg("-lclang_rt.hwasan")
        })
    }

    protected func HandleSanitizer(tool: Tool, cangjieLibPath: String, gccLibPath: String): Unit {
        if (!driverOptions.EnableSanitizer()) {
            return
        }
        let sanitizerPath = FileUtil.JoinPath(cangjieLibPath, driverOptions.SanitizerTypeToShortString())
        if (driverOptions.EnableAsan()) {
            HandleAsanDependencies(tool, sanitizerPath, gccLibPath)
        } else if (driverOptions.EnableTsan()) {
            if (driverOptions.outputMode == OutputMode.EXECUTABLE) {
                tool.AppendArg("--export-dynamic")
                LinkStaticLibrary(tool, FileUtil.JoinPath(sanitizerPath, "libclang_rt-tsan.a"))
                HandleSanitizerDependencies(tool)
            }
        } else if (driverOptions.EnableHwAsan()) {
            HandleHwasanDependencies(tool, sanitizerPath)
        }
        tool.AppendArg("--eh-frame-hdr")
    }

    protected func HandleLLVMLinkOptions(
        objFiles: ArrayList<TempFileInfo>,
        gccLibPath: String,
        tool: Tool,
        cjldScript: String
    ): Unit {
        let cangjieLibPath = FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "lib"),
            driverOptions.GetCangjieLibTargetPathName())
        HandleLibrarySearchPaths(tool, cangjieLibPath)
        if (!gccLibPath.isEmpty()) {
            tool.AppendArg("-L" + gccLibPath)
        }
        if (driverOptions.discardEhFrame && driverOptions.target.os != OSType.WINDOWS) {
            tool.AppendArg("-T")
            tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "discard_eh_frame.lds"))
        }
        if (driverOptions.target.os == OSType.WINDOWS) {
            tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "section.o"))
        } else {
            tool.AppendArg("-T")
            tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, cjldScript))
        }
        tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "cjstart.o"))
        if (driverOptions.target.env == EnvironmentType.OHOS && driverOptions.enablePgoInstrGen) {
            tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "cjpgo.o"))
        }
        SortInputlibraryFileAndAppend(tool, objFiles)
        if (driverOptions.enablePgoInstrGen) {
            tool.AppendArg("-u")
            tool.AppendArg("__llvm_profile_runtime")
        }
        if (driverOptions.enablePgoInstrGen || driverOptions.enableCoverage) {
            tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, GetClangRTProfileLibraryName()))
        }
        HandleSanitizer(tool, cangjieLibPath, gccLibPath)
        GenerateLinkOptionsOfBuiltinLibs(tool)
        GenerateLinkOptions(tool)
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
