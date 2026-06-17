package cangjie_compiler::driver

import std.collection.*
import std.convert.*

private class ParseCursor {
    let args: Array<String>
    var index: Int64 = 1

    init(args: Array<String>) {
        this.args = args
    }

    func hasNext(): Bool { return index < args.size }

    func current(): String { return args[index] }

    func orderIndex(): UInt64 { return UInt64(index - 1) }

    func advance(): Unit { index++ }

    func takeValue(optionName: String): Option<String> {
        if (index + 1 >= args.size) {
            eprintln("error: missing value for ${optionName}")
            return None
        }
        index += 1
        return args[index]
    }

    func takeOptionalValue(): Option<String> {
        if (index + 1 >= args.size) {
            return None
        }
        let candidate = args[index + 1]
        if (candidate.startsWith("-")) {
            return None
        }
        index += 1
        return Some(args[index])
    }
}

public func ParseDriverArgs(opts: DriverOptions, arguments: Array<String>): Bool {
    let cursor = ParseCursor(arguments)
    var ok = true
    while (cursor.hasNext()) {
        let arg = cursor.current()
        if (arg == "--") {
            cursor.advance()
            while (cursor.hasNext()) {
                let classified = ClassifyInput(opts, cursor.current(), cursor.orderIndex())
                ok = ok && classified
                if (IsFrontendInput(cursor.current())) {
                    opts.frontendForwardArgs.add(cursor.current())
                }
                cursor.advance()
            }
            break
        }
        if (arg.startsWith("-")) {
            let parsed = ParseOption(opts, cursor, arg)
            ok = ok && parsed
            cursor.advance()
            continue
        }
        let classified = ClassifyInput(opts, arg, cursor.orderIndex())
        ok = ok && classified
        if (IsFrontendInput(arg)) {
            opts.frontendForwardArgs.add(arg)
        }
        cursor.advance()
    }
    return ok
}

private func optionValueInline(arg: String, optionName: String): Option<String> {
    let prefix = optionName + "="
    if (arg.startsWith(prefix)) {
        return arg[prefix.size..]
    }
    return None
}

