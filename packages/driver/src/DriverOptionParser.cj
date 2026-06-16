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

    func advance(): Unit { index++ }

    func takeValue(optionName: String): Option<String> {
        if (index + 1 >= args.size) {
            eprintln("error: missing value for ${optionName}")
            return None
        }
        index += 1
        return args[index]
    }
}

public func ParseDriverArgs(opts: DriverOptions, arguments: Array<String>): Bool {
    let cursor = ParseCursor(arguments)
    var inputIndex: UInt64 = 0u64
    var ok = true
    while (cursor.hasNext()) {
        let arg = cursor.current()
        if (arg == "--") {
            cursor.advance()
            while (cursor.hasNext()) {
                ClassifyInput(opts, cursor.current(), inputIndex)
                inputIndex++
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
        ClassifyInput(opts, arg, inputIndex)
        inputIndex++
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

private func ParseOption(opts: DriverOptions, cursor: ParseCursor, arg: String): Bool {
    if (arg == "-h" || arg == "--help") { opts.showUsage = true; return true }
    if (arg == "-v" || arg == "--version") { opts.printVersionOnly = true; return true }
    if (arg == "-V" || arg == "--verbose") { opts.enableVerbose = true; return true }
    if (arg == "-g") { opts.enableCompileDebug = true; return true }
    if (arg == "-s" || arg == "--strip-all") { opts.stripSymbolTable = true; return true }
    if (arg == "--static") { opts.linkStatic = true; return true }
    if (arg == "--static-std") { opts.linkStaticStd = true; return true }
    if (arg == "--dy-std") { opts.linkStaticStd = false; return true }
    if (arg == "--static-libs") { opts.linkStaticLibs = true; return true }
    if (arg == "--dy-libs") { opts.linkStaticLibs = false; return true }
    if (arg == "--set-runtime-rpath") { opts.useRuntimeRpath = true; return true }
    if (arg == "--sanitize-set-rpath") { opts.sanitizerEnableRpath = true; return true }
    if (arg == "--scan-dependency") { opts.scanDepPkg = true; return true }
    if (arg == "-p" || arg == "--package") { opts.compilePackage = true; return true }
    if (arg == "--no-sub-pkg") { opts.noSubPkg = true; return true }
    if (arg == "--profile-compile-time") { opts.enableTimer = true; return true }
    if (arg == "--profile-compile-memory") { opts.enableMemoryCollect = true; return true }
    if (arg == "--coverage") { opts.enableCoverage = true; return true }
    if (arg == "--fast-math") { opts.fastMathMode = true; return true }
    if (arg == "--experimental") { opts.experimentalMode = true; return true }
    if (arg == "--compile-macro") { opts.compileMacro = true; return true }
    if (arg == "--test") { opts.parseTest = true; return true }
    if (arg == "--test-only") { opts.compileTestsOnly = true; return true }
    if (arg == "--incremental-compile") { opts.enIncrementalCompilation = true; return true }
    if (arg == "--compile-as-exe") { opts.compileTarget = CompileTarget.EXECUTABLE; return true }
    if (ParseOptimization(opts, arg)) { return true }
    if (ParseObfuscationFlag(opts, cursor, arg)) { return true }
    return ParseOptionWithValue(opts, cursor, arg)
}

private func ParseOptimization(opts: DriverOptions, arg: String): Bool {
    if (arg == "-O0") { return opts.SetOptimizationLevel(OptimizationLevel.O0) }
    if (arg == "-O" || arg == "-O1") { return opts.SetOptimizationLevel(OptimizationLevel.O1) }
    if (arg == "-O2") { return opts.SetOptimizationLevel(OptimizationLevel.O2) }
    if (arg == "-O3") { return opts.SetOptimizationLevel(OptimizationLevel.O3) }
    if (arg == "-Os") { return opts.SetOptimizationLevel(OptimizationLevel.Os) }
    if (arg == "-Oz") { return opts.SetOptimizationLevel(OptimizationLevel.Oz) }
    if (arg.startsWith("-O") && arg.size > 2) {
        let raw = arg[2..]
        if (let Some(parsed) <- TryParseInt64(raw)) {
            if (parsed <= 0) { return opts.SetOptimizationLevel(OptimizationLevel.O0) }
            if (parsed == 1) { return opts.SetOptimizationLevel(OptimizationLevel.O1) }
            if (parsed == 2) { return opts.SetOptimizationLevel(OptimizationLevel.O2) }
            return opts.SetOptimizationLevel(OptimizationLevel.O3)
        }
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
    if (arg == "-o" || arg == "--output" || arg.startsWith("--output=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--output")) { opts.output = value; return true }
        return false
    }
    if (arg == "--output-dir" || arg.startsWith("--output-dir=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--output-dir")) { opts.outputDir = value; return true }
        return false
    }
    if (arg == "--module-name" || arg.startsWith("--module-name=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--module-name")) { opts.moduleName = value; return true }
        return false
    }
    if (arg == "-B" || arg == "--toolchain" || arg.startsWith("--toolchain=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--toolchain")) { opts.toolChainPaths.add(value); return true }
        return false
    }
    if (arg == "-L" || arg == "--library-path" || arg.startsWith("--library-path=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--library-path")) { opts.librarySearchPaths.add(value); return true }
        return false
    }
    if (arg.startsWith("-L") && arg.size > 2) { opts.librarySearchPaths.add(arg[2..]); return true }
    if (arg == "-l" || arg == "--library" || arg.startsWith("--library=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--library")) { opts.libraries.add(value); return true }
        return false
    }
    if (arg.startsWith("-l") && arg.size > 2) { opts.libraries.add(arg[2..]); return true }
    if (arg == "--link-option" || arg.startsWith("--link-option=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--link-option")) { opts.linkOption.add(value); return true }
        return false
    }
    if (arg == "--link-options" || arg.startsWith("--link-options=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--link-options")) { opts.linkOptions.add(value); return true }
        return false
    }
    if (arg == "--target" || arg.startsWith("--target=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--target")) { opts.target = ParseTriple(value); opts.backend = opts.target.backend; return true }
        return false
    }
    if (arg == "--target-cpu" || arg.startsWith("--target-cpu=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--target-cpu")) { opts.targetCPU = value; return true }
        return false
    }
    if (arg == "--sysroot" || arg.startsWith("--sysroot=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--sysroot")) { opts.sysroot = value; opts.customizedSysroot = true; return true }
        return false
    }
    if (arg == "--save-temps" || arg.startsWith("--save-temps=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--save-temps")) { opts.saveTemps = true; opts.tempFolderPath = value; return true }
        return false
    }
    if (arg == "--diagnostic-format" || arg.startsWith("--diagnostic-format=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--diagnostic-format")) { opts.diagFormat = value; return true }
        return false
    }
    if (arg == "--error-count-limit" || arg.startsWith("--error-count-limit=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--error-count-limit")) {
            if (value == "all") { opts.errorCountLimit = UInt64.Max; return true }
            if (let Some(parsed) <- TryParseUInt64(value)) { opts.errorCountLimit = parsed; return true }
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
        if (let Some(value) <- readOptionValue(cursor, arg, "--output-type")) { return ParseOutputType(opts, value) }
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
        if (let Some(value) <- readOptionValue(cursor, arg, "--obf-apply-mapping-file")) { opts.layoutObfUserMappingFile = value; return true }
        return false
    }
    if (arg == "--obf-sym-prefix" || arg.startsWith("--obf-sym-prefix=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--obf-sym-prefix")) { opts.layoutObfSymPrefix = value; return true }
        return false
    }
    if (arg == "--obf-config" || arg.startsWith("--obf-config=")) {
        if (let Some(value) <- readOptionValue(cursor, arg, "--obf-config")) { opts.obfuscationConfigFile = value; return true }
        return false
    }
    eprintln("warning: unrecognized driver option '${arg}' is preserved for frontend compatibility.")
    opts.inputLinkOptions.add(arg)
    return true
}

