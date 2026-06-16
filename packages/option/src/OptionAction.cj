package cangjie_compiler::option

import cangjie_compiler::utils.FileUtil
import std.collection.*

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
        if (arg.value.isEmpty()) { return handled(success: false) }
        opts.output = arg.value
        return handled()
    }
    if (id == ID.OUTPUT_DIR) {
        if (!IsDir(arg.value)) { return handled(success: false) }
        opts.outputDir = MaybeString(arg.value)
        return handled()
    }
    if (id == ID.OUTPUT_JAVA_GEN_DIR) { opts.outputJavaGenDir = MaybeString(arg.value); return handled() }
    if (id == ID.OUTPUT_OBJC_GEN_DIR) { opts.outputObjCGenDir = arg.value; return handled() }
    if (id == ID.MODULE_NAME) {
        Warningln("option '" + arg.name + "' is deprecated and will be removed in the future")
        return handled()
    }
    if (id == ID.PACKAGE_COMPILE) { opts.compilePackage = true; return handled() }
    if (id == ID.IMPORT_PATH) {
        let path = opts.CheckDirectoryPath(arg.value)
        if (path.hasValue) { opts.importPaths.add(path.value) }
        return handled()
    }
    if (id == ID.PLUGIN_PATH) {
        let pluginPath = opts.CheckInputFilePath(arg.value)
        if (!pluginPath.hasValue) { return handled(success: false) }
        let suffix = GetSharedLibraryExtension(opts.host.os)
        if ("." + GetFileExtension(pluginPath.value) != suffix) { return handled(success: false) }
        opts.pluginPaths.add(pluginPath.value)
        return handled()
    }
    if (id == ID.COMMON_PART_CJO) {
        let commonCjo = opts.CheckInputFilePath(arg.value)
        if (commonCjo.hasValue) { opts.commonPartCjos.add(commonCjo.value) }
        return handled(success: commonCjo.hasValue)
    }
    if (id == ID.COMMON_PART_CHIR) {
        let commonChir = opts.CheckInputFilePath(arg.value)
        if (commonChir.hasValue) { opts.commonPartChirs.add(commonChir.value) }
        return handled(success: commonChir.hasValue)
    }
    if (id == ID.INCRE_COMPILE) { opts.enIncrementalCompilation = true; return handled() }
    if (id == ID.INCRE_DEBUG) { opts.printIncrementalInfo = true; return handled() }
    if (id == ID.DUMP_DEPENDENT_PACKAGE) { opts.scanDepPkg = true; return handled() }
    if (id == ID.NO_SUB_PACKAGE) { opts.noSubPkg = true; return handled() }
    if (id == ID.TARGET) { return handled(success: ParseTargetTriple(opts, arg.value)) }
    if (id == ID.TARGET_CPU) { opts.targetCPU = arg.value; return handled() }
    if (id == ID.SYSROOT) {
        let sysroot = opts.CheckDirectoryPath(arg.value)
        if (sysroot.hasValue) { opts.sysroot = sysroot.value }
        return handled(success: sysroot.hasValue)
    }
    if (id == ID.TOOLCHAIN) {
        let toolchain = opts.CheckDirectoryPath(arg.value)
        if (toolchain.hasValue) { opts.toolchains.add(toolchain.value) }
        return handled(success: toolchain.hasValue)
    }
    if (id == ID.LIBRARY_PATH) {
        let libPath = opts.CheckDirectoryPath(arg.value)
        if (libPath.hasValue) { opts.libraryPaths.add(libPath.value) }
        return handled(success: libPath.hasValue)
    }
    if (id == ID.LIBRARY) { opts.libraries.add(arg.value); return handled() }
    if (id == ID.LINK_OPTION) { opts.linkOptions.add(arg.value); return handled() }
    if (id == ID.LINK_OPTIONS) { opts.linkOptionGroups.add(arg.value); return handled() }
    if (id == ID.USE_RUNTIME_RPATH) { opts.useRuntimeRpath = true; return handled() }
    if (id == ID.OPT_OPTIONS) { opts.optOptions = arg.value; return handled() }
    if (id == ID.LLC_OPTIONS) { opts.llcOptions = arg.value; return handled() }
    if (id == ID.OUTPUT_TYPE) { return parseOutputType(opts, arg.value) }
    if (id == ID.COMPILE_TARGET) { return parseCompileTarget(opts, arg.value) }
    if (id == ID.OPTIMIZATION_0) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O0)) }
    if (id == ID.OPTIMIZATION_1) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O1)) }
    if (id == ID.OPTIMIZATION_2) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O2)) }
    if (id == ID.OPTIMIZATION_3) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O3)) }
    if (id == ID.OPTIMIZATION_S) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.Os)) }
    if (id == ID.OPTIMIZATION_Z) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.Oz)) }
    if (id == ID.OPTIMIZATION_CUSTOM) { return parseCustomOptimization(opts, arg.value) }
    if (id == ID.WARN_OFF) { parseWarn(arg.value, true); return handled() }
    if (id == ID.WARN_ON) { parseWarn(arg.value, false); return handled() }
    if (id == ID.ERROR_COUNT_LIMIT) { return parseErrorLimit(opts, arg.value) }
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
    if (id == ID.STRIP_ALL) { opts.stripAll = true; return handled() }
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
    if (id == ID.STATIC_STD) { opts.linkStaticStd = MaybeBool(true); return handled() }
    if (id == ID.DY_STD) { opts.linkStaticStd = MaybeBool(false); return handled() }
    if (id == ID.STATIC_LIBS || id == ID.DY_LIBS || id == ID.STATIC) { return handled() }
    if (id == ID.LTO) { return parseLto(opts, arg.value) }
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
    if (id == ID.SANITIZE_SET_RPATH) { opts.sanitizerSetRpath = true; return handled() }
    if (id == ID.ENABLE_COVERAGE) { opts.enableCoverage = true; return handled() }
    if (id == ID.COMPILE_MACRO) {
        opts.compileMacroPackage = true
        opts.outputMode = OutputMode.SHARED_LIB
        return handled()
    }
    if (id == ID.SAVE_TEMPS) {
        if (!IsDir(arg.value)) { return handled(success: false) }
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
    if (id == ID.JOBS) { return parseJobs(opts, arg.value, false) }
    if (id == ID.AGGRESSIVE_PARALLEL_COMPILE) { return parseJobs(opts, arg.value, true) }
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
        opts.linkStaticStd = MaybeBool(false)
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
    let parsed = TryParseUInt64(value)
    if (!parsed.hasValue) { return handled(success: false) }
    if (parsed.value == 0u64) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O0)) }
    if (parsed.value == 1u64) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O1)) }
    if (parsed.value == 2u64) { return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O2)) }
    return handled(success: opts.SetOptimizationLevel(OptimizationLevel.O3))
}

