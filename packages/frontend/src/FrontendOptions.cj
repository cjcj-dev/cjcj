package cangjie_compiler::frontend

public import cangjie_compiler::utils.{
    CACHED_AST_EXTENSION, CACHED_LOG_EXTENSION, CJ_D_FILE_EXTENSION, DEFAULT_PACKAGE_NAME, SERIALIZED_FILE_EXTENSION,
    OverflowStrategy, OverflowStrategyName, StringToOverflowStrategy, ValidOverflowStrategy
}
import cangjie_compiler::option.SetupConditionalCompilationCfgFromFile as OptionSetupConditionalCompilationCfgFromFile
import cangjie_compiler::option.StableHashString as OptionStableHashString
import cangjie_compiler::utils.FileUtil
import std.collection.*
import std.sort.*

public enum OptionID {
    | UNKNOWN
    | DUMP_TOKENS
    | DUMP_SYMBOLS
    | TYPE_CHECK
    | DUMP_DEPENDENT_PACKAGE
    | DESERIALIZE_CHIR_AND_DUMP
    | COMPILE_CJD
    | PACKAGE_COMPILE
    | MODULE_NAME
    | MODULE_SRC_PATH
    | OUTPUT_TYPE
    | OUTPUT_FILE
    | OUTPUT_DIR
    | IMPORT_PATH
    | PLUGIN_PATH
    | JOBS
    | CANGJIE_HOME
    | ENABLE_INCREMENTAL
    | DUMP_AST
    | DUMP_CHIR
    | DUMP_ALL
    | DUMP_TO_SCREEN
    | COMPILE_TEST
    | COMPILE_TESTS_ONLY
    | VERBOSE
    | ENABLE_MACRO_IN_LSP
    | NO_SUB_PACKAGE
    | COMMON_PART_CJO
    | COMMON_PART_CHIR
    | CONDITIONAL_COMPILATION_CONFIG
    | INT_OVERFLOW_MODE
    | INPUT
}

private func OptionIDIndex(id: OptionID): Int64 {
    return match (id) {
        case OptionID.UNKNOWN => 0
        case OptionID.DUMP_TOKENS => 1
        case OptionID.DUMP_SYMBOLS => 2
        case OptionID.TYPE_CHECK => 3
        case OptionID.DUMP_DEPENDENT_PACKAGE => 4
        case OptionID.DESERIALIZE_CHIR_AND_DUMP => 5
        case OptionID.COMPILE_CJD => 6
        case OptionID.PACKAGE_COMPILE => 7
        case OptionID.MODULE_NAME => 8
        case OptionID.MODULE_SRC_PATH => 9
        case OptionID.OUTPUT_TYPE => 10
        case OptionID.OUTPUT_FILE => 11
        case OptionID.OUTPUT_DIR => 12
        case OptionID.IMPORT_PATH => 13
        case OptionID.PLUGIN_PATH => 14
        case OptionID.JOBS => 15
        case OptionID.CANGJIE_HOME => 16
        case OptionID.ENABLE_INCREMENTAL => 17
        case OptionID.DUMP_AST => 18
        case OptionID.DUMP_CHIR => 19
        case OptionID.DUMP_ALL => 20
        case OptionID.DUMP_TO_SCREEN => 21
        case OptionID.COMPILE_TEST => 22
        case OptionID.COMPILE_TESTS_ONLY => 23
        case OptionID.VERBOSE => 24
        case OptionID.ENABLE_MACRO_IN_LSP => 25
        case OptionID.NO_SUB_PACKAGE => 26
        case OptionID.COMMON_PART_CJO => 27
        case OptionID.COMMON_PART_CHIR => 28
        case OptionID.CONDITIONAL_COMPILATION_CONFIG => 29
        case OptionID.INT_OVERFLOW_MODE => 30
        case OptionID.INPUT => 31
    }
}

extend OptionID <: Equatable<OptionID> {
    public operator func ==(rhs: OptionID): Bool {
        return OptionIDIndex(this) == OptionIDIndex(rhs)
    }

    public operator func !=(rhs: OptionID): Bool {
        return !(this == rhs)
    }
}

