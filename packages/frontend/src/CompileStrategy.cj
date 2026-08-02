package cjcj::frontend

import cjcj::ast.AddCurFile
import cjcj::ast.TokenKind
import cjcj::basic.InteropCJPackageConfigReader
import cjcj::conditional_compilation.ConditionalCompilation
import cjcj::lex.TokenVecMap
import cjcj::parse.Parser as RealParser
import cjcj::basic.DiagCategory
import cjcj::macro_pkg.MacroExpansion
import cjcj::sema.TypeCheckExpr.TypeChecker as FaithfulSemaTypeChecker
import cjcj::sema.StrategyType
import cjcj::utils.{CJC_ASSERT, CJC_ASSERT_WITH_MSG, CreateAltSignalStack, RegisterCrashSignalHandler, TaskQueue,
    TaskResult}
import cjcj::utils.FileUtil
import cjcj::utils.OverflowStrategy as FaithfulOverflowStrategy
import cjcj::utils.CJ_D_FILE_EXTENSION
import cjcj::utils.InternalError
import cjcj::utils.ProfileRecorder
import std.collection.*
import std.sort.*
import std.sync.*

// Faithful ports of the C++ .cj.d process-wide caches (Frontend/CompileStrategy.cpp:464-467).
private let g_cjdAstCache = HashMap<String, Option<Package>>()
private let g_cjdAstCacheLock = Mutex()
private let g_sourceManageLock = Mutex()

private type ParseResult = (File, TokenVecMap, Int64)
private type ParseTaskResult = TaskResult<ParseResult>
private type ParseTaskResults = ArrayList<ParseTaskResult>

// Faithful port of C++ ParseAndMergeCjd (Frontend/CompileStrategy.cpp:469-512).
func ParseAndMergeCjd(ci: CompilerInstance, cjdInfo: (String, String)): Unit {
    let cjoPath = cjdInfo[1]
    var sourceCode = ReadFileContent(cjoPath)
    if (!sourceCode[0]) {
        let searchPath = ci.importManager.getOrThrow().GetSearchPath()
        let cjdPath = FileUtil.FindSerializationFile(cjdInfo[0], CJ_D_FILE_EXTENSION, searchPath.toArray())
        if (cjdPath.isEmpty()) {
            return
        }
        sourceCode = ReadFileContent(cjdPath)
        if (!sourceCode[0]) {
            return
        }
    }

    let sourceManager = ci.diag.GetSourceManager()
    let fileId = synchronized(g_sourceManageLock) {
        let isCjmpFile = ci.invocation.globalOptions.IsCompilingCJMP() ||
            !ci.invocation.globalOptions.commonPartCjos.isEmpty()
        sourceManager.AddSource(cjoPath, sourceCode[1], packageName: Some(cjdInfo[0]), isCjmpFile: isCjmpFile)
    }
    let fileAst = RealParser(fileId, sourceCode[1], ci.diag.AsBasicDiagnosticEngine(),
        ci.diag.GetSourceManager(), parseDeclFile: true).ParseTopLevel()
    let pkg = Package(cjdInfo[0])
    fileAst.curPackage = Some(pkg)
    pkg.files.add(fileAst)
    if (let Some(originPkg) <- ci.importManager.getOrThrow().GetPackage(cjdInfo[0])) {
        MergeCusAnno(originPkg, pkg)
    } else {
        InternalError(cjdInfo[0] + " cannot find origin ast")
    }
    synchronized(g_cjdAstCacheLock) {
        g_cjdAstCache[cjdInfo[0]] = Some(pkg)
    }
}

public open class CompileStrategy {
    protected let ci: CompilerInstance
    public var strategyKind: StrategyType = StrategyType.DEFAULT
    protected let fileIds: HashSet<UInt64> = HashSet<UInt64>()

    public init(ci: CompilerInstance) {
        this.ci = ci
    }

    public open func Parse(): Bool {
        return false
    }

    public func ConditionCompile(): Bool {
        // Faithful port of C++ CompileStrategy::ConditionCompile (Frontend/CompileStrategy.cpp:59-67):
        // run the conditional-compilation pass over each source package; succeed iff it added no errors.
        let basicDiag = ci.diag.AsBasicDiagnosticEngine()
        let beforeErrCnt = basicDiag.GetErrorCount()
        let cc = ConditionalCompilation(ci.invocation.globalOptions, basicDiag)
        for (pkg in ci.srcPkgs) {
            cc.HandleConditionalCompilation(pkg)
        }
        return beforeErrCnt == basicDiag.GetErrorCount()
    }