private func readOptionValue(cursor: ParseCursor, arg: String, longName: String): Option<String> {
    if (let Some(value) <- optionValueInline(arg, longName)) {
        return value
    }
    return cursor.takeValue(longName)
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

private func setPackageSourcePath(opts: DriverOptions, value: String): Unit {
    opts.moduleSrcPath = value
    addFrontendSeparated(opts, "--module-src-path", value)
}

private func canonicalSpelling(arg: String, shortName: String, longName: String): String {
    return if (arg == shortName || arg.startsWith(shortName) && !shortName.isEmpty() && !shortName.startsWith("--")) {
        shortName
    } else {
        longName
    }
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

private func ParseJobsValue(value: String): Option<UInt64> {
    if (let Some(parsed) <- TryParseUInt64(value)) {
        if (parsed >= 1u64) {
            return parsed
        }
    }
    return None
}

private func ParseOption(opts: DriverOptions, cursor: ParseCursor, arg: String): Bool {
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
    if (arg == "-p" || arg == "--package" || arg.startsWith("--package=")) {
        opts.compilePackage = true
        addFrontendFlag(opts, "--package")
        if (let Some(inlinePackagePath) <- optionValueInline(arg, "--package")) {
            setPackageSourcePath(opts, inlinePackagePath)
        } else if (let Some(separatedPackagePath) <- cursor.takeOptionalValue()) {
            setPackageSourcePath(opts, separatedPackagePath)
        }
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
        opts.emitCHIRPhase = "opt"
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
    if (ParseOptimization(opts, arg)) { return true }
    if (ParseWarningFlag(opts, cursor, arg)) { return true }
    if (ParseObfuscationFlag(opts, cursor, arg)) { return true }
    return ParseOptionWithValue(opts, cursor, arg)
}

private func ParseOptimization(opts: DriverOptions, arg: String): Bool {
    if (arg == "-O0") { addFrontendFlag(opts, arg); return opts.SetOptimizationLevel(OptimizationLevel.O0) }
    if (arg == "-O" || arg == "-O1") { addFrontendFlag(opts, arg); return opts.SetOptimizationLevel(OptimizationLevel.O1) }
    if (arg == "-O2") { addFrontendFlag(opts, arg); return opts.SetOptimizationLevel(OptimizationLevel.O2) }
    if (arg == "-O3") { addFrontendFlag(opts, arg); return opts.SetOptimizationLevel(OptimizationLevel.O3) }
    if (arg == "-Os") { addFrontendFlag(opts, arg); return opts.SetOptimizationLevel(OptimizationLevel.Os) }
    if (arg == "-Oz") { addFrontendFlag(opts, arg); return opts.SetOptimizationLevel(OptimizationLevel.Oz) }
    if (arg.startsWith("-O") && arg.size > 2) {
        let raw = arg[2..]
        if (let Some(parsed) <- TryParseInt64(raw)) {
            addFrontendFlag(opts, arg)
            if (parsed <= 0) { return opts.SetOptimizationLevel(OptimizationLevel.O0) }
            if (parsed == 1) { return opts.SetOptimizationLevel(OptimizationLevel.O1) }
            if (parsed == 2) { return opts.SetOptimizationLevel(OptimizationLevel.O2) }
            return opts.SetOptimizationLevel(OptimizationLevel.O3)
        }
    }
    return false
}

private func ParseWarningFlag(opts: DriverOptions, cursor: ParseCursor, arg: String): Bool {
    if (arg == "-Woff" || arg == "--warn-off" || arg.startsWith("--warn-off=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--warn-off")) {
            addFrontendSeparated(opts, if (arg == "-Woff") { "-Woff" } else { "--warn-off" }, value)
            return true
        }
        return false
    }
    if (arg == "-Won" || arg == "--warn-on" || arg.startsWith("--warn-on=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--warn-on")) {
            addFrontendSeparated(opts, if (arg == "-Won") { "-Won" } else { "--warn-on" }, value)
            return true
        }
        return false
    }
    if (arg.startsWith("-Woff") && arg.size > 5) {
        addFrontendSeparated(opts, "-Woff", arg[5..])
        return true
    }
    if (arg.startsWith("-Won") && arg.size > 4) {
        addFrontendSeparated(opts, "-Won", arg[4..])
        return true
    }
    return false
}

private func ParseObfuscationFlag(opts: DriverOptions, cursor: ParseCursor, arg: String): Bool {
    let _ = cursor
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

private func ParseOptionWithValue(opts: DriverOptions, cursor: ParseCursor, arg: String): Bool {
    let optionIndex = cursor.orderIndex()
    if (arg.startsWith("-o") && arg.size > 2) {
        opts.output = arg[2..]
        return true
    }
    if (arg == "-o" || arg == "--output" || arg.startsWith("--output=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--output")) { opts.output = value; return true }
        return false
    }
    if (arg == "--output-dir" || arg.startsWith("--output-dir=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--output-dir")) {
            opts.outputDir = value
            addFrontendSeparated(opts, "--output-dir", value)
            return true
        }
        return false
    }
    if (arg == "--deserialize-chir-and-dump" || arg.startsWith("--deserialize-chir-and-dump=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--deserialize-chir-and-dump")) {
            opts.frontendOnlyAction = true
            addFrontendSeparated(opts, "--deserialize-chir-and-dump", value)
            return true
        }
        return false
    }
    if (arg == "--module-name" || arg.startsWith("--module-name=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--module-name")) {
            opts.moduleName = value
            addFrontendSeparated(opts, "--module-name", value)
            return true
        }
        return false
    }
    if (arg == "--module-src-path" || arg.startsWith("--module-src-path=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--module-src-path")) {
            opts.moduleSrcPath = value
            addFrontendSeparated(opts, "--module-src-path", value)
            return true
        }
        return false
    }
    if (arg.startsWith("-B") && arg.size > 2) {
        if (let Some(path) <- opts.CheckDirectoryPath(arg[2..])) { opts.toolChainPaths.add(path) }
        return true
    }
    if (arg == "-B" || arg == "--toolchain" || arg.startsWith("--toolchain=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--toolchain")) {
            if (let Some(path) <- opts.CheckDirectoryPath(value)) { opts.toolChainPaths.add(path) }
            return true
        }
        return false
    }
    if (arg == "-L" || arg == "--library-path" || arg.startsWith("--library-path=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--library-path")) {
            if (let Some(path) <- opts.CheckDirectoryPath(value)) { opts.librarySearchPaths.add(path) }
            return true
        }
        return false
    }
    if (arg.startsWith("-L") && arg.size > 2) {
        if (let Some(path) <- opts.CheckDirectoryPath(arg[2..])) { opts.librarySearchPaths.add(path) }
        return true
    }
    if (arg == "-l" || arg == "--library" || arg.startsWith("--library=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--library")) {
            opts.libraries.add(value)
            opts.orderedLibraries.add(OrderedInput("-l" + value, optionIndex))
            return true
        }
        return false
    }
    if (arg.startsWith("-l") && arg.size > 2) {
        let value = arg[2..]
        opts.libraries.add(value)
        opts.orderedLibraries.add(OrderedInput("-l" + value, optionIndex))
        return true
    }
    if (arg == "--link-option" || arg.startsWith("--link-option=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--link-option")) {
            opts.linkOption.add(value)
            opts.orderedLinkOptions.add(OrderedInput(value, optionIndex))
            return true
        }
        return false
    }
    if (arg == "--link-options" || arg.startsWith("--link-options=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--link-options")) {
            opts.linkOptions.add(value)
            opts.orderedLinkOptionGroups.add(OrderedInput(value, optionIndex))
            return true
        }
        return false
    }
    if (arg == "--target" || arg.startsWith("--target=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--target")) {
            if (let Some(triple) <- TryParseTriple(value)) {
                opts.target = triple
                addFrontendSeparated(opts, "--target", value)
                return true
            }
            eprintln("error: unsupported target triple '${value}'")
        }
        return false
    }
    if (arg == "--target-cpu" || arg.startsWith("--target-cpu=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--target-cpu")) { opts.targetCPU = value; return true }
        return false
    }
    if (arg == "--sysroot" || arg.startsWith("--sysroot=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--sysroot")) {
            if (let Some(path) <- opts.CheckDirectoryPath(value)) {
                opts.sysroot = path
                opts.customizedSysroot = true
            }
            return true
        }
        return false
    }
    if (arg == "--save-temps" || arg.startsWith("--save-temps=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--save-temps")) { opts.saveTemps = true; opts.tempFolderPath = value; return true }
        return false
    }
    if (arg == "--diagnostic-format" || arg.startsWith("--diagnostic-format=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--diagnostic-format")) {
            if (value != "json" && value != "noColor" && value != "default") {
                eprintln("error: unsupported --diagnostic-format value '${value}'")
                return false
            }
            opts.diagFormat = value
            addFrontendSeparated(opts, "--diagnostic-format", value)
            return true
        }
        return false
    }
    if (arg == "--error-count-limit" || arg.startsWith("--error-count-limit=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--error-count-limit")) {
            if (value == "all") {
                opts.errorCountLimit = UInt64.Max
                addFrontendSeparated(opts, "--error-count-limit", value)
                return true
            }
            if (let Some(parsed) <- TryParseUInt64(value)) {
                opts.errorCountLimit = parsed
                addFrontendSeparated(opts, "--error-count-limit", value)
                return true
            }
            eprintln("error: invalid value for --error-count-limit: ${value}")
        }
        return false
    }
    if (arg == "--lto" || arg.startsWith("--lto=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--lto")) {
            if (value == "full") { opts.ltoMod = LTOMode.FULL_LTO; return true }
            if (value == "thin") { opts.ltoMod = LTOMode.THIN_LTO; return true }
            eprintln("error: unsupported --lto value '${value}'")
        }
        return false
    }
    if (arg == "--output-type" || arg.startsWith("--output-type=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--output-type")) {
            if (!ParseOutputType(opts, value)) { return false }
            addFrontendSeparated(opts, "--output-type", value)
            return true
        }
        return false
    }
    if (arg.startsWith("--emit-chir=")) {
        if (let Some(value) <- optionValueInline(arg, "--emit-chir")) {
            if (value.isEmpty() || value == "opt" || value == "raw") {
                opts.emitCHIRPhase = if (value.isEmpty()) { "opt" } else { value }
                addFrontendJoined(opts, "--emit-chir", value)
                return true
            }
            eprintln("error: unsupported --emit-chir value '${value}'")
        }
        return false
    }
    if (arg == "--compile-target" || arg.startsWith("--compile-target=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--compile-target")) { return ParseCompileTarget(opts, value) }
        return false
    }
    if (arg == "--opt-options" || arg.startsWith("--opt-options=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--opt-options")) { opts.optArg = value; return true }
        return false
    }
    if (arg == "--llc-options" || arg.startsWith("--llc-options=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--llc-options")) { opts.llcArg = value; return true }
        return false
    }
    if (arg == "--opt-pass-options" || arg.startsWith("--opt-pass-options=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--opt-pass-options")) {
            opts.optPassOptions = value
            addFrontendSeparated(opts, "--opt-pass-options", value)
            return true
        }
        return false
    }
    if (arg == "--sanitize" || arg.startsWith("--sanitize=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--sanitize")) {
            if (!ParseSanitizer(opts, value)) { return false }
            addFrontendSeparated(opts, "--sanitize", value)
            return true
        }
        return false
    }
    if (arg == "--stack-trace-format" || arg.startsWith("--stack-trace-format=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--stack-trace-format")) {
            if (value != "default" && value != "simple" && value != "all") {
                eprintln("error: unsupported --stack-trace-format value '${value}'")
                return false
            }
            opts.stackTraceFormat = "--stack-trace-format=" + value
            return true
        }
        return false
    }
    if (arg == "--lto-keep-pkg-visibility" || arg.startsWith("--lto-keep-pkg-visibility=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--lto-keep-pkg-visibility")) {
            if (value.isEmpty()) {
                opts.ltoHideAllPkgs = true
            } else {
                for (rawPkg in SplitString(value, ",")) {
                    let pkg = rawPkg.trimAscii()
                    if (!pkg.isEmpty()) {
                        opts.ltoVisiblePkgs.add(pkg)
                    }
                }
            }
            return true
        }
        return false
    }
    if (arg == "--pgo-instr-gen" || arg.startsWith("--pgo-instr-gen=")) {
        opts.enablePgoInstrGen = true
        if (arg.startsWith("--pgo-instr-gen=")) {
            if (let Some(value) <- optionValueInline(arg, "--pgo-instr-gen")) {
                opts.pgoProfileFile = value
            }
        }
        return true
    }
    if (arg == "--pgo-instr-use" || arg.startsWith("--pgo-instr-use=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--pgo-instr-use")) {
            opts.enablePgoInstrUse = true
            opts.pgoProfileFile = value
            return true
        }
        return false
    }
    if (arg == "--backend" || arg.startsWith("--backend=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--backend")) {
            if (value != "llvm") {
                eprintln("error: unsupported --backend value '${value}'")
                return false
            }
            opts.backend = BackendType.CJNATIVE
            addFrontendSeparated(opts, "--backend", value)
            return true
        }
        return false
    }
    if (arg == "--import-path" || arg.startsWith("--import-path=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--import-path")) {
            addFrontendSeparated(opts, "--import-path", value)
            return true
        }
        return false
    }
    if (arg == "--plugin" || arg.startsWith("--plugin=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--plugin")) {
            addFrontendSeparated(opts, "--plugin", value)
            return true
        }
        return false
    }
    if (arg == "--common-part-cjo" || arg.startsWith("--common-part-cjo=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--common-part-cjo")) {
            addFrontendSeparated(opts, "--common-part-cjo", value)
            return true
        }
        return false
    }
    if (arg == "--common-part-chir" || arg.startsWith("--common-part-chir=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--common-part-chir")) {
            addFrontendSeparated(opts, "--common-part-chir", value)
            return true
        }
        return false
    }
    if (arg == "--cfg" || arg.startsWith("--cfg=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--cfg")) {
            addFrontendSeparated(opts, "--cfg", value)
            return true
        }
        return false
    }
    if (arg == "--cangjie-home" || arg.startsWith("--cangjie-home=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--cangjie-home")) {
            opts.cangjieHome = value
            addFrontendSeparated(opts, "--cangjie-home", value)
            return true
        }
        return false
    }
    if (arg.startsWith("-j") && arg.size > 2) {
        let value = arg[2..]
        if (let Some(parsed) <- ParseJobsValue(value)) {
            opts.jobs = parsed
            addFrontendSeparated(opts, "-j", value)
            return true
        }
        eprintln("error: --jobs expects a positive integer")
        return false
    }
    if (arg == "-j" || arg == "--jobs" || arg.startsWith("--jobs=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--jobs")) {
            if (let Some(parsed) <- ParseJobsValue(value)) {
                opts.jobs = parsed
                addFrontendSeparated(opts, canonicalSpelling(arg, "-j", "--jobs"), value)
                return true
            }
            eprintln("error: --jobs expects a positive integer")
        }
        return false
    }
    if (arg == "--aggressive-parallel-compile" || arg == "--apc" ||
        arg.startsWith("--aggressive-parallel-compile=") || arg.startsWith("--apc=")) {
        let optionName = if (arg.startsWith("--apc")) { "--apc" } else { "--aggressive-parallel-compile" }
        if (arg == "--aggressive-parallel-compile" || arg == "--apc") {
            opts.aggressiveParallelCompileWithoutArg = true
            addFrontendFlag(opts, optionName)
            return true
        }
        if (let Some(value) <- optionValueInline(arg, optionName)) {
            if (let Some(parsed) <- ParseJobsValue(value)) {
                opts.aggressiveParallelCompile = Int64(parsed)
                addFrontendJoined(opts, optionName, value)
                return true
            }
        }
        eprintln("error: --aggressive-parallel-compile expects a positive integer")
        return false
    }
    if (arg == "--int-overflow" || arg.startsWith("--int-overflow=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--int-overflow")) {
            if (value != "throwing" && value != "wrapping" && value != "saturating") {
                eprintln("error: unsupported --int-overflow value '${value}'")
                return false
            }
            addFrontendSeparated(opts, "--int-overflow", value)
            return true
        }
        return false
    }
    if (arg == "--obf-level" || arg.startsWith("--obf-level=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--obf-level")) {
            if (let Some(parsed) <- TryParseInt64(value)) {
                if (parsed >= OBFUCATION_LEVEL_MIN && parsed <= OBFUCATION_LEVEL_MAX) {
                    opts.obfuscationLevel = parsed
                    return true
                }
            }
            eprintln("error: --obf-level expects an integer in [1, 9].")
        }
        return false
    }
    if (arg == "--obf-seed" || arg.startsWith("--obf-seed=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--obf-seed")) {
            if (let Some(parsed) <- TryParseInt64(value)) { opts.obfuscationSeed = parsed; return true }
        }
        return false
    }
    if (arg == "--obf-sym-input-mapping" || arg.startsWith("--obf-sym-input-mapping=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--obf-sym-input-mapping")) { opts.layoutObfInputSymMappingFiles = value; return true }
        return false
    }
    if (arg == "--obf-sym-output-mapping" || arg.startsWith("--obf-sym-output-mapping=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--obf-sym-output-mapping")) { opts.layoutObfOutputSymMappingFile = value; return true }
        return false
    }
    if (arg == "--obf-apply-mapping-file" || arg.startsWith("--obf-apply-mapping-file=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--obf-apply-mapping-file")) {
            if (let Some(path) <- opts.ValidateInputFilePath(value)) {
                opts.layoutObfUserMappingFile = path
                return true
            }
        }
        return false
    }
    if (arg == "--obf-sym-prefix" || arg.startsWith("--obf-sym-prefix=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--obf-sym-prefix")) { opts.layoutObfSymPrefix = value; return true }
        return false
    }
    if (arg == "--obf-config" || arg.startsWith("--obf-config=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--obf-config")) {
            if (let Some(path) <- opts.ValidateInputFilePath(value)) {
                opts.obfuscationConfigFile = path
                return true
            }
        }
        return false
    }
    eprintln("error: unrecognized driver option '${arg}'")
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
    } else if (extension == "so" || extension == "dylib" || extension == "dll") {
        if (let Some(path) <- opts.ValidateInputFilePath(input)) {
            opts.inputLibraries.add(path)
            opts.orderedLibraries.add(OrderedInput(path, index))
            return true
        }
        return false
    } else if (let Some(_) <- opts.ValidateInputFilePath(input)) {
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
