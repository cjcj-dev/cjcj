package cangjie_compiler::driver

import std.collection.*

public open class ToolChain {
    protected let driver: Driver
    protected let driverOptions: DriverOptions
    protected let backendCmds: ArrayList<ToolBatch>
    private let cRuntimeLibraryPaths: ArrayList<String> = ArrayList<String>()
    private let libraryPaths: ArrayList<String> = ArrayList<String>()

    public init(driver: Driver, driverOptions: DriverOptions, backendCmds: ArrayList<ToolBatch>) {
        this.driver = driver
        this.driverOptions = driverOptions
        this.backendCmds = backendCmds
    }

    public open func InitializeLibraryPaths(): Unit {}
    public open func PrepareDependencyPath(): Bool { return false }
    public open func ProcessGeneration(input: ArrayList<TempFileInfo>): Bool {
        let _ = input
        return false
    }

    protected open func GetSharedLibraryExtension(): String { return ".so" }

    protected func CheckAndAddPathTo(results: ArrayList<String>, path: String, base!: String = ""): Unit {
        let fullPath = if (base.isEmpty()) { path } else { FileUtil.JoinPath(base, path) }
        if (FileUtil.FileExist(fullPath)) {
            results.add(fullPath)
        }
    }

    protected func AddCRuntimeLibraryPath(path: String): Unit {
        CheckAndAddPathTo(cRuntimeLibraryPaths, path)
    }

    protected func GetCRuntimeLibraryPath(): ArrayList<String> {
        return cRuntimeLibraryPaths
    }

    protected func AddLibraryPath(path: String): Unit {
        if (!path.isEmpty()) {
            libraryPaths.add(path)
        }
    }

    protected func AddLibraryPaths(paths: ArrayList<String>): Unit {
        for (path in paths) {
            AddLibraryPath(path)
        }
    }

    protected func GetLibraryPaths(): ArrayList<String> {
        return libraryPaths
    }

    protected func GetDynamicLinkerPath(tripleInfo: TripleInfo): String {
        if (tripleInfo.os == OSType.LINUX) {
            if (tripleInfo.env == EnvironmentType.OHOS && tripleInfo.arch == ArchType.AARCH64) {
                return "/lib/ld-musl-aarch64.so.1"
            }
            if (tripleInfo.env == EnvironmentType.OHOS && tripleInfo.arch == ArchType.ARM32) {
                return "/lib/ld-musl-arm.so.1"
            }
            if (tripleInfo.env == EnvironmentType.OHOS && tripleInfo.arch == ArchType.X86_64) {
                return "/lib/ld-musl-x86_64.so.1"
            }
            if (tripleInfo.env == EnvironmentType.ANDROID) {
                return if (tripleInfo.arch == ArchType.ARM32) { "/system/bin/linker" } else { "/system/bin/linker64" }
            }
            if (tripleInfo.arch == ArchType.X86_64) {
                return "/lib64/ld-linux-x86-64.so.2"
            }
            if (tripleInfo.arch == ArchType.AARCH64) {
                return "/lib/ld-linux-aarch64.so.1"
            }
        }
        return ""
    }

    protected func GenerateLinkOptionsOfBuiltinLibs(tool: Tool): Unit {
        let notOutputDylib = driverOptions.outputMode != OutputMode.SHARED_LIB
        if (driverOptions.linkStaticStd ?? notOutputDylib) {
            GenerateLinkOptionsOfBuiltinLibsForStaticLink(tool)
        } else {
            GenerateLinkOptionsOfBuiltinLibsForDyLink(tool)
        }
    }

    protected open func GenerateLinkOptionsOfBuiltinLibsForStaticLink(tool: Tool): Unit {
        let dynamicLibraries = HashSet<String>()
        let staticLibraries = HashSet<String>()
        let ltoBuiltInDependencies = HashSet<String>()
        let dyDependencies = HashSet<String>()
        GatherAlwaysDynamicStdDependencies(driverOptions.directBuiltinDependencies, dyDependencies)
        GatherAlwaysDynamicStdDependencies(driverOptions.indirectBuiltinDependencies, dyDependencies)
        for (pkg in driverOptions.directBuiltinDependencies) {
            AppendStaticBuiltinLibrary(pkg, dynamicLibraries, staticLibraries, ltoBuiltInDependencies, dyDependencies)
        }
        for (pkg in driverOptions.indirectBuiltinDependencies) {
            AppendStaticBuiltinLibrary(pkg, dynamicLibraries, staticLibraries, ltoBuiltInDependencies, dyDependencies)
        }
        if (driverOptions.IsLTOEnabled()) {
            for (bcFile in ltoBuiltInDependencies) {
                tool.AppendArg(bcFile)
            }
        }
        let needsElfGroup = driverOptions.target.os == OSType.LINUX || driverOptions.target.os == OSType.WINDOWS
        if (needsElfGroup) {
            tool.AppendArg("--start-group")
        }
        for (lib in staticLibraries) {
            tool.AppendArg(lib)
        }
        if (needsElfGroup) {
            tool.AppendArg("--end-group")
        }
        for (lib in dynamicLibraries) {
            tool.AppendArg(lib)
        }
    }

