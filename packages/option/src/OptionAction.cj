package cjcj::option

import cjcj::basic.DEFAULT_POSITION as BasicDefaultPosition
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.WarnGroup as BasicWarnGroup
import cjcj::basic.WarnGroupIndex as BasicWarnGroupIndex
import cjcj::basic.WarningOptionMgr as BasicWarningOptionMgr
import cjcj::utils.FileUtil
import cjcj::utils.NFC as UtilsNFC
import cjcj::utils.Semaphore as UtilsSemaphore
import cjcj::utils.Stoi as UtilsStoi
import cjcj::utils.StringToOverflowStrategy
import cjcj::utils.TryParseInt as UtilsTryParseInt
import cjcj::utils.ValidOverflowStrategy
import std.collection.*

private let CANGJIE_VISIBLE_OPTIONS_ONLY: Bool = true

public class ActionResult {
    public let handled: Bool
    public let success: Bool
    public let skipParsing: Bool
    public init(handled: Bool, success: Bool, skipParsing!: Bool = false) {
        this.handled = handled
        this.success = success
        this.skipParsing = skipParsing
    }
}

private func handled(success!: Bool = true): ActionResult { return ActionResult(true, success) }
private func missing(): ActionResult { return ActionResult(false, true) }

private func emitDiag(kind: BasicDiagKindRefactor): Unit {
    let diag = BasicDiagnosticEngine()
    diag.DiagnoseRefactor(kind, BasicDefaultPosition).Emit()
}

private func emitDiag(kind: BasicDiagKindRefactor, arg: String): Unit {
    let diag = BasicDiagnosticEngine()
    diag.DiagnoseRefactor(kind, BasicDefaultPosition, arguments: [arg]).Emit()
}

private func emitDiag(kind: BasicDiagKindRefactor, first: String, second: String): Unit {
    let diag = BasicDiagnosticEngine()
    diag.DiagnoseRefactor(kind, BasicDefaultPosition, arguments: [first, second]).Emit()
}

public func ParsePreAction(opts: GlobalOptions, arg: OptionArgInstance): ActionResult {
    let id = arg.info.GetID()
    if (id == ID.VERBOSE) {
        opts.enableVerbose = true
        return ActionResult(true, true)
    }
    if (id == ID.VERSION) {
        opts.printVersionOnly = true
        return ActionResult(true, true, skipParsing: true)
    }
    if (id == ID.HELP) {
        opts.showUsage = true
        return ActionResult(true, true, skipParsing: true)
    }
    if (id == ID.EXPERIMENTAL) {
        opts.experimentalMode = true
        return ActionResult(true, true)
    }
    if (id == ID.BACKEND_MODE) {
        if (arg.value == "llvm") {
            opts.backend = BackendType.CJNATIVE
            return ActionResult(true, true)
        }
        return ActionResult(true, false)
    }
    return missing()
}

