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
        if (driverOptions.linkStaticStd ?? false) {
            GenerateLinkOptionsOfBuiltinLibsForStaticLink(tool)
        } else {
            GenerateLinkOptionsOfBuiltinLibsForDyLink(tool)
        }
    }

    protected open func GenerateLinkOptionsOfBuiltinLibsForStaticLink(tool: Tool): Unit {
        for (pkg in driverOptions.directBuiltinDependencies) {
            if (let Some(name) <- StandardLibName(pkg)) {
                tool.AppendArg("-l:libcangjie-std-" + name + ".a")
            }
        }
        for (pkg in driverOptions.indirectBuiltinDependencies) {
            if (let Some(name) <- StandardLibName(pkg)) {
                tool.AppendArg("-l:libcangjie-std-" + name + ".a")
            }
        }
    }

    protected open func GenerateLinkOptionsOfBuiltinLibsForDyLink(tool: Tool): Unit {
        for (pkg in driverOptions.directBuiltinDependencies) {
            if (let Some(name) <- StandardLibName(pkg)) {
                tool.AppendArg("-lcangjie-std-" + name)
            }
        }
        for (pkg in driverOptions.indirectBuiltinDependencies) {
            if (let Some(name) <- StandardLibName(pkg)) {
                tool.AppendArg("-lcangjie-std-" + name)
            }
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
            case ArchType.X86_64 => "x86_64"
            case ArchType.AARCH64 => "aarch64"
            case ArchType.ARM32 => "arm"
            case ArchType.UNKNOWN => "unknown"
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
        let runtimePath = FileUtil.JoinPath(driver.cangjieHome, "runtime/lib")
        if (!runtimePath.isEmpty()) {
            tool.AppendArg("-rpath")
            tool.AppendArg(runtimePath)
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
