package cjcj::driver

import std.collection.*
import cjcj::basic.{DEFAULT_POSITION, DiagnosticEngine, DiagKindRefactor}
import cjcj::option.{Errorln, GlobalOptions, ID, OptionArgInstance, Warningln}

public let OBFUCATION_LEVEL_MIN: Int64 = 1
public let OBFUCATION_LEVEL_MAX: Int64 = 9

public class DriverOptions <: GlobalOptions {
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
    @When[os == "Windows"]
    public var sysroot: String = "C:/windows"
    @When[os != "Windows"]
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

    public init() {
        super()
    }

    public override func IsObfuscationEnabled(): Bool {
        return (enableStringObfuscation ?? false) || (enableConstObfuscation ?? false) ||
            (enableLayoutObfuscation ?? false) || (enableCFflattenObfuscation ?? false) ||
            (enableCFBogusObfuscation ?? false)
    }

    protected override func ParseOption(arg: OptionArgInstance): Option<Bool> {
        let id = arg.info.GetID()
        if (id == ID.STATIC) { linkStatic = true; return Some(true) }
        if (id == ID.TARGET_CPU) { targetCPU = arg.value; return Some(true) }
        if (id == ID.OPT_OPTIONS) { optArg = arg.value; return Some(true) }
        if (id == ID.LLC_OPTIONS) { llcArg = arg.value; return Some(true) }
        if (id == ID.LIBRARY_PATH) {
            let maybePath = CheckDirectoryPath(arg.value)
            if (maybePath.hasValue) { librarySearchPaths.add(maybePath.value) }
            return Some(true)
        }
        if (id == ID.LIBRARY) { libraries.add(arg.value); return Some(true) }
        if (id == ID.TOOLCHAIN) {
            let maybePath = CheckDirectoryPath(arg.value)
            if (maybePath.hasValue) { toolChainPaths.add(maybePath.value) }
            return Some(true)
        }
        if (id == ID.SYSROOT) {
            let maybePath = CheckDirectoryPath(arg.value)
            if (maybePath.hasValue) {
                sysroot = maybePath.value
                customizedSysroot = true
            }
            return Some(true)
        }
        if (id == ID.LINK_OPTION) { linkOption.add(arg.value); return Some(true) }
        if (id == ID.LINK_OPTIONS) { linkOptions.add(arg.value); return Some(true) }
        if (id == ID.STRIP_ALL) { stripSymbolTable = true; return Some(true) }
        if (id == ID.USE_RUNTIME_RPATH) { useRuntimeRpath = true; return Some(true) }
        if (id == ID.SANITIZE_SET_RPATH) { sanitizerEnableRpath = true; return Some(true) }
        if (id == ID.OBF_STRING) { enableStringObfuscation = true; return Some(true) }
        if (id == ID.NO_OBF_STRING) { enableStringObfuscation = false; return Some(true) }
        if (id == ID.OBF_CONST) { enableConstObfuscation = true; return Some(true) }
        if (id == ID.NO_OBF_CONST) { enableConstObfuscation = false; return Some(true) }
        if (id == ID.OBF_LAYOUT) { enableLayoutObfuscation = true; return Some(true) }
        if (id == ID.NO_OBF_LAYOUT) { enableLayoutObfuscation = false; return Some(true) }
        if (id == ID.OBF_CF_FLATTEN) { enableCFflattenObfuscation = true; return Some(true) }
        if (id == ID.NO_OBF_CF_FLATTEN) { enableCFflattenObfuscation = false; return Some(true) }
        if (id == ID.OBF_CF_BOGUS) { enableCFBogusObfuscation = true; return Some(true) }
        if (id == ID.NO_OBF_CF_BOGUS) { enableCFBogusObfuscation = false; return Some(true) }
        if (id == ID.OBF_EXPORT_SYMS) { enableObfExportSyms = true; return Some(true) }
        if (id == ID.NO_OBF_EXPORT_SYMS) { enableObfExportSyms = false; return Some(true) }
        if (id == ID.OBF_LINE_NUMBER) { enableObfLineNumber = true; return Some(true) }
        if (id == ID.NO_OBF_LINE_NUMBER) { enableObfLineNumber = false; return Some(true) }
        if (id == ID.OBF_SOURCE_PATH) { enableObfSourcePath = true; return Some(true) }
        if (id == ID.NO_OBF_SOURCE_PATH) { enableObfSourcePath = false; return Some(true) }
        if (id == ID.OBF_ALL) { enableObfAll = true; return Some(true) }
        if (id == ID.OBF_SYM_INPUT_MAPPING) { layoutObfInputSymMappingFiles = arg.value; return Some(true) }
        if (id == ID.OBF_SYM_OUTPUT_MAPPING) { layoutObfOutputSymMappingFile = arg.value; return Some(true) }
        if (id == ID.OBF_MAP_FILE) {
            let maybePath = GlobalOptions.ValidateInputFilePath(arg.value, DiagKindRefactor.no_such_file_or_directory)
            if (!maybePath.hasValue) { return Some(false) }
            layoutObfUserMappingFile = maybePath.value
            return Some(true)
        }
        if (id == ID.OBF_SYM_PREFIX) { layoutObfSymPrefix = arg.value; return Some(true) }
        if (id == ID.OBF_CONFIG) {
            let maybePath = GlobalOptions.ValidateInputFilePath(arg.value, DiagKindRefactor.no_such_file_or_directory)
            if (!maybePath.hasValue) { return Some(false) }
            obfuscationConfigFile = maybePath.value
            return Some(true)
        }
        if (id == ID.OBF_LEVEL) {
            let maybeNumber = GlobalOptions.ParseIntOptionValue(
                arg, from: OBFUCATION_LEVEL_MIN, to: OBFUCATION_LEVEL_MAX)
            if (let Some(number) <- maybeNumber) {
                obfuscationLevel = number
                return Some(true)
            }
            return Some(false)
        }
        if (id == ID.OBF_SEED) {
            let maybeNumber = GlobalOptions.ParseIntOptionValue(arg)
            if (let Some(number) <- maybeNumber) {
                obfuscationSeed = number
                return Some(true)
            }
            return Some(false)
        }
        return super.ParseOption(arg)
    }

