package cangjie_compiler::driver

import std.collection.*

public let OPTIMIZATION_LEVEL_TO_BACKEND_OPTION: Array<String> = ["-O0", "-O1", "-O2", "-O3", "-Os", "-Oz"]
public type SetFuncType = (String) -> Unit
public type ToolOptionType = (SetFuncType, DriverOptions) -> Unit

private func backendOptimizationOption(level: OptimizationLevel): String {
    return OPTIMIZATION_LEVEL_TO_BACKEND_OPTION[OptimizationLevelIndex(level)]
}

private func effectiveOptimizationLevel(driverOptions: DriverOptions): OptimizationLevel {
    return if (driverOptions.disableBackendOpt) { OptimizationLevel.O0 } else { driverOptions.optimizationLevel }
}

public func SetOptionStringArgs(setOptionHandler: (String) -> Unit, stringArg: String): Unit {
    for (item in SplitString(stringArg, " ")) {
        if (!item.isEmpty()) {
            setOptionHandler(item)
        }
    }
}

public func SetOptionIf(setOptionHandler: (String) -> Unit, condition: Bool, stringArg: String): Unit {
    if (condition) {
        setOptionHandler(stringArg)
    }
}

public func SetMtripleOption(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    let canSetMtriple = driverOptions.IsCrossCompiling() || driverOptions.target.IsMinGW()
    SetOptionIf(setOptionHandler, canSetMtriple, "--mtriple=" + driverOptions.target.GetEffectiveTripleString())
}

public func OPTSetOptimizationLevelOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    let opt = backendOptimizationOption(effectiveOptimizationLevel(driverOptions))
    setOptionHandler("default<" + opt[1..] + ">")
}

public func OPTSetNewPassManagerOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    SetOptionIf(setOptionHandler, driverOptions.enableCoverage, "-insert-gcov-profiling")
    SetOptionIf(setOptionHandler, driverOptions.EnableAsan(), "-asan-module")
    SetOptionIf(setOptionHandler, driverOptions.EnableTsan(), "-tsan")
    SetOptionIf(setOptionHandler, driverOptions.EnableHwAsan(), "-hwasan")
    SetOptionIf(setOptionHandler, !driverOptions.optPassOptions.isEmpty(), "-" + driverOptions.optPassOptions)
}

public func OPTSetCodeObfuscationOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    let obfString = driverOptions.enableStringObfuscation ?? false
    let obfConst = driverOptions.enableConstObfuscation ?? false
    let obfLayout = driverOptions.enableLayoutObfuscation ?? false
    let obfFlatten = driverOptions.enableCFflattenObfuscation ?? false
    let obfBogus = driverOptions.enableCFBogusObfuscation ?? false
    var enabled = false
    if (obfString || obfConst) {
        setOptionHandler("-obf-string=" + if (obfString) { "true" } else { "false" })
        setOptionHandler("-obf-const=" + if (obfConst) { "true" } else { "false" })
        enabled = true
    }
    if (obfLayout) {
        setOptionHandler("--obf-layout=true")
        if (let Some(value) <- driverOptions.layoutObfInputSymMappingFiles) {
            setOptionHandler("-obf-input-symbol-mapping-files=" + value)
        }
        if (let Some(value) <- driverOptions.layoutObfOutputSymMappingFile) {
            setOptionHandler("-obf-output-symbol-mapping-file=" + value)
        }
        if (let Some(value) <- driverOptions.layoutObfUserMappingFile) {
            setOptionHandler("-obf-apply-symbol-mapping=" + value)
        }
        if (let Some(value) <- driverOptions.layoutObfSymPrefix) {
            setOptionHandler("-obf-sym-prefix=" + value)
        }
        setOptionHandler("-obf-export-symbol=" + if (driverOptions.enableObfExportSyms ?? true) { "true" } else { "false" })
        setOptionHandler("-obf-line-number=" + if (driverOptions.enableObfLineNumber ?? false) { "true" } else { "false" })
        setOptionHandler("-obf-source-path=" + if (driverOptions.enableObfSourcePath ?? true) { "true" } else { "false" })
        enabled = true
    }
    if (obfFlatten || obfBogus) {
        setOptionHandler("-control-flow-flatten=" + if (obfFlatten) { "true" } else { "false" })
        setOptionHandler("-control-flow-bogus=" + if (obfBogus) { "true" } else { "false" })
        enabled = true
    }
    if (enabled) {
        setOptionHandler("-obf-level=" + driverOptions.obfuscationLevel.toString())
        if (let Some(seed) <- driverOptions.obfuscationSeed) {
            setOptionHandler("-obf-seed=" + seed.toString())
        }
        if (let Some(config) <- driverOptions.obfuscationConfigFile) {
            setOptionHandler("-obf-config-file=" + config)
        }
    }
}