    public func DesugarAfterSema(): Unit {
        let packages = ci.GetSourcePackages()
        let typeChecker = ci.GetTypeChecker()
        typeChecker.PerformDesugarAfterSema(packages)
    }

    public func InteropConfigTomlCheck(): Unit {
        try (recorder = ProfileRecorder("Semantic", "InteropConfigTomlCheck")) {
            let packagesFullConfig = InteropCJPackageConfigReader()
            if (ci.invocation.globalOptions.enableInteropCJMapping &&
                ci.invocation.globalOptions.interopCJPackageConfigPath != "./" &&
                !packagesFullConfig.Parse(ci.invocation.globalOptions.interopCJPackageConfigPath)) {
                ci.diag.DiagnoseRefactor(DiagKindRefactor.sema_cj_mapping_generic_method_not_get_instance_config,
                    DEFAULT_POSITION, arguments: [ci.invocation.globalOptions.interopCJPackageConfigPath])
            }
        }
    }

    public func ImportPackages(): Bool {
        let result = ci.ImportPackages()
        ParseAndMergeCjds()
        return result
    }

    // Faithful port of C++ CompileStrategy::ParseAndMergeCjds (Frontend/CompileStrategy.cpp:514-560).
    public func ParseAndMergeCjds(): Unit {
        let option = ci.invocation.globalOptions
        let hasLevelFlag = option.passedWhenKeyValue.contains("APILevel_level")
        let hasSyscapFlag = option.passedWhenKeyValue.contains("APILevel_syscap")
        if (!hasLevelFlag && !hasSyscapFlag) {
            return
        }
        ProfileRecorder.Start("ImportPackages", "ParseAndMergeCjds")
        let cjdInfos = ci.importManager.getOrThrow().GetDepPkgCjdPaths()
        let futures = ArrayList<Future<Unit>>()
        option.compileCjd = true
        for ((packageName, cjdPath) in cjdInfos) {
            let cjdInfo = (packageName, cjdPath)
            if (option.jobs.hasValue && option.jobs.value == 1u64) {
                ParseAndMergeCjd(ci, cjdInfo)
            } else {
                synchronized(g_cjdAstCacheLock) {
                    if (let Some(cachedPackage) <- g_cjdAstCache.get(packageName)) {
                        if (let Some(cachedPackageValue) <- cachedPackage) {
                            if (let Some(originPkg) <- ci.importManager.getOrThrow().GetPackage(packageName)) {
                                MergeCusAnno(originPkg, cachedPackageValue)
                            } else {
                                InternalError(packageName + " cannot find origin ast")
                            }
                        } else {
                            futures.add(spawn { ParseAndMergeCjd(ci, cjdInfo) })
                        }
                    } else {
                        g_cjdAstCache[packageName] = None
                        futures.add(spawn { ParseAndMergeCjd(ci, cjdInfo) })
                    }
                }
            }
        }
        for (future in futures) {
            future.get()
        }
        ci.diag.EmitCategoryGroup()
        option.compileCjd = false
        ProfileRecorder.Stop("ImportPackages", "ParseAndMergeCjds")
    }

    public func MacroExpand(): Bool {
        let beforeErrCnt = ci.diag.GetErrorCount()
        let host = MacroHostAdapter(ci)
        let expansion = MacroExpansion(host)
        expansion.Execute(ci.srcPkgs)
        ci.diag.EmitCategoryDiagnostics(DiagCategory.PARSE)
        ci.tokensEvalInMacro.clear()
        for (tokens in expansion.tokensEvalInMacro) {
            ci.tokensEvalInMacro.add(tokens)
        }
        return beforeErrCnt == ci.diag.GetErrorCount()
    }

    public open func Sema(): Bool {
        return true
    }

    public func OverflowStrategy(): Bool {
        let typeChecker = FaithfulSemaTypeChecker(ci.faithfulSemaInstance)
        CJC_ASSERT(ci.invocation.globalOptions.overflowStrategy != FaithfulOverflowStrategy.NA)
        typeChecker.SetOverflowStrategy(ci.GetSourcePackages())
        return true
    }
}

