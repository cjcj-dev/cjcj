package cjcj::option

import cjcj::basic.DEFAULT_POSITION as BasicDefaultPosition
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::utils.AccessResultType as UtilsAccessResultType
import cjcj::utils.CJC_ABORT
import cjcj::utils.CJC_ASSERT
import cjcj::utils.FileMode as UtilsFileMode
import cjcj::utils.Out64
import cjcj::utils.OverflowStrategy
import cjcj::utils.Semaphore as UtilsSemaphore
import cjcj::utils.TryParseInt as UtilsTryParseInt
import std.collection.*
import std.core.Option as CoreOption

private let ARGUMENT_IGNORED_SUFFIX: String = " The argument is ignored."
private let CJO_EXTENSION: String = "cjo"
private let BC_EXTENSION: String = "bc"
private let CJ_EXTENSION: String = "cj"
private let CHIR_EXTENSION: String = "chir"
private let ARCHIVE_EXTENSION: String = "a"
private let OBJECT_EXTENSION: String = "o"
private let COFF_OBJECT_EXTENSION: String = "obj"
private let CANGJIE_VISIBLE_OPTIONS_ONLY: Bool = true

private func emitOptionDiag(kind: BasicDiagKindRefactor): Unit {
    let diag = BasicDiagnosticEngine()
    diag.DiagnoseRefactor(kind, BasicDefaultPosition).Emit()
}

private func emitOptionDiag(kind: BasicDiagKindRefactor, arg: String): Unit {
    let diag = BasicDiagnosticEngine()
    diag.DiagnoseRefactor(kind, BasicDefaultPosition, arguments: [arg]).Emit()
}

private func emitOptionDiag(kind: BasicDiagKindRefactor, first: String, second: String): Unit {
    let diag = BasicDiagnosticEngine()
    diag.DiagnoseRefactor(kind, BasicDefaultPosition, arguments: [first, second]).Emit()
}

private func emitOptionDiag(
    kind: BasicDiagKindRefactor,
    first: String,
    second: String,
    third: String,
    fourth: String
): Unit {
    let diag = BasicDiagnosticEngine()
    diag.DiagnoseRefactor(kind, BasicDefaultPosition, arguments: [first, second, third, fourth]).Emit()
}

private func emitDirectoryAccessFailure(path: String, result: UtilsAccessResultType): Unit {
    match (result) {
        case UtilsAccessResultType.NO_PERMISSION => emitOptionDiag(BasicDiagKindRefactor.permission_denied, path)
        case _ => emitOptionDiag(BasicDiagKindRefactor.no_such_directory, path)
    }
}

private func ltoUnsupportedOSName(target: TripleInfo): String {
    let osFamily = target.GetOSFamily()
    if (osFamily == OSType.IOS) { return "iOS" }
    if (osFamily == OSType.DARWIN) { return "Darwin" }
    if (osFamily == OSType.WINDOWS) { return "Windows" }
    return target.OSToString()
}

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
        result += ",traceMemCmp" + BoolToSerializedString(traceMemCmp)
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