public func OPTSetLTOOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    if (driverOptions.IsLTOEnabled()) {
        setOptionHandler("--cangjie-lto")
        setOptionHandler("--module-summary")
        setOptionHandler("--module-hash")
    }
}

public func OPTSetVerifyOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    let _ = driverOptions
    setOptionHandler("--only-verify-out")
}

public func OPTSetOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    setOptionHandler("--cangjie-pipeline")
    SetOptionIf(setOptionHandler, driverOptions.EnableAsan(), "-cj-asan=true")
    SetOptionIf(setOptionHandler, driverOptions.EnableTsan(), "-cj-tsan=true")
    SetOptionIf(setOptionHandler, driverOptions.EnableTsan(), "-tsan-instrument-atomics=false")
    SetOptionIf(setOptionHandler, driverOptions.EnableTsan(), "--cj-tsan-support-for-mutexopt")
    SetOptionIf(setOptionHandler, driverOptions.EnableHwAsan(), "-cj-hwasan=true")
    SetOptionIf(setOptionHandler, driverOptions.enableFuncSections, "-function-sections")
    SetOptionIf(setOptionHandler, driverOptions.enableDataSections, "-data-sections")
    SetOptionIf(setOptionHandler, driverOptions.target.env == EnvironmentType.OHOS &&
        driverOptions.target.arch == ArchType.AARCH64, "--cj-ptrauth-backward-cfi=true")
}

public func OPTSetTripleOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    SetMtripleOption(setOptionHandler, driverOptions)
}

public func OPTSetTransparentOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    SetOptionStringArgs(setOptionHandler, driverOptions.optArg)
}

public func OPTSetPgoOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    if (driverOptions.enablePgoInstrGen) {
        setOptionHandler("-pgo-kind=pgo-instr-gen-pipeline")
        if (!driverOptions.pgoProfileFile.isEmpty()) {
            setOptionHandler("-profile-file=" + driverOptions.pgoProfileFile)
        }
        setOptionHandler("-runtime-counter-relocation")
    }
    if (driverOptions.enablePgoInstrUse) {
        setOptionHandler("-pgo-kind=pgo-instr-use-pipeline")
        setOptionHandler("-profile-file=" + driverOptions.pgoProfileFile)
    }
}

public func LLCSetOptimizationLevelOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    var level = effectiveOptimizationLevel(driverOptions)
    if (level == OptimizationLevel.Os || level == OptimizationLevel.Oz) {
        level = OptimizationLevel.O2
    }
    setOptionHandler(backendOptimizationOption(level))
}

public func LLCSetOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    setOptionHandler("--cangjie-pipeline")
    SetOptionIf(setOptionHandler, !driverOptions.enableCompileDebug && !driverOptions.enableCoverage &&
        driverOptions.displayLineInfo, "-disable-debug-info-print")
    setOptionHandler("--relocation-model=pic")
    if (driverOptions.target.arch == ArchType.ARM32 && driverOptions.optimizationLevel == OptimizationLevel.O2) {
        setOptionHandler("--frame-pointer=all")
    } else {
        setOptionHandler("--frame-pointer=non-leaf")
    }
    setOptionHandler(driverOptions.GetStackTraceFormat())
    SetOptionIf(setOptionHandler, driverOptions.fastMathMode, "-fp-contract=fast")
    SetOptionIf(setOptionHandler, driverOptions.enableFuncSections, "-function-sections")
    SetOptionIf(setOptionHandler, driverOptions.enableDataSections, "-data-sections")
    SetOptionIf(setOptionHandler, driverOptions.EnableTsan(), "-tsan")
    SetOptionIf(setOptionHandler, driverOptions.EnableHwAsan(), "-mattr=+tagged-globals")
    SetOptionIf(setOptionHandler, driverOptions.target.env == EnvironmentType.OHOS ||
        driverOptions.target.env == EnvironmentType.ANDROID, "--cj-stack-grow=false")
    if (let Some(cpu) <- driverOptions.targetCPU) {
        if (!cpu.isEmpty()) {
            setOptionHandler("-mcpu=" + cpu)
            SetOptionIf(setOptionHandler, driverOptions.target.arch == ArchType.X86_64, "-mattr=-avx")
        }
    }
    SetOptionIf(setOptionHandler, effectiveOptimizationLevel(driverOptions) == OptimizationLevel.O2,
        "--cj-safepoint-outline=false")
}