public enum OptionKind {
    | FLAG
    | SEPARATED
    | JOINED
    | INPUT
}

private func OptionKindIndex(kind: OptionKind): Int64 {
    return match (kind) {
        case OptionKind.FLAG => 0
        case OptionKind.SEPARATED => 1
        case OptionKind.JOINED => 2
        case OptionKind.INPUT => 3
    }
}

extend OptionKind <: Equatable<OptionKind> {
    public operator func ==(rhs: OptionKind): Bool {
        return OptionKindIndex(this) == OptionKindIndex(rhs)
    }

    public operator func !=(rhs: OptionKind): Bool {
        return !(this == rhs)
    }
}

public class OptionInfo {
    public let spelling: String
    public let alias: String
    public let id: OptionID
    public let kind: OptionKind

    public init(spelling: String, id: OptionID, kind: OptionKind, alias!: String = "") {
        this.spelling = spelling
        this.alias = alias
        this.id = id
        this.kind = kind
    }
}

public class OptionArgInstance {
    public let info: OptionInfo
    public let spelling: String
    public var value: String

    public init(info: OptionInfo, spelling: String, value!: String = "") {
        this.info = info
        this.spelling = spelling
        this.value = value
    }
}

public class ArgList {
    public let args: ArrayList<OptionArgInstance> = ArrayList<OptionArgInstance>()
    public let inputArgs: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func Add(arg: OptionArgInstance): Unit {
        args.add(arg)
        if (arg.info.id == OptionID.INPUT) {
            inputArgs.add(arg.value)
        }
    }

    public func Clear(): Unit {
        args.clear()
        inputArgs.clear()
    }
}

public class OptionTable {
    private let infos: ArrayList<OptionInfo> = ArrayList<OptionInfo>()

    public init() {
        add("--dump-tokens", OptionID.DUMP_TOKENS, OptionKind.FLAG)
        add("--dump-symbols", OptionID.DUMP_SYMBOLS, OptionKind.FLAG)
        add("--typecheck", OptionID.TYPE_CHECK, OptionKind.FLAG)
        add("--scan-dependency", OptionID.DUMP_DEPENDENT_PACKAGE, OptionKind.FLAG)
        add("--deserialize-chir-and-dump", OptionID.DESERIALIZE_CHIR_AND_DUMP, OptionKind.SEPARATED)
        add("-d", OptionID.COMPILE_CJD, OptionKind.FLAG)
        add("--package", OptionID.PACKAGE_COMPILE, OptionKind.FLAG, alias: "-p")
        add("--module-name", OptionID.MODULE_NAME, OptionKind.SEPARATED)
        add("--module-src-path", OptionID.MODULE_SRC_PATH, OptionKind.SEPARATED)
        add("--output-type", OptionID.OUTPUT_TYPE, OptionKind.SEPARATED)
        add("--output", OptionID.OUTPUT_FILE, OptionKind.SEPARATED, alias: "-o")
        add("--output-dir", OptionID.OUTPUT_DIR, OptionKind.SEPARATED)
        add("--import-path", OptionID.IMPORT_PATH, OptionKind.SEPARATED)
        add("--plugin", OptionID.PLUGIN_PATH, OptionKind.SEPARATED)
        add("--jobs", OptionID.JOBS, OptionKind.SEPARATED, alias: "-j")
        add("--cangjie-home", OptionID.CANGJIE_HOME, OptionKind.SEPARATED)
        add("--incremental-compile", OptionID.ENABLE_INCREMENTAL, OptionKind.FLAG)
        add("--dump-ast", OptionID.DUMP_AST, OptionKind.FLAG)
        add("--dump-chir", OptionID.DUMP_CHIR, OptionKind.FLAG)
        add("--dump-all", OptionID.DUMP_ALL, OptionKind.FLAG)
        add("--dump-to-screen", OptionID.DUMP_TO_SCREEN, OptionKind.FLAG)
        add("--test", OptionID.COMPILE_TEST, OptionKind.FLAG)
        add("--test-only", OptionID.COMPILE_TESTS_ONLY, OptionKind.FLAG)
        add("--verbose", OptionID.VERBOSE, OptionKind.FLAG, alias: "-V")
        add("--enable-macro-in-lsp", OptionID.ENABLE_MACRO_IN_LSP, OptionKind.FLAG)
        add("--no-sub-pkg", OptionID.NO_SUB_PACKAGE, OptionKind.FLAG)
        add("--common-part-cjo", OptionID.COMMON_PART_CJO, OptionKind.SEPARATED)
        add("--common-part-chir", OptionID.COMMON_PART_CHIR, OptionKind.SEPARATED)
        add("--cfg", OptionID.CONDITIONAL_COMPILATION_CONFIG, OptionKind.SEPARATED)
        add("--int-overflow", OptionID.INT_OVERFLOW_MODE, OptionKind.SEPARATED)
    }