public func ParseAction(opts: GlobalOptions, arg: OptionArgInstance): ActionResult {
    let id = arg.info.GetID()
    if (id == ID.OUTPUT_FILE) {
        if (arg.value.isEmpty()) {
            Errorln("'" + arg.name + "' requires a non-empty value.")
            return handled(success: false)
        }
        opts.output = arg.value
        return handled()
    }
    if (id == ID.OUTPUT_DIR) {
        if (!IsDir(arg.value)) {
            emitDiag(BasicDiagKindRefactor.no_such_directory, arg.value)
            return handled(success: false)
        }
        opts.outputDir = MaybeString(arg.value)
        return handled()
    }
    if (id == ID.OUTPUT_JAVA_GEN_DIR) { opts.outputJavaGenDir = MaybeString(arg.value); return handled() }
    if (id == ID.OUTPUT_OBJC_GEN_DIR) { opts.outputObjCGenDir = arg.value; return handled() }
    if (id == ID.MODULE_NAME) { emitDiag(BasicDiagKindRefactor.driver_useless_option, arg.name); return handled() }
    if (id == ID.PACKAGE_COMPILE) { opts.compilePackage = true; return handled() }
    if (id == ID.IMPORT_PATH) {
        let path = opts.CheckDirectoryPath(arg.value)
        if (path.hasValue) { opts.importPaths.add(path.value) }
        return handled()
    }
    if (id == ID.PLUGIN_PATH) {
        let pluginPath = opts.CheckInputFilePath(arg.value)
        if (!pluginPath.hasValue) {
            Errorln("'" + arg.name + "' only accepts an existing dynamic library path.")
            return handled(success: false)
        }
        let suffix = GetSharedLibraryExtension(opts.host.os)
        if ("." + GetFileExtension(pluginPath.value) != suffix) {
            Errorln("'" + arg.name + "' requires a dynamic library path with '" + suffix + "' suffix.")
            return handled(success: false)
        }
        opts.pluginPaths.add(pluginPath.value)
        return handled()
    }
    if (id == ID.COMMON_PART_CJO) {
        let commonCjo = GlobalOptions.ValidateInputFilePath(arg.value, BasicDiagKindRefactor.driver_invalid_binary_file)
        if (commonCjo.hasValue) {
            opts.commonPartCjos.add(commonCjo.value)
        } else {
            emitDiag(BasicDiagKindRefactor.no_such_file_or_directory, arg.value)
        }
        return handled()
    }
    if (id == ID.COMMON_PART_CHIR) {
        let commonChir = GlobalOptions.ValidateInputFilePath(arg.value, BasicDiagKindRefactor.no_such_file_or_directory)
        if (commonChir.hasValue) {
            opts.commonPartChirs.add(commonChir.value)
        } else {
            emitDiag(BasicDiagKindRefactor.no_such_file_or_directory, arg.value)
        }
        return handled()
    }
    if (id == ID.INCRE_COMPILE) { opts.enIncrementalCompilation = true; return handled() }
    if (id == ID.INCRE_DEBUG) { opts.printIncrementalInfo = true; return handled() }
    if (id == ID.DUMP_DEPENDENT_PACKAGE) { opts.scanDepPkg = true; return handled() }
    if (id == ID.NO_SUB_PACKAGE) { opts.noSubPkg = true; return handled() }
    if (id == ID.TARGET) { return handled(success: ParseTargetTriple(opts, arg.value)) }
    if (id == ID.OUTPUT_TYPE) { return parseOutputType(opts, arg.value) }
    if (id == ID.COMPILE_TARGET) { return parseCompileTarget(opts, arg.value) }
    if (id == ID.OPTIMIZATION_0) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O0)) }
    if (id == ID.OPTIMIZATION_1) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O1)) }
    if (id == ID.OPTIMIZATION_2) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O2)) }
    if (id == ID.OPTIMIZATION_3) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O3)) }
    if (id == ID.OPTIMIZATION_S) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.Os)) }
    if (id == ID.OPTIMIZATION_Z) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.Oz)) }
    if (id == ID.OPTIMIZATION_CUSTOM) { return parseCustomOptimization(opts, arg.value) }
    if (id == ID.WARN_OFF) { return handled(success: parseWarn(arg.value, true)) }
    if (id == ID.WARN_ON) { return handled(success: parseWarn(arg.value, false)) }
    if (id == ID.ERROR_COUNT_LIMIT) { return parseErrorLimit(opts, arg) }
    if (id == ID.DIAG_FORMAT) { return parseDiagFormat(opts, arg.value) }
    if (id == ID.CONDITIONAL_COMPILATION_CONFIG) { return parsePassedWhen(opts, arg.value) }
    if (id == ID.COMPILE_CJD) { opts.compileCjd = true; return handled() }
    if (id == ID.COMPILE_DEBUG_MACRO) { opts.enableMacroDebug = true; return handled() }
    if (id == ID.PARALLEL_MACRO_EXPANSION) { opts.enableParallelMacro = true; return handled() }
    if (id == ID.COMPILE_DEBUG) { opts.enableCompileDebug = true; return handled() }
    if (id == ID.TRIMPATH) {
        let normalized = NormalizeRawPath(arg.value)
        if (!normalized.isEmpty()) {
            opts.removedPathPrefix.add(if (normalized[normalized.size - 1] == b'/') { normalized } else { normalized + "/" })
        }
        return handled()
    }
    if (id == ID.NO_STACKTRACE_INFO) { opts.displayLineInfo = false; return handled() }
    if (id == ID.COMPILE_TEST) {
        opts.parseTest = true
        opts.enableCompileTest = true
        return handled()
    }
    if (id == ID.COMPILE_TESTS_ONLY) {
        opts.parseTest = true
        opts.enableCompileTest = true
        opts.compileTestsOnly = true
        return handled()
    }
    if (id == ID.EXPORT_FOR_TESTS) {
        opts.exportForTest = true
        opts.enableCompileTest = true
        return handled()
    }
    if (id == ID.MOCK) { return parseMockMode(opts, arg.value) }
    if (id == ID.NO_PRELUDE) { opts.implicitPrelude = false; return handled() }
    if (id == ID.PROFILE_COMPILE_TIME) { opts.enableTimer = true; return handled() }
    if (id == ID.PROFILE_COMPILE_MEMORY) { opts.enableMemoryCollect = true; return handled() }
    if (id == ID.ENABLE_EFFECTS) { opts.enableEH = true; return handled() }
    if (id == ID.STATIC_STD) { opts.linkStaticStd = Some(true); return handled() }
    if (id == ID.DY_STD) { opts.linkStaticStd = Some(false); return handled() }
    if (id == ID.STATIC_LIBS || id == ID.DY_LIBS || id == ID.STATIC) { return handled() }
    if (id == ID.LTO) { return parseLto(opts, arg.value) }
    if (id == ID.LTO_STATICLIB_FORMAT) {
        opts.emitStaticLibInLTO = Some(arg.value == "native")
        return handled()
    }
    if (id == ID.COMPILE_AS_EXE) { opts.enableCompileAsExe = true; return handled() }
    if (id == ID.LTO_KEEP_PKG_VISIBILITY) {
        if (arg.value.isEmpty()) {
            opts.ltoHideAllPkgs = true
        } else {
            for (pkgRaw in SplitString(arg.value, ",")) {
                let pkg = pkgRaw.trimAscii()
                if (!pkg.isEmpty()) { opts.AddLtoVisiblePkg(pkg) }
            }
        }
        return handled()
    }
    if (id == ID.DUMP_AST) { opts.dumpAST = true; return handled() }
    if (id == ID.DUMP_CHIR) { opts.dumpCHIR = true; return handled() }
    if (id == ID.DUMP_IR) { opts.dumpIR = true; return handled() }
    if (id == ID.DUMP_ALL) { opts.dumpAll = true; return handled() }
    if (id == ID.DUMP_TO_SCREEN) { opts.dumpToScreen = true; return handled() }
    if (id == ID.DUMP_ANNOTATIONS_DEBUG) { opts.computeAnnotationsDebug = true; return handled() }
    if (id == ID.DESERIALIZE_CHIR_AND_DUMP) {
        opts.chirDeserialize = true
        opts.chirDeserializePath = arg.value
        return handled()
    }
    if (id == ID.EMIT_CHIR) { return parseEmitCHIR(opts, arg.value) }
    if (id == ID.CHIR_EA) {
        if (arg.value != "on" && arg.value != "off") { return handled(success: false) }
        opts.chirEA = arg.value == "on"
        return handled()
    }
    if (id == ID.CHIR_WFC) {
        if (arg.value != "on" && arg.value != "off") { return handled(success: false) }
        opts.chirWFC = arg.value == "on"
        return handled()
    }
    if (id == ID.DISABLE_CHIR_OPT) { opts.disableChirOpt = true; return handled() }
    if (id == ID.DISABLE_BACKEND_OPT) { opts.disableBackendOpt = true; return handled() }
    if (id == ID.ENABLE_CHIR_REDUNDANT_GETORTHROW_ELIMINATION) {
        opts.SelectCHIROpt(OptimizationFlag.REDUNDANT_LOAD)
        opts.enableChirRGetOrThrowE = true
        return handled()
    }
    if (id == ID.DISABLE_CHIR_USELESS_IMPORT_ELIMINATION) {
        opts.disableChirUselessImportElimination = true
        return handled()
    }
    if (id == ID.DISABLE_SEMA_VIC) { opts.disableSemaVic = true; return handled() }
    if (id == ID.DEBUG_CODEGEN) { opts.codegenDebugMode = true; return handled() }
    if (id == ID.CHIR_OPT_DEBUG) { opts.chirDebugOptimizer = true; return handled() }
    if (id == ID.RENDER_CHIR) { return parseChirMode(opts, arg.value) }
    if (id == ID.INT_OVERFLOW_MODE) { return parseOverflowStrategy(opts, arg.value) }
    if (id == ID.FAST_MATH_MODE) { opts.fastMathMode = true; return handled() }
    if (id == ID.OPT_PASS_OPTIONS) { opts.optPassOptions = arg.value; return handled() }
    if (id == ID.CONST_PROPAGATION) { opts.SelectCHIROpt(OptimizationFlag.CONST_PROPAGATION); return handled() }
    if (id == ID.NO_CONST_PROPAGATION) { opts.DeselectCHIROpt(OptimizationFlag.CONST_PROPAGATION); return handled() }
    if (id == ID.FUNC_INLINING) { opts.SelectCHIROpt(OptimizationFlag.FUNC_INLINING); return handled() }
    if (id == ID.NO_FUNC_INLINING) { opts.DeselectCHIROpt(OptimizationFlag.FUNC_INLINING); return handled() }
    if (id == ID.DEVIRTUALIZATION) { opts.SelectCHIROpt(OptimizationFlag.DEVIRTUALIZATION); return handled() }
    if (id == ID.NO_DEVIRTUALIZATION) { opts.DeselectCHIROpt(OptimizationFlag.DEVIRTUALIZATION); return handled() }
    if (id == ID.SROA_OPT) { opts.SelectCHIROpt(OptimizationFlag.SROA_OPT); return handled() }
    if (id == ID.NO_SROA_OPT) { opts.DeselectCHIROpt(OptimizationFlag.SROA_OPT); return handled() }
    if (id == ID.REDUANDANT_RETURN_REMOVAL) { opts.SelectCHIROpt(OptimizationFlag.REDUNDANT_RETURNS); return handled() }
    if (id == ID.NO_REDUANDANT_RETURN_REMOVAL) { opts.DeselectCHIROpt(OptimizationFlag.REDUNDANT_RETURNS); return handled() }
    if (id == ID.REDUNDANT_FUTURE_REMOVAL) { opts.SelectCHIROpt(OptimizationFlag.REDUNDANT_FUTURE); return handled() }
    if (id == ID.NO_REDUNDANT_FUTURE_REMOVAL) { opts.DeselectCHIROpt(OptimizationFlag.REDUNDANT_FUTURE); return handled() }
    if (id == ID.REDUANDANT_ASSIGN_REMOVAL) { opts.SelectCHIROpt(OptimizationFlag.REMOVE_REDUNDANT_ASG); return handled() }
    if (id == ID.NO_REDUANDANT_ASSIGN_REMOVAL) { opts.DeselectCHIROpt(OptimizationFlag.REMOVE_REDUNDANT_ASG); return handled() }
    if (id == ID.LETC_FOLDING) { opts.SelectCHIROpt(OptimizationFlag.LETC_FOLDING); return handled() }
    if (id == ID.SWITCH_OPT) { opts.SelectCHIROpt(OptimizationFlag.SWITCH_OPT); return handled() }
    if (id == ID.REF_FOLDING) { opts.SelectCHIROpt(OptimizationFlag.REF_FOLDING); return handled() }
    if (id == ID.ARRAY_LAMBDA_OPT) { opts.SelectCHIROpt(OptimizationFlag.ARRAY_LAMBDA_OPT); return handled() }
    if (id == ID.LOOP_INVARIANT_CODE_MOTION) { opts.chirLICM = true; return handled() }
    if (id == ID.NO_LOOP_INVARIANT_CODE_MOTION) { opts.chirLICM = false; return handled() }
    if (id == ID.SANCOV_INLINE_8BIT) { opts.sancovOption.inline8bitCounters = true; return handled() }
    if (id == ID.SANCOV_INLINE_BOOL_FLAG) { opts.sancovOption.inlineBoolFlag = true; return handled() }
    if (id == ID.SANCOV_TRACE_PC_GUARD) { opts.sancovOption.tracePCGuard = true; return handled() }
    if (id == ID.SANCOV_PC_TABLE) { opts.sancovOption.pcTable = true; return handled() }
    if (id == ID.SANCOV_STACK_DEPTH) { opts.sancovOption.stackDepth = true; return handled() }
    if (id == ID.SANCOV_TRACE_COMPARES) { opts.sancovOption.traceCmp = true; return handled() }
    if (id == ID.SANCOV_TRACE_MEM_COMPARES) { opts.sancovOption.traceMemCmp = true; return handled() }
    if (id == ID.SANCOV_LEVEL_0) { opts.sancovOption.SetSancovLevel(SanitizerCoverageType.SCK_NONE); return handled() }
    if (id == ID.SANCOV_LEVEL_1) { opts.sancovOption.SetSancovLevel(SanitizerCoverageType.SCK_FUNCTION); return handled() }
    if (id == ID.SANCOV_LEVEL_2) { opts.sancovOption.SetSancovLevel(SanitizerCoverageType.SCK_BB); return handled() }
    if (id == ID.SANCOV_LEVEL_CUSTOM) { return parseSancovLevel(opts, arg.value) }
    if (id == ID.PRINT_BCHIR) { return parsePrintBCHIR(opts, arg.value) }
    if (id == ID.INTERP_CONST_EVAL_DEBUG) { opts.constEvalDebug = true; return handled() }
    if (id == ID.DISABLE_CODEGEN) { opts.disableCodeGen = true; return handled() }
    if (id == ID.DISABLE_REFLECTION) { opts.disableReflection = true; return handled() }
    if (id == ID.SANITIZE) { return parseSanitizer(opts, arg.value) }
    if (id == ID.ENABLE_COVERAGE) { opts.enableCoverage = true; return handled() }
    if (id == ID.COMPILE_MACRO) {
        opts.compileMacroPackage = true
        opts.outputMode = OutputMode.SHARED_LIB
        return handled()
    }
    if (id == ID.SAVE_TEMPS) {
        if (!IsDir(arg.value)) {
            emitDiag(BasicDiagKindRefactor.no_such_directory, arg.value)
            return handled(success: false)
        }
        opts.saveTemps = true
        opts.tempFolderPath = arg.value
        return handled()
    }
    if (id == ID.FUNC_SECTIONS) { opts.enableFuncSections = true; return handled() }
    if (id == ID.NO_FUNC_SECTIONS) { opts.enableFuncSections = false; return handled() }
    if (id == ID.DATA_SECTIONS) { opts.enableDataSections = true; return handled() }
    if (id == ID.NO_DATA_SECTIONS) { opts.enableDataSections = false; return handled() }
    if (id == ID.GC_SECTIONS) { opts.enableGcSections = true; return handled() }
    if (id == ID.NO_GC_SECTIONS) { opts.enableGcSections = false; return handled() }
    if (id == ID.PGO_INSTR_GEN) {
        opts.enablePgoInstrGen = true
        if (!arg.value.isEmpty()) { opts.pgoProfileFile = arg.value }
        return handled()
    }
    if (id == ID.PGO_INSTR_USE) {
        opts.enablePgoInstrUse = true
        opts.pgoProfileFile = arg.value
        return handled()
    }
    if (id == ID.STACK_TRACE_FORMAT) { return parseStackTraceFormat(opts, arg.value) }
    if (id == ID.DISCARD_EH_FRAME) { opts.discardEhFrame = true; return handled() }
    if (id == ID.JOBS) { return parseJobs(opts, arg, false) }
    if (id == ID.AGGRESSIVE_PARALLEL_COMPILE) { return parseJobs(opts, arg, true) }
    return missing()
}