public func LLCSetTripleOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    SetMtripleOption(setOptionHandler, driverOptions)
}

public func LLCSetTransparentOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    SetOptionStringArgs(setOptionHandler, driverOptions.llcArg)
}

public func LLDSetLTOOptimizationLevelOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    let level = effectiveOptimizationLevel(driverOptions)
    if (level == OptimizationLevel.O3) { setOptionHandler("--lto-O3") }
    else if (level == OptimizationLevel.Os || level == OptimizationLevel.Oz || level == OptimizationLevel.O2) { setOptionHandler("--lto-O2") }
    else if (level == OptimizationLevel.O1) { setOptionHandler("--lto-O1") }
    else { setOptionHandler("--lto-O0") }
}

public func LLDSetLTOOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    if (driverOptions.IsFullLTOEnabled()) {
        setOptionHandler("--mllvm")
        setOptionHandler("--cangjie-full-lto")
    } else {
        let normalizedPath = FileUtil.NormalizePath(driverOptions.compilationCachedPath)
        if (let Some(absolutePath) <- FileUtil.GetAbsPath(normalizedPath)) {
            setOptionHandler("--thinlto-cache-dir=" + FileUtil.TransferEscapeBacktick(absolutePath))
        }
    }
    if (effectiveOptimizationLevel(driverOptions) == OptimizationLevel.O2) {
        setOptionHandler("--mllvm")
        setOptionHandler("--cj-safepoint-outline=false")
    }
    setOptionHandler("--mllvm")
    setOptionHandler("--cj-lto-opt")
    setOptionHandler("--allow-multiple-definition")
    setOptionHandler("--plugin-opt=no-opaque-pointers")
    if (driverOptions.outputMode == OutputMode.SHARED_LIB) {
        let visible = driverOptions.GetLtoVisiblePkgs()
        if (visible.size > 0) {
            let list = ArrayList<String>()
            for (item in visible) { list.add(item) }
            setOptionHandler("--visible-pkgs=" + JoinStrings(list, ","))
        } else if (driverOptions.ltoHideAllPkgs || driverOptions.IsCompileAsExeEnabled()) {
            setOptionHandler("--visible-pkgs=")
        }
    }
}

public func LLDSetPgoOptions(setOptionHandler: (String) -> Unit, driverOptions: DriverOptions): Unit {
    if (driverOptions.enablePgoInstrGen) {
        setOptionHandler("-cj-pgo-kind=pgo-instr-gen-pipeline")
        if (!driverOptions.pgoProfileFile.isEmpty()) {
            setOptionHandler("-cj-profile-file=" + driverOptions.pgoProfileFile)
        }
    }
    if (driverOptions.enablePgoInstrUse) {
        setOptionHandler("-cj-pgo-kind=pgo-instr-use-pipeline")
        setOptionHandler("-cj-profile-file=" + driverOptions.pgoProfileFile)
    }
}

public func SetOptions(setOptionHandler: SetFuncType, driverOptions: DriverOptions, typeFunc: ToolOptionType): Unit {
    typeFunc(setOptionHandler, driverOptions)
}

public func SetOptions(setOptionHandler: SetFuncType, driverOptions: DriverOptions,
    typeFuncs: ArrayList<ToolOptionType>): Unit {
    for (typefunc in typeFuncs) {
        typefunc(setOptionHandler, driverOptions)
    }
}
