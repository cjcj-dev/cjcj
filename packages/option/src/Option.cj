package cangjie_compiler::option

import std.collection.*

public class Path {
    public var pathType: PathType
    public var path: String
    public init(pathType: PathType, path: String) {
        this.pathType = pathType
        this.path = path
    }
}

public open class Option {
    public var argList: ArgList = ArgList()
    public init() {}
    public open func ParseFromArgs(argList: ArgList): Bool {
        this.argList = argList
        return false
    }
}

public class EnvironmentOptions {
    public let allVariables: HashMap<String, String> = HashMap<String, String>()
    public var cangjieHome: MaybeString = MaybeString()
    public let cangjiePaths: ArrayList<String> = ArrayList<String>()
    public let libraryPaths: ArrayList<String> = ArrayList<String>()
    public let paths: ArrayList<String> = ArrayList<String>()
    public var macOSSDKRoot: MaybeString = MaybeString()
    public init() {}
}

public class SanitizerCoverageOptions {
    public var coverageType: SanitizerCoverageType = SanitizerCoverageType.SCK_UNKNOW
    public var traceCmp: Bool = false
    public var traceMemCmp: Bool = false
    public var tracePCGuard: Bool = false
    public var inline8bitCounters: Bool = false
    public var inlineBoolFlag: Bool = false
    public var pcTable: Bool = false
    public var stackDepth: Bool = false
    public init() {}
    public func SetSancovLevel(level: SanitizerCoverageType): Unit { coverageType = level }
    public func IsSancovEnabled(): Bool {
        return traceCmp || traceMemCmp || tracePCGuard || inline8bitCounters || inlineBoolFlag || pcTable || stackDepth
    }
    public func ToSerializedString(): String {
        var result = "coverageType:"
        if (coverageType == SanitizerCoverageType.SCK_UNKNOW) { result += "K" }
        else if (coverageType == SanitizerCoverageType.SCK_NONE) { result += "N" }
        else if (coverageType == SanitizerCoverageType.SCK_FUNCTION) { result += "F" }
        else if (coverageType == SanitizerCoverageType.SCK_BB) { result += "BB" }
        result += ",traceCmp:" + BoolToSerializedString(traceCmp)
        result += ",traceMemCmp:" + BoolToSerializedString(traceMemCmp)
        result += ",tracePCGuard:" + BoolToSerializedString(tracePCGuard)
        result += ",inline8bitCounters:" + BoolToSerializedString(inline8bitCounters)
        result += ",inlineBoolFlag:" + BoolToSerializedString(inlineBoolFlag)
        result += ",pcTable:" + BoolToSerializedString(pcTable)
        result += ",stackDepth:" + BoolToSerializedString(stackDepth)
        return result
    }
}

public class OrderedInput {
    public let value: String
    public let index: UInt64
    public init(value: String, index: UInt64) {
        this.value = value
        this.index = index
    }
}

public class TempFileInfo {
    public var fileName: String
    public var filePath: String
    public var rawPath: String
    public var isFrontendOutput: Bool
    public var isForeignInput: Bool
    public init(
        fileName!: String = "",
        filePath!: String = "",
        rawPath!: String = "",
        isFrontendOutput!: Bool = false,
        isForeignInput!: Bool = false
    ) {
        this.fileName = fileName
        this.filePath = filePath
        this.rawPath = rawPath
        this.isFrontendOutput = isFrontendOutput
        this.isForeignInput = isForeignInput
    }
}

public class CachePathName {
    public let dir: String
    public let file: String
    public init(dir: String, file: String) {
        this.dir = dir
        this.file = file
    }
}

private class CfgPair {
    let key: String
    let value: String
    init(key: String, value: String) {
        this.key = key
        this.value = value
    }
}

private func initPrintBCHIR(): ArrayList<Bool> {
    let ret = ArrayList<Bool>()
    var idx: Int64 = 0
    while (idx < 7) {
        ret.add(false)
        idx++
    }
    return ret
}

private func containsOptimizationFlag(values: ArrayList<OptimizationFlag>, flag: OptimizationFlag): Bool {
    for (value in values) {
        if (value == flag) { return true }
    }
    return false
}

private func addOptimizationFlag(values: ArrayList<OptimizationFlag>, flag: OptimizationFlag): Unit {
    if (!containsOptimizationFlag(values, flag)) { values.add(flag) }
}

private func removeOptimizationFlag(values: ArrayList<OptimizationFlag>, flag: OptimizationFlag): Unit {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (values[idx] == flag) {
            values.remove(at: idx)
            return
        }
        idx++
    }
}

private func joinStrings(values: ArrayList<String>, delimiter: String): String {
    var result = ""
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) { result += delimiter }
        result += values[idx]
        idx++
    }
    return result
}

private func appendSortedString(values: ArrayList<String>, value: String): Unit {
    values.add(value)
}

private func joinSortedStrings(values: ArrayList<String>): String {
    let used = ArrayList<Bool>()
    for (_ in 0..values.size) { used.add(false) }
    var result = ""
    var emitted: Int64 = 0
    while (emitted < values.size) {
        var bestIndex: Int64 = -1
        var idx: Int64 = 0
        while (idx < values.size) {
            if (!used[idx] && (bestIndex < 0 || values[idx] < values[bestIndex])) { bestIndex = idx }
            idx++
        }
        if (bestIndex < 0) { break }
        used[bestIndex] = true
        result += values[bestIndex]
        emitted++
    }
    return result
}

private func containsString(values: ArrayList<String>, target: String): Bool {
    for (value in values) {
        if (value == target) { return true }
    }
    return false
}

private func replaceStrings(target: ArrayList<String>, values: Array<String>): Unit {
    target.clear()
    for (value in values) { target.add(value) }
}