public class FullCompileStrategy <: CompileStrategy {
    private var impl: Option<FullCompileStrategyImpl> = None

    public init(ci: CompilerInstance) {
        super(ci)
        impl = Some(FullCompileStrategyImpl(this))
        strategyKind = StrategyType.FULL_COMPILE
    }

    public override func Parse(): Bool {
        var ret = true
        let strategyImpl = impl.getOrThrow()
        if (ci.loadSrcFilesFromCache || ci.compileOnePackageFromSrcFiles) {
            let incrParse = ci.loadSrcFilesFromCache && !ci.srcPkgs.isEmpty() && !ci.HasTypeChecker()
            if (incrParse) {
                strategyImpl.ParseOnePackage(ci.srcPkgs[0])
            } else {
                let parsed = strategyImpl.ParseOnePackage(ci.srcFilePaths, DEFAULT_PACKAGE_NAME)
                ci.srcPkgs.add(parsed[0])
                ret = parsed[1]
            }
        } else {
            ret = strategyImpl.ParseModule()
        }
        ci.RefreshASTContexts()
        ci.diag.EmitCategoryGroup()
        return ret
    }

    public override func Sema(): Bool {
        return true
    }
}

private class FullCompileStrategyImpl {
    private let s: FullCompileStrategy

    init(strategy: FullCompileStrategy) {
        s = strategy
    }

    public func ParseModule(): Bool {
        var success = true
        let moduleSrcPath = s.ci.invocation.globalOptions.moduleSrcPath
        let includeFileSet = HashSet<String>()
        for (srcPath in s.ci.invocation.globalOptions.srcFiles) {
            includeFileSet.add(srcPath)
        }
        for (srcDir in s.ci.srcDirs) {
            let allSrcFiles = ArrayList<String>()
            var currentPkg = DEFAULT_PACKAGE_NAME
            if (!moduleSrcPath.isEmpty()) {
                let basePath = if (IsDir(moduleSrcPath)) { JoinPath(moduleSrcPath, "") } else { moduleSrcPath }
                currentPkg = FileUtil.GetPkgNameFromRelativePath(FileUtil.GetRelativePath(basePath, srcDir) ?? "")
            }
            let parseTest = s.ci.invocation.globalOptions.parseTest
            let compileTestsOnly = s.ci.invocation.globalOptions.compileTestsOnly
            let files = GetAllFilesUnderCurrentPath(srcDir, "cj", shouldSkipTestFiles: !parseTest,
                shouldSkipRegularFiles: compileTestsOnly)
            for (srcFile in files) {
                let filename = JoinPath(srcDir, srcFile)
                if (includeFileSet.isEmpty() || includeFileSet.contains(filename)) {
                    allSrcFiles.add(filename)
                }
            }
            let parsed = ParseOnePackage(allSrcFiles, currentPkg)
            let parsedPkg = parsed[0]
            success = success && parsed[1]
            if (srcDir == moduleSrcPath) {
                parsedPkg.needExported = false
            }
            s.ci.srcPkgs.add(parsedPkg)
        }
        for (pkg in s.ci.srcPkgs) {
            sort(pkg.files, by: { left: File, right: File => compareString(left.fileName, right.fileName) })
        }
        return success
    }