    private func add(spelling: String, id: OptionID, kind: OptionKind, alias!: String = ""): Unit {
        infos.add(OptionInfo(spelling, id, kind, alias: alias))
    }

    private func findInfo(spelling: String): Option<OptionInfo> {
        for (info in infos) {
            if (spelling == info.spelling || (!info.alias.isEmpty() && spelling == info.alias)) {
                return Some(info)
            }
        }
        return None
    }

    public func ParseArgs(args: Array<String>, argList: ArgList): Bool {
        argList.Clear()
        var idx: Int64 = 0
        while (idx < args.size) {
            let raw = args[idx]
            if (raw.startsWith("-")) {
                var spelling = raw
                var value = ""
                if (let Some(eqPos) <- raw.indexOf("=")) {
                    spelling = raw[0..eqPos]
                    value = raw[eqPos + 1..]
                }
                if (let Some(info) <- findInfo(spelling)) {
                    if (info.kind == OptionKind.SEPARATED && value.isEmpty()) {
                        if (idx + 1 >= args.size) {
                            return false
                        }
                        idx++
                        value = args[idx]
                    }
                    argList.Add(OptionArgInstance(info, spelling, value: value))
                } else {
                    let unknownInfo = OptionInfo(spelling, OptionID.UNKNOWN, OptionKind.FLAG)
                    argList.Add(OptionArgInstance(unknownInfo, spelling))
                }
            } else {
                let inputInfo = OptionInfo(raw, OptionID.INPUT, OptionKind.INPUT)
                argList.Add(OptionArgInstance(inputInfo, raw, value: raw))
            }
            idx++
        }
        return true
    }
}

public func CreateOptionTable(frontendMode: Bool): OptionTable {
    let _ = frontendMode
    return OptionTable()
}

public class MaybeString {
    public var value: Option<String> = None
    public init() {}
    public init(text: String) { value = Some(text) }
    public func hasValue(): Bool { return if (let Some(_) <- value) { true } else { false } }
}

public class EnvironmentOptions {
    public var cangjieHome: Option<String> = None
    public let allVariables: HashMap<String, String> = HashMap<String, String>()
    public init() {}
}

