package cangjie_compiler::driver

import std.collection.*
import cangjie_compiler::option.Backend as OptionBackend
import cangjie_compiler::option.BackendToString as OptionBackendToString
import cangjie_compiler::option.GetHardwareConcurrency
import cangjie_compiler::utils.FileMode

public let OBFUCATION_LEVEL_MIN: Int64 = 1
public let OBFUCATION_LEVEL_MAX: Int64 = 9

private func HasStringValue(value: Option<String>): Bool {
    return if (let Some(_) <- value) { true } else { false }
}

private func HasBoolValue(value: Option<Bool>): Bool {
    return if (let Some(_) <- value) { true } else { false }
}

public class DriverOptions {
    public var argList: Array<String> = []
    public var executablePath: String = ""
    public var optArg: String = ""
    public var llcArg: String = ""
    public var targetCPU: Option<String> = None
    public var linkStatic: Bool = false
    public var stripSymbolTable: Bool = false
    public let linkOption: ArrayList<String> = ArrayList<String>()
    public let linkOptions: ArrayList<String> = ArrayList<String>()
    public let librarySearchPaths: ArrayList<String> = ArrayList<String>()
    public let libraries: ArrayList<String> = ArrayList<String>()
    public let toolChainPaths: ArrayList<String> = ArrayList<String>()
    public var sysroot: String = "/"
    public var customizedSysroot: Bool = false
    public var useRuntimeRpath: Bool = false
    public var sanitizerEnableRpath: Bool = false
    public var incrementalCompileNoChange: Bool = false
    public var enableObfAll: Bool = false
    public var enableObfExportSyms: Option<Bool> = None
    public var enableObfLineNumber: Option<Bool> = None
    public var enableObfSourcePath: Option<Bool> = None
    public var enableLayoutObfuscation: Option<Bool> = None
    public var enableConstObfuscation: Option<Bool> = None
    public var enableStringObfuscation: Option<Bool> = None
    public var enableCFflattenObfuscation: Option<Bool> = None
    public var enableCFBogusObfuscation: Option<Bool> = None
    public var layoutObfSymPrefix: Option<String> = None
    public var layoutObfInputSymMappingFiles: Option<String> = None
    public var layoutObfOutputSymMappingFile: Option<String> = None
    public var layoutObfUserMappingFile: Option<String> = None
    public var obfuscationConfigFile: Option<String> = None
    public var obfuscationLevel: Int64 = 5
    public var obfuscationSeed: Option<Int64> = 0

