package cangjie_compiler::frontend_tool

import std.collection.*
import cangjie_compiler::basic.DiagKindRefactor
import cangjie_compiler::basic.PrintVersion
import cangjie_compiler::basic.WriteError
import cangjie_compiler::frontend.*
import cangjie_compiler::incremental_compilation.IncreKind
import cangjie_compiler::incremental_compilation.IncrementalCompilationLogger
import cangjie_compiler::option.MockMode
import cangjie_compiler::option.OrderedInput as OptionOrderedInput
import cangjie_compiler::option.OutputMode
import cangjie_compiler::option.TempFileInfo as OptionTempFileInfo
import cangjie_compiler::utils.FileUtil
import cangjie_compiler::utils.ProfileRecorder
import cangjie_compiler::utils.ProfileRecorderType

public class DriverOptions {
    public let sourceFiles: ArrayList<String> = ArrayList<String>()
    public let inputObjs: ArrayList<String> = ArrayList<String>()
    public let packagePaths: ArrayList<String> = ArrayList<String>()
    public let importPaths: ArrayList<String> = ArrayList<String>()
    public let pluginPaths: ArrayList<String> = ArrayList<String>()
    public let commonPartCjos: ArrayList<String> = ArrayList<String>()
    public let commonPartChirs: ArrayList<String> = ArrayList<String>()
    public let bcPackageNames: ArrayList<String> = ArrayList<String>()
    public let frontendOutputFiles: ArrayList<OptionTempFileInfo> = ArrayList<OptionTempFileInfo>()
    public let inputLibraryOrder: ArrayList<OptionOrderedInput> = ArrayList<OptionOrderedInput>()
    public let directBuiltinDependencies: HashSet<String> = HashSet<String>()
    public let indirectBuiltinDependencies: HashSet<String> = HashSet<String>()
    public let symbolsNeedLocalized: ArrayList<String> = ArrayList<String>()
    public let symbolsNeedLocalizedPerPkg: HashMap<String, ArrayList<String>> =
        HashMap<String, ArrayList<String>>()
    public var output: String = ""
    public var executablePath: String = ""
    public var cangjieHome: String = ""
    public var moduleSrcPath: String = ""
    public var inputCjoFile: String = ""
    public var compilationCachedPath: String = ""
    public var compilationCachedDir: String = ""
    public var compilationCachedFileName: String = ""
    public var incrementalCompileNoChange: Bool = false

    public init() {}

    public func CopyFromOptions(opts: GlobalOptions, incrementalNoChange: Bool): Unit {
        CopyStringList(sourceFiles, opts.srcFiles)
        CopyStringList(inputObjs, opts.inputObjs)
        CopyStringList(packagePaths, opts.packagePaths)
        CopyStringList(importPaths, opts.importPaths)
        CopyStringList(pluginPaths, opts.pluginPaths)
        CopyStringList(commonPartCjos, opts.commonPartCjos)
        CopyStringList(commonPartChirs, opts.commonPartChirs)
        CopyStringList(bcPackageNames, opts.bcPackageNames)
        CopyOptionTempFileList(frontendOutputFiles, opts.frontendOutputFiles)
        CopyOptionOrderedInputList(inputLibraryOrder, opts.inputLibraryOrder)
        CopyStringSet(directBuiltinDependencies, opts.directBuiltinDependencies)
        CopyStringSet(indirectBuiltinDependencies, opts.indirectBuiltinDependencies)
        CopyStringList(symbolsNeedLocalized, opts.symbolsNeedLocalized)
        CopyStringArrayMap(symbolsNeedLocalizedPerPkg, opts.symbolsNeedLocalizedPerPkg)
        output = opts.output
        executablePath = opts.executablePath
        cangjieHome = opts.cangjieHome
        moduleSrcPath = opts.moduleSrcPath
        inputCjoFile = opts.inputCjoFile
        compilationCachedPath = opts.compilationCachedPath
        compilationCachedDir = opts.compilationCachedDir
        compilationCachedFileName = opts.compilationCachedFileName
        incrementalCompileNoChange = incrementalNoChange
    }
}