public open class GlobalOptions {
    public var frontendMode: Bool = false
    public let environment: EnvironmentOptions = EnvironmentOptions()
    public var cangjieHome: String = ""
    public var output: String = "./"
    public var outputType: String = ""
    public var outputDir: MaybeString = MaybeString()
    public var executablePath: String = ""
    public var moduleName: String = DEFAULT_PACKAGE_NAME
    public var moduleSrcPath: String = ""
    public let packagePaths: ArrayList<String> = ArrayList<String>()
    public let srcFiles: ArrayList<String> = ArrayList<String>()
    public let inputObjs: ArrayList<String> = ArrayList<String>()
    public var inputCjoFile: String = ""
    public let importPaths: ArrayList<String> = ArrayList<String>()
    public let pluginPaths: ArrayList<String> = ArrayList<String>()
    public let commonPartCjos: ArrayList<String> = ArrayList<String>()
    public let commonPartChirs: ArrayList<String> = ArrayList<String>()
    public let bcPackageNames: ArrayList<String> = ArrayList<String>()
    public let directBuiltinDependencies: HashSet<String> = HashSet<String>()
    public let indirectBuiltinDependencies: HashSet<String> = HashSet<String>()
    public let passedWhenKeyValue: HashMap<String, String> = HashMap<String, String>()
    public let passedWhenCfgPaths: ArrayList<String> = ArrayList<String>()
    public var compilePackage: Bool = false
    public var parseTest: Bool = false
    public var compileTestsOnly: Bool = false
    public var enableAddCommentToAst: Bool = false
    public var compileCjd: Bool = false
    public var noSubPkg: Bool = false
    public var scanDepPkg: Bool = false
    public var enableInteropCJMapping: Bool = false
    public var interopCJPackageConfigPath: String = "./"
    public var chirDeserialize: Bool = false
    public var chirDeserializePath: String = ""
    public var dumpCHIR: Bool = false
    public var dumpAST: Bool = false
    public var dumpToScreen: Bool = false
    public var dumpAll: Bool = false
    public var enableVerbose: Bool = false
    public var enableMacroInLSP: Bool = false
    public var enIncrementalCompilation: Bool = false
    public var cjdbMode: Bool = false
    public var printVersionOnly: Bool = false
    public var showUsage: Bool = false
    public var enableCompileDebug: Bool = false
    public var displayLineInfo: Bool = false
    public var interpreter: Bool = false
    public var overflowStrategy: OverflowStrategy = OverflowStrategy.THROWING
    public var jobs: Int64 = 1
    public var compilationCachedPath: String = ""
    public var compilationCachedDir: String = ""
    public var compilationCachedFileName: String = ""
    public var argList: ArgList = ArgList()

    public init() {}

    public func SetFrontendMode(): Unit {
        frontendMode = true
    }

    public func GetDefaultPackageName(): String {
        return if (moduleName.isEmpty()) { DEFAULT_PACKAGE_NAME } else { moduleName }
    }

    public open func ParseFromArgs(argList: ArgList): Bool {
        this.argList = argList
        for (arg in argList.args) {
            if (!HandleOption(arg)) {
                return false
            }
        }
        return true
    }

    protected open func ParseOption(arg: OptionArgInstance): Option<Bool> {
        let _ = arg
        return None
    }

    private func HandleOption(arg: OptionArgInstance): Bool {
        if (let Some(ret) <- ParseOption(arg)) {
            return ret
        }
        let id = arg.info.id
        if (id == OptionID.INPUT) {
            srcFiles.add(arg.value)
        } else if (id == OptionID.PACKAGE_COMPILE) {
            compilePackage = true
            if (!arg.value.isEmpty()) {
                packagePaths.add(arg.value)
            }
        } else if (id == OptionID.MODULE_NAME) {
            moduleName = arg.value
        } else if (id == OptionID.MODULE_SRC_PATH) {
            moduleSrcPath = arg.value
            if (!arg.value.isEmpty()) {
                packagePaths.add(arg.value)
            }
        } else if (id == OptionID.OUTPUT_TYPE) {
            outputType = arg.value
        } else if (id == OptionID.OUTPUT_FILE) {
            output = arg.value
        } else if (id == OptionID.OUTPUT_DIR) {
            outputDir = MaybeString(arg.value)
            output = arg.value
        } else if (id == OptionID.IMPORT_PATH) {
            importPaths.add(arg.value)
        } else if (id == OptionID.PLUGIN_PATH) {
            pluginPaths.add(arg.value)
        } else if (id == OptionID.JOBS) {
            jobs = ParsePositiveInt(arg.value, 1)
        } else if (id == OptionID.CANGJIE_HOME) {
            cangjieHome = arg.value
            environment.cangjieHome = Some(arg.value)
        } else if (id == OptionID.ENABLE_INCREMENTAL) {
            enIncrementalCompilation = true
        } else if (id == OptionID.DUMP_AST) {
            dumpAST = true
        } else if (id == OptionID.DUMP_CHIR) {
            dumpCHIR = true
        } else if (id == OptionID.DUMP_ALL) {
            dumpAll = true
            dumpAST = true
            dumpCHIR = true
        } else if (id == OptionID.DUMP_TO_SCREEN) {
            dumpToScreen = true
        } else if (id == OptionID.COMPILE_TEST) {
            parseTest = true
        } else if (id == OptionID.COMPILE_TESTS_ONLY) {
            compileTestsOnly = true
        } else if (id == OptionID.VERBOSE) {
            enableVerbose = true
        } else if (id == OptionID.ENABLE_MACRO_IN_LSP) {
            enableMacroInLSP = true
        } else if (id == OptionID.NO_SUB_PACKAGE) {
            noSubPkg = true
        } else if (id == OptionID.COMMON_PART_CJO) {
            commonPartCjos.add(arg.value)
        } else if (id == OptionID.COMMON_PART_CHIR) {
            commonPartChirs.add(arg.value)
        } else if (id == OptionID.CONDITIONAL_COMPILATION_CONFIG) {
            if (!ParsePassedWhenOption(this, arg.value)) {
                return false
            }
        } else if (id == OptionID.INT_OVERFLOW_MODE) {
            if (!ValidOverflowStrategy(arg.value)) {
                return false
            }
            overflowStrategy = StringToOverflowStrategy(arg.value)
        } else if (id == OptionID.UNKNOWN) {
            ()
        }
        return true
    }