    public let environment: EnvironmentOptions = EnvironmentOptions()
    public var host: TripleInfo = HostTripleInfo()
    public var target: TripleInfo = HostTripleInfo()
    public var backend: BackendType = BackendType.CJNATIVE
    public var cangjieHome: String = ""
    public var output: String = "./"
    public var outputDir: Option<String> = None
    public var moduleName: String = "main"
    public var moduleSrcPath: String = ""
    public var showUsage: Bool = false
    public var printVersionOnly: Bool = false
    public var enableVerbose: Bool = false
    public var enableTimer: Bool = false
    public var enableMemoryCollect: Bool = false
    public var experimentalMode: Bool = false
    public var diagFormat: String = "default"
    public var errorCountLimit: UInt64 = 8u64
    public var scanDepPkg: Bool = false
    public var frontendOnlyAction: Bool = false
    public var compilePackage: Bool = false
    public var noSubPkg: Bool = false
    public var saveTemps: Bool = false
    public var tempFolderPath: String = ""
    public var enableCompileDebug: Bool = false
    public var enableCoverage: Bool = false
    public var fastMathMode: Bool = false
    public var disableBackendOpt: Bool = false
    public var disableChirOpt: Bool = false
    public var displayLineInfo: Bool = true
    public var enableFuncSections: Bool = false
    public var enableDataSections: Bool = false
    public var enableGcSections: Bool = false
    public var enablePgoInstrGen: Bool = false
    public var enablePgoInstrUse: Bool = false
    public var pgoProfileFile: String = ""
    public var discardEhFrame: Bool = false
    public var optPassOptions: String = ""
    public var stackTraceFormat: String = "--stack-trace-format=default"
    public var linkStaticStd: Option<Bool> = None
    public var linkStaticLibs: Option<Bool> = None
    public var ltoMod: LTOMode = LTOMode.NO_LTO
    public var enableCompileAsExe: Bool = false
    public var ltoHideAllPkgs: Bool = false
    public let ltoVisiblePkgs: ArrayList<String> = ArrayList<String>()
    public var outputMode: OutputMode = OutputMode.EXECUTABLE
    public var enableOutputType: Bool = false
    public var enableHotReload: Bool = false
    public var emitCHIRPhase: String = ""
    public var compileTarget: CompileTarget = CompileTarget.DEFAULT
    public var optimizationLevel: OptimizationLevel = OptimizationLevel.O0
    public var sanitizerType: SanitizerType = SanitizerType.NONE
    public var enIncrementalCompilation: Bool = false
    public var printIncrementalInfo: Bool = false
    public var jobs: Option<UInt64> = None
    public var aggressiveParallelCompile: Option<Int64> = None
    public var aggressiveParallelCompileWithoutArg: Bool = false
    public var compileMacro: Bool = false
    public var enableMacroDebug: Bool = false
    public var enableParallelMacro: Bool = false
    public var compileCjd: Bool = false
    public var implicitPrelude: Bool = true
    public var exportForTest: Bool = false
    public var parseTest: Bool = false
    public var compileTestsOnly: Bool = false
    public var compilationCachedPath: String = ""
    public var compilationCachedDir: String = ""
    public var compilationCachedFileName: String = ""
    public let srcFiles: ArrayList<String> = ArrayList<String>()
    public let inputObjs: ArrayList<String> = ArrayList<String>()
    public let inputLibraries: ArrayList<String> = ArrayList<String>()
    public let inputLinkOptions: ArrayList<String> = ArrayList<String>()
    public let bcInputFiles: ArrayList<String> = ArrayList<String>()
    public let bcPackageNames: ArrayList<String> = ArrayList<String>()
    public let frontendOutputFiles: ArrayList<TempFileInfo> = ArrayList<TempFileInfo>()
    public let symbolsNeedLocalized: ArrayList<String> = ArrayList<String>()
    public let symbolsNeedLocalizedPerPkg: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()
    public let orderedInputObjs: ArrayList<OrderedInput> = ArrayList<OrderedInput>()
    public let orderedLibraries: ArrayList<OrderedInput> = ArrayList<OrderedInput>()
    public let orderedLinkOptions: ArrayList<OrderedInput> = ArrayList<OrderedInput>()
    public let orderedLinkOptionGroups: ArrayList<OrderedInput> = ArrayList<OrderedInput>()
    public let frontendForwardArgs: ArrayList<String> = ArrayList<String>()
    public let directBuiltinDependencies: HashSet<String> = HashSet<String>()
    public let indirectBuiltinDependencies: HashSet<String> = HashSet<String>()

    public init() {}

    public func ParseFromArgs(arguments: Array<String>): Bool {
        argList = arguments
        return ParseDriverArgs(this, arguments) && PerformPostActions()
    }

    public func ReadPathsFromEnvironmentVars(environmentVars: HashMap<String, String>): Unit {
        environment.allVariables.clear()
        for ((key, value) in environmentVars) {
            environment.allVariables.add(key, value)
        }
        if (let Some(home) <- environmentVars.get("CANGJIE_HOME")) {
            environment.cangjieHome = home
        }
        if (let Some(pathsValue) <- environmentVars.get("CANGJIE_PATH")) {
            for (item in FileUtil.SplitEnvironmentPaths(pathsValue)) {
                environment.cangjiePaths.add(item)
            }
        }
        if (let Some(libraryValue) <- environmentVars.get("LIBRARY_PATH")) {
            for (item in FileUtil.SplitEnvironmentPaths(libraryValue)) {
                environment.libraryPaths.add(item)
            }
        }
        if (let Some(pathValue) <- environmentVars.get("PATH")) {
            for (item in FileUtil.SplitEnvironmentPaths(pathValue)) {
                environment.paths.add(item)
            }
        }
        if (let Some(sdkRoot) <- environmentVars.get("SDKROOT")) {
            environment.macOSSDKRoot = sdkRoot
        }
        if (let Some(macosSdkRoot) <- environmentVars.get("MACOSX_DEPLOYMENT_TARGET")) {
            let _ = macosSdkRoot
        }
    }

    public func ReprocessObfuseOption(): Bool {
        if (enableObfAll) {
            if (let None <- enableStringObfuscation) { enableStringObfuscation = true }
            if (let None <- enableConstObfuscation) { enableConstObfuscation = true }
            if (let None <- enableLayoutObfuscation) { enableLayoutObfuscation = true }
            if (let None <- enableCFflattenObfuscation) { enableCFflattenObfuscation = true }
            if (let None <- enableCFBogusObfuscation) { enableCFBogusObfuscation = true }
            if (let None <- enableObfLineNumber) {
                if (enableLayoutObfuscation ?? false) {
                    enableObfLineNumber = true
                }
            }
        }
        return true
    }