public class Driver {
    public let driverOptions: DriverOptions

    public init(driverOptions!: DriverOptions = DriverOptions()) {
        this.driverOptions = driverOptions
    }
}

public func ExecuteFrontend(
    exePath: String,
    args: Array<String>,
    environmentVars: HashMap<String, String>
): Int64 {
    let diag = DiagnosticEngine()
    let invocation = CompilerInvocation()
    ConfigureInvocationPaths(invocation, exePath, environmentVars)
    if (!InitializeCompilerInvocation(invocation, args)) {
        return 1
    }

    let globalOptions = invocation.globalOptions
    if (globalOptions.showUsage) {
        PrintFrontendUsage()
        return 0
    }
    if (globalOptions.enableVerbose || globalOptions.printVersionOnly) {
        PrintVersion()
        if (globalOptions.printVersionOnly) {
            return 0
        }
    }
    ConfigureFrontendProfiling(globalOptions)
    ConfigureFrontendDiagnostics(diag, globalOptions)

    let instance = CreateCompilerInstance(invocation, diag)
    if (ExecuteCompile(instance)) {
        let _ = instance.UpdateAndWriteCachedInfoToDisk()
        return 0
    }
    return 1
}

public func ExecuteFrontend(
    exePath: String,
    args: ArrayList<String>,
    environmentVars: HashMap<String, String>
): Int64 {
    return ExecuteFrontend(exePath, args.toArray(), environmentVars)
}

public func ExecuteFrontendByDriver(instance: DefaultCompilerInstance, driver: Driver): Bool {
    if (ExecuteCompile(instance)) {
        let incrementalNoChange = if (let Some(incr) <- (instance as IncrementalCompilerInstance)) {
            incr.kind == IncreKind.NO_CHANGE
        } else {
            false
        }
        driver.driverOptions.CopyFromOptions(instance.invocation.globalOptions, incrementalNoChange)
        let _ = instance.UpdateAndWriteCachedInfoToDisk()
        return true
    }
    return false
}

public func NeedCreateIncrementalCompilerInstance(opts: GlobalOptions): Bool {
    let logger = IncrementalCompilationLogger.GetInstance()
    logger.SetDebugPrint(opts.printIncrementalInfo)
    if (opts.enIncrementalCompilation) {
        if (opts.mock == MockMode.ON) {
            logger.LogLn("enable mock, roll back to full compilation")
        } else if (opts.enableCoverage) {
            logger.LogLn("enable coverage, roll back to full compilation")
        } else if (opts.outputMode == OutputMode.CHIR) {
            logger.LogLn("enable compile common part mode, roll back to full compilation")
        } else if (!opts.commonPartCjos.isEmpty()) {
            logger.LogLn("enable compile platform part mode, roll back to full compilation")
        }
    }
    return opts.enIncrementalCompilation && opts.mock != MockMode.ON && !opts.enableCoverage &&
        opts.outputMode != OutputMode.CHIR && opts.commonPartCjos.isEmpty()
}

private func InitializeCompilerInvocation(ci: CompilerInvocation, args: Array<String>): Bool {
    if (!ci.ParseArgs(args)) {
        WriteError("Invalid options. Try: 'cjc-frontend --help' for more information.\n")
        return false
    }
    return true
}

private func CreateCompilerInstance(invocation: CompilerInvocation, diag: DiagnosticEngine): DefaultCompilerInstance {
    if (NeedCreateIncrementalCompilerInstance(invocation.globalOptions)) {
        return IncrementalCompilerInstance(invocation, diag)
    }
    if (invocation.globalOptions.compileCjd) {
        return CjdCompilerInstance(invocation, diag)
    }
    return DefaultCompilerInstance(invocation, diag)
}