    public func SetCompilationCachedPath(): Unit {
        if (outputDir.hasValue()) {
            compilationCachedPath = outputDir.value.getOrThrow()
        } else if (IsDir(output)) {
            compilationCachedPath = output
        } else {
            compilationCachedPath = GetDirPath(output)
        }
        if (compilationCachedPath.isEmpty()) {
            compilationCachedPath = "."
        }
    }

    public func GetCacheRelativeFilePath(filePath: String): String {
        if (compilationCachedPath.isEmpty()) {
            return GetFileName(filePath)
        }
        let absFilePath = FileUtil.GetAbsPath(filePath)
        if (let None <- absFilePath) {
            return GetFileName(filePath)
        }
        let relativePath = FileUtil.GetRelativePath(JoinPath(compilationCachedPath, ""), absFilePath.getOrThrow())
        if (let Some(value) <- relativePath) {
            return value
        }
        return GetFileName(filePath)
    }

    public func GenerateNamesOfCachedDirAndFile(fullPackageName: String): (String, String) {
        var fileName = ""
        if (compilePackage) {
            fileName = fullPackageName
        } else {
            let sortedSrcFiles = ArrayList<String>()
            for (srcFile in srcFiles) {
                sortedSrcFiles.add(GetCacheRelativeFilePath(srcFile))
            }
            sort(sortedSrcFiles, by: { left: String, right: String =>
                if (left < right) {
                    Ordering.LT
                } else if (left > right) {
                    Ordering.GT
                } else {
                    Ordering.EQ
                }
            })
            let builder = StringBuilder()
            for (srcFile in sortedSrcFiles) {
                builder.append(srcFile)
            }
            fileName = builder.toString()
        }
        return (JoinPath(compilationCachedPath, ".cached"), OptionStableHashString(fileName))
    }

    public func GenerateCachedPathName(fullPackageName: String, extension: String): String {
        let names = GenerateNamesOfCachedDirAndFile(fullPackageName)
        let folder = names[0]
        if (!FileExist(folder)) {
            let _ = CreateDirs(folder + DIR_SEPARATOR)
        }
        return JoinPath(folder, names[1] + extension)
    }

    public func GenerateCachedPathNameForCodeGen(subModuleName: String, extension: String): String {
        let hashedFileName = OptionStableHashString(subModuleName)
        let folder = JoinPath(compilationCachedPath, ".cached")
        if (!FileExist(folder)) {
            let _ = CreateDirs(folder + DIR_SEPARATOR)
        }
        return JoinPath(folder, hashedFileName + extension)
    }

