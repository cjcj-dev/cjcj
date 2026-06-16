package cangjie_compiler::frontend_tool

import std.collection.*
import cangjie_compiler::basic.PrintVersion
import cangjie_compiler::basic.WriteError
import cangjie_compiler::frontend.*
import cangjie_compiler::utils.FileUtil

public class DriverOptions {
    public let sourceFiles: ArrayList<String> = ArrayList<String>()
    public let directBuiltinDependencies: HashSet<String> = HashSet<String>()
    public let indirectBuiltinDependencies: HashSet<String> = HashSet<String>()
    public var compilationCachedPath: String = ""
    public var compilationCachedDir: String = ""
    public var compilationCachedFileName: String = ""
    public var incrementalCompileNoChange: Bool = false

    public init() {}

    public func CopyFromOptions(opts: GlobalOptions, incrementalNoChange: Bool): Unit {
        sourceFiles.clear()
        for (srcFile in opts.srcFiles) {
            sourceFiles.add(srcFile)
        }
        CopyStringSet(directBuiltinDependencies, opts.directBuiltinDependencies)
        CopyStringSet(indirectBuiltinDependencies, opts.indirectBuiltinDependencies)
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
    if (!opts.enIncrementalCompilation) {
        return false
    }
    if (opts.compileCjd) {
        return false
    }
    if (!opts.commonPartCjos.isEmpty() || !opts.commonPartChirs.isEmpty()) {
        return false
    }
    return true
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
    if (!isEmitCHIR) {
        res = instance.PerformCodeGen() && res
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
        instance.diag.Diagnose(DiagCategory.OTHER, DEFAULT_POSITION, "source file is empty")
        return false
    }
    if (globalOptions.scanDepPkg && globalOptions.inputCjoFile.isEmpty()) {
        instance.diag.Diagnose(DiagCategory.OTHER, DEFAULT_POSITION, "source cjo file is empty")
        return false
    }
    return true
}

private func ConfigureInvocationPaths(
    invocation: CompilerInvocation,
    exePath: String,
    environmentVars: HashMap<String, String>
): Unit {
    let absExePath = GetAbsPath(exePath) ?? exePath
    let cangjieHome = GetDirPath(GetDirPath(absExePath))
    invocation.frontendOptions.executablePath = exePath
    ReadPathsFromEnvironmentVars(invocation.frontendOptions, environmentVars)
    invocation.frontendOptions.cangjieHome = if (let Some(home) <- invocation.frontendOptions.environment.cangjieHome) {
        home
    } else {
        cangjieHome
    }
    invocation.globalOptions.executablePath = invocation.frontendOptions.executablePath
    invocation.globalOptions.environment.cangjieHome = invocation.frontendOptions.environment.cangjieHome
    invocation.globalOptions.cangjieHome = invocation.frontendOptions.cangjieHome
}

private func ReadPathsFromEnvironmentVars(opts: FrontendOptions, environmentVars: HashMap<String, String>): Unit {
    opts.environment.allVariables.clear()
    for ((key, value) in environmentVars) {
        opts.environment.allVariables.add(key, value)
    }
    if (let Some(home) <- environmentVars.get("CANGJIE_HOME")) {
        opts.environment.cangjieHome = GetAbsPath(home)
        if (let Some(absHome) <- opts.environment.cangjieHome) {
            opts.cangjieHome = absHome
        }
    }
}

private func ProcessObjectOnlyFrontendInputs(opts: GlobalOptions): Bool {
    for (inputObj in opts.inputObjs) {
        let rawName = LibraryBaseName(inputObj)
        if (rawName.isEmpty()) {
            continue
        }
        let normalizedName = if (rawName.startsWith("libcangjie-")) {
            rawName[3..]
        } else {
            rawName
        }
        if (!normalizedName.startsWith("cangjie-")) {
            continue
        }
        let potentialPkgName = normalizedName["cangjie-".size..].replace("-", ".")
        if (potentialPkgName.isEmpty()) {
            continue
        }
        let converted = FileUtil.ConvertPackageNameToLibCangjieBaseFormat(potentialPkgName)
        if (!converted.isEmpty() && converted == normalizedName) {
            opts.indirectBuiltinDependencies.add(potentialPkgName + ".cjo")
        }
    }
    return true
}

private func LibraryBaseName(path: String): String {
    var name = GetFileName(path)
    if (let Some(dotPos) <- name.lastIndexOf(".")) {
        name = name[0..dotPos]
    }
    return name
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

private func CopyStringSet(target: HashSet<String>, source: HashSet<String>): Unit {
    target.clear()
    for (value in source) {
        target.add(value)
    }
}