public class GlobalOptions <: Option {
    public var frontendMode: Bool = false
    public let environment: EnvironmentOptions = EnvironmentOptions()
    public var host: TripleInfo = TripleInfo()
    public var target: TripleInfo = TripleInfo()
    public let passedWhenKeyValue: HashMap<String, String> = HashMap<String, String>()
    public let passedWhenCfgPaths: ArrayList<String> = ArrayList<String>()
    public var cangjieHome: String = ""
    public var output: String = "./"
    public var outputDir: MaybeString = MaybeString()
    public var outputJavaGenDir: MaybeString = MaybeString()
    public var outputObjCGenDir: String = ""
    public let importPaths: ArrayList<String> = ArrayList<String>()
    public let pluginPaths: ArrayList<String> = ArrayList<String>()
    public let commonPartCjos: ArrayList<String> = ArrayList<String>()
    public let commonPartChirs: ArrayList<String> = ArrayList<String>()
    public var enIncrementalCompilation: Bool = false
    public var printIncrementalInfo: Bool = false
    public var compilationCachedPath: String = ""
    public var compilationCachedDir: String = ""
    public var compilationCachedFileName: String = ""
    public var executablePath: String = ""
    public var moduleSrcPath: String = ""
    public let packagePaths: ArrayList<String> = ArrayList<String>()
    public let srcFiles: ArrayList<String> = ArrayList<String>()
    public let inputObjs: ArrayList<String> = ArrayList<String>()
    public var inputCjoFile: String = ""
    public let inputPdbaFiles: ArrayList<String> = ArrayList<String>()
    public let directBuiltinDependencies: HashSet<String> = HashSet<String>()
    public let indirectBuiltinDependencies: HashSet<String> = HashSet<String>()
    public let frontendOutputFiles: ArrayList<TempFileInfo> = ArrayList<TempFileInfo>()
    public let bcInputFiles: ArrayList<String> = ArrayList<String>()
    public let bcPackageNames: ArrayList<String> = ArrayList<String>()
    public let inputFileOrder: ArrayList<OrderedInput> = ArrayList<OrderedInput>()
    public let inputLibraryOrder: ArrayList<OrderedInput> = ArrayList<OrderedInput>()
    public let inputLinkOptionsOrder: ArrayList<OrderedInput> = ArrayList<OrderedInput>()
    public let inputLinkOptionOrder: ArrayList<OrderedInput> = ArrayList<OrderedInput>()
    public let removedPathPrefix: ArrayList<String> = ArrayList<String>()
    public var moduleName: String = ""
    public var compilePackage: Bool = false
    public var compileMacroPackage: Bool = false
    public var enableOutputType: Bool = false
    public var saveTemps: Bool = false
    public var tempFolderPath: String = "."
    public var backend: BackendType = BackendType.CJNATIVE
    public let macroLib: ArrayList<String> = ArrayList<String>()
    public var enableVerbose: Bool = false
    public var showUsage: Bool = false
    public var printVersionOnly: Bool = false
    public var experimentalMode: Bool = false
    public var scanDepPkg: Bool = false
    public var noSubPkg: Bool = false
    public var displayLineInfo: Bool = true
    public var enableCompileDebug: Bool = false
    public var enableAddCommentToAst: Bool = false
    public var enableMacroInLSP: Bool = false
    public var enableMacroDebug: Bool = false
    public var enableParallelMacro: Bool = false
    public var enableCompileTest: Bool = false
    public var compileTestsOnly: Bool = false
    public var exportForTest: Bool = false
    public var enableEH: Bool = false
    public var mock: MockMode = MockMode.DEFAULT
    public var diagFormat: DiagFormat = DiagFormat.DEFAULT
    public var parseTest: Bool = false
    public var implicitPrelude: Bool = true
    public var enableInteropCJMapping: Bool = false
    public var targetInteropLanguage: InteropLanguage = InteropLanguage.NA
    public var enableTimer: Bool = false
    public var enableMemoryCollect: Bool = false
    public var linkStaticStd: MaybeBool = MaybeBool()
    public var ltoMod: LTOMode = LTOMode.NO_LTO
    public var enableCompileAsExe: Bool = false
    public var ltoHideAllPkgs: Bool = false
    public let ltoVisiblePkgs: ArrayList<String> = ArrayList<String>()
    public var outputMode: OutputMode = OutputMode.EXECUTABLE
    public var compileTarget: CompileTarget = CompileTarget.DEFAULT
    public var optimizationLevel: OptimizationLevel = OptimizationLevel.O0
    public var optPassOptions: String = ""
    public var enableFuncSections: Bool = false
    public var enableDataSections: Bool = false
    public var enableGcSections: Bool = false
    public var enableHotReload: Bool = false
    public var disableReflection: Bool = false
    public var enablePgoInstrGen: Bool = false
    public var enablePgoInstrUse: Bool = false
    public var pgoProfileFile: String = ""
    public var discardEhFrame: Bool = false
    public var disableChirOpt: Bool = false
    public var disableBackendOpt: Bool = false
    public let selectedCHIROpts: ArrayList<OptimizationFlag> = ArrayList<OptimizationFlag>()
    public var interpreter: Bool = false
    public let printBCHIR: ArrayList<Bool> = initPrintBCHIR()
    public let interpreterSearchPaths: ArrayList<String> = ArrayList<String>()
    public let interpLoadLib: ArrayList<String> = ArrayList<String>()
    public let interpreterArgs: ArrayList<String> = ArrayList<String>()
    public var interpreterPrintResult: Bool = false
    public var interpFullBchir: Bool = false
    public var interpMainNoLinkage: Bool = false
    public var interpCHIR: Bool = false
    public var constEvalDebug: Bool = false
    public var computeAnnotationsDebug: Bool = false
    public var disableCodeGen: Bool = false
    public var disableDeserializer: Bool = false
    public var chirDebugOptimizer: Bool = false
    public var chirEA: Bool = false
    public var chirLICM: Bool = false
    public var chirWFC: Bool = true
    public var chirCC: Bool = false
    public var codegenDebugMode: Bool = false
    public var chirLLVM: Bool = false
    public var chirDeserialize: Bool = false
    public var chirDeserializePath: String = ""
    public var disableSemaVic: Bool = false
    public var enableChirRGetOrThrowE: Bool = false
    public var disableChirUselessImportElimination: Bool = false
    public var enableOpaque: Bool = false
    public var chirRenderMode: CHIRMode = CHIRMode.NA
    public var chirHLIR: Bool = false
    public var strictNumberMode: Bool = false
    public var fastMathMode: Bool = false
    public var enableCoverage: Bool = false
    public var compileCjd: Bool = false
    public var cjdbMode: Bool = false
    public var interopCJPackageConfigPath: String = "./"
    public var dumpAST: Bool = false
    public var dumpCHIR: Bool = false
    public var dumpIR: Bool = false
    public var dumpAll: Bool = false
    public var dumpToScreen: Bool = false
    public var sanitizerType: SanitizerType = SanitizerType.NONE
    public var sanitizerSetRpath: Bool = false
    public var stackTraceFmt: StackTraceFormat = StackTraceFormat.DEFAULT
    public var errorCountLimit: MaybeUInt64 = MaybeUInt64(8u64)
    public var jobs: MaybeUInt64 = MaybeUInt64()
    public var aggressiveParallelCompile: MaybeUInt64 = MaybeUInt64()
    public var aggressiveParallelCompileWithoutArg: Bool = false
    public let bitcodeFilesName: ArrayList<String> = ArrayList<String>()
    public let symbolsNeedLocalized: ArrayList<String> = ArrayList<String>()
    public var overflowStrategy: OverflowStrategy = OverflowStrategy.THROWING
    public var targetCPU: String = ""
    public var sysroot: String = ""
    public let libraryPaths: ArrayList<String> = ArrayList<String>()
    public let libraries: ArrayList<String> = ArrayList<String>()
    public let linkOptions: ArrayList<String> = ArrayList<String>()
    public let linkOptionGroups: ArrayList<String> = ArrayList<String>()
    public let toolchains: ArrayList<String> = ArrayList<String>()
    public var useRuntimeRpath: Bool = false
    public var optOptions: String = ""
    public var llcOptions: String = ""
    public var stripAll: Bool = false
    public var emitCHIRPhase: CandidateEmitCHIRPhase = CandidateEmitCHIRPhase.NA
    public let sancovOption: SanitizerCoverageOptions = SanitizerCoverageOptions()
    public init() { super() }

