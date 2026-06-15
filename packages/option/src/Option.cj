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
}

public class GlobalOptions <: Option {
    public var frontendMode: Bool = false
    public let environment: EnvironmentOptions = EnvironmentOptions()
    public var host: TripleInfo = TripleInfo()
    public var target: TripleInfo = TripleInfo()
    public let passedWhenKeyValue: HashMap<String, String> = HashMap<String, String>()
    public let passedWhenCfgPaths: ArrayList<String> = ArrayList<String>()
    public var output: String = "./"
    public var outputDir: MaybeString = MaybeString()
    public let importPaths: ArrayList<String> = ArrayList<String>()
    public let packagePaths: ArrayList<String> = ArrayList<String>()
    public let srcFiles: ArrayList<String> = ArrayList<String>()
    public let inputObjs: ArrayList<String> = ArrayList<String>()
    public var inputCjoFile: String = ""
    public let bcInputFiles: ArrayList<String> = ArrayList<String>()
    public var moduleName: String = ""
    public var compilePackage: Bool = false
    public var compileMacroPackage: Bool = false
    public var enableOutputType: Bool = false
    public var backend: BackendType = BackendType.CJNATIVE
    public var enableVerbose: Bool = false
    public var showUsage: Bool = false
    public var printVersionOnly: Bool = false
    public var experimentalMode: Bool = false
    public var enableCompileDebug: Bool = false
    public var implicitPrelude: Bool = true
    public var linkStaticStd: MaybeBool = MaybeBool()
    public var ltoMod: LTOMode = LTOMode.NO_LTO
    public var enableCompileAsExe: Bool = false
    public var ltoHideAllPkgs: Bool = false
    public let ltoVisiblePkgs: ArrayList<String> = ArrayList<String>()
    public var outputMode: OutputMode = OutputMode.EXECUTABLE
    public var compileTarget: CompileTarget = CompileTarget.DEFAULT
    public var optimizationLevel: OptimizationLevel = OptimizationLevel.O0
    public var disableChirOpt: Bool = false
    public var disableBackendOpt: Bool = false
    public var chirEA: Bool = false
    public var chirWFC: Bool = true
    public var chirCC: Bool = false
    public var chirLLVM: Bool = false
    public var dumpAST: Bool = false
    public var dumpCHIR: Bool = false
    public var dumpIR: Bool = false
    public var dumpAll: Bool = false
    public var dumpToScreen: Bool = false
    public var sanitizerType: SanitizerType = SanitizerType.NONE
    public var errorCountLimit: MaybeUInt64 = MaybeUInt64(8u64)
    public var jobs: MaybeUInt64 = MaybeUInt64()
    public var aggressiveParallelCompile: MaybeUInt64 = MaybeUInt64()
    public var aggressiveParallelCompileWithoutArg: Bool = false
    public let sancovOption: SanitizerCoverageOptions = SanitizerCoverageOptions()
    public init() { super() }

    public override func ParseFromArgs(argList: ArgList): Bool {
        this.argList = argList
        let delayed = ArrayList<OptionArgInstance>()
        for (entry in argList.entries) {
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
        return out.toArray()
    }

    public func SetOptimizationLevel(level: OptimizationLevel): Bool {
        optimizationLevel = level
        if (enumIndex(level) >= enumIndex(OptimizationLevel.O2)) {
            chirEA = true
        }
        return true
    }

    public func IsLTOEnabled(): Bool { return ltoMod != LTOMode.NO_LTO }
    public func IsCompileAsExeEnabled(): Bool { return enableCompileAsExe }
    public func IsLTOPkgVisibilityEnabled(): Bool { return ltoHideAllPkgs || !ltoVisiblePkgs.isEmpty() }
    public func AddLtoVisiblePkg(pkg: String): Unit { ltoVisiblePkgs.add(pkg) }
    public func GetOptionsBackend(): Backend { return if (backend == BackendType.CJNATIVE) { Backend.CJNATIVE } else { Backend.UNKNOWN } }
    public func EnableSanitizer(): Bool { return sanitizerType != SanitizerType.NONE }
    public func EnableAsan(): Bool { return sanitizerType == SanitizerType.ADDRESS }
    public func EnableTsan(): Bool { return sanitizerType == SanitizerType.THREAD }
    public func EnableHwAsan(): Bool { return sanitizerType == SanitizerType.HWADDRESS }
    public func NeedDumpAST(): Bool { return dumpAll || dumpAST }
    public func NeedDumpASTToFile(): Bool { return NeedDumpAST() && !dumpToScreen }
    public func NeedDumpASTToScreen(): Bool { return NeedDumpAST() && dumpToScreen }
    public func NeedDumpCHIR(): Bool { return dumpAll || dumpCHIR }
    public func NeedDumpCHIRToFile(): Bool { return NeedDumpCHIR() && !dumpToScreen }
    public func NeedDumpCHIRToScreen(): Bool { return NeedDumpCHIR() && dumpToScreen }
    public func NeedDumpIR(): Bool { return dumpAll || dumpIR }
    public func NeedDumpIRToFile(): Bool { return NeedDumpIR() && !dumpToScreen }
    public func NeedDumpIRToScreen(): Bool { return NeedDumpIR() && dumpToScreen }

    public func CheckDirectoryPath(path: String): MaybeString {
        if (FileExist(path) && IsDir(path)) { return GetAbsPath(path) }
        return MaybeString()
    }

    private func ProcessInputs(inputs: Array<String>): Bool {
        for (input in inputs) {
            let ext = GetFileExtension(input)
            if (ext == "cj") {
                srcFiles.add(input)
            } else if (ext == "o" || ext == "a" || ext == "obj") {
                inputObjs.add(input)
            } else if (ext == "bc") {
                bcInputFiles.add(input)
            } else if (ext == "cjo") {
                if (!inputCjoFile.isEmpty()) { return false }
                inputCjoFile = input
            } else if (compilePackage) {
                packagePaths.add(input)
            }
        }
        if (compilePackage && packagePaths.isEmpty()) { return false }
        return true
    }

    private func PerformPostActions(): Bool {
        chirLLVM = backend == BackendType.CJNATIVE
        chirCC = chirCC || chirLLVM
        if (outputMode == OutputMode.OBJ && compileTarget == CompileTarget.DEFAULT) {
            compileTarget = CompileTarget.EXECUTABLE
        }
        if (outputDir.hasValue) {
            if (IsAbsolutePath(output)) { return false }
            output = JoinPath(outputDir.value, output)
        }
        if (compileMacroPackage && enableOutputType) { return false }
        if (IsLTOEnabled() && outputMode == OutputMode.OBJ) { return false }
        if (EnableSanitizer() && IsLTOEnabled()) { return false }
        if (!jobs.hasValue) { jobs = MaybeUInt64(1u64) }
        if (!aggressiveParallelCompile.hasValue) { aggressiveParallelCompile = MaybeUInt64(1u64) }
        return true
    }

    public func ToSerialized(): Array<String> {
        return [
            BoolToSerializedString(enableCompileDebug),
            target.ToFullTripleString(),
            BoolToSerializedString(compilePackage),
            BoolToSerializedString(implicitPrelude),
            BoolToSerializedString(chirEA),
            BoolToSerializedString(chirCC),
        ]
    }
}