private func vectorStrToSerializedString(values: ArrayList<String>, delimiter: String): String {
    var result = ""
    for (value in values) {
        result += value + delimiter
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

private func optionValueBelongsBackend(values: Array<Backend>, target: Backend): Bool {
    for (value in values) {
        if (value == Backend.ALL || value == target) { return true }
    }
    return false
}

private func optionValueBelongsGroup(values: Array<Group>, target: Group): Bool {
    for (value in values) {
        if (value == target) { return true }
    }
    return false
}

private func replaceStrings(target: ArrayList<String>, values: Array<String>): Unit {
    target.clear()
    for (value in values) { target.add(value) }
}

public open class GlobalOptions <: Option {
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
    // Serialized package .cjo outputs to publish next to the built library. Kept separate from
    // frontendOutputFiles, which the backend consumes as bitcode inputs (a .cjo there breaks opt).
    public let cjoOutputFiles: ArrayList<TempFileInfo> = ArrayList<TempFileInfo>()
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
    public var linkStaticStd: CoreOption<Bool> = None
    public var ltoMod: LTOMode = LTOMode.NO_LTO
    public var emitStaticLibInLTO: CoreOption<Bool> = None
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
    public var chirWFC: Bool = false
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
    public var stackTraceFmt: StackTraceFormat = StackTraceFormat.DEFAULT
    public var errorCountLimit: MaybeUInt64 = MaybeUInt64(8u64)
    public var jobs: MaybeUInt64 = MaybeUInt64()
    public var aggressiveParallelCompile: MaybeUInt64 = MaybeUInt64()
    public var aggressiveParallelCompileWithoutArg: Bool = false
    public let bitcodeFilesName: ArrayList<String> = ArrayList<String>()
    public let symbolsNeedLocalized: ArrayList<String> = ArrayList<String>()
    public let symbolsNeedLocalizedPerPkg: HashMap<String, ArrayList<String>> =
        HashMap<String, ArrayList<String>>()
    public var overflowStrategy: OverflowStrategy = OverflowStrategy.THROWING
    public var emitCHIRPhase: CandidateEmitCHIRPhase = CandidateEmitCHIRPhase.NA
    public let sancovOption: SanitizerCoverageOptions = SanitizerCoverageOptions()
    public init() { super() }

    public override func ParseFromArgs(argList: ArgList): Bool {
        this.argList = argList
        let delayed = ArrayList<OptionArgInstance>()
        var rawArgIndex: UInt64 = 0u64
        var skipParsing = false
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
                    DeprecatedOptionCheck(opt)
                    if (!pre.success) { return false }
                    skipParsing = skipParsing || pre.skipParsing
                } else {
                    delayed.add(opt)
                }
            }
        }
        if (skipParsing) { return true }
        for (opt in delayed) {
            if (!TryParseOption(opt, argList)) { return false }
        }
        if (!ProcessInputs(argList.GetInputs())) { return false }
        if (!PerformPostActions()) { return false }
        return true
    }

    protected open func ParseOption(arg: OptionArgInstance): CoreOption<Bool> {
        let result = ParseAction(this, arg)
        if (!result.handled) { return None }
        return Some(result.success)
    }

    private func ErrorExperimentalOption(argName: String): Unit {
        Errorln(argName + " is an experimental feature. \"--experimental\" option is required to enable experimental features.")
    }

    private func TryParseOption(arg: OptionArgInstance, argList: ArgList): Bool {
        if (CANGJIE_VISIBLE_OPTIONS_ONLY && !arg.info.BelongsGroup(Group.VISIBLE)) {
            return false
        }
        if (!experimentalMode && !arg.info.BelongsGroup(Group.STABLE)) {
            ErrorExperimentalOption(arg.str)
            return false
        }
        if (!arg.info.values.isEmpty()) {
            var matchedValue: CoreOption<OptionValue> = None
            for (optionValue in arg.info.values) {
                if (optionValue.value == arg.value &&
                    optionValueBelongsBackend(optionValue.backends, GetOptionsBackend())) {
                    matchedValue = Some(optionValue)
                    break
                }
            }
            if (let Some(optionValue) <- matchedValue) {
                if (CANGJIE_VISIBLE_OPTIONS_ONLY && !optionValueBelongsGroup(optionValue.groups, Group.VISIBLE)) {
                    Errorln("invalid value: '" + optionValue.value + "'")
                    return false
                }
                if (!experimentalMode && !optionValueBelongsGroup(optionValue.groups, Group.STABLE)) {
                    ErrorExperimentalOption(arg.str)
                    return false
                }
            }
        }
        DeprecatedOptionCheck(arg)
        let maybeResult = ParseOption(arg)
        CJC_ASSERT(maybeResult.isSome())
        let optionSuccess = maybeResult.getOrThrow()
        OccurrenceCheck(arg, argList)
        return optionSuccess
    }

    private func DeprecatedOptionCheck(arg: OptionArgInstance): Unit {
        let id = arg.info.GetID()
        if (id == ID.STATIC_LIBS || id == ID.DY_LIBS || id == ID.COMPILE_AS_EXE) {
            emitOptionDiag(BasicDiagKindRefactor.driver_deprecated_option, arg.str, "")
        }
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
            var name = arg.info.GetName()
            if (!arg.info.GetAlias().isEmpty()) { name += "' or '" + arg.info.GetAlias() }
            Warningln("'" + name + "' is specified multiple times. The last one is chosen.")
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
    public func ShouldEmitStaticLibInLTO(): Bool {
        return (emitStaticLibInLTO ?? false) && outputMode == OutputMode.STATIC_LIB && IsLTOEnabled()
    }
    public func IsCompileAsExeEnabled(): Bool { return enableCompileAsExe }
    public func IsLTOPkgVisibilityEnabled(): Bool { return ltoHideAllPkgs || !ltoVisiblePkgs.isEmpty() }
    public func GetLtoVisiblePkgs(): Array<String> { return ltoVisiblePkgs.toArray() }
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
    public open func IsObfuscationEnabled(): Bool { return false }
    public open func ReprocessObfuseOption(): Bool { return true }
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
    public func SetFrontendMode(): Unit { frontendMode = true }
    public func GetStackTraceFormat(): String { return "--" + StackTraceFormatToSerializedString() }
    public func GetJobs(): UInt64 { return if (jobs.hasValue) { jobs.value } else { GetHardwareConcurrency() } }

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
        CJC_ASSERT(!compilationCachedPath.isEmpty())
    }

    public func GetCacheRelativeFilePath(filePath: String): String {
        if (compilationCachedPath.isEmpty()) { return GetFileName(filePath) }
        let absFilePath = GetAbsPath(filePath)
        if (!absFilePath.hasValue) { return GetFileName(filePath) }
        let relativePath = GetRelativePath(JoinPath(compilationCachedPath, ""), absFilePath.value)
        if (relativePath.hasValue) { return relativePath.value }
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
        if (!FileExist(path)) {
            emitOptionDiag(BasicDiagKindRefactor.driver_warning_no_such_directory, path, ARGUMENT_IGNORED_SUFFIX)
            return MaybeString()
        }
        if (!IsDir(path)) {
            emitOptionDiag(BasicDiagKindRefactor.driver_warning_not_a_directory, path, ARGUMENT_IGNORED_SUFFIX)
            return MaybeString()
        }
        let absPath = GetAbsPath(path)
        if (!absPath.hasValue) {
            emitOptionDiag(BasicDiagKindRefactor.driver_warning_invalid_path, path, ARGUMENT_IGNORED_SUFFIX)
        }
        return absPath
    }

    public func ValidateDirectoryPath(path: String, mode!: UtilsFileMode = UtilsFileMode.FM_EXIST): MaybeString {
        let accessResult = AccessFileWithResult(path, mode)
        if (!IsAccessOK(accessResult)) {
            emitDirectoryAccessFailure(path, accessResult)
            return MaybeString()
        }
        if (!IsDir(path)) {
            emitOptionDiag(BasicDiagKindRefactor.not_a_directory, path)
            return MaybeString()
        }
        if (mode == UtilsFileMode.FM_WRITE) {
            let execResult = AccessFileWithResult(path, UtilsFileMode.FM_EXE)
            if (!IsAccessOK(execResult)) {
                emitDirectoryAccessFailure(path, execResult)
                return MaybeString()
            }
        }
        let absPath = GetAbsPath(path)
        if (!absPath.hasValue) {
            emitOptionDiag(BasicDiagKindRefactor.invalid_path, path)
        }
        return absPath
    }

    public func CheckInputFilePath(path: String): MaybeString {
        if (!FileExist(path)) {
            emitOptionDiag(BasicDiagKindRefactor.driver_warning_no_such_file_or_directory, path, ARGUMENT_IGNORED_SUFFIX)
            return MaybeString()
        }
        if (!CanAccessFile(path, UtilsFileMode.FM_READ)) {
            emitOptionDiag(BasicDiagKindRefactor.driver_warning_permission_denied, path, ARGUMENT_IGNORED_SUFFIX)
            return MaybeString()
        }
        if (IsDir(path)) {
            emitOptionDiag(BasicDiagKindRefactor.driver_warning_not_a_file, path, ARGUMENT_IGNORED_SUFFIX)
            return MaybeString()
        }
        let absPath = GetAbsPath(path)
        if (!absPath.hasValue) {
            emitOptionDiag(BasicDiagKindRefactor.driver_warning_invalid_path, path, ARGUMENT_IGNORED_SUFFIX)
        }
        return absPath
    }

    public static func ValidateInputFilePath(path: String): MaybeString {
        return ValidateInputFilePath(path, BasicDiagKindRefactor.driver_invalid_source_file)
    }

    public static func ValidateInputFilePath(path: String, notFoundError: BasicDiagKindRefactor): MaybeString {
        if (IsPathAboveLengthLimit(path)) {
            emitOptionDiag(BasicDiagKindRefactor.driver_path_exceeds_length_limit, path, FILE_PATH_MAX_LENGTH.toString())
            return MaybeString()
        }
        if (!FileExist(path)) {
            emitOptionDiag(notFoundError, path)
            return MaybeString()
        }
        if (!CanAccessFile(path, UtilsFileMode.FM_READ)) {
            emitOptionDiag(BasicDiagKindRefactor.permission_denied, path)
            return MaybeString()
        }
        if (IsDir(path)) {
            emitOptionDiag(BasicDiagKindRefactor.not_a_file, path)
            return MaybeString()
        }
        let absPath = GetAbsPath(path)
        if (!absPath.hasValue) {
            emitOptionDiag(BasicDiagKindRefactor.invalid_path, path)
        }
        return absPath
    }

    public static func ValidateInputFilePath(
        path: String,
        notFoundError: BasicDiagKindRefactor,
        diag: BasicDiagnosticEngine
    ): MaybeString {
        if (IsPathAboveLengthLimit(path)) {
            diag.DiagnoseRefactor(
                BasicDiagKindRefactor.driver_path_exceeds_length_limit,
                BasicDefaultPosition,
                path,
                FILE_PATH_MAX_LENGTH.toString()).Emit()
            return MaybeString()
        }
        if (!FileExist(path)) {
            diag.DiagnoseRefactor(notFoundError, BasicDefaultPosition, path).Emit()
            return MaybeString()
        }
        if (!CanAccessFile(path, UtilsFileMode.FM_READ)) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.permission_denied, BasicDefaultPosition, path).Emit()
            return MaybeString()
        }
        if (IsDir(path)) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.not_a_file, BasicDefaultPosition, path).Emit()
            return MaybeString()
        }
        let absPath = GetAbsPath(path)
        if (!absPath.hasValue) {
            diag.DiagnoseRefactor(BasicDiagKindRefactor.invalid_path, BasicDefaultPosition, path).Emit()
        }
        return absPath
    }

    public static func ParseIntOptionValue(
        arg: OptionArgInstance,
        from!: Int64 = -2147483648,
        to!: Int64 = 2147483647
    ): CoreOption<Int64> {
        if (let Some(number) <- UtilsTryParseInt(arg.value)) {
            let parsedValue = Int64(number)
            if (parsedValue >= from && parsedValue <= to) {
                return Some(parsedValue)
            }
        }
        Errorln("The value of " + arg.name + " is invalid.")
        return None
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

    private func VerifyFileExtension(file: String, fullPath: String, extension: String): Bool {
        if (GetFileExtension(fullPath) != extension) {
            emitOptionDiag(
                BasicDiagKindRefactor.driver_warning_unexpected_file_extension,
                extension,
                file,
                fullPath,
                ARGUMENT_IGNORED_SUFFIX
            )
            return false
        }
        return true
    }

    private func HandleArchiveExtension(value: String): Bool {
        let maybePath = ValidateInputFilePath(value, BasicDiagKindRefactor.driver_invalid_binary_file)
        if (!maybePath.hasValue) { return false }
        let fullPath = maybePath.value
        let extension = GetFileExtension(value)
        if (!VerifyFileExtension(value, fullPath, extension)) { return true }
        inputObjs.add(fullPath)
        ReplaceInputFileName(value, fullPath)
        return true
    }

    private func HandleCJOExtension(value: String): Bool {
        let maybePath = ValidateInputFilePath(value, BasicDiagKindRefactor.driver_invalid_binary_file)
        if (!maybePath.hasValue) { return false }
        if (!VerifyFileExtension(value, maybePath.value, CJO_EXTENSION)) { return true }
        if (!inputCjoFile.isEmpty()) {
            emitOptionDiag(BasicDiagKindRefactor.driver_require_one_package_directory_scan_dependency, "--scan-dependency")
            return false
        }
        inputCjoFile = value
        return true
    }

    private func HandleCJExtension(value: String): Bool {
        if (compilePackage) {
            emitOptionDiag(BasicDiagKindRefactor.driver_unsupport_compile_package_with_source_file, value)
            return false
        }
        let maybePath = ValidateInputFilePath(value, BasicDiagKindRefactor.driver_invalid_source_file)
        if (!maybePath.hasValue) { return false }
        if (!VerifyFileExtension(value, maybePath.value, CJ_EXTENSION)) { return true }
        srcFiles.add(value)
        return true
    }

    private func HandleCJDExtension(value: String): Bool {
        if (compilePackage) {
            emitOptionDiag(BasicDiagKindRefactor.driver_unsupport_compile_package_with_source_file, value)
            return false
        }
        if (!ValidateInputFilePath(value, BasicDiagKindRefactor.driver_invalid_source_file).hasValue) {
            return false
        }
        srcFiles.add(value)
        return true
    }

    private func HandleBCExtension(value: String): Bool {
        let maybePath = ValidateInputFilePath(value, BasicDiagKindRefactor.driver_invalid_source_file)
        if (!maybePath.hasValue) { return false }
        let fullPath = maybePath.value
        if (!VerifyFileExtension(value, fullPath, BC_EXTENSION)) { return true }
        bcInputFiles.add(fullPath)
        ReplaceInputFileName(value, fullPath)
        return true
    }

    private func HandleNoExtension(value: String): Bool {
        if (IsPathAboveLengthLimit(value)) {
            emitOptionDiag(
                BasicDiagKindRefactor.driver_path_exceeds_length_limit,
                value,
                FILE_PATH_MAX_LENGTH.toString()
            )
            return false
        }
        if (!FileExist(value)) {
            emitOptionDiag(BasicDiagKindRefactor.driver_invalid_file_or_directory, value)
            return false
        }
        if (IsDir(value)) {
            if (!compilePackage) {
                emitOptionDiag(BasicDiagKindRefactor.driver_unsupport_compile_source_file_with_path, value)
            }
            if (!ValidateDirectoryPath(value, mode: UtilsFileMode.FM_EXIST).hasValue) { return false }
            packagePaths.add(value)
        } else {
            emitOptionDiag(BasicDiagKindRefactor.driver_warning_argument_unused, value)
        }
        return true
    }

    private func ProcessInputs(inputs: Array<String>): Bool {
        for (input in inputs) {
            let ext = GetFileExtension(input)
            if (ext == OBJECT_EXTENSION || ext == ARCHIVE_EXTENSION || ext == COFF_OBJECT_EXTENSION) {
                if (!HandleArchiveExtension(input)) { return false }
            } else if (ext == CJ_EXTENSION && !compileCjd) {
                if (!HandleCJExtension(input)) { return false }
            } else if (ext == BC_EXTENSION) {
                if (!HandleBCExtension(input)) { return false }
            } else if (ext == CJO_EXTENSION) {
                if (!HandleCJOExtension(input)) { return false }
            } else if (HasCJDExtension(input) && compileCjd) {
                if (!HandleCJDExtension(input)) { return false }
            } else if (!HandleNoExtension(input)) {
                return false
            }
        }
        if (compilePackage && packagePaths.isEmpty()) {
            emitOptionDiag(BasicDiagKindRefactor.driver_require_package_directory)
            return false
        }
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
        let defaultOutputNameLen = GetDefaultOutputNameLength()
        let fullLength = if (IsDir(output)) { output.size + defaultOutputNameLen } else { output.size }
        if (fullLength > FILE_PATH_MAX_LENGTH) {
            emitOptionDiag(
                BasicDiagKindRefactor.driver_path_exceeds_length_limit,
                "the output file",
                FILE_PATH_MAX_LENGTH.toString()
            )
            return false
        }
        if (fullLength > FILE_PATH_MAX_LENGTH - 15) {
            emitOptionDiag(
                BasicDiagKindRefactor.driver_warning_path_close_to_length_limit,
                "the output file",
                FILE_PATH_MAX_LENGTH.toString()
            )
        }
        return true
    }

    private func ReprocessOutputs(): Bool {
        if (outputDir.hasValue) {
            if (IsAbsolutePath(output)) {
                Errorln("'-o' does not accept absolute path when '--output-dir' is specified")
                return false
            }
            output = JoinPath(outputDir.value, output)
            let outputDirAbs = ValidateDirectoryPath(outputDir.value, mode: UtilsFileMode.FM_WRITE)
            if (!outputDirAbs.hasValue) { return false }
            outputDir = MaybeString(outputDirAbs.value)
        }

        let outputIsDir = IsDir(output)
        let dirPath = GetDirPath(output)
        let saveDir = if (outputIsDir) { output } else if (dirPath.isEmpty()) { "/" } else { dirPath }
        let saveDirAbs = ValidateDirectoryPath(saveDir, mode: UtilsFileMode.FM_WRITE)
        if (!saveDirAbs.hasValue) { return false }
        output = if (outputIsDir) { saveDirAbs.value } else { JoinPath(saveDirAbs.value, GetFileName(output)) }
        if (!CheckOutputPathLength()) { return false }
        if (!compileMacroPackage && StartsWith(GetFileName(output), "lib-macro_")) {
            Errorln("Cannot support specify file prefix 'lib-macro_' without '--compile-macro' option.")
            return false
        }
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
            if (!absInputFile.hasValue) {
                emitOptionDiag(BasicDiagKindRefactor.no_such_file_or_directory, inputFile)
                return false
            }
            if (absInputFile.value == output) {
                emitOptionDiag(BasicDiagKindRefactor.input_file_overwritten_by_generated_output, inputFile)
                return false
            }
        }
        return true
    }

    protected open func PerformPostActions(): Bool {
        chirLLVM = backend == BackendType.CJNATIVE
        chirCC = chirCC || chirLLVM
        if (interpreter) { chirCC = true }
        if (outputMode == OutputMode.OBJ && compileTarget == CompileTarget.DEFAULT) {
            compileTarget = CompileTarget.EXECUTABLE
        }
        if (!SetupConditionalCompilationCfg(this)) { return false }
        if (!ReprocessOutputs()) { return false }
        if (!ReprocessInputs()) { return false }
        if (target.IsMacOS() || target.IsArm32()) { disableReflection = true }
        if (compileMacroPackage && enableOutputType) {
            Errorln("using both '--compile-macro' and '--output-type' is not allowed.")
            return false
        }
        if (compileMacroPackage && !output.isEmpty() && !IsDir(output)) {
            Errorln("Cannot support specify output file name with '--compile-macro' option.")
            return false
        }
        if (enableCoverage) {
            if (optimizationLevel != OptimizationLevel.O0) {
                Warningln("'--coverage' should be used without optimizations.")
                let _ = SetOptimizationLevel(OptimizationLevel.O0)
            }
            if (!removedPathPrefix.isEmpty()) {
                Warningln("'--coverage' should be used without option '--trimpath'.")
                removedPathPrefix.clear()
            }
        }
        if (scanDepPkg) {
            if (compilePackage) {
                if (!inputCjoFile.isEmpty()) {
                    emitOptionDiag(
                        BasicDiagKindRefactor.driver_not_accept_cjo_inputs_when,
                        "'-p' or '--package'"
                    )
                    return false
                }
                if (packagePaths.isEmpty()) {
                    emitOptionDiag(BasicDiagKindRefactor.driver_require_package_directory_scan_dependency)
                    return false
                }
            } else if (inputCjoFile.isEmpty()) {
                emitOptionDiag(BasicDiagKindRefactor.driver_source_cjo_empty)
                return false
            }
        }
        if (EnableSanitizer()) {
            let runtimeDirPath = JoinPath(cangjieHome, "runtime")
            let libraryDirPath = JoinPath(JoinPath(runtimeDirPath, "lib"), GetCangjieLibTargetPathName())
            let sanitizerPath = JoinPath(libraryDirPath, SanitizerTypeToShortString())
            let runtimePath = JoinPath(sanitizerPath, "libcangjie-runtime" + GetSharedLibraryExtension(target.os))
            if (!FileExist(runtimePath)) {
                Errorln(SanitizerTypeToSerializedString() + " sanitizer feature is not supported.")
                return false
            }
            if (IsLTOEnabled()) {
                Errorln("Option '--sanitize' and '--lto' cannot be enabled together.")
                return false
            }
            if (discardEhFrame) {
                Errorln("Option '--sanitize' and '--discard-eh-frame' cannot be enabled together.")
                return false
            }
            if (compileMacroPackage) {
                Errorln("Option '--sanitize' and '--compile-macro' cannot be enabled together.")
                return false
            }
            if (EnableAsan() && target.GetOSFamily() != OSType.LINUX) {
                Errorln("Address Sanitizer is only supported on Linux")
                return false
            }
            if (EnableHwAsan() && target.GetOSFamily() != OSType.LINUX) {
                Errorln("Hardware-Assisted Address Sanitizer is only supported on Linux")
                return false
            }
            if (EnableHwAsan() && target.arch != ArchType.X86_64 && target.arch != ArchType.AARCH64) {
                Errorln("Hardware-Assisted Address Sanitizer is only supported on X86_64 or aarch64")
                return false
            }
            if (EnableTsan() && target.GetOSFamily() != OSType.LINUX && target.GetOSFamily() != OSType.WINDOWS) {
                Errorln("Thread Sanitizer is only supported on Linux/Windows")
                return false
            }
        }
        if (IsLTOEnabled()) {
            if (target.GetOSFamily() == OSType.DARWIN || target.GetOSFamily() == OSType.WINDOWS) {
                emitOptionDiag(BasicDiagKindRefactor.driver_target_lto_unsupported, ltoUnsupportedOSName(target))
                return false
            }
            if (!experimentalMode && target.os == OSType.IOS) {
                Errorln("LTO on iOS is an experimental feature, use '--experimental' to enable it.")
                return false
            }
            if (target.os == OSType.IOS && IsObfuscationEnabled()) {
                Errorln("Obfuscation is not supported when LTO is enabled on iOS.")
                return false
            }
            if (target.os == OSType.IOS && outputMode != OutputMode.STATIC_LIB) {
                Errorln("iOS LTO only supports --output-type=staticlib.")
                return false
            }
            if (outputMode == OutputMode.OBJ) {
                Errorln("--output-type=obj is not allowed in LTO mode")
                return false
            }
            if (outputMode == OutputMode.STATIC_LIB && !bcInputFiles.isEmpty() && !ShouldEmitStaticLibInLTO()) {
                Errorln("The input file cannot be bc files When generating a static library in LTO mode.")
                return false
            }
            if (optimizationLevel == OptimizationLevel.Os || optimizationLevel == OptimizationLevel.Oz) {
                Errorln("-Os and -Oz optimize options are not supported in LTO mode.")
                return false
            }
        }
        if (IsCompileAsExeEnabled()) {
            if (!IsLTOEnabled()) {
                emitOptionDiag(BasicDiagKindRefactor.driver_invalid_compile_as_exe)
                return false
            }
            if (target.GetOSFamily() == OSType.WINDOWS || target.GetOSFamily() == OSType.DARWIN ||
                target.GetOSFamily() == OSType.IOS) {
                emitOptionDiag(BasicDiagKindRefactor.driver_invalid_compile_as_exe_platform)
                return false
            }
        }
        if (IsLTOPkgVisibilityEnabled()) {
            if (!IsLTOEnabled()) {
                emitOptionDiag(BasicDiagKindRefactor.driver_invalid_visible_pkgs)
                return false
            }
            if (!ltoVisiblePkgs.isEmpty() && IsCompileAsExeEnabled()) {
                emitOptionDiag(BasicDiagKindRefactor.driver_invalid_visible_pkgs_conflict)
                return false
            }
            if (outputMode != OutputMode.SHARED_LIB) {
                emitOptionDiag(BasicDiagKindRefactor.driver_visible_pkgs_only_for_dylib)
            }
        }
        if (!CheckLTOStaticLibFormatOptions()) { return false }
        if (enablePgoInstrGen && enablePgoInstrUse) {
            emitOptionDiag(BasicDiagKindRefactor.driver_pgo_both_gen_and_use)
            return false
        }
        if (enablePgoInstrGen && target.env == EnvironmentType.OHOS && pgoProfileFile.isEmpty()) {
            emitOptionDiag(BasicDiagKindRefactor.driver_ohos_pgo_gen_without_file)
            return false
        }
        if (enablePgoInstrUse) {
            if (!FileExist(pgoProfileFile)) {
                emitOptionDiag(BasicDiagKindRefactor.no_such_file_or_directory, pgoProfileFile)
                return false
            }
            if (GetFileExtension(pgoProfileFile) != "profdata") {
                emitOptionDiag(BasicDiagKindRefactor.driver_pgo_invalid_profile_extension, pgoProfileFile)
                return false
            }
        }
        if (outputMode != OutputMode.OBJ && compileTarget != CompileTarget.DEFAULT) {
            compileTarget = CompileTarget.DEFAULT
            emitOptionDiag(BasicDiagKindRefactor.driver_invalid_compile_target)
        }
        if (srcFiles.isEmpty() && (outputMode == OutputMode.OBJ || outputMode == OutputMode.CHIR) && !compilePackage) {
            emitOptionDiag(BasicDiagKindRefactor.driver_source_file_empty)
            return false
        }
        if (!compilePackage && srcFiles.isEmpty() && !inputObjs.isEmpty() && !experimentalMode) {
            emitOptionDiag(BasicDiagKindRefactor.driver_require_experimental)
            return false
        }
        if (!ReprocessObfuseOption()) { return false }
        var cjmpOk = true
        for (commonCjo in commonPartCjos) {
            if (GetFileExtension(commonCjo) != CJO_EXTENSION) {
                emitOptionDiag(
                    BasicDiagKindRefactor.driver_warning_unexpected_file_extension,
                    CJO_EXTENSION,
                    commonCjo,
                    commonCjo,
                    ARGUMENT_IGNORED_SUFFIX
                )
                cjmpOk = false
            }
        }
        for (commonChir in commonPartChirs) {
            if (GetFileExtension(commonChir) != CHIR_EXTENSION) {
                emitOptionDiag(
                    BasicDiagKindRefactor.driver_warning_unexpected_file_extension,
                    CHIR_EXTENSION,
                    commonChir,
                    commonChir,
                    ARGUMENT_IGNORED_SUFFIX
                )
                cjmpOk = false
            }
        }
        if (commonPartCjos.size != commonPartChirs.size) {
            emitOptionDiag(BasicDiagKindRefactor.driver_require_common_chir_for_each_common_cjo)
            cjmpOk = false
        }
        if (!cjmpOk) { return false }
        if (!jobs.hasValue) { jobs = MaybeUInt64(GetHardwareConcurrency()) }
        if (target.os == OSType.WINDOWS || target.os == OSType.DARWIN || target.os == OSType.IOS ||
            IsObfuscationEnabled() || IsLTOEnabled() || enableCoverage) {
            if ((target.os == OSType.WINDOWS || target.os == OSType.DARWIN || target.os == OSType.IOS) &&
                (aggressiveParallelCompile.hasValue || aggressiveParallelCompileWithoutArg)) {
                Warningln("'--apc' is not supported when targeting " + target.OSToString() + ".")
            }
            aggressiveParallelCompile = MaybeUInt64(1u64)
        } else if (!aggressiveParallelCompile.hasValue && (optimizationLevel == OptimizationLevel.O0 ||
            aggressiveParallelCompileWithoutArg)) {
            aggressiveParallelCompile = jobs
            UtilsSemaphore.Get().SetCount(Int64(jobs.value + 2u64))
        } else if (!aggressiveParallelCompile.hasValue) {
            aggressiveParallelCompile = MaybeUInt64(1u64)
        }
        if (target.env == EnvironmentType.OHOS) {
            if (let Some(staticStd) <- linkStaticStd) {
                if (staticStd) {
                    emitOptionDiag(BasicDiagKindRefactor.driver_static_std_for_ohos)
                }
            }
            linkStaticStd = Some(false)
        }
        return true
    }

    private func CheckLTOStaticLibFormatOptions(): Bool {
        if (let None <- emitStaticLibInLTO) {
            return true
        }
        if (!IsLTOEnabled()) {
            Errorln("Option '--lto-staticlib-format' only takes effect when lto mode is enabled.")
            return false
        }
        if (outputMode != OutputMode.STATIC_LIB) {
            Errorln("Option '--lto-staticlib-format' requires '--output-type=staticlib'.")
            return false
        }
        if (target.os != OSType.IOS) {
            Errorln("Option '--lto-staticlib-format' is only supported on iOS platforms.")
            return false
        }
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
        if (compileTarget == CompileTarget.EXECUTABLE) { return "E" }
        if (compileTarget == CompileTarget.STATIC_LIB) { return "C" }
        if (compileTarget == CompileTarget.SHARED_LIB) { return "S" }
        CJC_ABORT()
        return ""
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
        let printer = Out64(v: 0u64, start: false, finish: false)
        for (flag in selectedCHIROpts) {
            let bit = 1u64 << OptimizationFlagIndex(flag)
            let _ = printer.append(bit)
        }
        return printer.toString()
    }

    public func OverflowStrategyToSerializedString(): String {
        if (overflowStrategy == OverflowStrategy.NA) { return "N" }
        if (overflowStrategy == OverflowStrategy.CHECKED) { return "C" }
        if (overflowStrategy == OverflowStrategy.WRAPPING) { return "W" }
        if (overflowStrategy == OverflowStrategy.THROWING) { return "T" }
        if (overflowStrategy == OverflowStrategy.SATURATING) { return "S" }
        CJC_ABORT()
        return ""
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
            vectorStrToSerializedString(removedPathPrefix, ":"),
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
            vectorStrToSerializedString(interpreterSearchPaths, ":"),
            vectorStrToSerializedString(interpLoadLib, ":"),
            vectorStrToSerializedString(interpreterArgs, "\\"),
            BoolToSerializedString(interpreterPrintResult),
            BoolToSerializedString(interpMainNoLinkage),
            BoolToSerializedString(disableCodeGen),
            BoolToSerializedString(disableDeserializer),
        ]
    }
}