    public override func ParseFromArgs(argList: ArgList): Bool {
        this.argList = argList
        let delayed = ArrayList<OptionArgInstance>()
        var rawArgIndex: UInt64 = 0u64
        for (entry in argList.entries) {
            CollectOrderedInputFiles(entry, rawArgIndex)
            rawArgIndex++
            if (entry.argInstanceType == ArgInstanceType.Input) {
                argList.AddInput(argList.inputArgs[entry.index].value)
            } else {
                let opt = argList.optionArgs[entry.index]
                let pre = ParsePreAction(this, opt)
                if (pre.handled) {
                    OccurrenceCheck(opt, argList)
                    if (pre.skipParsing) { return pre.success }
                    if (!pre.success) { return false }
                } else {
                    delayed.add(opt)
                }
            }
        }
        for (opt in delayed) {
            if (!experimentalMode && !opt.info.BelongsGroup(Group.STABLE)) {
                Errorln(opt.str + " is an experimental feature. \"--experimental\" option is required.")
                return false
            }
            let parsed = ParseAction(this, opt)
            if (!parsed.success) { return false }
            OccurrenceCheck(opt, argList)
        }
        return ProcessInputs(argList.GetInputs()) && PerformPostActions()
    }

    private func CollectOrderedInputFiles(entry: ArgListEntry, index: UInt64): Unit {
        if (entry.argInstanceType == ArgInstanceType.Input) {
            inputFileOrder.add(OrderedInput(argList.inputArgs[entry.index].value, index))
        } else {
            let opt = argList.optionArgs[entry.index]
            if (opt.info.GetID() == ID.LIBRARY) {
                inputLibraryOrder.add(OrderedInput(opt.value, index))
            } else if (opt.info.GetID() == ID.LINK_OPTION) {
                inputLinkOptionOrder.add(OrderedInput(opt.value, index))
            } else if (opt.info.GetID() == ID.LINK_OPTIONS) {
                inputLinkOptionsOrder.add(OrderedInput(opt.value, index))
            }
        }
    }

    private func ReplaceInputFileName(oldName: String, newName: String): Unit {
        var idx: Int64 = 0
        while (idx < inputFileOrder.size) {
            let oldInput = inputFileOrder[idx]
            if (oldInput.value == oldName) {
                inputFileOrder[idx] = OrderedInput(newName, oldInput.index)
            }
            idx++
        }
    }

    private func OccurrenceCheck(arg: OptionArgInstance, argList: ArgList): Unit {
        if (argList.IsSpecified(arg.info.GetID()) &&
            arg.info.GetOccurrenceType() == Occurrence.SINGLE_OCCURRENCE && !argList.IsWarned(arg.info.GetID())) {
            Warningln("'" + arg.info.GetName() + "' is specified multiple times. The last one is chosen.")
            argList.MarkWarned(arg.info.GetID())
        }
        argList.MarkSpecified(arg)
    }