private func parseWarn(value: String, suppress: Bool): Unit {
    if (value == "all") {
        WarningOptionMgr.UpdateFlags(suppress)
    } else if (value == "unused") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.UNUSED)), suppress)
    } else if (value == "unused-main") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.UNUSED_MAIN)), suppress)
    } else if (value == "driver-arg") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.DRIVER_ARG)), suppress)
    } else if (value == "deprecated") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.DEPRECATED)), suppress)
    } else if (value == "unsupport-compile-source") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.UNSUPPORT_COMPILE_SOURCE)), suppress)
    } else if (value == "package-import") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.PACKAGE_IMPORT)), suppress)
    } else if (value == "parser") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.PARSER)), suppress)
    } else if (value == "semantics") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.SEMANTICS)), suppress)
    } else if (value == "interpreter") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.INTERPRETER)), suppress)
    } else if (value == "apilevel-check") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.APILEVEL_CHECK)), suppress)
    }
}

private func parseErrorLimit(opts: GlobalOptions, value: String): ActionResult {
    if (value == "all") {
        opts.errorCountLimit = MaybeUInt64()
        return handled()
    }
    let parsed = TryParseUInt64(value)
    if (!parsed.hasValue) { return handled(success: false) }
    opts.errorCountLimit = parsed
    return handled()
}