private func parseOutputType(opts: GlobalOptions, value: String): ActionResult {
    if (value == "exe") {
        opts.outputMode = OutputMode.EXECUTABLE
        opts.enableHotReload = false
    }
    else if (value == "staticlib") {
        opts.outputMode = OutputMode.STATIC_LIB
        opts.enableHotReload = false
    }
    else if (value == "dylib") {
        opts.outputMode = OutputMode.SHARED_LIB
        opts.enableHotReload = false
    }
    else if (value == "chir") {
        opts.outputMode = OutputMode.CHIR
        opts.enableHotReload = false
    }
    else if (value == "obj") {
        opts.outputMode = OutputMode.OBJ
        opts.enableHotReload = false
    }
    else if (value == "hotreload") {
        opts.outputMode = OutputMode.SHARED_LIB
        opts.enableHotReload = true
        opts.linkStaticStd = Some(false)
    }
    else { return handled(success: false) }
    opts.enableOutputType = true
    return handled()
}

private func parseCompileTarget(opts: GlobalOptions, value: String): ActionResult {
    if (value == "exe") { opts.compileTarget = CompileTarget.EXECUTABLE }
    else if (value == "staticlib") { opts.compileTarget = CompileTarget.STATIC_LIB }
    else if (value == "dylib") { opts.compileTarget = CompileTarget.SHARED_LIB }
    else { return handled(success: false) }
    return handled()
}