private func ExecuteCompile(instance: DefaultCompilerInstance): Bool {
    let opts = instance.invocation.frontendOptions
    let globalOptions = instance.invocation.globalOptions
    let isEmitCHIR = globalOptions.IsEmitCHIREnable()
    if (IsEmptyInputFile(instance) && opts.dumpAction != DumpAction.DESERIALIZE_CHIR) {
        return HandleEmptyInputFileSituation(instance)
    }

    if (!globalOptions.compilePackage && globalOptions.srcFiles.isEmpty() && !globalOptions.inputObjs.isEmpty()) {
        return ProcessObjectOnlyFrontendInputs(globalOptions)
    }

    if (opts.dumpAction != DumpAction.NO_ACTION) {
        return PerformDumpAction(instance, opts.dumpAction)
    }

    if (!instance.Compile(stage: CompileStage.CHIR)) {
        return false
    }
    var res = true
    if (!isEmitCHIR && globalOptions.outputMode != OutputMode.CHIR) {
        res = instance.PerformCodeGen() && res
    }
    if (!isEmitCHIR) {
        res = instance.PerformResultsSaving() && res
    }
    return res
}

private func PerformDumpAction(instance: DefaultCompilerInstance, dumpAction: DumpAction): Bool {
    var ret = true
    if (dumpAction == DumpAction.DUMP_TOKENS) {
        return instance.DumpTokens()
    } else if (dumpAction == DumpAction.DUMP_SYMBOLS) {
        ret = instance.Compile(stage: CompileStage.SEMA)
        instance.DumpSymbols()
    } else if (dumpAction == DumpAction.TYPE_CHECK) {
        ret = instance.Compile(stage: CompileStage.CHIR)
    } else if (dumpAction == DumpAction.DUMP_DEP_PKG) {
        ret = instance.Compile(stage: CompileStage.IMPORT_PACKAGE)
        instance.DumpDepPackage()
    } else if (dumpAction == DumpAction.DESERIALIZE_CHIR) {
        ret = instance.DeserializeCHIR()
    }
    return ret && instance.diag.GetErrorCount() == 0
}

private func IsEmptyInputFile(instance: DefaultCompilerInstance): Bool {
    let globalOptions = instance.invocation.globalOptions
    if (globalOptions.scanDepPkg) {
        return !globalOptions.compilePackage && globalOptions.inputCjoFile.isEmpty()
    }
    return !globalOptions.compilePackage && globalOptions.srcFiles.isEmpty() &&
        globalOptions.commonPartChirs.isEmpty() && globalOptions.inputObjs.isEmpty()
}

private func HandleEmptyInputFileSituation(instance: DefaultCompilerInstance): Bool {
    let globalOptions = instance.invocation.globalOptions
    if (!globalOptions.scanDepPkg && globalOptions.srcFiles.isEmpty() && globalOptions.commonPartChirs.isEmpty() &&
        globalOptions.inputObjs.isEmpty()) {
        instance.diag.DiagnoseRefactor(DiagKindRefactor.driver_source_file_empty, DEFAULT_POSITION)
        return false
    }
    if (globalOptions.scanDepPkg && globalOptions.inputCjoFile.isEmpty()) {
        instance.diag.DiagnoseRefactor(DiagKindRefactor.driver_source_cjo_empty, DEFAULT_POSITION)
        return false
    }
    return true
}

private func ConfigureFrontendProfiling(globalOptions: GlobalOptions): Unit {
    if (globalOptions.enableTimer) {
        ProfileRecorder.Enable(true, `type`: ProfileRecorderType.TIMER)
    }
    if (globalOptions.enableMemoryCollect) {
        ProfileRecorder.Enable(true, `type`: ProfileRecorderType.MEMORY)
    }
}

private func ConfigureFrontendDiagnostics(diag: DiagnosticEngine, globalOptions: GlobalOptions): Unit {
    let _ = diag
    let _ = globalOptions
    // TODO(selfhost:frontend_tool): C++ calls SetErrorCountLimit and RegisterHandler here, but
    // frontend.DiagnosticEngine does not expose those basic DiagnosticEngine hooks in the stable DAG.
}