private func parsePassedWhen(opts: GlobalOptions, value: String): ActionResult {
    if (value.isEmpty()) { return handled(success: false) }
    if (isCfgPathMode(value)) {
        let path = value.replace("\\=", "=")
        if (!IsDir(path)) { return handled(success: false) }
        opts.passedWhenCfgPaths.add(path)
        return handled()
    }
    let parts = SplitString(value, ",")
    for (part in parts) {
        let kv = SplitString(part, "=")
        if (kv.size != 2) { return handled(success: false) }
        let maybeKey = normalizeCfgKey(kv[0].trimAscii())
        let val = kv[1].trimAscii()
        if (!maybeKey.hasValue || val.isEmpty()) { return handled(success: false) }
        if (!addCfgKeyValue(opts.passedWhenKeyValue, maybeKey.value, val)) { return handled(success: false) }
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

private func normalizeCfgKey(rawKey: String): MaybeString {
    if (rawKey.isEmpty() || !FileUtil.IsIdentifier(rawKey)) { return MaybeString() }
    var key = rawKey
    if (key.size > 2 && key[0] == b'`' && key[key.size - 1] == b'`') {
        key = key[1..key.size - 1]
    }
    if (isBuiltinCondition(key)) { return MaybeString() }
    return MaybeString(key)
}

private func addCfgKeyValue(map: HashMap<String, String>, key: String, value: String): Bool {
    if (map.contains(key)) { return false }
    map.add(key, value)
    return true
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
    if (kv.size != 2) { return false }
    let maybeKey = normalizeCfgKey(kv[0].trimAscii())
    let quotedValue = kv[1].trimAscii()
    if (!maybeKey.hasValue || quotedValue.size <= 2 || quotedValue[0] != b'"' ||
        quotedValue[quotedValue.size - 1] != b'"') {
        return false
    }
    let unquotedValue = quotedValue[1..quotedValue.size - 1].replace("\\\"", "\"")
    return addCfgKeyValue(map, maybeKey.value, unquotedValue)
}

public func SetupConditionalCompilationCfgFromFile(filePath: String, map: HashMap<String, String>): Bool {
    let content = ReadTextFile(filePath)
    if (!content.hasValue) { return false }
    for (line in SplitLines(content.value)) {
        if (line.isEmpty() || seeingTomlComment(line)) { continue }
        if (!parseConditionKeyValueLine(line, map)) { return false }
    }
    return true
}

public func SetupConditionalCompilationCfg(opts: GlobalOptions): Bool {
    if (!opts.passedWhenKeyValue.isEmpty()) { return true }
    for (path in opts.passedWhenCfgPaths) {
        let filePath = JoinPath(path, "cfg.toml")
        if (FileExist(filePath)) {
            return SetupConditionalCompilationCfgFromFile(filePath, opts.passedWhenKeyValue)
        }
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
    if (value == "standard") { opts.chirRenderMode = CHIRMode.STANDARD; return handled() }
    if (value == "withID") { opts.chirRenderMode = CHIRMode.WITH_ID; return handled() }
    if (value == "all") { opts.chirRenderMode = CHIRMode.ALL; return handled() }
    return handled(success: false)
}

private func parseOverflowStrategy(opts: GlobalOptions, value: String): ActionResult {
    if (value == "throwing") { opts.overflowStrategy = OverflowStrategy.THROWING; return handled() }
    if (value == "wrapping") { opts.overflowStrategy = OverflowStrategy.WRAPPING; return handled() }
    if (value == "saturating") { opts.overflowStrategy = OverflowStrategy.SATURATING; return handled() }
    return handled(success: false)
}

private func parseSancovLevel(opts: GlobalOptions, value: String): ActionResult {
    let parsed = TryParseUInt64(value)
    if (!parsed.hasValue) { return handled(success: false) }
    if (parsed.value == 0u64) { opts.sancovOption.SetSancovLevel(SanitizerCoverageType.SCK_NONE); return handled() }
    if (parsed.value == 1u64) { opts.sancovOption.SetSancovLevel(SanitizerCoverageType.SCK_FUNCTION); return handled() }
    opts.sancovOption.SetSancovLevel(SanitizerCoverageType.SCK_BB)
    return handled()
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

private func parseJobsValue(optionName: String, value: String): MaybeUInt64 {
    let maxLen: Int64 = 9
    if (value.isEmpty() || value.size > maxLen) { return MaybeUInt64() }
    let parsed = TryParseUInt64(value)
    if (!parsed.hasValue) { return MaybeUInt64() }
    if (parsed.value < 1u64) {
        Warningln("'" + optionName + "' value must be greater than 0, the compiler will use 1 as the value.")
        return MaybeUInt64(1u64)
    }
    return parsed
}

private func parseJobs(opts: GlobalOptions, value: String, aggressive: Bool): ActionResult {
    if (value.isEmpty() && aggressive) {
        opts.aggressiveParallelCompileWithoutArg = true
        return handled()
    }
    let optionName = if (aggressive) { "--aggressive-parallel-compile" } else { "--jobs" }
    let parsed = parseJobsValue(optionName, value)
    if (!parsed.hasValue) { return handled(success: false) }
    if (aggressive) {
        opts.aggressiveParallelCompile = parsed
    } else {
        opts.jobs = parsed
    }
    return handled()
}

public func ParseTargetTriple(opts: GlobalOptions, triple: String): Bool {
    let parts = SplitString(triple, "-")
    if (parts.size != 3 && parts.size != 4) { return false }
    opts.target.vendor = Vendor.UNKNOWN
    if (parts[0] == "x86_64") { opts.target.arch = ArchType.X86_64 }
    else if (parts[0] == "aarch64" || parts[0] == "arm64") { opts.target.arch = ArchType.AARCH64 }
    else if (parts[0] == "arm") { opts.target.arch = ArchType.ARM32 }
    else if (parts[0] == "unknown") { opts.target.arch = ArchType.UNKNOWN }
    else { return false }
    if (parts.size >= 3 && parts[1] == "apple") {
        opts.target.vendor = Vendor.APPLE
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
            return false
        }
        if (parts[2] == "darwin") {
            opts.target.os = OSType.DARWIN
            opts.target.env = EnvironmentType.NOT_AVAILABLE
            return true
        }
    }
    let osStr = parts[parts.size - 2]
    if (osStr == "linux") { opts.target.os = OSType.LINUX }
    else if (osStr == "windows" || osStr == "w64") { opts.target.os = OSType.WINDOWS }
    else if (osStr == "darwin") { opts.target.os = OSType.DARWIN }
    else if (osStr == "ios") { opts.target.os = OSType.IOS }
    else if (osStr == "unknown") { opts.target.os = OSType.UNKNOWN }
    else { return false }
    let envStr = parts[parts.size - 1]
    if (envStr == "gnu" || envStr == "mingw32") { opts.target.env = EnvironmentType.GNU }
    else if (envStr == "ohos") { opts.target.env = EnvironmentType.OHOS }
    else if (envStr == "android") { opts.target.env = EnvironmentType.ANDROID; opts.target.apiLevel = MIN_ANDROID_API }
    else if (StartsWith(envStr, "android")) {
        opts.target.env = EnvironmentType.ANDROID
        opts.target.apiLevel = ""
        var idx: Int64 = 0
        while (idx < envStr.size) {
            if (envStr[idx] >= b'0' && envStr[idx] <= b'9') {
                opts.target.apiLevel = envStr[idx..]
                break
            }
            idx++
        }
        if (!opts.target.apiLevel.isEmpty()) {
            let parsed = TryParseUInt64(opts.target.apiLevel)
            if (parsed.hasValue && (parsed.value < 23u64 || parsed.value > 10000u64)) {
                Errorln("The Android API level is not supported in the target. Please use a valid API level which is larger than 23.")
            } else if (!parsed.hasValue) {
                Errorln("The Android API level is illegal. Please use a valid API level which is greater than or equal to 26.")
            }
        }
    }
    else if (envStr == "simulator") { opts.target.env = EnvironmentType.SIMULATOR }
    else if (envStr == "") { opts.target.env = EnvironmentType.NOT_AVAILABLE }
    else { return false }
    return true
}