private func parseDiagFormat(opts: GlobalOptions, value: String): ActionResult {
    if (value == "json") { opts.diagFormat = DiagFormat.JSON; return handled() }
    if (value == "noColor") { opts.diagFormat = DiagFormat.NO_COLOR; return handled() }
    if (value == "default") { opts.diagFormat = DiagFormat.DEFAULT; return handled() }
    return handled(success: false)
}

private func parseMockMode(opts: GlobalOptions, value: String): ActionResult {
    if (value == "on") { opts.mock = MockMode.ON; return handled() }
    if (value == "off") { opts.mock = MockMode.OFF; return handled() }
    if (value == "runtime-error") { opts.mock = MockMode.RUNTIME_ERROR; return handled() }
    return handled(success: false)
}

private func parseCustomOptimization(opts: GlobalOptions, value: String): ActionResult {
    if (let Some(level) <- UtilsTryParseInt(value)) {
        if (level < 0) {
            Errorln("Optimization level " + value + " is invalid")
            return handled(success: false)
        }
        if (level == 0) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O0)) }
        if (level == 1) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O1)) }
        if (level == 2) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O2)) }
        if (CANGJIE_VISIBLE_OPTIONS_ONLY) {
            Errorln("Optimization level " + value + " is invalid")
            return handled(success: false)
        }
        return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O3))
    }
    Errorln("Optimization level " + value + " is invalid")
    return handled(success: false)
}