    public override func ReprocessObfuseOption(): Bool {
        if (enableObfAll) {
            if (let None <- enableStringObfuscation) { enableStringObfuscation = true }
            if (let None <- enableConstObfuscation) { enableConstObfuscation = true }
            if (let None <- enableLayoutObfuscation) { enableLayoutObfuscation = true }
            if (let None <- enableCFflattenObfuscation) { enableCFflattenObfuscation = true }
            if (let None <- enableCFBogusObfuscation) { enableCFBogusObfuscation = true }
            if (let None <- enableObfLineNumber) {
                if (enableLayoutObfuscation ?? false) { enableObfLineNumber = true }
            }
        }
        return true
    }

    protected override func PerformPostActions(): Bool {
        if (!super.PerformPostActions()) { return false }
        var success = true
        success = success && CheckTargetCPUOption()
        success = success && CheckObfuscationOptions()
        success = success && SetupSysroot()
        success = success && CheckRuntimeRPath()
        success = success && CheckSanitizerRPath()
        success = success && CheckStaticOption()
        return success
    }

    private func CheckObfuscationOptions(): Bool {
        if (enableCompileDebug && IsObfuscationEnabled()) {
            Warningln("Obfuscation options should be used without '-g' or debugging may not work properly.")
        }
        if (!(enableLayoutObfuscation ?? false)) {
            if (let Some(_) <- layoutObfInputSymMappingFiles) {
                Errorln("Input symbol mapping files can be specified only when layout obfuscation is enabled.")
                return false
            }
            if (let Some(_) <- layoutObfOutputSymMappingFile) {
                Errorln("Output symbol mapping file can be specified only when layout obfuscation is enabled.")
                return false
            }
            if (let Some(_) <- layoutObfUserMappingFile) {
                Errorln("User-defined symbol mapping file can be specified only when layout obfuscation is enabled.")
                return false
            }
            if (let Some(_) <- enableObfExportSyms) {
                Errorln("You can set whether to obfuscate export symbols only when layout obfuscation is enabled.")
                return false
            }
            if (let Some(_) <- enableObfLineNumber) {
                Errorln("You can set whether to obfuscate line number only when layout obfuscation is enabled.")
                return false
            }
            if (let Some(_) <- enableObfSourcePath) {
                Errorln("You can set whether to obfuscate source path only when layout obfuscation is enabled.")
                return false
            }
            if (let Some(_) <- layoutObfSymPrefix) {
                Errorln("Symbol prefix can be specified only when layout obfuscation is enabled.")
                return false
            }
        }
        return true
    }