    public func IsObfuscationEnabled(): Bool {
        return (enableStringObfuscation ?? false) || (enableConstObfuscation ?? false) ||
            (enableLayoutObfuscation ?? false) || (enableCFflattenObfuscation ?? false) ||
            (enableCFBogusObfuscation ?? false)
    }

    public func IsLTOEnabled(): Bool { return ltoMod != LTOMode.NO_LTO }
    public func IsFullLTOEnabled(): Bool { return ltoMod == LTOMode.FULL_LTO }
    public func IsEmitCHIREnable(): Bool { return outputMode == OutputMode.CHIR || !emitCHIRPhase.isEmpty() }
    public func GetLtoVisiblePkgs(): Array<String> { return ltoVisiblePkgs.toArray() }
    public func IsCompileAsExeEnabled(): Bool { return enableCompileAsExe }
    public func IsLTOPkgVisibilityEnabled(): Bool { return ltoHideAllPkgs || !ltoVisiblePkgs.isEmpty() }
    public func EnableAsan(): Bool { return sanitizerType == SanitizerType.ADDRESS }
    public func EnableTsan(): Bool { return sanitizerType == SanitizerType.THREAD }
    public func EnableHwAsan(): Bool { return sanitizerType == SanitizerType.HWADDRESS }
    public func EnableSanitizer(): Bool { return EnableAsan() || EnableTsan() || EnableHwAsan() }

    public func GetOptionsBackend(): OptionBackend {
        return if (backend == BackendType.CJNATIVE) { OptionBackend.CJNATIVE } else { OptionBackend.UNKNOWN }
    }

    public func HasInputs(): Bool {
        return !srcFiles.isEmpty() || !inputObjs.isEmpty() || !inputLibraries.isEmpty() || !bcInputFiles.isEmpty()
    }

    public func CheckDirectoryPath(path: String): Option<String> {
        if (!FileUtil.FileExist(path)) {
            eprintln("warning: no such directory '${path}', argument ignored.")
            return None
        }
        if (!FileUtil.IsDir(path)) {
            eprintln("warning: not a directory '${path}', argument ignored.")
            return None
        }
        if (let Some(absPath) <- FileUtil.GetAbsPath(path)) {
            return absPath
        }
        eprintln("warning: invalid path '${path}', argument ignored.")
        return None
    }

    public func ValidateInputFilePath(path: String): Option<String> {
        if (!FileUtil.FileExist(path)) {
            eprintln("error: no such file or directory '${path}'")
            return None
        }
        if (!FileUtil.Access(path, FileMode.FM_READ)) {
            eprintln("error: permission denied '${path}'")
            return None
        }
        if (FileUtil.IsDir(path)) {
            eprintln("error: not a file '${path}'")
            return None
        }
        if (let Some(absPath) <- FileUtil.GetAbsPath(path)) {
            return absPath
        }
        eprintln("error: invalid path '${path}'")
        return None
    }

    public func IsCrossCompiling(): Bool {
        return !host.Equal(target)
    }

    public func GetStackTraceFormat(): String {
        return stackTraceFormat
    }

    public func GetCangjieLibTargetPathName(): String {
        var name = target.OSToString()
        if (target.env != EnvironmentType.GNU && target.env != EnvironmentType.NOT_AVAILABLE) {
            var envName = target.EnvironmentToString()
            if (target.env == EnvironmentType.ANDROID && target.ArchToString() != "arm" &&
                !target.apiLevel.isEmpty() && envName.endsWith(target.apiLevel)) {
                envName = envName[0..envName.size - target.apiLevel.size]
            }
            name += "_" + envName
        }
        return name + "_" + target.ArchToString() + "_" + OptionBackendToString(backend)
    }

    public func SanitizerTypeToShortString(): String {
        return match (sanitizerType) {
            case SanitizerType.ADDRESS => "asan"
            case SanitizerType.THREAD => "tsan"
            case SanitizerType.HWADDRESS => "hwasan"
            case SanitizerType.NONE => ""
        }
    }

    public func SetOptimizationLevel(level: OptimizationLevel): Bool {
        optimizationLevel = level
        if (OptimizationLevelIndex(level) >= OptimizationLevelIndex(OptimizationLevel.O2)) {
            enableFuncSections = true
            enableDataSections = true
        }
        return true
    }