private func parseWarn(value: String, suppress: Bool): Bool {
    if (value == "all") {
        BasicWarningOptionMgr.UpdateFlags(Array<Bool>(BasicWarnGroupIndex(BasicWarnGroup.NONE), repeat: suppress))
    } else if (value == "unused") {
        BasicWarningOptionMgr.UpdateFlag(UInt64(BasicWarnGroupIndex(BasicWarnGroup.UNUSED)), suppress)
    } else if (value == "unused-main") {
        BasicWarningOptionMgr.UpdateFlag(UInt64(BasicWarnGroupIndex(BasicWarnGroup.UNUSED_MAIN)), suppress)
    } else if (value == "driver-arg") {
        BasicWarningOptionMgr.UpdateFlag(UInt64(BasicWarnGroupIndex(BasicWarnGroup.DRIVER_ARG)), suppress)
    } else if (value == "deprecated") {
        BasicWarningOptionMgr.UpdateFlag(UInt64(BasicWarnGroupIndex(BasicWarnGroup.DEPRECATED)), suppress)
    } else if (value == "unsupport-compile-source") {
        BasicWarningOptionMgr.UpdateFlag(UInt64(BasicWarnGroupIndex(BasicWarnGroup.UNSUPPORT_COMPILE_SOURCE)), suppress)
    } else if (value == "package-import") {
        BasicWarningOptionMgr.UpdateFlag(UInt64(BasicWarnGroupIndex(BasicWarnGroup.PACKAGE_IMPORT)), suppress)
    } else if (value == "parser") {
        BasicWarningOptionMgr.UpdateFlag(UInt64(BasicWarnGroupIndex(BasicWarnGroup.PARSER)), suppress)
    } else if (value == "semantics") {
        BasicWarningOptionMgr.UpdateFlag(UInt64(BasicWarnGroupIndex(BasicWarnGroup.SEMANTICS)), suppress)
    } else if (value == "interpreter") {
        BasicWarningOptionMgr.UpdateFlag(UInt64(BasicWarnGroupIndex(BasicWarnGroup.INTERPRETER)), suppress)
    } else if (value == "apilevel-check") {
        BasicWarningOptionMgr.UpdateFlag(UInt64(BasicWarnGroupIndex(BasicWarnGroup.APILEVEL_CHECK)), suppress)
    } else {
        return false
    }
    return true
}

private func parseErrorLimit(opts: GlobalOptions, arg: OptionArgInstance): ActionResult {
    if (arg.value == "all") {
        opts.errorCountLimit = MaybeUInt64()
        return handled()
    }
    if (let Some(limit) <- UtilsTryParseInt(arg.value)) {
        if (limit < 0) {
            Errorln("The value of " + arg.name + " is invalid.")
            return handled(success: false)
        }
        opts.errorCountLimit = MaybeUInt64(UInt64(limit))
        return handled()
    }
    Errorln("The value of " + arg.name + " is invalid.")
    return handled(success: false)
}