    public func GenerateFrontendOptions(): Array<String> {
        let out = ArrayList<String>()
        for (entry in argList.entries) {
            if (entry.argInstanceType == ArgInstanceType.Input) {
                out.add(argList.inputArgs[entry.index].value)
            } else {
                let opt = argList.optionArgs[entry.index]
                if (opt.info.GetID() != ID.OUTPUT_FILE && !opt.info.BelongsGroup(Group.DRIVER)) {
                    out.add(opt.name)
                    if (opt.info.GetKind() == Kind.SEPARATED) { out.add(opt.value) }
                }
            }
        }
        let multiBC = aggressiveParallelCompile.hasValue && aggressiveParallelCompile.value > 1u64
        if (!frontendOutputFiles.isEmpty() && !multiBC) {
            out.add("-o")
            out.add(frontendOutputFiles[0].filePath)
        }
        return out.toArray()
    }

    public func SetOptimizationLevel(level: OptimizationLevel): Bool {
        optimizationLevel = level
        if (enumIndex(level) >= enumIndex(OptimizationLevel.O2)) {
            addOptimizationFlag(selectedCHIROpts, OptimizationFlag.CONST_PROPAGATION)
            addOptimizationFlag(selectedCHIROpts, OptimizationFlag.LETC_FOLDING)
            addOptimizationFlag(selectedCHIROpts, OptimizationFlag.REF_FOLDING)
            addOptimizationFlag(selectedCHIROpts, OptimizationFlag.REF_TO_LETC)
            addOptimizationFlag(selectedCHIROpts, OptimizationFlag.REDUNDANT_RETURNS)
            addOptimizationFlag(selectedCHIROpts, OptimizationFlag.REDUNDANT_FUTURE)
            addOptimizationFlag(selectedCHIROpts, OptimizationFlag.FUNC_INLINING)
            addOptimizationFlag(selectedCHIROpts, OptimizationFlag.DEVIRTUALIZATION)
            addOptimizationFlag(selectedCHIROpts, OptimizationFlag.ARRAY_LAMBDA_OPT)
            addOptimizationFlag(selectedCHIROpts, OptimizationFlag.SROA_OPT)
            addOptimizationFlag(selectedCHIROpts, OptimizationFlag.SWITCH_OPT)
            addOptimizationFlag(selectedCHIROpts, OptimizationFlag.VALUE_RANGE_ANALYSIS)
            addOptimizationFlag(selectedCHIROpts, OptimizationFlag.REDUNDANT_LOAD)
            chirEA = true
            chirLICM = true
        } else {
            selectedCHIROpts.clear()
        }
        return true
    }

    public func IsLTOEnabled(): Bool { return ltoMod != LTOMode.NO_LTO }
    public func IsFullLTOEnabled(): Bool { return ltoMod == LTOMode.FULL_LTO }
    public func IsCompileAsExeEnabled(): Bool { return enableCompileAsExe }
    public func IsLTOPkgVisibilityEnabled(): Bool { return ltoHideAllPkgs || !ltoVisiblePkgs.isEmpty() }
    public func AddLtoVisiblePkg(pkg: String): Unit { ltoVisiblePkgs.add(pkg) }
    public func SelectCHIROpt(flag: OptimizationFlag): Unit { addOptimizationFlag(selectedCHIROpts, flag) }
    public func DeselectCHIROpt(flag: OptimizationFlag): Unit { removeOptimizationFlag(selectedCHIROpts, flag) }
    public func SetPrintBCHIR(stage: PrintBCHIROption): Unit {
        printBCHIR[PrintBCHIROptionIndex(stage)] = true
    }
    public func GetOptionsBackend(): Backend { return if (backend == BackendType.CJNATIVE) { Backend.CJNATIVE } else { Backend.UNKNOWN } }
    public func EnableSanitizer(): Bool { return sanitizerType != SanitizerType.NONE }
    public func EnableAsan(): Bool { return sanitizerType == SanitizerType.ADDRESS }
    public func EnableTsan(): Bool { return sanitizerType == SanitizerType.THREAD }
    public func EnableHwAsan(): Bool { return sanitizerType == SanitizerType.HWADDRESS }
    public func IsCrossCompiling(): Bool { return !host.Equal(target) }
    public func IsCHIROptimizationLevelOverO2(): Bool {
        return !disableChirOpt && enumIndex(optimizationLevel) >= enumIndex(OptimizationLevel.O2)
    }
    public func IsOptimizationExisted(flag: OptimizationFlag): Bool {
        return !disableChirOpt && containsOptimizationFlag(selectedCHIROpts, flag)
    }
    public func IsConstEvalEnabled(): Bool { return !interpreter && !interpCHIR }
    public func IsSancovOptionEnabled(): Bool { return sancovOption.IsSancovEnabled() }
    public func IsEmitCHIREnable(): Bool { return emitCHIRPhase != CandidateEmitCHIRPhase.NA }
    public func IsCompilingCJMPSpecific(): Bool { return !commonPartChirs.isEmpty() }
    public func IsCompilingCJMP(): Bool { return IsCompilingCJMPSpecific() || outputMode == OutputMode.CHIR }
    public func CompileExecutable(): Bool {
        return outputMode == OutputMode.EXECUTABLE ||
            (outputMode == OutputMode.OBJ && compileTarget == CompileTarget.EXECUTABLE)
    }
    public func PrintBchir(stage: PrintBCHIROption): Bool {
        return printBCHIR[PrintBCHIROptionIndex(PrintBCHIROption.ALL)] ||
            printBCHIR[PrintBCHIROptionIndex(stage)]
    }
    public func NeedDumpAST(): Bool { return dumpAll || dumpAST }
    public func NeedDumpASTToFile(): Bool { return NeedDumpAST() && !dumpToScreen }
    public func NeedDumpASTToScreen(): Bool { return NeedDumpAST() && dumpToScreen }
    public func NeedDumpCHIR(): Bool { return dumpAll || dumpCHIR }
    public func NeedDumpCHIRToFile(): Bool { return NeedDumpCHIR() && !dumpToScreen }
    public func NeedDumpCHIRToScreen(): Bool { return NeedDumpCHIR() && dumpToScreen }
    public func NeedDumpIR(): Bool { return dumpAll || dumpIR }
    public func NeedDumpIRToFile(): Bool { return (NeedDumpIR() && !dumpToScreen) || codegenDebugMode }
    public func NeedDumpIRToScreen(): Bool { return NeedDumpIR() && dumpToScreen }