    public func GetHashedObjFileName(objFileName: String): String {
        return JoinPath(compilationCachedDir, OptionStableHashString(compilationCachedFileName + objFileName))
    }

    public func GetHashedObjFileNameForPackage(fullPackageName: String, objFileName: String): String {
        let names = GenerateNamesOfCachedDirAndFile(fullPackageName)
        return JoinPath(names[0], OptionStableHashString(names[1] + objFileName))
    }

    public func UpdateCachedDirName(fullPackageName: String): Unit {
        let names = GenerateNamesOfCachedDirAndFile(fullPackageName)
        compilationCachedDir = names[0]
        compilationCachedFileName = names[1]
        if (!FileExist(compilationCachedDir)) {
            let _ = CreateDirs(compilationCachedDir + DIR_SEPARATOR)
        }
    }

    public func GetJobs(): Int64 {
        return if (jobs <= 0) { 1 } else { jobs }
    }

    public func NeedDumpASTToFile(): Bool {
        return NeedDumpAST() && !dumpToScreen
    }

    public func NeedDumpASTToScreen(): Bool {
        return NeedDumpAST() && dumpToScreen
    }

    public func NeedDumpAST(): Bool {
        return dumpAST || dumpAll
    }

    public func NeedDumpCHIRToScreen(): Bool {
        return dumpCHIR && dumpToScreen
    }

    public func IsCompilingCJMP(): Bool {
        return !commonPartCjos.isEmpty() || !commonPartChirs.isEmpty()
    }

    public func IsConstEvalEnabled(): Bool {
        return interpreter
    }

    public func IsEmitCHIREnable(): Bool {
        return false
    }

    public func GetCangjieLibTargetPathName(): String {
        return "linux_x86_64_cjnative"
    }

    public func GetCangjieLibHostPathName(): String {
        return "linux_x86_64_cjnative"
    }

    public func ToSerialized(): String {
        let builder = StringBuilder()
        builder.append("frontendMode:")
        builder.append(frontendMode.toString())
        builder.append(",output:")
        builder.append(output)
        builder.append(",srcFiles:")
        var idx: Int64 = 0
        while (idx < srcFiles.size) {
            if (idx > 0) {
                builder.append(";")
            }
            builder.append(srcFiles[idx])
            idx++
        }
        return builder.toString()
    }

    public func CopyBaseFrom(other: GlobalOptions): Unit {
        frontendMode = other.frontendMode
        cangjieHome = other.cangjieHome
        environment.cangjieHome = other.environment.cangjieHome
        output = other.output
        outputDir = other.outputDir
        executablePath = other.executablePath
        moduleSrcPath = other.moduleSrcPath
        replaceArrayList(packagePaths, other.packagePaths)
        replaceArrayList(srcFiles, other.srcFiles)
        replaceArrayList(inputObjs, other.inputObjs)
        inputCjoFile = other.inputCjoFile
        replaceArrayList(importPaths, other.importPaths)
        replaceArrayList(pluginPaths, other.pluginPaths)
        replaceArrayList(commonPartCjos, other.commonPartCjos)
        replaceArrayList(commonPartChirs, other.commonPartChirs)
        replaceArrayList(bcPackageNames, other.bcPackageNames)
        copyStringSet(directBuiltinDependencies, other.directBuiltinDependencies)
        copyStringSet(indirectBuiltinDependencies, other.indirectBuiltinDependencies)
        copyStringMap(passedWhenKeyValue, other.passedWhenKeyValue)
        replaceArrayList(passedWhenCfgPaths, other.passedWhenCfgPaths)
        compilePackage = other.compilePackage
        parseTest = other.parseTest
        compileTestsOnly = other.compileTestsOnly
        enableAddCommentToAst = other.enableAddCommentToAst
        compileCjd = other.compileCjd
        noSubPkg = other.noSubPkg
        scanDepPkg = other.scanDepPkg
        enableInteropCJMapping = other.enableInteropCJMapping
        interopCJPackageConfigPath = other.interopCJPackageConfigPath
        chirDeserialize = other.chirDeserialize
        chirDeserializePath = other.chirDeserializePath
        dumpCHIR = other.dumpCHIR
        dumpAST = other.dumpAST
        dumpToScreen = other.dumpToScreen
        dumpAll = other.dumpAll
        enableVerbose = other.enableVerbose
        enableMacroInLSP = other.enableMacroInLSP
        enIncrementalCompilation = other.enIncrementalCompilation
        cjdbMode = other.cjdbMode
        printVersionOnly = other.printVersionOnly
        showUsage = other.showUsage
        enableCompileDebug = other.enableCompileDebug
        displayLineInfo = other.displayLineInfo
        interpreter = other.interpreter
        overflowStrategy = other.overflowStrategy
        jobs = other.jobs
        compilationCachedPath = other.compilationCachedPath
        compilationCachedDir = other.compilationCachedDir
        compilationCachedFileName = other.compilationCachedFileName
        argList = other.argList
    }
}

