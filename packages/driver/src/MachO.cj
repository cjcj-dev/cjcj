package cangjie_compiler::driver

import std.collection.*

private func MachOLibCangjieBaseFormat(pkg: String): Option<String> {
    if (let Some(name) <- StandardLibName(pkg)) {
        if (let Some(pos) <- pkg.indexOf(".")) {
            return "cangjie-" + pkg[0..pos] + "-" + name
        }
        return "cangjie-" + name
    }
    let base = FileUtil.ConvertFilenameToLibCangjieBaseFormat(pkg)
    if (!base.isEmpty()) {
        return base
    }
    return None
}

private func MachOLibCangjieFormat(pkg: String, extension: String): Option<String> {
    if (let Some(base) <- MachOLibCangjieBaseFormat(pkg)) {
        return "lib" + base + extension
    }
    return None
}

private func MachOLtoLibCangjieFormat(pkg: String): Option<String> {
    if (let Some(base) <- MachOLibCangjieBaseFormat(pkg)) {
        return "lib" + base + ".bc"
    }
    return None
}

private func MachOLTOCStdFFILib(staticLib: String): Option<String> {
    return match (staticLib) {
        case "libcangjie-std-core.a" => "libcangjie-std-coreFFI.a"
        case "libcangjie-std-ast.a" => "libcangjie-std-astFFI.a"
        case "libcangjie-std-convert.a" => "libcangjie-std-convertFFI.a"
        case "libcangjie-std-fs.a" => "libcangjie-std-fsFFI.a"
        case "libcangjie-std-console.a" => "libcangjie-std-envFFI.a"
        case "libcangjie-std-math.a" => "libcangjie-std-mathFFI.a"
        case "libcangjie-std-time.a" => "libcangjie-std-timeFFI.a"
        case "libcangjie-std-posix.a" => "libcangjie-std-posixFFI.a"
        case "libcangjie-std-process.a" => "libcangjie-std-processFFI.a"
        case "libcangjie-std-env.a" => "libcangjie-std-envFFI.a"
        case "libcangjie-std-random.a" => "libcangjie-std-randomFFI.a"
        case "libcangjie-std-net.a" => "libcangjie-std-netFFI.a"
        case "libcangjie-std-objectpool.a" => "libcangjie-std-objectpoolFFI.a"
        case "libcangjie-std-unittest.a" => "libcangjie-std-unittestFFI.a"
        case "libcangjie-std-regex.a" => "libcangjie-std-regexFFI.a"
        case "libcangjie-std-collection.concurrent.a" => "libcangjie-std-collection.concurrentFFI.a"
        case "libcangjie-dynamicLoader-openssl.a" => "libcangjie-dynamicLoader-opensslFFI.a"
        case "libcangjie-std-runtime.a" => "libcangjie-std-runtimeFFI.a"
        case _ => None
    }
}

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
        AddCRuntimeLibraryPaths()
        AddSystemLibraryPaths()
    }

    protected open func AddCRuntimeLibraryPaths(): Unit {
        let archFolderName = GetArchFolderName(driverOptions.target.arch)
        AddCRuntimeLibraryPath(FileUtil.JoinPath(driverOptions.sysroot, archFolderName))
        let usrPath = FileUtil.JoinPath(driverOptions.sysroot, "usr")
        AddCRuntimeLibraryPath(FileUtil.JoinPath(usrPath, archFolderName))
        let usrLibPath = FileUtil.JoinPath(usrPath, "lib")
        AddCRuntimeLibraryPath(usrLibPath)
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
        arPath = FindUserToolPath(ToolName(ToolID.AR))
        ldPath = FindCangjieLLVMToolPath(ToolName(ToolID.LD64_LLD))
        dsymutilPath = FindUserToolPath(ToolName(ToolID.DSYMUTIL))
        stripPath = FindUserToolPath(ToolName(ToolID.STRIP))
        return !arPath.isEmpty() && !ldPath.isEmpty() && !dsymutilPath.isEmpty() && !stripPath.isEmpty()
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
        let output = GenerateLinking(input)
        if (driverOptions.enableCompileDebug) {
            GenerateDebugSymbolFile(output)
        }
        if (driverOptions.stripSymbolTable) {
            GenerateStripSymbolFile(output)
        }
        return true
    }

    protected open func GenerateArchiveTool(objFiles: ArrayList<TempFileInfo>): Unit {
        let tool = Tool(arPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        tool.AppendArg("cr")
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

    protected open func GenerateLinking(objFiles: ArrayList<TempFileInfo>): TempFileInfo {
        let sdkVersionOpt = GetDarwinSDKVersion(driverOptions.sysroot)
        if (driverOptions.enableVerbose) {
            let sdkVersionText = sdkVersionOpt ?? "N/A"
            println("selected Darwin SDK path: " + driverOptions.sysroot + " (SDK Version: " + sdkVersionText + ")")
        }
        return GenerateLinkingTool(objFiles, sdkVersionOpt ?? "12")
    }

    protected open func GenerateLinkingTool(objFiles: ArrayList<TempFileInfo>, darwinSDKVersion: String): TempFileInfo {
        let _ = objFiles
        let _ = darwinSDKVersion
        return TempFileInfo()
    }

    protected open func GetTargetArchString(): String {
        if (driverOptions.target.arch == ArchType.AARCH64) { return "arm64" }
        if (driverOptions.target.arch == ArchType.X86_64) { return "x86_64" }
        return ""
    }

    protected open func HandleLibrarySearchPaths(tool: Tool, cangjieLibPath: String): Unit {
        for (path in driverOptions.librarySearchPaths) {
            tool.AppendArg("-L" + path)
        }
        let cangjieRuntimeLibPath = FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "runtime/lib"),
            driverOptions.GetCangjieLibTargetPathName())
        tool.AppendArg("-L" + cangjieRuntimeLibPath)
        tool.AppendArg("-L" + cangjieLibPath)
        for (path in GetLibraryPaths()) {
            tool.AppendArg("-L" + path)
        }
        if (driverOptions.IsCrossCompiling()) {
            tool.AppendArg("-L")
            tool.AppendArg(cangjieRuntimeLibPath)
        }
    }

    protected func HandleLLVMLinkOptions(objFiles: ArrayList<TempFileInfo>, tool: Tool): Unit {
        let cangjieLibPath = FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "lib"),
            driverOptions.GetCangjieLibTargetPathName())
        HandleLibrarySearchPaths(tool, cangjieLibPath)
        tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "section.o"))
        tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, "cjstart.o"))
        SortInputlibraryFileAndAppend(tool, objFiles)
        if (driverOptions.enablePgoInstrGen) {
            tool.AppendArg("-u")
            tool.AppendArg("___llvm_profile_runtime")
        }
        if (driverOptions.enablePgoInstrGen || driverOptions.enableCoverage) {
            tool.AppendArg(FileUtil.JoinPath(cangjieLibPath, GetClangRTProfileLibraryName()))
        }
        GenerateLinkOptionsOfBuiltinLibs(tool)
        GenerateLinkOptions(tool)
    }

    protected open func GenerateLinkOptions(tool: Tool): Unit {
        let _ = tool
    }

    protected open func GenerateDebugSymbolFile(binaryFile: TempFileInfo): Unit {
        let tool = Tool(dsymutilPath, ToolType.OTHER, driverOptions.environment.allVariables)
        tool.AppendArg(binaryFile.filePath)
        tool.AppendArg("-o")
        tool.AppendArg(binaryFile.filePath + ".dSYM")
        backendCmds.add(MakeSingleToolBatch(tool))

        let codesignTool = Tool(ToolName(ToolID.CODESIGN), ToolType.OTHER, driverOptions.environment.allVariables)
        codesignTool.AppendArg("-s")
        codesignTool.AppendArg("-")
        codesignTool.AppendArg("-f")
        codesignTool.AppendArg("--entitlements")
        codesignTool.AppendArg(FileUtil.JoinPath(driver.cangjieHome, "lib/entitlement.plist"))
        codesignTool.AppendArg(binaryFile.filePath)
        backendCmds.add(MakeSingleToolBatch(codesignTool))
    }

    protected func GenerateStripSymbolFile(binaryFile: TempFileInfo): Unit {
        let tool = Tool(stripPath, ToolType.BACKEND, driverOptions.environment.allVariables)
        if (driverOptions.outputMode == OutputMode.EXECUTABLE) {
            tool.AppendArg("-u")
            tool.AppendArg("-r")
        } else if (driverOptions.outputMode == OutputMode.SHARED_LIB) {
            tool.AppendArg("-x")
        }
        let binaryFiles = ArrayList<TempFileInfo>()
        binaryFiles.add(binaryFile)
        let newBinaryFile = GetOutputFileInfo(binaryFiles)
        tool.AppendArg(binaryFile.filePath)
        tool.AppendArg("-o")
        tool.AppendArg(newBinaryFile.filePath)
        backendCmds.add(MakeSingleToolBatch(tool))
    }

    protected override func GenerateLinkOptionsOfBuiltinLibsForStaticLink(tool: Tool): Unit {
        let dynamicLibraries = ArrayList<String>()
        let staticLibraries = ArrayList<String>()
        let ltoBuiltInDependencies = ArrayList<String>()
        let dyDependencies = HashSet<String>()
        GatherMachOAlwaysDynamicStdDependencies(driverOptions.directBuiltinDependencies, dyDependencies)
        GatherMachOAlwaysDynamicStdDependencies(driverOptions.indirectBuiltinDependencies, dyDependencies)
        for (pkg in driverOptions.directBuiltinDependencies) {
            AppendMachOStaticBuiltinLibrary(pkg, dynamicLibraries, staticLibraries, ltoBuiltInDependencies,
                dyDependencies)
        }
        for (pkg in driverOptions.indirectBuiltinDependencies) {
            AppendMachOStaticBuiltinLibrary(pkg, dynamicLibraries, staticLibraries, ltoBuiltInDependencies,
                dyDependencies)
        }
        if (driverOptions.IsLTOEnabled()) {
            AppendSortedLinkOrderedSet(tool, ltoBuiltInDependencies)
        }
        AppendSortedLinkOrderedSet(tool, staticLibraries)
        AppendSortedLinkOrderedSet(tool, dynamicLibraries)
    }

    protected override func GenerateLinkOptionsOfBuiltinLibsForDyLink(tool: Tool): Unit {
        for (pkg in driverOptions.directBuiltinDependencies) {
            if (let Some(base) <- MachOLibCangjieBaseFormat(pkg)) {
                tool.AppendArg("-l" + base)
            }
        }
        for (pkg in driverOptions.indirectBuiltinDependencies) {
            if (let Some(base) <- MachOLibCangjieBaseFormat(pkg)) {
                tool.AppendArg("-l" + base)
            }
        }
    }

    private func GatherMachOAlwaysDynamicStdDependencies(pkgs: HashSet<String>, dyDependencies: HashSet<String>): Unit {
        for (pkg in pkgs) {
            if (let Some(staticLib) <- MachOLibCangjieFormat(pkg, ".a")) {
                if (staticLib == "libcangjie-std-ast.a") {
                    dyDependencies.add(staticLib)
                    dyDependencies.add("libcangjie-std-core.a")
                    dyDependencies.add("libcangjie-std-collection.a")
                    dyDependencies.add("libcangjie-std-sort.a")
                    dyDependencies.add("libcangjie-std-math.a")
                }
            }
        }
    }

    private func AppendMachOStaticBuiltinLibrary(
        pkg: String,
        dynamicLibraries: ArrayList<String>,
        staticLibraries: ArrayList<String>,
        ltoBuiltInDependencies: ArrayList<String>,
        dyDependencies: HashSet<String>
    ): Unit {
        if (let Some(staticLib) <- MachOLibCangjieFormat(pkg, ".a")) {
            if (dyDependencies.contains(staticLib) && !driverOptions.linkStatic) {
                if (let Some(base) <- MachOLibCangjieBaseFormat(pkg)) {
                    AddLinkOrderedSetValue(dynamicLibraries, "-l" + base)
                }
                return
            }
            var cangjieLibPath = FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "lib"),
                driverOptions.GetCangjieLibTargetPathName())
            if (driverOptions.sanitizerType != SanitizerType.NONE) {
                cangjieLibPath = FileUtil.JoinPath(cangjieLibPath, driverOptions.SanitizerTypeToShortString())
            }
            if (driverOptions.IsLTOEnabled()) {
                if (let Some(ffiLib) <- MachOLTOCStdFFILib(staticLib)) {
                    AddLinkOrderedSetValue(staticLibraries, FileUtil.JoinPath(cangjieLibPath, ffiLib))
                }
                if (let Some(ltoLib) <- MachOLtoLibCangjieFormat(pkg)) {
                    AddLinkOrderedSetValue(ltoBuiltInDependencies, ltoLib)
                }
            } else {
                if (driverOptions.linkStaticStd ?? true) {
                    AddLinkOrderedSetValue(staticLibraries, FileUtil.JoinPath(cangjieLibPath, staticLib))
                } else if (let Some(base) <- MachOLibCangjieBaseFormat(pkg)) {
                    AddLinkOrderedSetValue(staticLibraries, "-l" + base)
                }
            }
            CheckMachOOtherDependenciesOfStaticLib(staticLib, dynamicLibraries, staticLibraries)
        }
    }

    private func CheckMachOOtherDependenciesOfStaticLib(
        libName: String,
        dynamicLibraries: ArrayList<String>,
        staticLibraries: ArrayList<String>
    ): Unit {
        if (libName == "libcangjie-std-net.a") {
            if (driverOptions.target.IsMinGW()) {
                AddLinkOrderedSetValue(staticLibraries, "-l:libws2_32.a")
            }
        } else if (libName == "cangjie-dynamicLoader-openssl.a") {
            if (!driverOptions.target.IsMinGW()) {
                AddLinkOrderedSetValue(dynamicLibraries, "-ldl")
            } else {
                AddLinkOrderedSetValue(dynamicLibraries, "-lcrypt32")
            }
        } else if (libName == "libcangjie-std-ffi.python.a") {
            AddLinkOrderedSetValue(dynamicLibraries, "-ldl")
        } else if (libName == "libcangjie-std-ast.a") {
            if (driverOptions.target.os == OSType.DARWIN) {
                AddLinkOrderedSetValue(staticLibraries, "-lcangjie-std-astFFI")
            } else {
                AddLinkOrderedSetValue(staticLibraries, "-l:libcangjie-std-astFFI.a")
            }
            if (driverOptions.target.arch != ArchType.AARCH64 && driverOptions.target.os == OSType.LINUX &&
                driverOptions.target.env != EnvironmentType.OHOS &&
                driverOptions.target.env != EnvironmentType.ANDROID) {
                AddLinkOrderedSetValue(staticLibraries, "-lclang_rt-builtins")
            }
            if (driverOptions.target.os == OSType.LINUX &&
                driverOptions.target.env == EnvironmentType.ANDROID) {
                AddLinkOrderedSetValue(staticLibraries, "-lc++")
                AddLinkOrderedSetValue(staticLibraries, "-lunwind")
            } else if (!driverOptions.target.IsMacOS() && !driverOptions.target.IsMinGW()) {
                AddLinkOrderedSetValue(dynamicLibraries, "-lgcc_s")
            }
        }
    }
}