    public func ReadPathsFromEnvironmentVars(environmentVars: HashMap<String, String>): Unit {
        environment.allVariables.clear()
        for ((key, value) in environmentVars) {
            environment.allVariables.add(key, value)
        }
        if (let Some(value) <- environmentVars.get("CANGJIE_PATH")) {
            replaceStrings(environment.cangjiePaths, SplitEnvironmentPaths(value))
        }
        if (let Some(value) <- environmentVars.get("CANGJIE_HOME")) {
            environment.cangjieHome = GetAbsPath(value)
            if (environment.cangjieHome.hasValue) { cangjieHome = environment.cangjieHome.value }
        }
        if (let Some(value) <- environmentVars.get("LIBRARY_PATH")) {
            replaceStrings(environment.libraryPaths, SplitEnvironmentPaths(value))
        }
        if (let Some(value) <- environmentVars.get("PATH")) {
            replaceStrings(environment.paths, SplitEnvironmentPaths(value))
        }
        if (let Some(value) <- environmentVars.get("SDKROOT")) {
            environment.macOSSDKRoot = GetAbsPath(value)
        }
    }

    public func GetCangjieLibHostPathName(): String {
        var name = host.OSToString()
        if (host.env == EnvironmentType.OHOS) { name += "_" + host.EnvironmentToString() }
        return name + "_" + host.ArchToString() + "_" + BackendToString(backend)
    }

    public func GetCangjieLibTargetPathName(): String {
        var name = target.OSToString()
        if (target.env != EnvironmentType.GNU && target.env != EnvironmentType.NOT_AVAILABLE) {
            var envName = target.EnvironmentToString()
            if (target.env == EnvironmentType.ANDROID && target.ArchToString() != "arm" &&
                !target.apiLevel.isEmpty() && envName.size >= target.apiLevel.size) {
                envName = envName[0..envName.size - target.apiLevel.size]
            }
            name += "_" + envName
        }
        return name + "_" + target.ArchToString() + "_" + BackendToString(backend)
    }

    public func SetCompilationCachedPath(): Unit {
        if (outputDir.hasValue) {
            compilationCachedPath = outputDir.value
        } else if (IsDir(output)) {
            compilationCachedPath = output
        } else {
            compilationCachedPath = GetDirPath(output)
        }
        if (compilationCachedPath.isEmpty()) { compilationCachedPath = "." }
    }

    public func GetCacheRelativeFilePath(filePath: String): String {
        if (compilationCachedPath.isEmpty()) { return GetFileName(filePath) }
        let absFilePath = GetAbsPath(filePath)
        if (!absFilePath.hasValue) { return GetFileName(filePath) }
        var base = NormalizePath(compilationCachedPath)
        if (!base.isEmpty() && base[base.size - 1] != b'/') { base += "/" }
        let normalized = NormalizePath(absFilePath.value)
        if (StartsWith(normalized, base)) { return normalized[base.size..] }
        return GetFileName(filePath)
    }

    public func GenerateNamesOfCachedDirAndFile(fullPackageName: String): CachePathName {
        var fileName = ""
        if (compilePackage) {
            fileName = fullPackageName
        } else {
            let sortedSrcFiles = ArrayList<String>()
            for (srcFile in srcFiles) {
                appendSortedString(sortedSrcFiles, GetCacheRelativeFilePath(srcFile))
            }
            fileName = joinSortedStrings(sortedSrcFiles)
        }
        let folder = JoinPath(compilationCachedPath, ".cached")
        return CachePathName(folder, StableHashString(fileName))
    }

    public func GenerateCachedPathName(fullPackageName: String, extension: String): String {
        let names = GenerateNamesOfCachedDirAndFile(fullPackageName)
        if (!FileExist(names.dir)) { let _ = CreateDirectory(names.dir) }
        return JoinPath(names.dir, names.file + extension)
    }

    public func GenerateCachedPathNameForCodeGen(subModuleName: String, extension: String): String {
        let hashedFileName = if (codegenDebugMode) { subModuleName } else { StableHashString(subModuleName) }
        let folder = JoinPath(compilationCachedPath, ".cached")
        if (!FileExist(folder)) { let _ = CreateDirectory(folder) }
        return JoinPath(folder, hashedFileName + extension)
    }

    public func GetHashedObjFileName(objFileName: String): String {
        return JoinPath(compilationCachedDir, StableHashString(compilationCachedFileName + objFileName))
    }

    public func GetHashedObjFileNameForPackage(fullPackageName: String, objFileName: String): String {
        let names = GenerateNamesOfCachedDirAndFile(fullPackageName)
        return JoinPath(names.dir, StableHashString(names.file + objFileName))
    }