private func ConfigureInvocationPaths(
    invocation: CompilerInvocation,
    exePath: String,
    environmentVars: HashMap<String, String>
): Unit {
    let absExePath = GetAbsPath(exePath) ?? exePath
    let cangjieHome = GetDirPath(GetDirPath(absExePath))
    invocation.frontendOptions.executablePath = exePath
    invocation.frontendOptions.ReadPathsFromEnvironmentVars(environmentVars)
    invocation.frontendOptions.cangjieHome = if (invocation.frontendOptions.environment.cangjieHome.hasValue) {
        invocation.frontendOptions.environment.cangjieHome.value
    } else {
        cangjieHome
    }
    invocation.globalOptions.executablePath = invocation.frontendOptions.executablePath
    invocation.globalOptions.environment.cangjieHome = invocation.frontendOptions.environment.cangjieHome
    invocation.globalOptions.cangjieHome = invocation.frontendOptions.cangjieHome
}

private func ProcessObjectOnlyFrontendInputs(opts: GlobalOptions): Bool {
    var idx: Int64 = 0
    while (idx < opts.inputLibraryOrder.size) {
        let rawName = opts.inputLibraryOrder[idx].value
        if (let Some(cjoName) <- ConvertBuiltinLibraryBaseToCjo(rawName, false)) {
            opts.indirectBuiltinDependencies.add(cjoName)
            opts.inputLibraryOrder.remove(at: idx)
            continue
        }
        idx++
    }
    return true
}

private func ConvertBuiltinLibraryBaseToCjo(rawName: String, trimNativeLibPrefix: Bool): Option<String> {
    if (rawName.isEmpty()) {
        return None
    }
    let normalizedName = if (trimNativeLibPrefix && rawName.startsWith("libcangjie-")) {
        rawName[3..]
    } else {
        rawName
    }
    if (!normalizedName.startsWith("cangjie-")) {
        return None
    }
    let potentialPkgName = normalizedName["cangjie-".size..].replace("-", ".")
    if (potentialPkgName.isEmpty()) {
        return None
    }
    let converted = FileUtil.ConvertPackageNameToLibCangjieBaseFormat(potentialPkgName)
    if (!converted.isEmpty() && converted == normalizedName) {
        return Some(potentialPkgName + ".cjo")
    }
    return None
}

private func PrintFrontendUsage(): Unit {
    println("Usage:")
    println("  cjc-frontend [option] file...")
    println("Options:")
    println("  --dump-tokens")
    println("  --dump-symbols")
    println("  --typecheck")
    println("  --scan-dependency")
    println("  --deserialize-chir-and-dump <file>")
    println("  -d")
    println("  -p, --package")
    println("  -o, --output <file>")
}

private func CopyStringList(target: ArrayList<String>, source: ArrayList<String>): Unit {
    target.clear()
    for (value in source) {
        target.add(value)
    }
}

private func CopyStringSet(target: HashSet<String>, source: HashSet<String>): Unit {
    target.clear()
    for (value in source) {
        target.add(value)
    }
}

private func CopyOptionTempFileList(
    target: ArrayList<OptionTempFileInfo>,
    source: ArrayList<OptionTempFileInfo>
): Unit {
    target.clear()
    for (value in source) {
        target.add(OptionTempFileInfo(
            fileName: value.fileName,
            filePath: value.filePath,
            rawPath: value.rawPath,
            isFrontendOutput: value.isFrontendOutput,
            isForeignInput: value.isForeignInput))
    }
}

private func CopyOptionOrderedInputList(
    target: ArrayList<OptionOrderedInput>,
    source: ArrayList<OptionOrderedInput>
): Unit {
    target.clear()
    for (value in source) {
        target.add(OptionOrderedInput(value.value, value.index))
    }
}

private func CopyStringArrayMap(
    target: HashMap<String, ArrayList<String>>,
    source: HashMap<String, ArrayList<String>>
): Unit {
    target.clear()
    for ((key, values) in source) {
        let copiedValues = ArrayList<String>()
        for (value in values) {
            copiedValues.add(value)
        }
        target.add(key, copiedValues)
    }
}