private func parsePassedWhen(opts: GlobalOptions, value: String): ActionResult {
    if (value.isEmpty()) {
        emitDiag(BasicDiagKindRefactor.driver_cfg_value_err)
        return handled(success: false)
    }
    if (isCfgPathMode(value)) {
        let path = value.replace("\\=", "=")
        if (!IsDir(path)) {
            emitDiag(BasicDiagKindRefactor.dirver_cfg_not_a_dir, path)
            return handled(success: false)
        }
        opts.passedWhenCfgPaths.add(path)
        return handled()
    }
    let parts = SplitString(value, ",")
    for (part in parts) {
        let kv = SplitString(part, "=")
        if (kv.size != 2) {
            emitDiag(BasicDiagKindRefactor.driver_cfg_value_err)
            return handled(success: false)
        }
        let rawKey = kv[0].trimAscii()
        let val = kv[1].trimAscii()
        if (rawKey.isEmpty() || val.isEmpty()) {
            emitDiag(BasicDiagKindRefactor.driver_cfg_value_err)
            return handled(success: false)
        }
        let maybeKey = parseCfgKey(rawKey, opts.passedWhenKeyValue)
        if (!maybeKey.hasValue) { return handled(success: false) }
        opts.passedWhenKeyValue.add(maybeKey.value, val)
    }
    return handled()
}

private func countOccurrences(input: String, needle: String): Int64 {
    if (needle.isEmpty()) { return 0 }
    var count: Int64 = 0
    var offset: Int64 = 0
    var foundPos = input.indexOf(needle, offset)
    while (let Some(found) <- foundPos) {
        count++
        offset = found + needle.size
        foundPos = input.indexOf(needle, offset)
    }
    return count
}

private func isCfgPathMode(value: String): Bool {
    return countOccurrences(value, "=") == countOccurrences(value, "\\=")
}

private func isBuiltinCondition(key: String): Bool {
    return key == "os" || key == "backend" || key == "arch" || key == "debug" ||
        key == "cjc_version" || key == "test"
}

private func checkCfgIdentifier(rawKey: String): Bool {
    if (!FileUtil.IsIdentifier(rawKey)) {
        emitDiag(BasicDiagKindRefactor.dirver_cfg_invaild_identifier)
        return false
    }
    return true
}

private func parseCfgKey(rawKey: String, map: HashMap<String, String>): MaybeString {
    if (!checkCfgIdentifier(rawKey)) { return MaybeString() }
    var key = rawKey
    if (key.size > 2 && key[0] == b'`') {
        key = key[1..key.size - 1]
    }
    key = UtilsNFC(key)
    if (isBuiltinCondition(key)) {
        emitDiag(BasicDiagKindRefactor.dirver_cfg_same_with_builtin)
        return MaybeString()
    }
    if (map.contains(key)) {
        emitDiag(BasicDiagKindRefactor.dirver_cfg_key_repeat)
        return MaybeString()
    }
    return MaybeString(key)
}

private func isEscaped(input: String, index: Int64): Bool {
    var count: Int64 = 0
    var idx = index
    while (idx >= 0 && input[idx] == b'\\') {
        count++
        idx--
    }
    return count % 2 == 1
}

private func findTomlComment(line: String): Int64 {
    var insideString = false
    var idx: Int64 = 0
    while (idx < line.size) {
        if (!insideString && line[idx] == b'#') {
            return idx
        }
        if (line[idx] == b'"' && (idx == 0 || !isEscaped(line, idx - 1))) {
            insideString = !insideString
        }
        idx++
    }
    return -1
}

private func seeingTomlComment(line: String): Bool {
    if (line.isEmpty() || !line.contains("#")) { return false }
    var idx: Int64 = 0
    while (idx < line.size) {
        if (line[idx] == b' ' || line[idx] == b'\t') {
            idx++
            continue
        }
        return line[idx] == b'#'
    }
    return true
}

private func parseConditionKeyValueLine(line: String, map: HashMap<String, String>): Bool {
    let commentPos = findTomlComment(line)
    let processedLine = if (commentPos >= 0) { line[0..commentPos] } else { line }
    let kv = SplitString(processedLine, "=")
    if (kv.size != 2) {
        emitDiag(BasicDiagKindRefactor.driver_cfg_toml_content_err)
        return false
    }
    let rawKey = kv[0].trimAscii()
    let quotedValue = kv[1].trimAscii()
    if (rawKey.isEmpty() || quotedValue.size <= 2 || quotedValue[0] != b'"' ||
        quotedValue[quotedValue.size - 1] != b'"') {
        emitDiag(BasicDiagKindRefactor.driver_cfg_toml_content_err)
        return false
    }
    let maybeKey = parseCfgKey(rawKey, map)
    if (!maybeKey.hasValue) { return false }
    let unquotedValue = quotedValue[1..quotedValue.size - 1].replace("\\\"", "\"")
    map.add(maybeKey.value, unquotedValue)
    return true
}

public func SetupConditionalCompilationCfgFromFile(filePath: String, map: HashMap<String, String>): Bool {
    let readResult = ReadTextFileWithReason(filePath)
    if (!readResult.content.hasValue) {
        emitDiag(BasicDiagKindRefactor.driver_cfg_file_read_failed, filePath, readResult.failedReason)
        return false
    }
    for (line in SplitLines(readResult.content.value)) {
        if (line.isEmpty() || seeingTomlComment(line)) { continue }
        if (!parseConditionKeyValueLine(line, map)) { return false }
    }
    return true
}