    public func UpdateCachedDirName(fullPackageName: String): Unit {
        let names = GenerateNamesOfCachedDirAndFile(fullPackageName)
        compilationCachedDir = names.dir
        compilationCachedFileName = names.file
    }

    public func CheckDirectoryPath(path: String): MaybeString {
        if (FileExist(path) && IsDir(path)) { return GetAbsPath(path) }
        return MaybeString()
    }

    public func CheckInputFilePath(path: String): MaybeString {
        if (FileExist(path) && !IsDir(path)) { return GetAbsPath(path) }
        return MaybeString()
    }

    public static func ValidateInputFilePath(path: String): MaybeString {
        if (!IsPathAboveLengthLimit(path) && FileExist(path) && !IsDir(path)) { return GetAbsPath(path) }
        return MaybeString()
    }

    public static func ParseIntOptionValue(
        arg: OptionArgInstance,
        from!: Int64 = -2147483648,
        to!: Int64 = 2147483647
    ): MaybeInt64 {
        let parsed = TryParseInt64(arg.value)
        if (!parsed.hasValue || parsed.value < from || parsed.value > to) {
            Errorln("The value of " + arg.name + " is invalid.")
            return MaybeInt64()
        }
        return parsed
    }

    public static func GetSharedLibraryExtension(osType: OSType): String {
        return match (osType) {
            case OSType.WINDOWS => ".dll"
            case OSType.DARWIN => ".dylib"
            case OSType.IOS => ".dylib"
            case OSType.LINUX => ".so"
            case OSType.UNKNOWN => ".so"
        }
    }

    private func ProcessInputs(inputs: Array<String>): Bool {
        for (input in inputs) {
            let ext = GetFileExtension(input)
            if (ext == "cj" && !compileCjd) {
                if (compilePackage) { return false }
                if (!ValidateInputFilePath(input).hasValue) { return false }
                srcFiles.add(input)
            } else if (ext == "o" || ext == "a" || ext == "obj") {
                let objPath = ValidateInputFilePath(input)
                if (!objPath.hasValue) { return false }
                inputObjs.add(objPath.value)
                ReplaceInputFileName(input, objPath.value)
            } else if (ext == "bc") {
                let bcPath = ValidateInputFilePath(input)
                if (!bcPath.hasValue) { return false }
                bcInputFiles.add(bcPath.value)
                ReplaceInputFileName(input, bcPath.value)
            } else if (ext == "cjo") {
                if (compilePackage || !inputCjoFile.isEmpty()) { return false }
                let cjoPath = ValidateInputFilePath(input)
                if (!cjoPath.hasValue) { return false }
                inputCjoFile = input
            } else if (HasCJDExtension(input) && compileCjd) {
                if (compilePackage || !ValidateInputFilePath(input).hasValue) { return false }
                srcFiles.add(input)
            } else {
                if (IsPathAboveLengthLimit(input)) { return false }
                if (!FileExist(input)) { return false }
                if (IsDir(input)) {
                    let packagePath = CheckDirectoryPath(input)
                    if (!packagePath.hasValue) { return false }
                    packagePaths.add(input)
                } else {
                    Warningln("argument unused: " + input)
                }
            }
        }
        if (compilePackage && packagePaths.isEmpty()) { return false }
        if (compilePackage && packagePaths.size > 1 && !ValidateUniquePackagePaths()) { return false }
        return true
    }

    private func ValidateUniquePackagePaths(): Bool {
        let seen = ArrayList<String>()
        for (packagePath in packagePaths) {
            let absPath = GetAbsPath(packagePath)
            let canonical = if (absPath.hasValue) { absPath.value } else { NormalizePath(packagePath) }
            if (containsString(seen, canonical)) {
                Errorln("duplicate package path '" + packagePath + "' specified with '-p'")
                return false
            }
            seen.add(canonical)
        }
        return true
    }

    private func CheckOutputPathLength(): Bool {
        let defaultOutputNameLen: Int64 = 4
        let fullLength = if (IsDir(output)) { output.size + defaultOutputNameLen } else { output.size }
        if (fullLength > FILE_PATH_MAX_LENGTH) { return false }
        if (fullLength > FILE_PATH_MAX_LENGTH - 15) {
            Warningln("the output file path is close to the length limit " + FILE_PATH_MAX_LENGTH.toString())
        }
        return true
    }

    private func ReprocessOutputs(): Bool {
        if (outputDir.hasValue) {
            if (IsAbsolutePath(output)) { return false }
            output = JoinPath(outputDir.value, output)
            let outputDirAbs = CheckDirectoryPath(outputDir.value)
            if (!outputDirAbs.hasValue) { return false }
            outputDir = MaybeString(outputDirAbs.value)
        }

        let outputIsDir = IsDir(output)
        let dirPath = GetDirPath(output)
        let saveDir = if (outputIsDir) { output } else if (dirPath.isEmpty()) { "/" } else { dirPath }
        let saveDirAbs = CheckDirectoryPath(saveDir)
        if (!saveDirAbs.hasValue) { return false }
        output = if (outputIsDir) { saveDirAbs.value } else { JoinPath(saveDirAbs.value, GetFileName(output)) }
        if (!CheckOutputPathLength()) { return false }
        if (!compileMacroPackage && StartsWith(GetFileName(output), "lib-macro_")) { return false }
        return true
    }

    private func ReprocessInputs(): Bool {
        if (IsDir(output)) { return true }
        let inputsToCheck = ArrayList<String>()
        for (input in argList.GetInputs()) { inputsToCheck.add(input) }
        if (compilePackage) {
            for (packagePath in packagePaths) {
                for (fileName in GetAllFilesUnderCurrentPath(packagePath, "cj")) {
                    inputsToCheck.add(JoinPath(packagePath, fileName))
                }
            }
        }
        for (inputFile in inputsToCheck) {
            let absInputFile = GetAbsPath(inputFile)
            if (!absInputFile.hasValue) { return false }
            if (absInputFile.value == output) { return false }
        }
        return true
    }