    protected open func GenerateLinkOptionsOfBuiltinLibsForDyLink(tool: Tool): Unit {
        for (pkg in driverOptions.directBuiltinDependencies) {
            if (let Some(dynamicArg) <- BuiltinDynamicLinkArg(pkg)) {
                tool.AppendArg(dynamicArg)
            }
        }
        if (driverOptions.target.os == OSType.LINUX && !driverOptions.target.IsMinGW()) {
            tool.AppendArg("--as-needed")
        }
        for (pkg in driverOptions.indirectBuiltinDependencies) {
            if (let Some(dynamicArg) <- BuiltinDynamicLinkArg(pkg)) {
                tool.AppendArg(dynamicArg)
            }
        }
        if (driverOptions.target.os == OSType.LINUX && !driverOptions.target.IsMinGW()) {
            tool.AppendArg("--no-as-needed")
        }
    }

    private func GatherAlwaysDynamicStdDependencies(pkgs: HashSet<String>, dyDependencies: HashSet<String>): Unit {
        for (pkg in pkgs) {
            if (let Some(staticLib) <- LibCangjieFormat(pkg, ".a")) {
                if (staticLib == "libcangjie-std-ast.a") {
                    dyDependencies.add(staticLib)
                    if (driverOptions.target.os != OSType.WINDOWS) {
                        dyDependencies.add("libcangjie-std-core.a")
                        dyDependencies.add("libcangjie-std-collection.a")
                        dyDependencies.add("libcangjie-std-sort.a")
                        dyDependencies.add("libcangjie-std-math.a")
                    }
                }
            }
        }
    }