public func SetupConditionalCompilationCfg(opts: GlobalOptions): Bool {
    if (!opts.passedWhenKeyValue.isEmpty()) {
        if (!opts.passedWhenCfgPaths.isEmpty()) {
            emitDiag(BasicDiagKindRefactor.driver_cfg_path_ignored)
        }
        return true
    }
    for (path in opts.passedWhenCfgPaths) {
        let filePath = JoinPath(path, "cfg.toml")
        if (FileExist(filePath)) {
            return SetupConditionalCompilationCfgFromFile(filePath, opts.passedWhenKeyValue)
        }
        emitDiag(BasicDiagKindRefactor.driver_warning_no_such_file, filePath)
    }
    let defaultCfgFilePath = if (opts.packagePaths.isEmpty()) { "cfg.toml" } else { JoinPath(opts.packagePaths[0], "cfg.toml") }
    if (!FileExist(defaultCfgFilePath)) { return true }
    return SetupConditionalCompilationCfgFromFile(defaultCfgFilePath, opts.passedWhenKeyValue)
}

private func parseLto(opts: GlobalOptions, value: String): ActionResult {
    if (value == "full") { opts.ltoMod = LTOMode.FULL_LTO; return handled() }
    if (value == "thin") { opts.ltoMod = LTOMode.THIN_LTO; return handled() }
    return handled(success: false)
}

private func parseEmitCHIR(opts: GlobalOptions, value: String): ActionResult {
    if (value.isEmpty() || value == "opt") { opts.emitCHIRPhase = CandidateEmitCHIRPhase.OPT; return handled() }
    if (value == "raw") { opts.emitCHIRPhase = CandidateEmitCHIRPhase.RAW; return handled() }
    return handled(success: false)
}

private func parseChirMode(opts: GlobalOptions, value: String): ActionResult {
    if (value == "na") { opts.chirRenderMode = CHIRMode.NA; return handled() }
    if (value == "standard") { opts.chirRenderMode = CHIRMode.STANDARD; return handled() }
    if (value == "withID") { opts.chirRenderMode = CHIRMode.WITH_ID; return handled() }
    if (value == "all") { opts.chirRenderMode = CHIRMode.ALL; return handled() }
    return handled(success: false)
}

private func parseOverflowStrategy(opts: GlobalOptions, value: String): ActionResult {
    if (!ValidOverflowStrategy(value)) { return handled(success: false) }
    opts.overflowStrategy = StringToOverflowStrategy(value)
    return handled()
}

private func parseSancovLevel(opts: GlobalOptions, value: String): ActionResult {
    if (let Some(level) <- UtilsTryParseInt(value)) {
        if (level < 0) {
            Errorln("Sancov level " + value + " is invalid")
            return handled(success: false)
        }
        if (level == 0) { opts.sancovOption.SetSancovLevel(SanitizerCoverageType.SCK_NONE); return handled() }
        if (level == 1) { opts.sancovOption.SetSancovLevel(SanitizerCoverageType.SCK_FUNCTION); return handled() }
        opts.sancovOption.SetSancovLevel(SanitizerCoverageType.SCK_BB)
        return handled()
    }
    Errorln("Sancov level " + value + " is invalid")
    return handled(success: false)
}

private func parsePrintBCHIR(opts: GlobalOptions, value: String): ActionResult {
    if (value == "deserialized") { opts.SetPrintBCHIR(PrintBCHIROption.DESERIALIED); return handled() }
    if (value == "linked") { opts.SetPrintBCHIR(PrintBCHIROption.LINKED); return handled() }
    if (value == "chir2bchir") { opts.SetPrintBCHIR(PrintBCHIROption.CHIR2BCHIR); return handled() }
    if (value == "ce-chir2bchir") { opts.SetPrintBCHIR(PrintBCHIROption.CE_CHIR2BCHIR); return handled() }
    if (value == "interpreter") { opts.SetPrintBCHIR(PrintBCHIROption.INTERPRETER); return handled() }
    if (value == "ce-linked") { opts.SetPrintBCHIR(PrintBCHIROption.CE_LINKED); return handled() }
    if (value == "all") { opts.SetPrintBCHIR(PrintBCHIROption.ALL); return handled() }
    return handled(success: false)
}

private func parseSanitizer(opts: GlobalOptions, value: String): ActionResult {
    if (value == "address") { opts.sanitizerType = SanitizerType.ADDRESS; return handled() }
    if (value == "thread") { opts.sanitizerType = SanitizerType.THREAD; return handled() }
    if (value == "hwaddress") { opts.sanitizerType = SanitizerType.HWADDRESS; return handled() }
    return handled(success: false)
}

private func parseStackTraceFormat(opts: GlobalOptions, value: String): ActionResult {
    if (value == "default") { opts.stackTraceFmt = StackTraceFormat.DEFAULT; return handled() }
    if (value == "simple") { opts.stackTraceFmt = StackTraceFormat.SIMPLE; return handled() }
    if (value == "all") { opts.stackTraceFmt = StackTraceFormat.ALL; return handled() }
    return handled(success: false)
}

private func isAsciiDigitsOnly(value: String): Bool {
    for (byte in value.toArray()) {
        if (byte < b'0' || byte > b'9') { return false }
    }
    return true
}

private func parseJobsValue(optionName: String, value: String): MaybeUInt64 {
    let maxLen: Int64 = 9
    if (value.isEmpty()) {
        Errorln("'" + optionName + "' requires a non-empty value.")
        return MaybeUInt64()
    }
    if (!isAsciiDigitsOnly(value)) {
        Errorln("'" + optionName + "' only accepts a positive integer number as value.")
        return MaybeUInt64()
    }
    if (value.size > maxLen) {
        Errorln("'" + optionName + "' gets an invalid number input.")
        return MaybeUInt64()
    }
    let parsed = UtilsTryParseInt(value)
    if (let None <- parsed) { return MaybeUInt64() }
    let parsedValue = UInt64(parsed.getOrThrow())
    if (parsedValue < 1u64) {
        Warningln("'" + optionName + "' value must be greater than 0, the compiler will use 1 as the value.")
        return MaybeUInt64(1u64)
    }
    let threadNum = GetHardwareConcurrency()
    if (parsedValue > threadNum) { return MaybeUInt64(threadNum) }
    return MaybeUInt64(parsedValue)
}