    private func PerformPostActions(): Bool {
        chirLLVM = backend == BackendType.CJNATIVE
        chirCC = chirCC || chirLLVM
        if (interpreter) { chirCC = true }
        if (outputMode == OutputMode.OBJ && compileTarget == CompileTarget.DEFAULT) {
            compileTarget = CompileTarget.EXECUTABLE
        }
        if (!SetupConditionalCompilationCfg(this)) { return false }
        if (target.IsMacOS() || target.IsArm32()) { disableReflection = true }
        if (!ReprocessOutputs()) { return false }
        if (!ReprocessInputs()) { return false }
        if (compileMacroPackage && enableOutputType) { return false }
        if (compileMacroPackage && !output.isEmpty() && !IsDir(output)) { return false }
        if (enableCoverage) {
            if (optimizationLevel != OptimizationLevel.O0) {
                let _ = SetOptimizationLevel(OptimizationLevel.O0)
            }
            removedPathPrefix.clear()
        }
        if (scanDepPkg) {
            if (compilePackage) {
                if (!inputCjoFile.isEmpty() || packagePaths.isEmpty()) { return false }
            } else if (inputCjoFile.isEmpty()) {
                return false
            }
        }
        if (EnableSanitizer()) {
            if (IsLTOEnabled() || discardEhFrame || compileMacroPackage) { return false }
            if ((EnableAsan() || EnableHwAsan()) && target.GetOSFamily() != OSType.LINUX) { return false }
            if (EnableHwAsan() && target.arch != ArchType.X86_64 && target.arch != ArchType.AARCH64) { return false }
            if (EnableTsan() && target.GetOSFamily() != OSType.LINUX && target.GetOSFamily() != OSType.WINDOWS) {
                return false
            }
        }
        if (IsLTOEnabled()) {
            if (target.GetOSFamily() == OSType.DARWIN || target.GetOSFamily() == OSType.IOS ||
                target.GetOSFamily() == OSType.WINDOWS) {
                return false
            }
            if (outputMode == OutputMode.OBJ) { return false }
            if (outputMode == OutputMode.STATIC_LIB && !bcInputFiles.isEmpty()) { return false }
            if (optimizationLevel == OptimizationLevel.Os || optimizationLevel == OptimizationLevel.Oz) { return false }
        }
        if (IsCompileAsExeEnabled()) {
            if (!IsLTOEnabled()) { return false }
            if (target.GetOSFamily() == OSType.WINDOWS || target.GetOSFamily() == OSType.DARWIN ||
                target.GetOSFamily() == OSType.IOS) {
                return false
            }
        }
        if (IsLTOPkgVisibilityEnabled()) {
            if (!IsLTOEnabled()) { return false }
            if (!ltoVisiblePkgs.isEmpty() && IsCompileAsExeEnabled()) { return false }
        }
        if (enablePgoInstrGen && enablePgoInstrUse) { return false }
        if (enablePgoInstrGen && target.env == EnvironmentType.OHOS && pgoProfileFile.isEmpty()) { return false }
        if (enablePgoInstrUse && (!FileExist(pgoProfileFile) || GetFileExtension(pgoProfileFile) != "profdata")) {
            return false
        }
        for (commonCjo in commonPartCjos) {
            if (GetFileExtension(commonCjo) != "cjo") { return false }
        }
        for (commonChir in commonPartChirs) {
            if (GetFileExtension(commonChir) != "chir") { return false }
        }
        if (commonPartCjos.size != commonPartChirs.size) { return false }
        if (outputMode != OutputMode.OBJ && compileTarget != CompileTarget.DEFAULT) {
            compileTarget = CompileTarget.DEFAULT
        }
        if (srcFiles.isEmpty() && (outputMode == OutputMode.OBJ || outputMode == OutputMode.CHIR) && !compilePackage) {
            return false
        }
        if (!compilePackage && srcFiles.isEmpty() && !inputObjs.isEmpty() && !experimentalMode) { return false }
        if (!jobs.hasValue) { jobs = MaybeUInt64(1u64) }
        if (target.os == OSType.WINDOWS || target.os == OSType.DARWIN || target.os == OSType.IOS ||
            IsLTOEnabled() || enableCoverage) {
            aggressiveParallelCompile = MaybeUInt64(1u64)
        } else if (!aggressiveParallelCompile.hasValue && (optimizationLevel == OptimizationLevel.O0 ||
            aggressiveParallelCompileWithoutArg)) {
            aggressiveParallelCompile = jobs
        } else if (!aggressiveParallelCompile.hasValue) {
            aggressiveParallelCompile = MaybeUInt64(1u64)
        }
        if (target.env == EnvironmentType.OHOS) { linkStaticStd = MaybeBool(false) }
        return true
    }

    public func PassedWhenKeyValueToSerializedString(): String {
        let pairs = ArrayList<CfgPair>()
        for ((key, value) in passedWhenKeyValue) {
            pairs.add(CfgPair(key, value))
        }
        let used = ArrayList<Bool>()
        for (_ in 0..pairs.size) { used.add(false) }
        var result = ""
        var emitted: Int64 = 0
        while (emitted < pairs.size) {
            var bestIndex: Int64 = -1
            var idx: Int64 = 0
            while (idx < pairs.size) {
                if (!used[idx] && (bestIndex < 0 || pairs[idx].key < pairs[bestIndex].key)) {
                    bestIndex = idx
                }
                idx++
            }
            if (bestIndex < 0) { break }
            used[bestIndex] = true
            result += pairs[bestIndex].key + pairs[bestIndex].value
            emitted++
        }
        return result
    }