    public func GenerateFrontendOptions(): Array<String> {
        let out = ArrayList<String>()
        if (!frontendForwardArgs.isEmpty()) {
            for (arg in frontendForwardArgs) {
                out.add(arg)
            }
        } else {
            if (compilePackage) { out.add("--package") }
            if (noSubPkg) { out.add("--no-sub-pkg") }
            if (scanDepPkg) { out.add("--scan-dependency") }
            if (enableCompileDebug) { out.add("-g") }
            if (parseTest) { out.add("--test") }
            if (compileTestsOnly) { out.add("--test-only") }
            if (let Some(dir) <- outputDir) {
                out.add("--output-dir")
                out.add(dir)
            }
            if (moduleName != "main") {
                out.add("--module-name")
                out.add(moduleName)
            }
            for (file in srcFiles) {
                out.add(file)
            }
        }
        let multiBC = if (let Some(count) <- aggressiveParallelCompile) { count > 1 } else { false }
        if (!frontendOutputFiles.isEmpty() && !multiBC) {
            out.add("-o")
            out.add(frontendOutputFiles[0].filePath)
        }
        return out.toArray()
    }

    public func SetCompilationCachedPath(): Unit {
        if (!compilationCachedPath.isEmpty()) {
            return
        }
        let baseDir = outputDir ?? FileUtil.GetDirPath(output)
        compilationCachedDir = FileUtil.JoinPath(baseDir, ".cangjie_cache")
        compilationCachedFileName = moduleName
        compilationCachedPath = FileUtil.JoinPath(compilationCachedDir, compilationCachedFileName)
    }

    public func GetHashedObjFileName(fileName: String): String {
        if (compilationCachedPath.isEmpty()) {
            SetCompilationCachedPath()
        }
        return FileUtil.JoinPath(compilationCachedDir, fileName)
    }

    public func GetHashedObjFileNameForPackage(fullPackageName: String, fileName: String): String {
        if (compilationCachedPath.isEmpty()) {
            SetCompilationCachedPath()
        }
        if (!compilePackage || fullPackageName == fileName) {
            return FileUtil.JoinPath(compilationCachedDir, fileName)
        }
        return FileUtil.JoinPath(compilationCachedDir, fullPackageName + "-" + fileName)
    }

    private func PerformPostActions(): Bool {
        if (showUsage || printVersionOnly) {
            return true
        }
        if (outputMode == OutputMode.OBJ && compileTarget == CompileTarget.DEFAULT) {
            compileTarget = CompileTarget.EXECUTABLE
        }
        if (!ReprocessObfuseOption()) {
            return false
        }
        var success = true
        success = success && CheckTargetCPUOption()
        success = success && CheckObfuscationOptions()
        success = success && SetupSysroot()
        success = success && CheckSanitizerOptions()
        success = success && CheckLTOOptions()
        success = success && CheckPGOOptions()
        success = success && CheckCompileTargetOption()
        ReprocessAggressiveParallelCompile()
        success = success && CheckRuntimeRPath()
        success = success && CheckSanitizerRPath()
        success = success && CheckStaticOption()
        return success
    }

    private func CheckObfuscationOptions(): Bool {
        if (enableCompileDebug && IsObfuscationEnabled()) {
            eprintln("warning: Obfuscation options should be used without '-g' or debugging may not work properly.")
        }
        if (!(enableLayoutObfuscation ?? false) && (HasStringValue(layoutObfInputSymMappingFiles) ||
            HasStringValue(layoutObfOutputSymMappingFile) || HasStringValue(layoutObfUserMappingFile) ||
            HasBoolValue(enableObfExportSyms) || HasBoolValue(enableObfLineNumber) ||
            HasBoolValue(enableObfSourcePath) || HasStringValue(layoutObfSymPrefix))) {
            eprintln("error: layout obfuscation sub-options require layout obfuscation to be enabled.")
            return false
        }
        return true
    }

    private func CheckTargetCPUOption(): Bool {
        if (target.IsMacOS()) {
            if (let None <- targetCPU) {
                return true
            }
        }
        if (let None <- targetCPU) {
            targetCPU = "generic"
        }
        let value = targetCPU ?? "generic"
        if (value == "generic" || value == "native") {
            return true
        }
        if (IsSupportedTargetCPU(target.arch, value)) {
            return true
        }
        eprintln("error: unsupported target CPU '${value}'")
        return false
    }

