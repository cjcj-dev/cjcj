package cjcj::driver

import std.collection.*
import std.convert.*
import cjcj::option.{
    ArgInstanceType, ArgList, CreateOptionTable, GetHardwareConcurrency, Group, ID, Kind, OptionArgInstance, OptionTable
}
import cjcj::utils.Semaphore as UtilsSemaphore

private let g_driverOptionTable: OptionTable = CreateOptionTable(frontendMode: false)

public func ParseDriverArgs(opts: DriverOptions, arguments: Array<String>): Bool {
    let argList = ArgList()
    if (!g_driverOptionTable.ParseArgs(ReorderWarningArgs(arguments), argList)) {
        return false
    }
    var ok = true
    var orderIndex = 0u64
    for (entry in argList.entries) {
        if (entry.argInstanceType == ArgInstanceType.Option) {
            let parsed = ParseOption(opts, argList.optionArgs[entry.index], orderIndex)
            ok = ok && parsed
        } else {
            let input = argList.inputArgs[entry.index].value
            let classified = ClassifyInput(opts, input, orderIndex)
            ok = ok && classified
            if (IsFrontendInput(input)) {
                opts.frontendForwardArgs.add(input)
            }
        }
        orderIndex += 1u64
    }
    return ok
}

private func IsWarningArg(arg: String): Bool {
    return arg.startsWith("-Woff") || arg.startsWith("--warn-off") || arg.startsWith("-Won") ||
        arg.startsWith("--warn-on")
}

private func WarningArgTakesSeparatedValue(arg: String): Bool {
    return arg == "-Woff" || arg == "--warn-off" || arg == "-Won" || arg == "--warn-on"
}

private func ReorderWarningArgs(arguments: Array<String>): Array<String> {
    if (arguments.size <= 2) {
        return arguments
    }
    let warningArgs = ArrayList<String>()
    let otherArgs = ArrayList<String>()
    var idx: Int64 = 1
    while (idx < arguments.size) {
        let arg = arguments[idx]
        if (arg == "--") {
            while (idx < arguments.size) {
                otherArgs.add(arguments[idx])
                idx++
            }
            break
        }
        if (IsWarningArg(arg)) {
            warningArgs.add(arg)
            if (WarningArgTakesSeparatedValue(arg) && idx + 1 < arguments.size) {
                idx++
                warningArgs.add(arguments[idx])
            }
        } else {
            otherArgs.add(arg)
        }
        idx++
    }
    let reordered = ArrayList<String>()
    if (!arguments.isEmpty()) {
        reordered.add(arguments[0])
    }
    for (arg in warningArgs) {
        reordered.add(arg)
    }
    for (arg in otherArgs) {
        reordered.add(arg)
    }
    return reordered.toArray()
}

private func addFrontendFlag(opts: DriverOptions, spelling: String): Unit {
    opts.frontendForwardArgs.add(spelling)
}

private func addFrontendJoined(opts: DriverOptions, spelling: String, value: String): Unit {
    opts.frontendForwardArgs.add(spelling + "=" + value)
}

private func addFrontendSeparated(opts: DriverOptions, spelling: String, value: String): Unit {
    opts.frontendForwardArgs.add(spelling)
    opts.frontendForwardArgs.add(value)
}

private func TryParseInt64(value: String): Option<Int64> {
    try {
        return Int64.parse(value)
    } catch (e: Exception) {
        return None
    }
}

private func TryParseUInt64(value: String): Option<UInt64> {
    try {
        return UInt64.parse(value)
    } catch (e: Exception) {
        return None
    }
}

private func ParseSanitizer(opts: DriverOptions, value: String): Bool {
    if (value == "address") { opts.sanitizerType = SanitizerType.ADDRESS; return true }
    if (value == "thread") { opts.sanitizerType = SanitizerType.THREAD; return true }
    if (value == "hwaddress") { opts.sanitizerType = SanitizerType.HWADDRESS; return true }
    eprintln("error: unsupported --sanitize value '${value}'")
    return false
}