    public func BackendTypeToSerializedString(): String {
        return match (backend) {
            case BackendType.CJNATIVE => "LL"
            case BackendType.UNKNOWN => "K"
        }
    }

    public func OptimizationLevelToSerializedString(): String {
        return match (optimizationLevel) {
            case OptimizationLevel.O0 => "O0"
            case OptimizationLevel.O1 => "O1"
            case OptimizationLevel.O2 => "O2"
            case OptimizationLevel.O3 => "O3"
            case OptimizationLevel.Os => "Os"
            case OptimizationLevel.Oz => "Oz"
        }
    }

    public func OutputModeToSerializedString(): String {
        return match (outputMode) {
            case OutputMode.EXECUTABLE => "E"
            case OutputMode.STATIC_LIB => "C"
            case OutputMode.SHARED_LIB => "S"
            case OutputMode.CHIR => "CH"
            case OutputMode.OBJ => CompileTargetToSerializedString()
        }
    }

    public func CompileTargetToSerializedString(): String {
        return match (compileTarget) {
            case CompileTarget.EXECUTABLE => "E"
            case CompileTarget.STATIC_LIB => "C"
            case CompileTarget.SHARED_LIB => "S"
            case CompileTarget.DEFAULT => "K"
        }
    }

    public func StackTraceFormatToSerializedString(): String {
        let mode = match (stackTraceFmt) {
            case StackTraceFormat.ALL => "all"
            case StackTraceFormat.SIMPLE => "simple"
            case StackTraceFormat.DEFAULT => "default"
        }
        return "stack-trace-format=" + mode
    }

    public func SelectedCHIROptsToSerializedString(): String {
        var result = ""
        var idx: Int64 = 0
        while (idx <= OptimizationFlagIndex(OptimizationFlag.REDUNDANT_LOAD)) {
            var selected = false
            for (flag in selectedCHIROpts) {
                if (OptimizationFlagIndex(flag) == idx) { selected = true }
            }
            result += if (selected) { "1" } else { "0" }
            idx++
        }
        return result
    }

    public func OverflowStrategyToSerializedString(): String {
        return match (overflowStrategy) {
            case OverflowStrategy.NA => "N"
            case OverflowStrategy.CHECKED => "C"
            case OverflowStrategy.WRAPPING => "W"
            case OverflowStrategy.THROWING => "T"
            case OverflowStrategy.SATURATING => "S"
        }
    }

    public func SanitizerTypeToSerializedString(): String {
        return match (sanitizerType) {
            case SanitizerType.NONE => "none"
            case SanitizerType.ADDRESS => "address"
            case SanitizerType.THREAD => "thread"
            case SanitizerType.HWADDRESS => "hardware address"
        }
    }

    public func SanitizerTypeToShortString(): String {
        return match (sanitizerType) {
            case SanitizerType.NONE => ""
            case SanitizerType.ADDRESS => "asan"
            case SanitizerType.THREAD => "tsan"
            case SanitizerType.HWADDRESS => "hwasan"
        }
    }

    public func LTOModeToSerializedString(): String {
        return match (ltoMod) {
            case LTOMode.FULL_LTO => "0"
            case LTOMode.THIN_LTO => "1"
            case LTOMode.NO_LTO => "2"
        }
    }

    public func ToSerialized(): Array<String> {
        return [
            BoolToSerializedString(enableCompileDebug),
            target.ToFullTripleString(),
            PassedWhenKeyValueToSerializedString(),
            SelectedCHIROptsToSerializedString(),
            BoolToSerializedString(compilePackage),
            BoolToSerializedString(noSubPkg),
            BoolToSerializedString(displayLineInfo),
            moduleName,
            LTOModeToSerializedString(),
            joinStrings(removedPathPrefix, ":"),
            BackendTypeToSerializedString(),
            BoolToSerializedString(enableMacroInLSP),
            BoolToSerializedString(enableCompileTest),
            BoolToSerializedString(implicitPrelude),
            BoolToSerializedString(enableInteropCJMapping),
            BoolToSerializedString(chirEA),
            BoolToSerializedString(chirLICM),
            BoolToSerializedString(chirCC),
            OptimizationLevelToSerializedString(),
            StackTraceFormatToSerializedString(),
            OutputModeToSerializedString(),
            BoolToSerializedString(enableHotReload),
            BoolToSerializedString(disableChirOpt),
            sancovOption.ToSerializedString(),
            BoolToSerializedString(chirLLVM),
            BoolToSerializedString(strictNumberMode),
            BoolToSerializedString(fastMathMode),
            BoolToSerializedString(enableCoverage),
            SanitizerTypeToSerializedString(),
            BoolToSerializedString(experimentalMode),
            OverflowStrategyToSerializedString(),
            BoolToSerializedString(interpreter),
            joinStrings(interpreterSearchPaths, ":"),
            joinStrings(interpLoadLib, ":"),
            joinStrings(interpreterArgs, "\\"),
            BoolToSerializedString(interpreterPrintResult),
            BoolToSerializedString(interpFullBchir),
            BoolToSerializedString(interpMainNoLinkage),
            BoolToSerializedString(interpCHIR),
            BoolToSerializedString(constEvalDebug),
            BoolToSerializedString(disableCodeGen),
            BoolToSerializedString(disableReflection),
            BoolToSerializedString(enableEH),
            BoolToSerializedString(compileCjd),
            BoolToSerializedString(enableParallelMacro),
            BoolToSerializedString(enableCoverage),
            targetCPU,
            sysroot,
        ]
    }
}