    private func SetupSysroot(): Bool {
        if (!customizedSysroot && target.IsMacOS()) {
            if (let Some(sdkRoot) <- environment.macOSSDKRoot) {
                sysroot = sdkRoot
            }
        }
        return true
    }

    private func CheckRuntimeRPath(): Bool {
        if (!useRuntimeRpath) {
            return true
        }
        if (target.os == OSType.WINDOWS) {
            eprintln("warning: '--set-runtime-rpath' option has no effect on PE targets.")
        } else if (IsCrossCompiling()) {
            eprintln("warning: '--set-runtime-rpath' option has no effect on cross-compiled targets.")
        }
        return true
    }

    private func CheckSanitizerRPath(): Bool {
        if (!sanitizerEnableRpath) {
            return true
        }
        if (!EnableSanitizer()) {
            eprintln("error: option '--sanitize-set-rpath' can only be enabled along with '--sanitize'.")
            return false
        }
        if (useRuntimeRpath) {
            eprintln("error: option '--sanitize-set-rpath' and '--set-runtime-rpath' cannot be enabled together.")
            return false
        }
        if (IsCrossCompiling()) {
            eprintln("warning: '--sanitize-set-rpath' option has no effect on cross-compiled targets.")
        }
        return true
    }

    private func CheckSanitizerOptions(): Bool {
        if (!EnableSanitizer()) {
            return true
        }
        let runtimeDirPath = FileUtil.JoinPath(cangjieHome, "runtime")
        let libraryDirPath = FileUtil.JoinPath(FileUtil.JoinPath(runtimeDirPath, "lib"), GetCangjieLibTargetPathName())
        let sanitizerPath = FileUtil.JoinPath(libraryDirPath, SanitizerTypeToShortString())
        let runtimePath = FileUtil.JoinPath(sanitizerPath, "libcangjie-runtime" + DylibSuffix(target.os))
        if (!FileUtil.FileExist(runtimePath)) {
            eprintln("error: ${SanitizerTypeToShortString()} sanitizer feature is not supported.")
            return false
        }
        if (IsLTOEnabled()) {
            eprintln("error: option '--sanitize' and '--lto' cannot be enabled together.")
            return false
        }
        if (discardEhFrame) {
            eprintln("error: option '--sanitize' and '--discard-eh-frame' cannot be enabled together.")
            return false
        }
        if (compileMacro) {
            eprintln("error: option '--sanitize' and '--compile-macro' cannot be enabled together.")
            return false
        }
        if (EnableAsan() && target.GetOSFamily() != OSType.LINUX) {
            eprintln("error: Address Sanitizer is only supported on Linux.")
            return false
        }
        if (EnableHwAsan() && target.GetOSFamily() != OSType.LINUX) {
            eprintln("error: Hardware-Assisted Address Sanitizer is only supported on Linux.")
            return false
        }
        if (EnableHwAsan() && target.arch != ArchType.X86_64 && target.arch != ArchType.AARCH64) {
            eprintln("error: Hardware-Assisted Address Sanitizer is only supported on X86_64 or aarch64.")
            return false
        }
        if (EnableTsan() && target.GetOSFamily() != OSType.LINUX && target.GetOSFamily() != OSType.WINDOWS) {
            eprintln("error: Thread Sanitizer is only supported on Linux/Windows.")
            return false
        }
        return true
    }

    private func CheckLTOOptions(): Bool {
        if (IsLTOEnabled()) {
            if (target.GetOSFamily() == OSType.DARWIN || target.GetOSFamily() == OSType.IOS ||
                target.GetOSFamily() == OSType.WINDOWS) {
                eprintln("error: LTO mode is not supported on target '${target.OSToString()}'.")
                return false
            }
            if (outputMode == OutputMode.OBJ) {
                eprintln("error: --output-type=obj is not allowed in LTO mode.")
                return false
            }
            if (outputMode == OutputMode.STATIC_LIB && !bcInputFiles.isEmpty()) {
                eprintln("error: input bitcode files cannot be used when generating a static library in LTO mode.")
                return false
            }
            if (optimizationLevel == OptimizationLevel.Os || optimizationLevel == OptimizationLevel.Oz) {
                eprintln("error: -Os and -Oz optimize options are not supported in LTO mode.")
                return false
            }
        }
        if (IsCompileAsExeEnabled()) {
            if (!IsLTOEnabled()) {
                eprintln("error: option '--compile-as-exe' can only be enabled in LTO mode.")
                return false
            }
            if (target.GetOSFamily() == OSType.WINDOWS || target.GetOSFamily() == OSType.DARWIN ||
                target.GetOSFamily() == OSType.IOS) {
                eprintln("error: option '--compile-as-exe' is not supported on this target platform.")
                return false
            }
        }
        if (IsLTOPkgVisibilityEnabled()) {
            if (!IsLTOEnabled()) {
                eprintln("error: option '--lto-keep-pkg-visibility' can only be enabled in LTO mode.")
                return false
            }
            if (!ltoVisiblePkgs.isEmpty() && IsCompileAsExeEnabled()) {
                eprintln("error: option '--lto-keep-pkg-visibility' conflicts with '--compile-as-exe'.")
                return false
            }
            if (outputMode != OutputMode.SHARED_LIB) {
                eprintln("warning: option '--lto-keep-pkg-visibility' has effect only when emitting a dynamic library.")
            }
        }
        return true
    }