    private func CheckTargetCPUOption(): Bool {
        if (target.IsMacOS()) {
            if (let None <- targetCPU) { return true }
        }
        if (let None <- targetCPU) { targetCPU = "generic" }
        let value = targetCPU ?? "generic"
        if (value == "generic" || value == "native") { return true }
        if (IsSupportedTargetCPU(target.arch, value)) { return true }
        let diag = DiagnosticEngine()
        diag.DiagnoseRefactor(
            DiagKindRefactor.driver_unsupported_target_cpu, DEFAULT_POSITION, arguments: [value]).Emit()
        return false
    }

    private func SetupSysroot(): Bool {
        if (!customizedSysroot && target.IsMacOS() && environment.macOSSDKRoot.hasValue) {
            sysroot = environment.macOSSDKRoot.value
        }
        return true
    }

    private func CheckRuntimeRPath(): Bool {
        if (!useRuntimeRpath) { return true }
        if (target.os == OSType.WINDOWS) {
            Warningln("'--set-runtime-rpath' option has no effect on PE targets.")
        } else if (IsCrossCompiling()) {
            Warningln("'--set-runtime-rpath' option has no effect on cross-compiled targets.")
        }
        return true
    }

    private func CheckSanitizerRPath(): Bool {
        if (!sanitizerEnableRpath) { return true }
        if (!EnableSanitizer()) {
            Errorln("Option '--sanitize-set-rpath' can only be enabled along with '--sanitize'")
            return false
        }
        if (useRuntimeRpath) {
            Errorln("Option '--sanitize-set-rpath' and '--set-runtime-rpath' cannot be enabled together.")
            return false
        }
        if (IsCrossCompiling()) {
            Warningln("'--sanitize-set-rpath' option has no effect on cross-compiled targets.")
        }
        return true
    }

    private func CheckStaticOption(): Bool {
        if ((target.os == OSType.LINUX && target.env != EnvironmentType.OHOS) ||
            target.os == OSType.DARWIN || target.os == OSType.WINDOWS || target.os == OSType.IOS) {
            if (linkStatic && outputMode != OutputMode.EXECUTABLE) {
                linkStatic = false
                let diag = DiagnosticEngine()
                diag.DiagnoseRefactor(
                    DiagKindRefactor.driver_warning_unusable_static, DEFAULT_POSITION).Emit()
            }
            if ((linkStaticStd ?? true) == false && linkStatic) {
                let diag = DiagnosticEngine()
                diag.DiagnoseRefactor(
                    DiagKindRefactor.driver_static_dystd_conflict, DEFAULT_POSITION).Emit()
                return false
            }
            return true
        }
        if (linkStatic) {
            linkStatic = false
            let diag = DiagnosticEngine()
            diag.DiagnoseRefactor(
                DiagKindRefactor.driver_warning_no_support_static,
                DEFAULT_POSITION,
                arguments: [target.ToFullTripleString()]
            ).Emit()
        }
        return true
    }
}