public func SetupConditionalCompilationCfg(opts: GlobalOptions): Bool {
    if (!opts.passedWhenKeyValue.isEmpty()) {
        return true
    }
    for (path in opts.passedWhenCfgPaths) {
        let filePath = JoinPath(path, "cfg.toml")
        if (FileExist(filePath)) {
            return OptionSetupConditionalCompilationCfgFromFile(filePath, opts.passedWhenKeyValue)
        }
    }
    let defaultCfgFilePath = if (opts.packagePaths.isEmpty()) {
        "cfg.toml"
    } else {
        JoinPath(opts.packagePaths[0], "cfg.toml")
    }
    if (!FileExist(defaultCfgFilePath)) {
        return true
    }
    return OptionSetupConditionalCompilationCfgFromFile(defaultCfgFilePath, opts.passedWhenKeyValue)
}

public enum DumpAction {
    | NO_ACTION
    | DUMP_TOKENS
    | DUMP_SYMBOLS
    | TYPE_CHECK
    | DUMP_DEP_PKG
    | DESERIALIZE_CHIR
}

private func DumpActionIndex(action: DumpAction): Int64 {
    return match (action) {
        case DumpAction.NO_ACTION => 0
        case DumpAction.DUMP_TOKENS => 1
        case DumpAction.DUMP_SYMBOLS => 2
        case DumpAction.TYPE_CHECK => 3
        case DumpAction.DUMP_DEP_PKG => 4
        case DumpAction.DESERIALIZE_CHIR => 5
    }
}

extend DumpAction <: Equatable<DumpAction> {
    public operator func ==(rhs: DumpAction): Bool {
        return DumpActionIndex(this) == DumpActionIndex(rhs)
    }

    public operator func !=(rhs: DumpAction): Bool {
        return !(this == rhs)
    }
}

public class FrontendOptions <: GlobalOptions {
    public var dumpAction: DumpAction = DumpAction.NO_ACTION

    public init() {
        super()
    }

    protected override func ParseOption(arg: OptionArgInstance): Option<Bool> {
        let id = arg.info.id
        if (id == OptionID.DUMP_TOKENS) {
            dumpAction = DumpAction.DUMP_TOKENS
            return Some(true)
        }
        if (id == OptionID.DUMP_SYMBOLS) {
            dumpAction = DumpAction.DUMP_SYMBOLS
            return Some(true)
        }
        if (id == OptionID.TYPE_CHECK) {
            dumpAction = DumpAction.TYPE_CHECK
            return Some(true)
        }
        if (id == OptionID.DUMP_DEPENDENT_PACKAGE) {
            scanDepPkg = true
            dumpAction = DumpAction.DUMP_DEP_PKG
            return Some(true)
        }
        if (id == OptionID.DESERIALIZE_CHIR_AND_DUMP) {
            chirDeserialize = true
            dumpCHIR = true
            chirDeserializePath = arg.value
            dumpAction = DumpAction.DESERIALIZE_CHIR
            return Some(true)
        }
        if (id == OptionID.COMPILE_CJD) {
            compileCjd = true
            return Some(true)
        }
        return None
    }