    private func CheckPGOOptions(): Bool {
        if (enablePgoInstrGen && enablePgoInstrUse) {
            eprintln("error: options '--pgo-instr-gen' and '--pgo-instr-use' cannot be enabled together.")
            return false
        }
        if (enablePgoInstrGen && target.env == EnvironmentType.OHOS && pgoProfileFile.isEmpty()) {
            eprintln("error: option '--pgo-instr-gen' requires a profile file on OHOS targets.")
            return false
        }
        if (enablePgoInstrUse) {
            if (!FileUtil.FileExist(pgoProfileFile)) {
                eprintln("error: no such file or directory '${pgoProfileFile}'")
                return false
            }
            if (FileUtil.GetFileExtension(pgoProfileFile) != "profdata") {
                eprintln("error: PGO profile '${pgoProfileFile}' must have .profdata extension.")
                return false
            }
        }
        return true
    }

    private func CheckCompileTargetOption(): Bool {
        if (outputMode != OutputMode.OBJ && compileTarget != CompileTarget.DEFAULT) {
            compileTarget = CompileTarget.DEFAULT
            eprintln("warning: '--compile-target' is valid only with '--output-type=obj'; argument ignored.")
        }
        if (srcFiles.isEmpty() && (outputMode == OutputMode.OBJ || outputMode == OutputMode.CHIR) && !compilePackage) {
            eprintln("error: no source file is provided.")
            return false
        }
        if (!compilePackage && srcFiles.isEmpty() && !inputObjs.isEmpty() && !experimentalMode) {
            eprintln("error: object-file-only compilation requires '--experimental'.")
            return false
        }
        return true
    }

    private func ReprocessAggressiveParallelCompile(): Unit {
        if (let None <- jobs) {
            jobs = GetHardwareConcurrency()
        }
        let jobsValue = jobs ?? 1u64
        let targetDisablesAPC = target.os == OSType.WINDOWS || target.os == OSType.DARWIN || target.os == OSType.IOS
        if (targetDisablesAPC || IsObfuscationEnabled() || IsLTOEnabled() || enableCoverage) {
            if (targetDisablesAPC && (aggressiveParallelCompileWithoutArg || (if (let Some(_) <- aggressiveParallelCompile) { true } else { false }))) {
                eprintln("warning: '--apc' is not supported when targeting ${target.OSToString()}.")
            }
            aggressiveParallelCompile = 1
        } else if (let None <- aggressiveParallelCompile) {
            if (optimizationLevel == OptimizationLevel.O0 || aggressiveParallelCompileWithoutArg) {
                aggressiveParallelCompile = Int64(jobsValue)
            } else {
                aggressiveParallelCompile = 1
            }
        }
    }

    private func CheckStaticOption(): Bool {
        let supported = (target.os == OSType.LINUX && target.env != EnvironmentType.OHOS) ||
            target.os == OSType.DARWIN || target.os == OSType.WINDOWS || target.os == OSType.IOS
        if (supported) {
            if (linkStatic && outputMode != OutputMode.EXECUTABLE) {
                linkStatic = false
                eprintln("warning: '--static' is usable only when emitting an executable.")
            }
            if ((linkStaticStd ?? true) == false && linkStatic) {
                eprintln("error: '--static' conflicts with dynamic standard library linking.")
                return false
            }
            return true
        }
        if (linkStatic) {
            linkStatic = false
            eprintln("warning: target '${target.ToFullTripleString()}' does not support '--static'.")
        }
        return true
    }
}