private func ParseOutputType(opts: DriverOptions, value: String): Bool {
    if (value == "exe") { opts.outputMode = OutputMode.EXECUTABLE; return true }
    if (value == "staticlib") { opts.outputMode = OutputMode.STATIC_LIB; return true }
    if (value == "dylib") { opts.outputMode = OutputMode.SHARED_LIB; return true }
    eprintln("error: unsupported --output-type value '${value}'")
    return false
}

private func ParseCompileTarget(opts: DriverOptions, value: String): Bool {
    if (value == "exe") { opts.compileTarget = CompileTarget.EXECUTABLE; return true }
    if (value == "staticlib") { opts.compileTarget = CompileTarget.STATIC_LIB; return true }
    if (value == "dylib") { opts.compileTarget = CompileTarget.DYNAMIC_LIB; return true }
    eprintln("error: unsupported --compile-target value '${value}'")
    return false
}

public func ClassifyInput(opts: DriverOptions, input: String, index: UInt64): Unit {
    let extension = FileUtil.GetFileExtension(input)
    if (extension == "cj") {
        opts.srcFiles.add(input)
    } else if (extension == "o" || extension == "obj") {
        opts.inputObjs.add(input)
        opts.orderedInputObjs.add(OrderedInput(input, index))
    } else if (extension == "bc") {
        opts.bcInputFiles.add(input)
    } else if (extension == "a" || extension == "so" || extension == "dylib" || extension == "dll") {
        opts.inputLibraries.add(input)
        opts.orderedLibraries.add(OrderedInput(input, index))
    } else {
        opts.srcFiles.add(input)
    }
}

public func ParseTriple(value: String): TripleInfo {
    let info = TripleInfo()
    info.raw = value
    let lower = value.toAsciiLower()
    if (lower.contains("x86_64") || lower.contains("amd64")) {
        info.arch = ArchType.X86_64
    } else if (lower.contains("aarch64") || lower.contains("arm64")) {
        info.arch = ArchType.AARCH64
    } else if (lower.contains("arm")) {
        info.arch = ArchType.ARM32
    } else {
        info.arch = ArchType.UNKNOWN
    }
    if (lower.contains("windows") || lower.contains("mingw")) {
        info.os = OSType.WINDOWS
    } else if (lower.contains("darwin") || lower.contains("macos")) {
        info.os = OSType.DARWIN
    } else if (lower.contains("ios")) {
        info.os = OSType.IOS
    } else if (lower.contains("linux") || lower.contains("ohos") || lower.contains("android")) {
        info.os = OSType.LINUX
    } else {
        info.os = OSType.UNKNOWN
    }
    if (lower.contains("ohos")) {
        info.env = EnvironmentType.OHOS
    } else if (lower.contains("android")) {
        info.env = EnvironmentType.ANDROID
    } else if (lower.contains("mingw")) {
        info.env = EnvironmentType.GNU
    } else if (lower.contains("gnu")) {
        info.env = EnvironmentType.GNU
    } else if (lower.contains("simulator")) {
        info.env = EnvironmentType.SIMULATOR
    } else {
        info.env = EnvironmentType.NOT_AVAILABLE
    }
    info.backend = BackendType.CJNATIVE
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