private func parseJobs(opts: GlobalOptions, arg: OptionArgInstance, aggressive: Bool): ActionResult {
    if (arg.value.isEmpty() && aggressive) {
        opts.aggressiveParallelCompileWithoutArg = true
        return handled()
    }
    let parsed = parseJobsValue(arg.name, arg.value)
    if (!parsed.hasValue) { return handled(success: false) }
    if (aggressive) {
        opts.aggressiveParallelCompile = parsed
        UtilsSemaphore.Get().SetCount(Int64(parsed.value + 2u64))
    } else {
        opts.jobs = parsed
    }
    return handled()
}

private func parseAppleTargetTriple(opts: GlobalOptions, parts: Array<String>): Bool {
    if (parts.size < 3) {
        return false
    }
    if (parts[1] != "apple") {
        return false
    }
    opts.target.vendor = Vendor.APPLE
    if (parts[2] == "darwin") {
        opts.target.os = OSType.DARWIN
        opts.target.env = EnvironmentType.NOT_AVAILABLE
        return true
    }
    if (StartsWith(parts[2], "ios")) {
        opts.target.os = OSType.IOS
        opts.target.apiLevel = parts[2][3..]
        if (opts.target.apiLevel.isEmpty()) { opts.target.apiLevel = "11" }
        if (parts.size == 4 && parts[3] == "simulator") {
            opts.target.env = EnvironmentType.SIMULATOR
            return true
        }
        if (parts.size == 3) {
            opts.target.env = EnvironmentType.NOT_AVAILABLE
            return true
        }
    }
    return false
}

public func ParseTargetTriple(opts: GlobalOptions, triple: String): Bool {
    let parts = SplitString(triple, "-")
    if (parts.size != 3 && parts.size != 4) {
        Errorln("The target must be in either form of {ARCH}-{VENDOR}-{SYSTEM}-{ENV} or {ARCH}-{SYSTEM}-{ENV}.")
        return false
    }
    opts.target.vendor = Vendor.UNKNOWN
    if (parts[0] == "x86_64") { opts.target.arch = ArchType.X86_64 }
    else if (parts[0] == "aarch64" || parts[0] == "arm64") { opts.target.arch = ArchType.AARCH64 }
    else if (parts[0] == "arm") { opts.target.arch = ArchType.ARM32 }
    else if (parts[0] == "unknown") { opts.target.arch = ArchType.UNKNOWN }
    else {
        Errorln("The architecture \"" + parts[0] + "\" is not found or supported!")
        return false
    }
    if (parseAppleTargetTriple(opts, parts)) { return true }
    let osStr = parts[parts.size - 2]
    if (osStr == "linux") { opts.target.os = OSType.LINUX }
    else if (osStr == "windows" || osStr == "w64") { opts.target.os = OSType.WINDOWS }
    else if (osStr == "darwin") { opts.target.os = OSType.DARWIN }
    else if (osStr == "ios") { opts.target.os = OSType.IOS }
    else if (osStr == "unknown") { opts.target.os = OSType.UNKNOWN }
    else {
        Errorln("The OS \"" + osStr + "\" is not found or supported!")
        return false
    }
    let envStr = parts[parts.size - 1]
    if (envStr == "gnu" || envStr == "mingw32") { opts.target.env = EnvironmentType.GNU }
    else if (envStr == "ohos") { opts.target.env = EnvironmentType.OHOS }
    else if (envStr == "android") {
        opts.target.env = EnvironmentType.ANDROID
        opts.target.apiLevel = MIN_ANDROID_API
        Infoln("ANDROID API level is not suggested in the target. Use API level " + opts.target.apiLevel +
            " by default.")
    }
    else if (StartsWith(envStr, "android")) {
        opts.target.env = EnvironmentType.ANDROID
        var idx: Int64 = 0
        while (idx < envStr.size) {
            if (envStr[idx] >= b'0' && envStr[idx] <= b'9') {
                opts.target.apiLevel = envStr[idx..]
                break
            }
            idx++
        }
        if (!opts.target.apiLevel.isEmpty()) {
            let parsedApiLevel = UtilsStoi(opts.target.apiLevel)
            if (let Some(apiLevel) <- parsedApiLevel) {
                if (apiLevel < 23 || apiLevel > 10000) {
                    Errorln("The Android API level is not supported in the target. Please use a valid API level which is larger than 23.")
                }
            } else {
                Errorln("The Android API level is illegal. Please use a valid API level which is greater than or equal to 26.")
            }
        }
    }
    else if (envStr == "simulator") { opts.target.env = EnvironmentType.SIMULATOR }
    else if (envStr == "") { opts.target.env = EnvironmentType.NOT_AVAILABLE }
    else {
        Errorln("The environment \"" + envStr + "\" is not found or supported!")
        return false
    }
    return true
}