private func ParseJobsValue(optionName: String, value: String): Option<UInt64> {
    let maxLen: Int64 = 9
    if (value.isEmpty()) {
        eprintln("'" + optionName + "' requires a non-empty value.")
        return None
    }
    for (byte in value.toArray()) {
        if (byte < b'0' || byte > b'9') {
            eprintln("'" + optionName + "' only accepts a positive integer number as value.")
            return None
        }
    }
    if (value.size > maxLen) {
        eprintln("'" + optionName + "' gets an invalid number input.")
        return None
    }
    if (let Some(parsed) <- TryParseUInt64(value)) {
        if (parsed < 1u64) {
            eprintln("warning: '" + optionName + "' value must be greater than 0, the compiler will use 1 as the value.")
            return 1u64
        }
        let threadNum = GetHardwareConcurrency()
        if (parsed > threadNum) { return threadNum }
        return parsed
    }
    return None
}

private func ParseOption(opts: DriverOptions, optionArg: OptionArgInstance, optionIndex: UInt64): Bool {
    let arg = optionArg.name
    let value = optionArg.value
    if (arg == "-h" || arg == "--help") { opts.showUsage = true; return true }
    if (arg == "-v" || arg == "--version") { opts.printVersionOnly = true; return true }
    if (arg == "-V" || arg == "--verbose") { opts.enableVerbose = true; addFrontendFlag(opts, arg); return true }
    if (arg == "-g") { opts.enableCompileDebug = true; addFrontendFlag(opts, arg); return true }
    if (arg == "-s" || arg == "--strip-all") { opts.stripSymbolTable = true; return true }
    if (arg == "--static") { opts.linkStatic = true; return true }
    if (arg == "--static-std") { opts.linkStaticStd = true; return true }
    if (arg == "--dy-std") { opts.linkStaticStd = false; return true }
    if (arg == "--static-libs") { opts.linkStaticLibs = true; return true }
    if (arg == "--dy-libs") { opts.linkStaticLibs = false; return true }
    if (arg == "--set-runtime-rpath") { opts.useRuntimeRpath = true; return true }
    if (arg == "--sanitize-set-rpath") { opts.sanitizerEnableRpath = true; return true }
    if (arg == "--scan-dependency") {
        opts.scanDepPkg = true
        opts.frontendOnlyAction = true
        addFrontendFlag(opts, arg)
        return true
    }
    if (arg == "-p" || arg == "--package") {
        opts.compilePackage = true
        addFrontendFlag(opts, arg)
        return true
    }
    if (arg == "--no-sub-pkg") { opts.noSubPkg = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--profile-compile-time") { opts.enableTimer = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--profile-compile-memory") { opts.enableMemoryCollect = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--coverage") { opts.enableCoverage = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--fast-math") { opts.fastMathMode = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--experimental") { opts.experimentalMode = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--compile-macro") { opts.compileMacro = true; opts.outputMode = OutputMode.SHARED_LIB; addFrontendFlag(opts, arg); return true }
    if (arg == "--debug-macro") { opts.enableMacroDebug = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--parallel-macro-expansion") { opts.enableParallelMacro = true; addFrontendFlag(opts, arg); return true }
    if (arg == "-d") { opts.compileCjd = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--test") { opts.parseTest = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--test-only") { opts.parseTest = true; opts.compileTestsOnly = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--export-for-test") { opts.exportForTest = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--incremental-compile") { opts.enIncrementalCompilation = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--incremental-debug") { opts.printIncrementalInfo = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--no-prelude") { opts.implicitPrelude = false; addFrontendFlag(opts, arg); return true }
    if (arg == "--dump-ast" || arg == "--dump-chir" || arg == "--dump-ir" || arg == "--dump-all" ||
        arg == "--dump-to-screen" || arg == "--typecheck" || arg == "--dump-tokens" || arg == "--dump-symbols") {
        if (arg == "--typecheck" || arg == "--dump-tokens" || arg == "--dump-symbols") {
            opts.frontendOnlyAction = true
        }
        addFrontendFlag(opts, arg)
        return true
    }
    if (arg == "--emit-chir") {
        opts.emitCHIRPhase = if (value.isEmpty()) { "opt" } else { value }
        addFrontendFlag(opts, arg)
        return true
    }
    if (arg == "--disable-chir-opt") { opts.disableChirOpt = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--disable-backend-opt") { opts.disableBackendOpt = true; addFrontendFlag(opts, arg); return true }
    if (arg == "--ffunction-sections") { opts.enableFuncSections = true; return true }
    if (arg == "--fno-function-sections") { opts.enableFuncSections = false; return true }
    if (arg == "--fdata-sections") { opts.enableDataSections = true; return true }
    if (arg == "--fno-data-sections") { opts.enableDataSections = false; return true }
    if (arg == "--gc-sections") { opts.enableGcSections = true; return true }
    if (arg == "--no-gc-sections") { opts.enableGcSections = false; return true }
    if (arg == "--discard-eh-frame") { opts.discardEhFrame = true; return true }
    if (arg == "--compile-as-exe") { opts.enableCompileAsExe = true; return true }
    if (ParseOptimization(opts, optionArg)) { return true }
    if (ParseWarningFlag(opts, optionArg)) { return true }
    if (ParseObfuscationFlag(opts, arg)) { return true }
    return ParseOptionWithValue(opts, optionArg, optionIndex)
}

private func ParseOptimization(opts: DriverOptions, optionArg: OptionArgInstance): Bool {
    let arg = optionArg.name
    let value = optionArg.value
    if (arg == "-O0") { addFrontendFlag(opts, arg); return opts.SetOptimizationLevel(OptimizationLevel.O0) }
    if ((arg == "-O" && value.isEmpty()) || arg == "-O1") {
        addFrontendFlag(opts, arg)
        return opts.SetOptimizationLevel(OptimizationLevel.O1)
    }
    if (arg == "-O2") { addFrontendFlag(opts, arg); return opts.SetOptimizationLevel(OptimizationLevel.O2) }
    if (arg == "-O3") { addFrontendFlag(opts, arg); return opts.SetOptimizationLevel(OptimizationLevel.O3) }
    if (arg == "-Os") { addFrontendFlag(opts, arg); return opts.SetOptimizationLevel(OptimizationLevel.Os) }
    if (arg == "-Oz") { addFrontendFlag(opts, arg); return opts.SetOptimizationLevel(OptimizationLevel.Oz) }
    if (arg == "-O" && !value.isEmpty()) {
        if (let Some(parsed) <- TryParseInt64(value)) {
            addFrontendFlag(opts, arg)
            if (parsed <= 0) { return opts.SetOptimizationLevel(OptimizationLevel.O0) }
            if (parsed == 1) { return opts.SetOptimizationLevel(OptimizationLevel.O1) }
            if (parsed == 2) { return opts.SetOptimizationLevel(OptimizationLevel.O2) }
            return opts.SetOptimizationLevel(OptimizationLevel.O3)
        }
    }
    return false
}

private func ParseWarningFlag(opts: DriverOptions, optionArg: OptionArgInstance): Bool {
    if (optionArg.info.GetID() == ID.WARN_OFF) {
        addFrontendSeparated(opts, optionArg.name, optionArg.value)
        return true
    }
    if (optionArg.info.GetID() == ID.WARN_ON) {
        addFrontendSeparated(opts, optionArg.name, optionArg.value)
        return true
    }
    return false
}

private func ParseObfuscationFlag(opts: DriverOptions, arg: String): Bool {
    if (arg == "--fobf-string") { opts.enableStringObfuscation = true; return true }
    if (arg == "--fno-obf-string") { opts.enableStringObfuscation = false; return true }
    if (arg == "--fobf-const") { opts.enableConstObfuscation = true; return true }
    if (arg == "--fno-obf-const") { opts.enableConstObfuscation = false; return true }
    if (arg == "--fobf-layout") { opts.enableLayoutObfuscation = true; return true }
    if (arg == "--fno-obf-layout") { opts.enableLayoutObfuscation = false; return true }
    if (arg == "--fobf-cf-flatten") { opts.enableCFflattenObfuscation = true; return true }
    if (arg == "--fno-obf-cf-flatten") { opts.enableCFflattenObfuscation = false; return true }
    if (arg == "--fobf-cf-bogus") { opts.enableCFBogusObfuscation = true; return true }
    if (arg == "--fno-obf-cf-bogus") { opts.enableCFBogusObfuscation = false; return true }
    if (arg == "--fobf-all") { opts.enableObfAll = true; return true }
    if (arg == "--fobf-export-symbols") { opts.enableObfExportSyms = true; return true }
    if (arg == "--fno-obf-export-symbols") { opts.enableObfExportSyms = false; return true }
    if (arg == "--fobf-source-path") { opts.enableObfSourcePath = true; return true }
    if (arg == "--fno-obf-source-path") { opts.enableObfSourcePath = false; return true }
    if (arg == "--fobf-line-number") { opts.enableObfLineNumber = true; return true }
    if (arg == "--fno-obf-line-number") { opts.enableObfLineNumber = false; return true }
    return false
}

private func ParseOptionWithValue(opts: DriverOptions, optionArg: OptionArgInstance, optionIndex: UInt64): Bool {
    let arg = optionArg.name
    let value = optionArg.value
    if (arg == "-o" || arg == "--output") { opts.output = value; return true }
    if (arg == "--output-dir") {
        opts.outputDir = value
        addFrontendSeparated(opts, arg, value)
        return true
    }
    if (arg == "--deserialize-chir-and-dump") {
        opts.frontendOnlyAction = true
        addFrontendSeparated(opts, arg, value)
        return true
    }
    if (arg == "--module-name") {
        opts.moduleName = value
        addFrontendSeparated(opts, arg, value)
        return true
    }
    if (arg == "--module-src-path") {
        opts.moduleSrcPath = value
        addFrontendSeparated(opts, arg, value)
        return true
    }
    if (arg == "-B" || arg == "--toolchain") {
        if (let Some(path) <- opts.CheckDirectoryPath(value)) { opts.toolChainPaths.add(path) }
        return true
    }
    if (arg == "-L" || arg == "--library-path") {
        if (let Some(path) <- opts.CheckDirectoryPath(value)) { opts.librarySearchPaths.add(path) }
        return true
    }
    if (arg == "-l" || arg == "--library") {
        opts.libraries.add(value)
        opts.orderedLibraries.add(OrderedInput("-l" + value, optionIndex))
        return true
    }
    if (arg == "--link-option") {
        opts.linkOption.add(value)
        opts.orderedLinkOptions.add(OrderedInput(value, optionIndex))
        return true
    }
    if (arg == "--link-options") {
        opts.linkOptions.add(value)
        opts.orderedLinkOptionGroups.add(OrderedInput(value, optionIndex))
        return true
    }
    if (arg == "--target") {
        if (let Some(triple) <- TryParseTriple(value)) {
            opts.target = triple
            addFrontendSeparated(opts, arg, value)
            return true
        }
        eprintln("error: unsupported target triple '${value}'")
        return false
    }
    if (arg == "--target-cpu") { opts.targetCPU = value; return true }
    if (arg == "--sysroot") {
        if (let Some(path) <- opts.CheckDirectoryPath(value)) {
            opts.sysroot = path
            opts.customizedSysroot = true
        }
        return true
    }
    if (arg == "--save-temps") { opts.saveTemps = true; opts.tempFolderPath = value; return true }
    if (arg == "--diagnostic-format") {
        if (value != "json" && value != "noColor" && value != "default") {
            eprintln("error: unsupported --diagnostic-format value '${value}'")
            return false
        }
        opts.diagFormat = value
        addFrontendSeparated(opts, arg, value)
        return true
    }
    if (arg == "--error-count-limit") {
        if (value == "all") {
            opts.errorCountLimit = UInt64.Max
            addFrontendSeparated(opts, arg, value)
            return true
        }
        if (let Some(parsed) <- TryParseUInt64(value)) {
            opts.errorCountLimit = parsed
            addFrontendSeparated(opts, arg, value)
            return true
        }
        eprintln("error: invalid value for --error-count-limit: ${value}")
        return false
    }
    if (arg == "--lto") {
        if (value == "full") { opts.ltoMod = LTOMode.FULL_LTO; return true }
        if (value == "thin") { opts.ltoMod = LTOMode.THIN_LTO; return true }
        eprintln("error: unsupported --lto value '${value}'")
        return false
    }
    if (arg == "--output-type") {
        if (!ParseOutputType(opts, value)) { return false }
        addFrontendSeparated(opts, arg, value)
        return true
    }
    if (arg == "--compile-target") { return ParseCompileTarget(opts, value) }
    if (arg == "--opt-options") { opts.optArg = value; return true }
    if (arg == "--llc-options") { opts.llcArg = value; return true }
    if (arg == "--opt-pass-options") {
        opts.optPassOptions = value
        addFrontendSeparated(opts, arg, value)
        return true
    }
    if (arg == "--sanitize") {
        if (!ParseSanitizer(opts, value)) { return false }
        addFrontendSeparated(opts, arg, value)
        return true
    }
    if (arg == "--stack-trace-format") {
        if (value != "default" && value != "simple" && value != "all") {
            eprintln("error: unsupported --stack-trace-format value '${value}'")
            return false
        }
        opts.stackTraceFormat = "--stack-trace-format=" + value
        return true
    }
    if (arg == "--lto-keep-pkg-visibility") {
        if (value.isEmpty()) {
            opts.ltoHideAllPkgs = true
        } else {
            for (rawPkg in SplitString(value, ",")) {
                let pkg = rawPkg.trimAscii()
                if (!pkg.isEmpty()) { opts.ltoVisiblePkgs.add(pkg) }
            }
        }
        return true
    }
    if (arg == "--pgo-instr-gen") {
        opts.enablePgoInstrGen = true
        if (!value.isEmpty()) { opts.pgoProfileFile = value }
        return true
    }
    if (arg == "--pgo-instr-use") {
        opts.enablePgoInstrUse = true
        opts.pgoProfileFile = value
        return true
    }
    if (arg == "--backend") {
        if (value != "llvm") {
            eprintln("error: unsupported --backend value '${value}'")
            return false
        }
        opts.backend = BackendType.CJNATIVE
        addFrontendSeparated(opts, arg, value)
        return true
    }
    if (arg == "--import-path") { addFrontendSeparated(opts, arg, value); return true }
    if (arg == "--plugin") { addFrontendSeparated(opts, arg, value); return true }
    if (arg == "--common-part-cjo") {
        if (let Some(path) <- opts.ValidateInputFilePath(value)) {
            opts.commonPartCjos.add(path)
            addFrontendSeparated(opts, arg, path)
            return true
        }
        return false
    }
    if (arg == "--common-part-chir") {
        if (let Some(path) <- opts.ValidateInputFilePath(value)) {
            opts.commonPartChirs.add(path)
            addFrontendSeparated(opts, arg, path)
            return true
        }
        return false
    }
    if (arg == "--cfg") { addFrontendSeparated(opts, arg, value); return true }
    if (arg == "--cangjie-home") {
        opts.cangjieHome = value
        addFrontendSeparated(opts, arg, value)
        return true
    }
    if (arg == "-j" || arg == "--jobs") {
        if (let Some(parsed) <- ParseJobsValue(arg, value)) {
            opts.jobs = parsed
            addFrontendSeparated(opts, arg, value)
            return true
        }
        return false
    }
    if (arg == "--aggressive-parallel-compile" || arg == "--apc") {
        if (value.isEmpty()) {
            opts.aggressiveParallelCompileWithoutArg = true
            addFrontendFlag(opts, arg)
            return true
        }
        if (let Some(parsed) <- ParseJobsValue(arg, value)) {
            opts.aggressiveParallelCompile = Int64(parsed)
            UtilsSemaphore.Get().SetCount(Int64(parsed + 2u64))
            addFrontendJoined(opts, arg, value)
            return true
        }
        return false
    }
    if (arg == "--int-overflow") {
        if (value != "throwing" && value != "wrapping" && value != "saturating") {
            eprintln("error: unsupported --int-overflow value '${value}'")
            return false
        }
        addFrontendSeparated(opts, arg, value)
        return true
    }
    if (arg == "--obf-level") {
        if (let Some(parsed) <- TryParseInt64(value)) {
            if (parsed >= OBFUCATION_LEVEL_MIN && parsed <= OBFUCATION_LEVEL_MAX) {
                opts.obfuscationLevel = parsed
                return true
            }
        }
        eprintln("error: --obf-level expects an integer in [1, 9].")
        return false
    }
    if (arg == "--obf-seed") {
        if (let Some(parsed) <- TryParseInt64(value)) { opts.obfuscationSeed = parsed; return true }
        return false
    }
    if (arg == "--obf-sym-input-mapping") { opts.layoutObfInputSymMappingFiles = value; return true }
    if (arg == "--obf-sym-output-mapping") { opts.layoutObfOutputSymMappingFile = value; return true }
    if (arg == "--obf-apply-mapping-file") {
        if (let Some(path) <- opts.ValidateInputFilePath(value)) {
            opts.layoutObfUserMappingFile = path
            return true
        }
        return false
    }
    if (arg == "--obf-sym-prefix") { opts.layoutObfSymPrefix = value; return true }
    if (arg == "--obf-config") {
        if (let Some(path) <- opts.ValidateInputFilePath(value)) {
            opts.obfuscationConfigFile = path
            return true
        }
        return false
    }
    return ForwardNonDriverOption(opts, optionArg)
}

// Group-based auto-forward, mirroring C++ GlobalOptions::GenerateFrontendOptions
// (src/Option/Option.cpp:993-1021): any option recognized by the driver-mode option table that
// does NOT belong to the DRIVER group (and is not OUTPUT_FILE) is forwarded verbatim to
// cjc-frontend, instead of being rejected by the hand-written allowlist. The driver-mode table
// (src/Option/OptionTable.cpp:145) rejects FRONTEND-group-only options, so passing one still
// produces C++'s "invalid option" diagnostic.

private func ForwardNonDriverOption(opts: DriverOptions, optArg: OptionArgInstance): Bool {
    let info = optArg.info
    // OUTPUT_FILE and DRIVER-group options are consumed by the driver, never forwarded
    // (src/Option/Option.cpp:1004-1009). The hand-written parser above already handles all
    // such options; reaching here for one would indicate a recognized-but-unhandled driver
    // option, so fall through to the error below.
    if (info.GetID() != ID.OUTPUT_FILE && !info.BelongsGroup(Group.DRIVER)) {
        opts.frontendForwardArgs.add(optArg.name)
        if (info.GetKind() == Kind.SEPARATED) {
            opts.frontendForwardArgs.add(optArg.value)
        }
        return true
    }
    eprintln("error: unrecognized driver option '${optArg.str}'")
    return false
}

private func ParseOutputType(opts: DriverOptions, value: String): Bool {
    if (value == "exe") { opts.outputMode = OutputMode.EXECUTABLE; opts.enableHotReload = false; opts.enableOutputType = true; return true }
    if (value == "staticlib") { opts.outputMode = OutputMode.STATIC_LIB; opts.enableHotReload = false; opts.enableOutputType = true; return true }
    if (value == "dylib") { opts.outputMode = OutputMode.SHARED_LIB; opts.enableHotReload = false; opts.enableOutputType = true; return true }
    if (value == "chir") { opts.outputMode = OutputMode.CHIR; opts.enableHotReload = false; opts.enableOutputType = true; return true }
    if (value == "obj") { opts.outputMode = OutputMode.OBJ; opts.enableHotReload = false; opts.enableOutputType = true; return true }
    if (value == "hotreload") {
        opts.outputMode = OutputMode.SHARED_LIB
        opts.enableHotReload = true
        opts.linkStaticStd = false
        opts.enableOutputType = true
        return true
    }
    eprintln("error: unsupported --output-type value '${value}'")
    return false
}

private func ParseCompileTarget(opts: DriverOptions, value: String): Bool {
    if (value == "exe") { opts.compileTarget = CompileTarget.EXECUTABLE; return true }
    if (value == "staticlib") { opts.compileTarget = CompileTarget.STATIC_LIB; return true }
    if (value == "dylib") { opts.compileTarget = CompileTarget.SHARED_LIB; return true }
    eprintln("error: unsupported --compile-target value '${value}'")
    return false
}

public func IsFrontendInput(input: String): Bool {
    let extension = FileUtil.GetFileExtension(input)
    return !(extension == "o" || extension == "obj" || extension == "bc" || extension == "a" ||
        extension == "so" || extension == "dylib" || extension == "dll")
}

public func ClassifyInput(opts: DriverOptions, input: String, index: UInt64): Bool {
    let extension = FileUtil.GetFileExtension(input)
    if (extension == "cj") {
        if (opts.compilePackage) {
            let diag = DiagnosticEngine()
            diag.DiagnoseRefactor(
                DiagKindRefactor.driver_unsupport_compile_package_with_source_file,
                DEFAULT_POSITION,
                arguments: [input]
            ).Emit()
            return false
        }
        if (let None <- opts.ValidateInputFilePath(input)) {
            return false
        }
        opts.srcFiles.add(input)
        return true
    } else if (extension == "o" || extension == "obj" || extension == "a") {
        if (let Some(path) <- opts.ValidateInputFilePath(input)) {
            opts.inputObjs.add(path)
            opts.orderedInputObjs.add(OrderedInput(path, index))
            return true
        }
        return false
    } else if (extension == "bc") {
        if (let Some(path) <- opts.ValidateInputFilePath(input)) {
            opts.bcInputFiles.add(path)
            return true
        }
        return false
    } else if (extension == "cjo") {
        if (let Some(path) <- opts.ValidateInputFilePath(input)) {
            if (!opts.inputCjoFile.isEmpty()) {
                eprintln("error: only one cjo input is accepted with '--scan-dependency'.")
                return false
            }
            opts.inputCjoFile = path
            return true
        }
        return false
    } else if (extension == "so" || extension == "dylib" || extension == "dll") {
        if (let Some(path) <- opts.ValidateInputFilePath(input)) {
            opts.inputLibraries.add(path)
            opts.orderedLibraries.add(OrderedInput(path, index))
            return true
        }
        return false
    } else if (FileUtil.FileExist(input) && FileUtil.IsDir(input)) {
        if (!opts.compilePackage) {
            eprintln("error: source file path '${input}' requires '-p' or '--package'.")
            return false
        }
        if (let Some(path) <- opts.ValidateDirectoryPath(input)) {
            opts.packagePaths.add(path)
            return true
        }
        return false
    } else if (let Some(_) <- opts.ValidateInputFilePath(input)) {
        if (opts.compilePackage) {
            eprintln("error: source file '${input}' cannot be used with '-p' or '--package'.")
            return false
        }
        opts.srcFiles.add(input)
        return true
    }
    return false
}

public func TryParseTriple(value: String): Option<TripleInfo> {
    let info = TripleInfo()
    info.vendor = Vendor.UNKNOWN
    info.apiLevel = ""
    let parts = SplitString(value.toAsciiLower(), "-")
    if (parts.size != 3 && parts.size != 4) {
        return None
    }
    if (parts[0] == "x86_64" || parts[0] == "amd64") {
        info.arch = ArchType.X86_64
    } else if (parts[0] == "aarch64" || parts[0] == "arm64") {
        info.arch = ArchType.AARCH64
    } else if (parts[0] == "arm") {
        info.arch = ArchType.ARM32
    } else {
        return None
    }

    if (parts.size >= 3 && parts[1] == "apple") {
        info.vendor = Vendor.APPLE
        if (parts[2].startsWith("ios")) {
            info.os = OSType.IOS
            info.apiLevel = parts[2][3..]
            if (info.apiLevel.isEmpty()) { info.apiLevel = "11" }
            if (parts.size == 4 && parts[3] == "simulator") {
                info.env = EnvironmentType.SIMULATOR
                return info
            }
            if (parts.size == 3) {
                info.env = EnvironmentType.NOT_AVAILABLE
                return info
            }
            return None
        }
        if (parts[2] == "darwin" && parts.size == 3) {
            info.os = OSType.DARWIN
            info.env = EnvironmentType.NOT_AVAILABLE
            return info
        }
        return None
    }

    let osPart = parts[parts.size - 2]
    if (osPart == "linux") {
        info.os = OSType.LINUX
    } else if (osPart == "windows" || osPart == "w64") {
        info.os = OSType.WINDOWS
    } else if (osPart == "darwin") {
        info.os = OSType.DARWIN
    } else if (osPart == "ios") {
        info.os = OSType.IOS
    } else {
        return None
    }

    let envPart = parts[parts.size - 1]
    if (envPart == "ohos") {
        info.env = EnvironmentType.OHOS
    } else if (envPart == "android") {
        info.env = EnvironmentType.ANDROID
        info.apiLevel = "26"
    } else if (envPart.startsWith("android")) {
        info.env = EnvironmentType.ANDROID
        info.apiLevel = envPart[7..]
        if (let Some(api) <- TryParseUInt64(info.apiLevel)) {
            if (api < 23u64 || api > 10000u64) {
                return None
            }
        } else {
            return None
        }
    } else if (envPart == "gnu" || envPart == "mingw32") {
        info.env = EnvironmentType.GNU
    } else if (envPart == "simulator") {
        info.env = EnvironmentType.SIMULATOR
    } else {
        return None
    }
    return info
}

public func ParseTriple(value: String): TripleInfo {
    if (let Some(info) <- TryParseTriple(value)) {
        return info
    }
    let info = TripleInfo()
    info.arch = ArchType.UNKNOWN
    info.vendor = Vendor.UNKNOWN
    info.os = OSType.UNKNOWN
    info.env = EnvironmentType.NOT_AVAILABLE
    info.apiLevel = ""
    return info
}

public func IsSupportedTargetCPU(arch: ArchType, cpu: String): Bool {
    if (cpu == "generic" || cpu == "native") {
        return true
    }
    if (arch == ArchType.X86_64) {
        return X86_64_TARGET_CPUS.contains(cpu)
    }
    if (arch == ArchType.AARCH64) {
        return AARCH64_TARGET_CPUS.contains(cpu)
    }
    return false
}