    private func AppendStaticBuiltinLibrary(
        pkg: String,
        dynamicLibraries: HashSet<String>,
        staticLibraries: HashSet<String>,
        ltoBuiltInDependencies: HashSet<String>,
        dyDependencies: HashSet<String>
    ): Unit {
        if (let Some(staticLib) <- LibCangjieFormat(pkg, ".a")) {
            if (dyDependencies.contains(staticLib) && !driverOptions.linkStatic) {
                if (let Some(dynamicArg) <- BuiltinDynamicLinkArg(pkg)) {
                    dynamicLibraries.add(dynamicArg)
                }
                return
            }
            if (driverOptions.IsLTOEnabled()) {
                if (let Some(ffiLib) <- LTOCStdFFILib(staticLib)) {
                    staticLibraries.add("-l:" + ffiLib)
                }
                if (let Some(ltoLib) <- LtoLibCangjieFormat(pkg)) {
                    ltoBuiltInDependencies.add(ltoLib)
                }
            } else if (driverOptions.EnableSanitizer()) {
                let cangjieLibPath = FileUtil.JoinPath(FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "lib"),
                    driverOptions.GetCangjieLibTargetPathName()), driverOptions.SanitizerTypeToShortString())
                staticLibraries.add(FileUtil.JoinPath(cangjieLibPath, staticLib))
            } else {
                staticLibraries.add("-l:" + staticLib)
            }
            CheckOtherDependenciesOfStaticLib(staticLib, dynamicLibraries, staticLibraries)
        }
    }

    private func CheckOtherDependenciesOfStaticLib(
        libName: String,
        dynamicLibraries: HashSet<String>,
        staticLibraries: HashSet<String>
    ): Unit {
        if (libName == "libcangjie-std-net.a") {
            if (driverOptions.target.IsMinGW()) {
                staticLibraries.add("-l:libws2_32.a")
            }
        } else if (libName == "libcangjie-dynamicLoader-openssl.a") {
            if (!driverOptions.target.IsMinGW()) {
                dynamicLibraries.add("-ldl")
            } else {
                dynamicLibraries.add("-lcrypt32")
            }
        } else if (libName == "libcangjie-std-ffi.python.a") {
            dynamicLibraries.add("-ldl")
        } else if (libName == "libcangjie-std-ast.a") {
            if (driverOptions.target.os == OSType.DARWIN) {
                staticLibraries.add("-lcangjie-std-astFFI")
            } else {
                staticLibraries.add("-l:libcangjie-std-astFFI.a")
            }
            if (driverOptions.target.arch != ArchType.AARCH64 && driverOptions.target.os == OSType.LINUX &&
                driverOptions.target.env != EnvironmentType.OHOS &&
                driverOptions.target.env != EnvironmentType.ANDROID) {
                staticLibraries.add("-lclang_rt-builtins")
            }
            if (driverOptions.target.os == OSType.LINUX &&
                driverOptions.target.env == EnvironmentType.ANDROID) {
                staticLibraries.add("-lc++")
                staticLibraries.add("-lunwind")
            } else if (!driverOptions.target.IsMacOS() && !driverOptions.target.IsMinGW()) {
                dynamicLibraries.add("-lgcc_s")
            }
        }
    }

    private func LibCangjieBaseFormat(pkg: String): Option<String> {
        if (let Some(name) <- StandardLibName(pkg)) {
            if (let Some(pos) <- pkg.indexOf(".")) {
                return "cangjie-" + pkg[0..pos] + "-" + name
            }
            return "cangjie-" + name
        }
        return None
    }

    private func LibCangjieFormat(pkg: String, extension: String): Option<String> {
        if (let Some(base) <- LibCangjieBaseFormat(pkg)) {
            return "lib" + base + extension
        }
        return None
    }

    private func BuiltinDynamicLinkArg(pkg: String): Option<String> {
        if (driverOptions.target.os == OSType.DARWIN || driverOptions.target.os == OSType.IOS) {
            if (let Some(base) <- LibCangjieBaseFormat(pkg)) {
                return "-l:" + base
            }
            return None
        }
        if (let Some(libName) <- LibCangjieFormat(pkg, GetSharedLibraryExtension())) {
            return "-l:" + libName
        }
        return None
    }

    private func LtoLibCangjieFormat(pkg: String): Option<String> {
        if (let Some(base) <- LibCangjieBaseFormat(pkg)) {
            return "lib" + base + ".bc"
        }
        return None
    }

    private func LTOCStdFFILib(staticLib: String): Option<String> {
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

    protected func AppendObjectsFromCompiled(tool: Tool, objFiles: ArrayList<TempFileInfo>,
        inputOrderTuples: ArrayList<(String, UInt64)>): Unit {
        var index: UInt64 = 0u64
        for (objFile in objFiles) {
            inputOrderTuples.add((objFile.filePath, index))
            index++
        }
        let _ = tool
    }

    protected func AppendObjectsFromInput(inputOrderTuples: ArrayList<(String, UInt64)>): Unit {
        for (item in driverOptions.orderedInputObjs) {
            inputOrderTuples.add((item.value, item.index))
        }
    }

    protected func AppendLibrariesFromInput(inputOrderTuples: ArrayList<(String, UInt64)>): Unit {
        for (item in driverOptions.orderedLibraries) {
            inputOrderTuples.add((item.value, item.index))
        }
    }

    protected func AppendLinkOptionFromInput(inputOrderTuples: ArrayList<(String, UInt64)>): Unit {
        var base = UInt64(1000000)
        for (item in driverOptions.linkOption) {
            inputOrderTuples.add((item, base))
            base++
        }
    }

    protected func AppendLinkOptionsFromInput(inputOrderTuples: ArrayList<(String, UInt64)>): Unit {
        var base = UInt64(2000000)
        for (item in driverOptions.linkOptions) {
            for (part in SplitString(item, " ")) {
                if (!part.isEmpty()) {
                    inputOrderTuples.add((part, base))
                    base++
                }
            }
        }
    }

    protected func SortInputlibraryFileAndAppend(tool: Tool, objFiles: ArrayList<TempFileInfo>): Unit {
        let inputOrderTuples = ArrayList<(String, UInt64)>()
        AppendObjectsFromCompiled(tool, objFiles, inputOrderTuples)
        AppendObjectsFromInput(inputOrderTuples)
        AppendLibrariesFromInput(inputOrderTuples)
        AppendLinkOptionFromInput(inputOrderTuples)
        AppendLinkOptionsFromInput(inputOrderTuples)
        let used = ArrayList<Bool>()
        for (_ in 0..inputOrderTuples.size) {
            used.add(false)
        }
        var emitted: Int64 = 0
        while (emitted < inputOrderTuples.size) {
            var best: Int64 = -1
            var idx: Int64 = 0
            while (idx < inputOrderTuples.size) {
                if (!used[idx] && (best < 0 || inputOrderTuples[idx][1] < inputOrderTuples[best][1])) {
                    best = idx
                }
                idx++
            }
            if (best < 0) {
                break
            }
            used[best] = true
            tool.AppendArg(inputOrderTuples[best][0])
            emitted++
        }
    }

    protected func GenerateObjTool(objFiles: ArrayList<TempFileInfo>): Unit {
        if (objFiles.isEmpty()) {
            return
        }
        let output = GetOutputFileInfo(objFiles)
        let tool = Tool("CacheCopy", ToolType.INTERNAL_IMPLEMENTED, driverOptions.environment.allVariables)
        tool.AppendArg(objFiles[0].filePath)
        tool.AppendArg(output.filePath)
        backendCmds.add(MakeSingleToolBatch(tool))
    }

    protected func GetOutputFileInfo(objFiles: ArrayList<TempFileInfo>): TempFileInfo {
        let kind = match (driverOptions.outputMode) {
            case OutputMode.EXECUTABLE => TempFileKind.O_EXE
            case OutputMode.STATIC_LIB => TempFileKind.O_STATICLIB
            case OutputMode.SHARED_LIB => TempFileKind.O_DYLIB
            case OutputMode.CHIR => TempFileKind.O_CHIR
            case OutputMode.OBJ => TempFileKind.O_OBJ
        }
        return CreateNewFileInfoWrapper(objFiles, kind)
    }

    protected func CreateNewFileInfoWrapper(objFiles: ArrayList<TempFileInfo>, kind: TempFileKind): TempFileInfo {
        let base = if (objFiles.isEmpty()) {
            TempFileInfo(fileName: driverOptions.moduleName)
        } else {
            TempFileInfo(fileName: objFiles[0].fileName)
        }
        return TempFileManager.Instance().CreateNewFileInfo(base, kind)
    }

    protected func GetArchFolderName(arch: ArchType): String {
        return match (arch) {
            case ArchType.X86_64 => "lib64"
            case ArchType.AARCH64 => "lib64"
            case ArchType.ARM32 => "lib"
            case ArchType.UNKNOWN => ""
        }
    }

    protected open func ComputeLibPaths(): ArrayList<String> {
        let paths = ArrayList<String>()
        let archFolder = GetArchFolderName(driverOptions.target.arch)
        paths.add(FileUtil.JoinPath(driver.cangjieHome, "lib"))
        paths.add(FileUtil.JoinPath(driver.cangjieHome, "lib/" + archFolder))
        paths.add(FileUtil.JoinPath(driverOptions.sysroot, "lib"))
        paths.add(FileUtil.JoinPath(driverOptions.sysroot, "usr/lib"))
        for (path in driverOptions.environment.libraryPaths) {
            paths.add(path)
        }
        for (path in driverOptions.librarySearchPaths) {
            paths.add(path)
        }
        return paths
    }

    protected open func ComputeBinPaths(): ArrayList<String> {
        let paths = ArrayList<String>()
        for (path in driverOptions.toolChainPaths) {
            paths.add(path)
        }
        paths.add(FileUtil.JoinPath(driver.cangjieHome, "third_party/llvm/bin"))
        paths.add(FileUtil.JoinPath(driverOptions.sysroot, "bin"))
        paths.add(FileUtil.JoinPath(driverOptions.sysroot, "usr/bin"))
        for (path in driverOptions.environment.paths) {
            paths.add(path)
        }
        return paths
    }

    protected func GenerateRuntimePath(tool: Tool): Unit {
        if (!driverOptions.useRuntimeRpath && !driverOptions.sanitizerEnableRpath) {
            return
        }
        if (driverOptions.IsCrossCompiling()) {
            return
        }
        let runtimePath = FileUtil.JoinPath(FileUtil.JoinPath(driver.cangjieHome, "runtime/lib"),
            driverOptions.GetCangjieLibTargetPathName())
        if (driverOptions.useRuntimeRpath) {
            tool.AppendArg("-rpath")
            tool.AppendArg(runtimePath)
        } else if (driverOptions.sanitizerEnableRpath) {
            let sanitizerRuntimePath = FileUtil.JoinPath(runtimePath, driverOptions.SanitizerTypeToShortString())
            tool.AppendArg("--disable-new-dtags")
            tool.AppendArg("-rpath")
            tool.AppendArg(sanitizerRuntimePath)
        }
    }

    protected func FindToolPath(toolName: String, paths: ArrayList<String>): String {
        return FileUtil.FindProgramByName(toolName, paths.toArray())
    }

    protected func FindCangjieLLVMToolPath(toolName: String): String {
        let paths = ArrayList<String>()
        paths.add(FileUtil.JoinPath(driver.cangjieHome, "third_party/llvm/bin"))
        for (path in driverOptions.toolChainPaths) {
            paths.add(path)
        }
        for (path in driverOptions.environment.paths) {
            paths.add(path)
        }
        return FindToolPath(toolName, paths)
    }

    protected func FindUserToolPath(toolName: String): String {
        return FindToolPath(toolName, ComputeBinPaths())
    }

    protected open func GetClangRTProfileLibraryName(): String {
        return "libclang_rt-profile.a"
    }
}