    public func ParseOnePackage(files: ArrayList<String>, defaultPackageName: String): (Package, Bool) {
        var success = true
        let fileInfoQueue = ArrayList<(String, UInt64)>()
        if (s.ci.loadSrcFilesFromCache) {
            for ((path, cacheInfo) in s.ci.bufferCache) {
                if (cacheInfo.state == SrcCodeChangeState.DELETED) {
                    continue
                }
                let isCjmpFile = s.ci.invocation.globalOptions.IsCompilingCJMP()
                let fileID = s.ci.GetSourceManager().AddSource(path, cacheInfo.code, isCjmpFile: isCjmpFile)
                if (s.fileIds.contains(fileID)) {
                    s.ci.diag.DiagnoseRefactor(DiagKindRefactor.module_read_file_conflicted,
                        DEFAULT_POSITION, arguments: [path])
                }
                s.fileIds.add(fileID)
                fileInfoQueue.add((cacheInfo.code, fileID))
            }
        } else {
            let parseFiles = ArrayList<String>()
            for (file in files) {
                parseFiles.add(file)
            }
            sort(parseFiles, by: { left: String, right: String => compareString(GetFileName(left), GetFileName(right)) })
            for (filePath in parseFiles) {
                let readResult = ReadFileContent(filePath)
                if (!readResult[0]) {
                    s.ci.diag.DiagnoseRefactor(DiagKindRefactor.module_read_file_to_buffer_failed,
                        DEFAULT_POSITION, arguments: [filePath, readResult[2]])
                    success = false
                    continue
                }
                let isCjmpFile = s.ci.invocation.globalOptions.IsCompilingCJMP()
                let fileID = s.ci.GetSourceManager().AddSource(filePath, readResult[1], isCjmpFile: isCjmpFile)
                if (s.fileIds.contains(fileID)) {
                    s.ci.diag.DiagnoseRefactor(DiagKindRefactor.module_read_file_conflicted,
                        DEFAULT_POSITION, arguments: [filePath])
                    continue
                }
                s.fileIds.add(fileID)
                fileInfoQueue.add((readResult[1], fileID))
            }
        }
        let pkg = MultiThreadParseOnePackage(fileInfoQueue, defaultPackageName)
        AddCurFile(pkg)
        return (pkg, success)
    }

    public func ParseOnePackage(pkg: Package): Unit {
        let fileInfoQueue = ArrayList<(String, UInt64)>()
        BuildFileInfoQueueFromCache(pkg, fileInfoQueue)
        if (!fileInfoQueue.isEmpty()) {
            MultiThreadParseOnePackage(pkg, fileInfoQueue)
            sort(pkg.files, by: { left: File, right: File => compareString(left.fileName, right.fileName) })
            AddCurFile(pkg)
            s.ci.diag.EmitCategoryGroup()
        }
    }

    public func CheckPackageConsistency(pkg: Package): Unit {
        if (pkg.files.isEmpty()) {
            return
        }
        if (let Some(packageSpec) <- pkg.files[0].packageSpec) {
            for (file in pkg.files) {
                if (let Some(filePackageSpec) <- file.packageSpec) {
                    if (filePackageSpec.hasMacro != packageSpec.hasMacro) {
                        s.ci.diag.DiagnoseRefactor(DiagKindRefactor.package_name_inconsistent_with_macro,
                            filePackageSpec.begin)
                        return
                    }
                }
            }
            pkg.isMacroPackage = packageSpec.hasMacro
        }
    }

    public func InitializePackageInfoFromFirstFile(pkg: Package): Unit {
        if (pkg.files.isEmpty()) {
            return
        }
        if (let Some(packageSpec) <- pkg.files[0].packageSpec) {
            pkg.fullPackageName = packageSpec.GetPackageName()
            if (let Some(modifier) <- packageSpec.modifier) {
                if (modifier.modifier == TokenKind.PROTECTED) {
                    pkg.accessible = AccessLevel.PROTECTED
                } else if (modifier.modifier == TokenKind.INTERNAL) {
                    pkg.accessible = AccessLevel.INTERNAL
                } else {
                    pkg.accessible = AccessLevel.PUBLIC
                }
            } else {
                pkg.accessible = AccessLevel.PUBLIC
            }
        }
    }

    public func AddFilesToPackage(pkg: Package, taskResults: ParseTaskResults): Int64 {
        var lineCountOfAddedFiles: Int64 = 0
        for (taskResult in taskResults) {
            let curResult = taskResult.get()
            let file = curResult[0]
            file.curPackage = Some(pkg)
            file.indexOfPackage = UInt64(pkg.files.size)
            pkg.files.add(file)
            // C++ CompileStrategy.cpp:188 calls SourceManager::AddComments here. The selfhost TokenVecMap is
            // retained in ParseResult, while the existing lex.TokenVecMap -> basic.SourceManager package boundary is
            // registered in compiler_unittest/PortDeferred.cj.
            let _ = curResult[1]
            lineCountOfAddedFiles += curResult[2]
        }
        InitializePackageInfoFromFirstFile(pkg)
        return lineCountOfAddedFiles
    }

    public func GetMultiThreadParseOnePackage(taskResults: ParseTaskResults,
        defaultPackageName: String): Package {
        let pkg = Package(defaultPackageName)
        let lineNumInOnePackage = AddFilesToPackage(pkg, taskResults)
        ProfileRecorder.RecordCodeInfo("package line num", lineNumInOnePackage)
        CheckPackageConsistency(pkg)
        return pkg
    }