    public func CopyFrom(other: FrontendOptions): Unit {
        CopyBaseFrom(other)
        dumpAction = other.dumpAction
    }
}

private func ParsePositiveInt(text: String, fallback: Int64): Int64 {
    if (text.isEmpty()) {
        return fallback
    }
    var out: Int64 = 0
    for (byte in text.toArray()) {
        if (byte < b'0' || byte > b'9') {
            return fallback
        }
        out = out * 10 + Int64(byte - b'0')
    }
    return if (out <= 0) { fallback } else { out }
}

private func replaceArrayList(target: ArrayList<String>, source: ArrayList<String>): Unit {
    target.clear()
    for (value in source) {
        target.add(value)
    }
}

private func copyStringSet(target: HashSet<String>, source: HashSet<String>): Unit {
    target.clear()
    for (value in source) {
        target.add(value)
    }
}

private func copyStringMap(target: HashMap<String, String>, source: HashMap<String, String>): Unit {
    target.clear()
    for ((key, value) in source) {
        target.add(key, value)
    }
}

private func ParsePassedWhenOption(opts: GlobalOptions, value: String): Bool {
    if (value.isEmpty()) {
        return false
    }
    if (IsCfgPathMode(value)) {
        let path = value.replace("\\=", "=")
        if (!IsDir(path)) {
            return false
        }
        opts.passedWhenCfgPaths.add(path)
        return true
    }
    let entries = SplitStringByByte(value, b',')
    for (entry in entries) {
        if (!ParseCfgEntry(entry, opts.passedWhenKeyValue)) {
            return false
        }
    }
    return true
}

private func ParseCfgEntry(entry: String, target: HashMap<String, String>): Bool {
    let content = TrimAscii(entry)
    if (content.isEmpty() || CountOccurrences(content, "=") != 1) {
        return false
    }
    if (let Some(eqPos) <- content.indexOf("=")) {
        let rawKey = TrimAscii(content[0..eqPos])
        let rawValue = TrimAscii(content[eqPos + 1..])
        let key = NormalizeCfgKey(rawKey)
        if (key.isEmpty() || rawValue.isEmpty() || IsBuiltinCfgKey(key) || target.contains(key)) {
            return false
        }
        target.add(key, rawValue)
        return true
    }
    return false
}

private func IsCfgPathMode(value: String): Bool {
    return CountOccurrences(value, "=") == CountOccurrences(value, "\\=")
}

private func CountOccurrences(input: String, needle: String): Int64 {
    if (needle.isEmpty()) {
        return 0
    }
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

private func NormalizeCfgKey(rawKey: String): String {
    if (rawKey.size > 2 && rawKey[0] == b'`' && rawKey[rawKey.size - 1] == b'`') {
        return rawKey[1..rawKey.size - 1]
    }
    if (!FileUtil.IsIdentifier(rawKey)) {
        return ""
    }
    return rawKey
}

private func IsBuiltinCfgKey(key: String): Bool {
    return key == "os" || key == "backend" || key == "arch" || key == "debug" ||
        key == "cjc_version" || key == "test"
}

private func SplitStringByByte(value: String, delimiter: UInt8): ArrayList<String> {
    let out = ArrayList<String>()
    var start: Int64 = 0
    var idx: Int64 = 0
    while (idx < value.size) {
        if (value[idx] == delimiter) {
            out.add(value[start..idx])
            start = idx + 1
        }
        idx++
    }
    out.add(value[start..])
    return out
}

private func TrimAscii(value: String): String {
    var start: Int64 = 0
    var end = value.size
    while (start < end && IsAsciiSpace(value[start])) {
        start++
    }
    while (end > start && IsAsciiSpace(value[end - 1])) {
        end--
    }
    return value[start..end]
}

private func IsAsciiSpace(byte: UInt8): Bool {
    return byte == b' ' || byte == b'\t' || byte == b'\r' || byte == b'\n'
}
