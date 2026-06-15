package cangjie_compiler::option

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
    if (id == ID.MODULE_NAME) { opts.moduleName = arg.value; return handled() }
    if (id == ID.PACKAGE_COMPILE) { opts.compilePackage = true; return handled() }
    if (id == ID.IMPORT_PATH) {
        let path = opts.CheckDirectoryPath(arg.value)
        if (path.hasValue) { opts.importPaths.add(path.value) }
        return handled()
    }
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
    if (id == ID.WARN_OFF) { parseWarn(arg.value, true); return handled() }
    if (id == ID.WARN_ON) { parseWarn(arg.value, false); return handled() }
    if (id == ID.ERROR_COUNT_LIMIT) { return parseErrorLimit(opts, arg.value) }
    if (id == ID.CONDITIONAL_COMPILATION_CONFIG) { return parsePassedWhen(opts, arg.value) }
    if (id == ID.COMPILE_DEBUG) { opts.enableCompileDebug = true; return handled() }
    if (id == ID.NO_PRELUDE) { opts.implicitPrelude = false; return handled() }
    if (id == ID.STATIC_STD) { opts.linkStaticStd = MaybeBool(true); return handled() }
    if (id == ID.DY_STD) { opts.linkStaticStd = MaybeBool(false); return handled() }
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
    if (id == ID.SANITIZE) { return parseSanitizer(opts, arg.value) }
    if (id == ID.JOBS) { return parseJobs(opts, arg.value, false) }
    if (id == ID.AGGRESSIVE_PARALLEL_COMPILE) { return parseJobs(opts, arg.value, true) }
    return handled()
}

private func parseOutputType(opts: GlobalOptions, value: String): ActionResult {
    if (value == "exe") { opts.outputMode = OutputMode.EXECUTABLE }
    else if (value == "staticlib") { opts.outputMode = OutputMode.STATIC_LIB }
    else if (value == "dylib") { opts.outputMode = OutputMode.SHARED_LIB }
    else if (value == "chir") { opts.outputMode = OutputMode.CHIR }
    else if (value == "obj") { opts.outputMode = OutputMode.OBJ }
    else if (value == "hotreload") { opts.outputMode = OutputMode.SHARED_LIB }
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
    } else if (value == "driver-arg") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.DRIVER_ARG)), suppress)
    } else if (value == "deprecated") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.DEPRECATED)), suppress)
    } else if (value == "parser") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.PARSER)), suppress)
    } else if (value == "semantics") {
        WarningOptionMgr.UpdateFlag(UInt64(WarnGroupIndex(WarnGroup.SEMANTICS)), suppress)
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
    let parts = SplitString(value, ",")
    for (part in parts) {
        let kv = SplitString(part, "=")
        if (kv.size != 2) {
            opts.passedWhenCfgPaths.add(part.replace("\\=", "="))
        } else {
            let key = kv[0].trimAscii()
            let val = kv[1].trimAscii()
            if (key.isEmpty() || val.isEmpty()) { return handled(success: false) }
            if (opts.passedWhenKeyValue.contains(key)) { opts.passedWhenKeyValue.remove(key) }
            opts.passedWhenKeyValue.add(key, val)
        }
    }
    return handled()
}

private func parseLto(opts: GlobalOptions, value: String): ActionResult {
    if (value == "full") { opts.ltoMod = LTOMode.FULL_LTO; return handled() }
    if (value == "thin") { opts.ltoMod = LTOMode.THIN_LTO; return handled() }
    return handled(success: false)
}

private func parseSanitizer(opts: GlobalOptions, value: String): ActionResult {
    if (value == "address") { opts.sanitizerType = SanitizerType.ADDRESS; return handled() }
    if (value == "thread") { opts.sanitizerType = SanitizerType.THREAD; return handled() }
    if (value == "hwaddress") { opts.sanitizerType = SanitizerType.HWADDRESS; return handled() }
    return handled(success: false)
}

private func parseJobs(opts: GlobalOptions, value: String, aggressive: Bool): ActionResult {
    if (value.isEmpty() && aggressive) {
        opts.aggressiveParallelCompileWithoutArg = true
        return handled()
    }
    let parsed = TryParseUInt64(value)
    if (!parsed.hasValue || parsed.value < 1u64) { return handled(success: false) }
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
    if (parts[0] == "x86_64") { opts.target.arch = ArchType.X86_64 }
    else if (parts[0] == "aarch64" || parts[0] == "arm64") { opts.target.arch = ArchType.AARCH64 }
    else if (parts[0] == "arm") { opts.target.arch = ArchType.ARM32 }
    else { return false }
    if (parts.size >= 3 && parts[1] == "apple") {
        opts.target.vendor = Vendor.APPLE
        if (StartsWith(parts[2], "ios")) {
            opts.target.os = OSType.IOS
            opts.target.apiLevel = parts[2][3..]
            opts.target.env = if (parts.size == 4 && parts[3] == "simulator") { EnvironmentType.SIMULATOR } else { EnvironmentType.NOT_AVAILABLE }
            return true
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
    else { return false }
    let envStr = parts[parts.size - 1]
    if (envStr == "gnu" || envStr == "mingw32") { opts.target.env = EnvironmentType.GNU }
    else if (envStr == "ohos") { opts.target.env = EnvironmentType.OHOS }
    else if (envStr == "android") { opts.target.env = EnvironmentType.ANDROID; opts.target.apiLevel = MIN_ANDROID_API }
    else if (StartsWith(envStr, "android")) { opts.target.env = EnvironmentType.ANDROID; opts.target.apiLevel = envStr[7..] }
    else if (envStr == "simulator") { opts.target.env = EnvironmentType.SIMULATOR }
    else { return false }
    return true
}