    public func ParseFilesWithTaskQueue(fileInfoQueue: ArrayList<(String, UInt64)>): ParseTaskResults {
        let options = s.ci.invocation.globalOptions
        let threadsNum = if (options.disableParseConcurrency) { 1 } else { Int64(options.GetJobs()) }
        let taskQueue = TaskQueue(threadsNum)
        let taskResults = ParseTaskResults()
        for (curFile in fileInfoQueue) {
            let taskResult = taskQueue.AddTask<ParseResult>({ =>
                @When[!debug && os != "Windows"]
                let _ = CreateAltSignalStack()
                @When[!debug && os == "Windows"]
                let _ = RegisterCrashSignalHandler()
                let parser = CreateParser(curFile)
                parser.SetCompileOptions(options)
                let file = parser.ParseTopLevel()
                return (file, parser.GetCommentsMap(), parser.GetLineNum())
            })
            taskResults.add(taskResult)
        }
        taskQueue.RunAndWaitForAllTasksCompleted()
        return taskResults
    }

    public func MultiThreadParseOnePackage(fileInfoQueue: ArrayList<(String, UInt64)>,
        defaultPackageName: String): Package {
        let taskResults = ParseFilesWithTaskQueue(fileInfoQueue)
        return GetMultiThreadParseOnePackage(taskResults, defaultPackageName)
    }

    public func MultiThreadParseOnePackage(pkg: Package, fileInfoQueue: ArrayList<(String, UInt64)>): Unit {
        let taskResults = ParseFilesWithTaskQueue(fileInfoQueue)
        let lineCountOfAddedFiles = AddFilesToPackage(pkg, taskResults)
        for (file in pkg.files) {
            if (let Some(curPackage) <- file.curPackage) {
                CJC_ASSERT_WITH_MSG(curPackage == pkg, "curPackage should be set to package")
            } else {
                CJC_ASSERT_WITH_MSG(false, "curPackage should be set to package")
            }
        }
        ProfileRecorder.RecordCodeInfo("added line num", lineCountOfAddedFiles)
        CheckPackageConsistency(pkg)
    }

    public func CreateParser(curFile: (String, UInt64)): RealParser {
        let options = s.ci.invocation.globalOptions
        return RealParser(curFile[1], curFile[0], s.ci.diag.AsBasicDiagnosticEngine(), s.ci.GetSourceManager(),
            attachComment: options.enableAddCommentToAst, parseDeclFile: options.compileCjd)
    }

    public func DeleteFileInPackage(pkg: Package, filePath: String): Unit {
        var idx: Int64 = 0
        while (idx < pkg.files.size) {
            if (pkg.files[idx].filePath == filePath) {
                pkg.files.remove(at: idx)
            } else {
                idx++
            }
        }
    }

    public func BuildFileInfoQueueFromCache(pkg: Package, fileInfoQueue: ArrayList<(String, UInt64)>): Unit {
        let deletedFiles = ArrayList<String>()
        for ((filePath, cacheInfo) in s.ci.bufferCache) {
            let state = cacheInfo.state
            if (state == SrcCodeChangeState.UNCHANGED) {
                continue
            }
            if (state == SrcCodeChangeState.DELETED) {
                DeleteFileInPackage(pkg, filePath)
                deletedFiles.add(filePath)
                continue
            }
            if (state != SrcCodeChangeState.ADDED) {
                DeleteFileInPackage(pkg, filePath)
            }
            var fileAlreadyExists = false
            for (file in pkg.files) {
                if (file.filePath == filePath) {
                    fileAlreadyExists = true
                    break
                }
            }
            CJC_ASSERT_WITH_MSG(state != SrcCodeChangeState.ADDED || !fileAlreadyExists, "File already exists")
            let fileID = s.ci.GetSourceManager().AddSource(filePath, cacheInfo.code)
            s.fileIds.add(fileID)
            fileInfoQueue.add((cacheInfo.code, fileID))
        }
        for (filePath in deletedFiles) {
            s.ci.bufferCache.remove(filePath)
        }
    }
}

private func compareString(left: String, right: String): Ordering {
    if (left < right) {
        return Ordering.LT
    }
    if (left > right) {
        return Ordering.GT
    }
    return Ordering.EQ
}
