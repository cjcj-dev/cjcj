package cjcj::frontend

import cjcj::ast.Package as RealASTPackage
import cjcj::ast.PackageDecl as RealASTPackageDecl
import cjcj::ast.StructTy as RealASTStructTy
import cjcj::ast.PrintNode
import cjcj::mangle.BaseMangler as RealBaseMangler
import cjcj::mangle.CHIRMangler as RealCHIRMangler
import cjcj::mangle.MangleAstAdapter as RealMangleAstAdapter
import cjcj::mangle.MangleDecl as RealMangleDecl
import cjcj::mangle.ManglerContext as RealManglerContext
import cjcj::sema.CompilerInstance as FaithfulSemaCompilerInstance
import cjcj::sema.GenericInstantiation.GenericInstantiationManager
import cjcj::sema.Desugar.DesugarBeforeTypeCheck as FaithfulDesugarBeforeTypeCheck
import cjcj::sema.AnalyzeFunctionLinkage
import cjcj::sema.CheckInlineFunctionsForPackages
import cjcj::sema.TypeCheckExpr.TypeChecker as FaithfulSemaTypeChecker
import cjcj::sema.TypeCheckReferenceRemoveTargetNotMeetExtendConstraint
import cjcj::meta_transformation.MetaTransformPluginBuilder
import cjcj::meta_transformation.NativeMetaTransformPlugin
import cjcj::lex.Lexer as CangjieLexer
import cjcj::lex.TokenKind as CangjieTokenKind
import cjcj::lex.TokenKindValue
import cjcj::incremental_compilation.CachedMangleMap
import cjcj::incremental_compilation.IncreKind
import cjcj::incremental_compilation.{ASTCache, ASTCacheCalculator, CompilationCache, FileMap,
    MemberDeclCache, OptEffectStrMap, RawMangled2DeclMap, SemanticInfo, TopLevelDeclCache, VarInitDepMap,
    VirtualWrapperDepMap, WriteCache}
import cjcj::macro_pkg.{GetMethodPointer, OpenSymbolTable, OpenSymbolTableSafely, RuntimeInit}
import cjcj::option.OutputMode
import cjcj::utils.FreeIdleMemoryToOS
import cjcj::utils.ProfileRecorder
import cjcj::utils.STANDARD_LIBS
import cjcj::utils.IncrementalCompilationLogger
import cjcj::utils.InternalError
import cjcj::utils.CJC_ABORT
import cjcj::chir.CHIRBuilder as ChirBuilder
import cjcj::chir.CHIRDeserializer as ChirDeserializer
import cjcj::chir.CHIRPrinter as ChirPrinter
import cjcj::chir.ToCHIRPhase as ChirToCHIRPhase
import std.collection.*
import std.core.Box as CoreBox

// Faithful port of C++ RegisterMacroCallDiagInfos (Frontend/CompilerInstance.cpp:935-947).
func RegisterMacroCallDiagInfos(diag: DiagnosticEngine, pkg: Package): Unit {
    for (file in pkg.files) {
        for (macroCall in file.originalMacroCallNodes) {
            if (let Some(invocation) <- macroCall.GetInvocation()) {
                diag.AsBasicDiagnosticEngine().RegisterMacroCallDiagInfo(invocation.macroCallDiagInfo)
            }
        }
    }
}

private class PendingMangledDecl {
    public let astDecl: Decl
    public let mangleDecl: RealMangleDecl
    public let mangledName: String

    public init(astDecl: Decl, mangleDecl: RealMangleDecl, mangledName: String) {
        this.astDecl = astDecl
        this.mangleDecl = mangleDecl
        this.mangledName = mangledName
    }
}

private class PendingMangledLambda {
    public let astLambda: LambdaExpr
    public let mangleLambda: RealMangleDecl
    public let mangledName: String

    public init(astLambda: LambdaExpr, mangleLambda: RealMangleDecl, mangledName: String) {
        this.astLambda = astLambda
        this.mangleLambda = mangleLambda
        this.mangledName = mangledName
    }
}

public enum CompileStage {
    | LOAD_PLUGINS
    | PARSE
    | CONDITION_COMPILE
    | IMPORT_PACKAGE
    | MACRO_EXPAND
    | AST_DIFF
    | SEMA
    | DESUGAR_AFTER_SEMA
    | GENERIC_INSTANTIATION
    | OVERFLOW_STRATEGY
    | MANGLING
    | SAVE_CJO
    | CHIR
    | CODEGEN
    | SAVE_RESULTS
    | COMPILE_STAGE_NUMBER
}

public func CompileStageIndex(stage: CompileStage): Int64 {
    return match (stage) {
        case CompileStage.LOAD_PLUGINS => 0
        case CompileStage.PARSE => 1
        case CompileStage.CONDITION_COMPILE => 2
        case CompileStage.IMPORT_PACKAGE => 3
        case CompileStage.MACRO_EXPAND => 4
        case CompileStage.AST_DIFF => 5
        case CompileStage.SEMA => 6
        case CompileStage.DESUGAR_AFTER_SEMA => 7
        case CompileStage.GENERIC_INSTANTIATION => 8
        case CompileStage.OVERFLOW_STRATEGY => 9
        case CompileStage.MANGLING => 10
        case CompileStage.SAVE_CJO => 11
        case CompileStage.CHIR => 12
        case CompileStage.CODEGEN => 13
        case CompileStage.SAVE_RESULTS => 14
        case CompileStage.COMPILE_STAGE_NUMBER => 15
    }
}

extend CompileStage <: Equatable<CompileStage> {
    public operator func ==(rhs: CompileStage): Bool {
        return CompileStageIndex(this) == CompileStageIndex(rhs)
    }

    public operator func !=(rhs: CompileStage): Bool {
        return !(this == rhs)
    }
}

private func StageFromIndex(idx: Int64): CompileStage {
    if (idx == 0) { return CompileStage.LOAD_PLUGINS }
    if (idx == 1) { return CompileStage.PARSE }
    if (idx == 2) { return CompileStage.CONDITION_COMPILE }
    if (idx == 3) { return CompileStage.IMPORT_PACKAGE }
    if (idx == 4) { return CompileStage.MACRO_EXPAND }
    if (idx == 5) { return CompileStage.AST_DIFF }
    if (idx == 6) { return CompileStage.SEMA }
    if (idx == 7) { return CompileStage.DESUGAR_AFTER_SEMA }
    if (idx == 8) { return CompileStage.GENERIC_INSTANTIATION }
    if (idx == 9) { return CompileStage.OVERFLOW_STRATEGY }
    if (idx == 10) { return CompileStage.MANGLING }
    if (idx == 11) { return CompileStage.SAVE_CJO }
    if (idx == 12) { return CompileStage.CHIR }
    if (idx == 13) { return CompileStage.CODEGEN }
    return CompileStage.SAVE_RESULTS
}

public class CHIRInfo {
    public let optEffectMap: OptEffectStrMap = OptEffectStrMap()
    public let ccTys: HashSet<RealASTStructTy> = HashSet<RealASTStructTy>()
    public let curVirtFuncWrapDep: VirtualWrapperDepMap = VirtualWrapperDepMap()
    public let delVirtFuncWrapForIncr: VirtualWrapperDepMap = VirtualWrapperDepMap()
    public let ccOutFuncsRawMangle: HashSet<String> = HashSet<String>()
    public let varInitDepMap: VarInitDepMap = VarInitDepMap()
    public init() {}
}

// C++: Frontend/CompilerInstance.cpp:567-577.
private func UpdateMemberDeclMangleNameForCachedInfo(rawMangleName2DeclMap: RawMangled2DeclMap,
    memCache: MemberDeclCache): Unit {
    if (let Some(decl) <- rawMangleName2DeclMap.get(memCache.rawMangle)) {
        memCache.cgMangle = decl.mangledName
    } else {
        CJC_ABORT()
    }
    for (member in memCache.members) {
        UpdateMemberDeclMangleNameForCachedInfo(rawMangleName2DeclMap, member)
    }
}

// C++: Frontend/CompilerInstance.cpp:579-590.
private func UpdateTopLevelDeclMangleNameForCachedInfo(rawMangleName2DeclMap: RawMangled2DeclMap,
    rawMangle: String, topCache: TopLevelDeclCache): Unit {
    if (let Some(decl) <- rawMangleName2DeclMap.get(rawMangle)) {
        topCache.cgMangle = decl.mangledName
    } else {
        CJC_ABORT()
    }
    for (member in topCache.members) {
        UpdateMemberDeclMangleNameForCachedInfo(rawMangleName2DeclMap, member)
    }
}

private func PackageDiagnosticPosition(pkg: Package): Position {
    if (!pkg.files.isEmpty()) {
        return pkg.files[0].begin
    }
    return DEFAULT_POSITION
}

public enum ExtendMemberQueryType {
    | ByTy(Ty)
    | ByInheritableDecl(InheritableDecl)
}

public class CompilerInstance {
    public let invocation: CompilerInvocation
    public var cangjieHome: String = ""
    public var cangjieModules: String = ""
    public let srcFilePaths: ArrayList<String> = ArrayList<String>()
    public let srcDirs: HashSet<String> = HashSet<String>()
    public let diag: DiagnosticEngine
    public var cachedInfo: CompilationCache = CompilationCache()
    public var rawMangleName2DeclMap: RawMangled2DeclMap = RawMangled2DeclMap()
    public var astCacheInfo: ASTCache = ASTCache()
    public var declsWithDuplicatedRawMangleName: HashSet<Decl> = HashSet<Decl>()
    public var directExtends: HashMap<String, ArrayList<(ExtendDecl, Int64)>> =
        HashMap<String, ArrayList<(ExtendDecl, Int64)>>()
    public var fileMap: FileMap = FileMap()
    public var order: ArrayList<Decl> = ArrayList<Decl>()
    public let chirInfo: CHIRInfo = CHIRInfo()
    public let metaTransformPluginBuilder: MetaTransformPluginBuilder = MetaTransformPluginBuilder()
    public let sm: SourceManager = SourceManager()
    public let typeManager: TypeManager = TypeManager()
    public let importManager: ImportManager
    public let packageManager: PackageManager
    public let testManager: TestManager
    public var gim: Option<GenericInstantiationManager> = None
    public var compileOnePackageFromSrcFiles: Bool = false
    public var loadSrcFilesFromCache: Bool = false
    public let bufferCache: HashMap<String, SrcCodeCacheInfo> = HashMap<String, SrcCodeCacheInfo>()
    public let tokensEvalInMacro: ArrayList<String> = ArrayList<String>()
    public var currentPkg: Option<Package> = None
    public var mangler: RealBaseMangler = RealCHIRMangler(false)
    public let mangledName2DeclMap: HashMap<String, Decl> = HashMap<String, Decl>()
    public var kind: IncreKind = IncreKind.INVALID
    public var releaseCHIRMemory: Bool = true
    public var needToOptString: Bool = false
    public var needToOptGenericDecl: Bool = false
    public var isCJLint: Bool = false
    public var buildTrie: Bool = true
    public let srcPkgs: ArrayList<Package> = ArrayList<Package>()
    public let realASTPkgs: HashMap<String, RealASTPackage> = HashMap<String, RealASTPackage>()
    public let chirData: CHIRData = CHIRData()
    public var faithfulSemaInstance: Option<FaithfulSemaCompilerInstance> = None
    private let pkgs: ArrayList<Package> = ArrayList<Package>()
    private let pkgCtxMap: HashMap<String, ASTContext> = HashMap<String, ASTContext>()
    private let depPackageInfo: ArrayList<String> = ArrayList<String>()
    // ImportManager.h:392 astWriters. Package inherits Node, so this preserves
    // the C++ map's Package* identity semantics.
    private let astWriters: HashMap<Node, ASTWriter> = HashMap<Node, ASTWriter>()
    private var astResourcesDestroyed: Bool = false
    private var compileStrategy: Option<CompileStrategy> = None
    private var hasTypeCheckerFlag: Bool = false
    private let fileNameMap: HashMap<UInt64, String> = HashMap<UInt64, String>()
    private let loadedPluginPaths: ArrayList<String> = ArrayList<String>()
    private let loadedNativeMetaTransformPlugins: ArrayList<NativeMetaTransformPlugin> =
        ArrayList<NativeMetaTransformPlugin>()

    public init(invocation: CompilerInvocation, diag: DiagnosticEngine) {
        this.invocation = invocation
        this.diag = diag
        let faithfulTypeManager = typeManager.AsFaithfulSemaTypeManager()
        importManager = ImportManager(diag, faithfulTypeManager, invocation.globalOptions)
        packageManager = PackageManager(importManager)
        testManager = TestManager(importManager, faithfulTypeManager, diag.AsBasicDiagnosticEngine(),
            invocation.globalOptions)
        compileStrategy = Some(FullCompileStrategy(this))
        chirData.InitData(fileNameMap, Int64(invocation.globalOptions.GetJobs()))
        if (invocation.globalOptions.compilePackage) {
            for (pkgPath in invocation.globalOptions.packagePaths) {
                srcDirs.add(pkgPath)
            }
            compileOnePackageFromSrcFiles = srcDirs.isEmpty()
        } else {
            compileOnePackageFromSrcFiles = true
            for (srcFile in invocation.globalOptions.srcFiles) {
                srcFilePaths.add(srcFile)
            }
        }
        diag.SetSourceManager(sm)
    }

    public func DestroyASTResources(): Unit {
        if (astResourcesDestroyed || invocation.globalOptions.enIncrementalCompilation || invocation.globalOptions.cjdbMode) {
            return
        }
        astResourcesDestroyed = true
        srcPkgs.clear()
        realASTPkgs.clear()
        pkgs.clear()
        pkgCtxMap.clear()
        gim = None
        hasTypeCheckerFlag = false
    }

    public func SetCompileStrategy(newCompileStrategy: CompileStrategy): Unit {
        compileStrategy = Some(newCompileStrategy)
    }

    public func InitCompilerInstance(): Bool {
        return true
    }

    public func Compile(stage!: CompileStage = CompileStage.CHIR): Bool {
        if (!InitCompilerInstance()) {
            diag.ReportErrorAndWarningCount()
            return false
        }
        let endStageNum = CompileStageIndex(stage)
        var idx: Int64 = 0
        var success = true
        while (idx <= endStageNum) {
            if (!performStage(StageFromIndex(idx))) {
                success = false
                break
            }
            idx++
        }
        if (invocation.globalOptions.NeedDumpASTToScreen() && idx < CompileStageIndex(CompileStage.MANGLING)) {
            DumpASTToScreen(GetSourcePackages())
        }
        diag.ReportErrorAndWarningCount()
        return success
    }

    private func performStage(stage: CompileStage): Bool {
        if (stage == CompileStage.LOAD_PLUGINS) { return PerformPluginLoad() }
        if (stage == CompileStage.PARSE) { return PerformParse() }
        if (stage == CompileStage.CONDITION_COMPILE) { return PerformConditionCompile() }
        if (stage == CompileStage.IMPORT_PACKAGE) { return PerformImportPackage() }
        if (stage == CompileStage.MACRO_EXPAND) { return PerformMacroExpand() }
        if (stage == CompileStage.AST_DIFF) { return PerformIncrementalScopeAnalysis() }
        if (stage == CompileStage.SEMA) { return PerformSema() }
        if (stage == CompileStage.DESUGAR_AFTER_SEMA) { return PerformDesugarAfterSema() }
        if (stage == CompileStage.GENERIC_INSTANTIATION) { return PerformGenericInstantiation() }
        if (stage == CompileStage.OVERFLOW_STRATEGY) { return PerformOverflowStrategy() }
        if (stage == CompileStage.MANGLING) { return PerformMangling() }
        if (stage == CompileStage.SAVE_CJO) { return PerformCjoSaving() }
        if (stage == CompileStage.CHIR) { return PerformCHIRCompilation() }
        if (stage == CompileStage.CODEGEN) { return PerformCodeGen() }
        if (stage == CompileStage.SAVE_RESULTS) { return PerformResultsSaving() }
        return true
    }

    public func PerformPluginLoad(): Bool {
        if (invocation.globalOptions.pluginPaths.isEmpty()) {
            return true
        }
        loadedPluginPaths.clear()
        CloseLoadedNativeMetaTransformPlugins()
        try {
            if (RegisterCjPlugin()) {
                metaTransformPluginBuilder.SetIsCppPlugin(false)
                return true
            }
        } catch (e: Exception) {
            return false
        }
        for (pluginPath in invocation.globalOptions.pluginPaths) {
            try {
                let metaTransformPlugin = NativeMetaTransformPlugin.Get(pluginPath)
                if (!metaTransformPlugin.IsValid()) {
                    DiagnoseInvalidPlugin(pluginPath)
                }
                loadedPluginPaths.add(pluginPath)
                loadedNativeMetaTransformPlugins.add(metaTransformPlugin)
                // Native C++ callbacks require a C++ MetaTransformPluginBuilder ABI adapter.
            } catch (e: Exception) {
                DiagnoseInvalidPlugin(pluginPath)
                return false
            }
        }
        metaTransformPluginBuilder.SetIsCppPlugin(true)
        return true
    }

    private func RegisterCjPlugin(): Bool {
        let firstPlugin = invocation.globalOptions.pluginPaths[0]
        let temporaryHandle = OpenSymbolTable(firstPlugin)
        if (!temporaryHandle.opened) {
            return false
        }
        let execute = GetMethodPointer(temporaryHandle, "executeCHIRPlugins")
        if (execute.isNull()) {
            return false
        }
        let initArgs = ArrayList<(String, String)>()
        for ((name, value) in invocation.globalOptions.environment.allVariables) {
            initArgs.add((name, value))
        }
        let _ = RuntimeInit.GetInstance().InitRuntime(invocation.GetRuntimeLibPath(), initArgs: initArgs)
        let runtimeHandle = OpenSymbolTableSafely(invocation.GetRuntimeLibPath())
        if (!runtimeHandle.opened) {
            return false
        }
        let initLibPointer = GetMethodPointer(runtimeHandle, "InitCJLibrary")
        if (initLibPointer.isNull()) {
            return false
        }
        let initLibFunc = CFunc<(CString) -> Int32>(initLibPointer)
        for (pluginPath in invocation.globalOptions.pluginPaths) {
            let handle = OpenSymbolTableSafely(pluginPath)
            if (!handle.opened) {
                DiagnoseInvalidPlugin(pluginPath)
                return false
            }
            var result: Int32 = 1
            try (path = unsafe { LibC.mallocCString(pluginPath) }.asResource()) {
                result = unsafe { initLibFunc(path.value) }
            }
            if (result != 0) {
                DiagnoseInvalidPlugin(pluginPath)
                return false
            }
        }
        return true
    }

    private func DiagnoseInvalidPlugin(pluginPath: String): Unit {
        diag.DiagnoseRefactor(DiagKindRefactor.not_a_valid_plugin, DEFAULT_POSITION, arguments: [pluginPath])
    }

    private func CloseLoadedNativeMetaTransformPlugins(): Unit {
        for (plugin in loadedNativeMetaTransformPlugins) {
            let _ = plugin.Close()
        }
        loadedNativeMetaTransformPlugins.clear()
    }

    public func PerformParse(): Bool {
        var ret = getCompileStrategy().Parse()
        if (!srcPkgs.isEmpty()) {
            let globalOpts = invocation.globalOptions
            srcPkgs[0].noSubPkg = globalOpts.noSubPkg
            ProfileRecorder.SetPackageName(srcPkgs[0].fullPackageName)
            ProfileRecorder.SetOutputDir(globalOpts.output)
            if (IsNeedSaveIncrCompilationLogFile(globalOpts, invocation.frontendOptions)) {
                let incrLogPath = globalOpts.GenerateCachedPathName(srcPkgs[0].fullPackageName, CACHED_LOG_EXTENSION)
                IncrementalCompilationLogger.GetInstance().InitLogFile(incrLogPath)
                IncrementalCompilationLogger.GetInstance().WriteBuffToFile()
            }
            if (globalOpts.NeedDumpASTToFile()) {
                DumpAST(GetSourcePackages(), globalOpts.output, "parse")
            }
        }
        if (ret) {
            ret = CaptureRealASTPackages()
        } else {
            realASTPkgs.clear()
        }
        return ret
    }

    public func PerformConditionCompile(): Bool {
        let ret = getCompileStrategy().ConditionCompile()
        if (!srcPkgs.isEmpty() && invocation.globalOptions.NeedDumpASTToFile()) {
            DumpAST(GetSourcePackages(), invocation.globalOptions.output, "condcomp")
        }
        return ret
    }

    public func PerformImportPackage(): Bool {
        let ret = getCompileStrategy().ImportPackages()
        if (!srcPkgs.isEmpty() && invocation.globalOptions.NeedDumpASTToFile()) {
            DumpAST(GetSourcePackages(), invocation.globalOptions.output, "import")
        }
        return ret
    }

    public func PerformMacroExpand(): Bool {
        let ret = getCompileStrategy().MacroExpand()
        if (ret) {
            importManager.ReindexSourcePackagesAfterMacroExpand(GetSourcePackages())
        }
        if (!invocation.globalOptions.IsConstEvalEnabled() && !invocation.globalOptions.interpreter) {
            importManager.DeleteASTLoaders()
        }
        importManager.ClearPackageBCHIRCache()
        if (invocation.globalOptions.compileTestsOnly && invocation.globalOptions.enableVerbose) {
            PrintTestOnlySourceFiles(srcPkgs)
        }
        if (!srcPkgs.isEmpty() && invocation.globalOptions.NeedDumpASTToFile()) {
            DumpAST(GetSourcePackages(), invocation.globalOptions.output, "macroexp")
        }
        return ret
    }

    public func ExpandDecl(decl: Decl): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        out.add(decl)
        return out
    }

    public func PerformIncrementalScopeAnalysis(): Bool {
        // IncrementalCompilerInstance.cpp:192-205 invokes the calculator only for the incremental instance.
        if (invocation.globalOptions.compileCjd || !invocation.globalOptions.enIncrementalCompilation) {
            return true
        }
        CalculateASTCache()
        return true
    }

    public func CalculateASTCache(): Bool {
        if (srcPkgs.isEmpty()) {
            return false
        }
        var terminate = false
        var message = ""
        if (diag.GetErrorCount() != 0) {
            terminate = true
            kind = IncreKind.ROLLBACK
            message = "frontend error detected, roll back to full compilation"
        } else if (srcPkgs[0].IsEmpty()) {
            terminate = true
            kind = IncreKind.EMPTY_PKG
            message = "empty package, skip"
        }
        if (terminate) {
            IncrementalCompilationLogger.GetInstance().LogLn(message)
            return false
        }
        let calculator = ASTCacheCalculator(srcPkgs[0],
            (invocation.globalOptions.enableCompileDebug, invocation.globalOptions.displayLineInfo))
        calculator.Walk()
        rawMangleName2DeclMap = calculator.mangled2Decl
        astCacheInfo = calculator.ret
        declsWithDuplicatedRawMangleName = calculator.duplicatedMangleNames
        directExtends = calculator.directExtends
        fileMap = calculator.fileMap
        order = calculator.order
        return true
    }

    public func PerformSema(): Bool {
        let ret = getCompileStrategy().Sema()
        hasTypeCheckerFlag = true
        let realSemaOk = if (ret) { RunRealSema() } else { false }
        if (!srcPkgs.isEmpty() && invocation.globalOptions.NeedDumpASTToFile()) {
            DumpAST(GetSourcePackages(), invocation.globalOptions.output, "sema")
        }
        return ret && realSemaOk
    }

    public func PerformDesugarAfterSema(): Bool {
        testManager.MarkDeclsForTestIfNeeded(GetSourcePackages())
        getCompileStrategy().DesugarAfterSema()
        // Inline checking needs to process source package and imported packages which has source imported decls.
        CheckInlineFunctionsForPackages(GetPackages(), invocation.globalOptions)
        // Since the inlined function will affect decls' visibility, analyze linkage after inline decl checking.
        for (pkg in srcPkgs) {
            AnalyzeFunctionLinkage(pkg, invocation.globalOptions)
        }
        if (!invocation.globalOptions.enIncrementalCompilation) {
            testManager.PrepareToMock(GetSourcePackages())
        }
        // Sema/Desugar/AfterTypeCheck.cpp:466-476: pre-save full exported
        // declarations after desugaring and linkage analysis, before generic instantiation.
        let saveFileWithAbsPath = invocation.globalOptions.enableCompileDebug ||
            invocation.globalOptions.enableCoverage
        for (pkg in srcPkgs) {
            let saveAbsPath = if (STANDARD_LIBS.contains(pkg.fullPackageName)) {
                invocation.globalOptions.enableCoverage
            } else {
                saveFileWithAbsPath
            }
            ExportDeclsWithContent(saveAbsPath, pkg)
        }
        if (!srcPkgs.isEmpty() && invocation.globalOptions.NeedDumpASTToFile()) {
            DumpAST(GetSourcePackages(), invocation.globalOptions.output, "desugar")
        }
        return true
    }

    // ImportManager.cpp:342-363 ImportManager::ExportDeclsWithContent.
    public func ExportDeclsWithContent(saveFileWithAbsPath: Bool, pkg: Package): Unit {
        let packageDepInfo = importManager.GeneratePkgDepInfo(pkg)
        let writer = ASTWriter(packageDepInfo, importManager.GetCjoManager(),
            invocation.globalOptions.enableCompileDebug, invocation.globalOptions.optimizationLevel,
            saveFileWithAbsPath: saveFileWithAbsPath, diag: diag,
            serializingCommon: invocation.globalOptions.outputMode == OutputMode.CHIR,
            exportContent: importManager.IsSourceCodeImported(), exportForIncr: false, exportFuncBody: true)
        writer.PreSaveFullExportDecls(pkg)
        astWriters[pkg] = writer
    }

    // ImportManager.cpp:291-320 ImportManager::ExportAST.
    public func ExportAST(saveFileWithAbsPath: Bool, pkg: Package): Array<UInt8> {
        let writer = if (let Some(savedWriter) <- astWriters.get(pkg)) {
            savedWriter
        } else {
            let packageDepInfo = importManager.GeneratePkgDepInfo(pkg)
            let newWriter = ASTWriter(packageDepInfo, importManager.GetCjoManager(),
                invocation.globalOptions.enableCompileDebug, invocation.globalOptions.optimizationLevel,
                saveFileWithAbsPath: saveFileWithAbsPath, diag: diag,
                serializingCommon: invocation.globalOptions.outputMode == OutputMode.CHIR,
                exportContent: importManager.IsSourceCodeImported(), exportForIncr: false, exportFuncBody: true)
            newWriter.PreSaveFullExportDecls(pkg)
            newWriter
        }
        writer.ExportAST(pkg)
        return writer.AST2FB(pkg)
    }

    public func PerformGenericInstantiation(): Bool {
        if (let None <- gim) {
            gim = Some(GenericInstantiationManager(faithfulSemaInstance.getOrThrow(), testManager.GetImpl()))
        }
        if (!invocation.globalOptions.enIncrementalCompilation) {
            if (let Some(genericInstantiationManager) <- gim) {
                genericInstantiationManager.ResetGenericInstantiationStage()
                var resetGlobalState = true
                for (pkg in srcPkgs) {
                    genericInstantiationManager.GenericInstantiatePackage(pkg, resetGlobalState: resetGlobalState)
                    resetGlobalState = false
                    if (diag.GetErrorCount() != 0) {
                        return false
                    }
                }
            }
        }
        let semaInstance = faithfulSemaInstance.getOrThrow()
        let typeChecker = FaithfulSemaTypeChecker(Some(semaInstance))
        for (pkg in srcPkgs) {
            let astCtx = semaInstance.GetASTContextByPackage(Some(pkg)).getOrThrow()
            typeChecker.PerformDesugarAfterInstantiation(astCtx, pkg)
        }
        if (!srcPkgs.isEmpty() && invocation.globalOptions.NeedDumpASTToFile()) {
            DumpAST(GetSourcePackages(), invocation.globalOptions.output, "genericinst")
        }
        return true
    }

    public func PerformOverflowStrategy(): Bool {
        if (invocation.globalOptions.overflowStrategy == OverflowStrategy.NA) {
            return true
        }
        let _ = getCompileStrategy().OverflowStrategy()
        if (!srcPkgs.isEmpty() && invocation.globalOptions.NeedDumpASTToFile()) {
            DumpAST(GetSourcePackages(), invocation.globalOptions.output, "overflow")
        }
        return true
    }

    public func PerformMangling(): Bool {
        mangler = RealCHIRMangler(invocation.globalOptions.enableCompileTest)
        let adapter = mangler.adapter
        PrepareManglerContexts(mangler, adapter)
        mangler.lambdaCounter = Int64(cachedInfo.lambdaCounter)
        ManglingHelpFunction(mangler, adapter)
        cachedInfo.lambdaCounter = UInt64(mangler.lambdaCounter)
        if (!srcPkgs.isEmpty() && invocation.globalOptions.NeedDumpAST()) {
            DumpAST(GetSourcePackages(), invocation.globalOptions.output, "mangle", dumpToScreen: invocation.globalOptions.dumpToScreen)
        }
        return true
    }

    private func CaptureRealASTPackages(): Bool {
        realASTPkgs.clear()
        for (pkg in srcPkgs) {
            realASTPkgs[pkg.fullPackageName] = pkg
        }
        return true
    }

    private func RunRealSema(): Bool {
        if (realASTPkgs.isEmpty()) {
            return true
        }
        let pkgs = ArrayList<RealASTPackage>()
        for (pkg in srcPkgs) {
            if (let Some(realPkg) <- realASTPkgs.get(pkg.fullPackageName)) {
                pkgs.add(realPkg)
            }
        }
        if (pkgs.isEmpty()) {
            return true
        }
        for (pkg in pkgs) {
            FaithfulDesugarBeforeTypeCheck(pkg)
        }
        let semaInstance = FaithfulSemaCompilerInstance()
        semaInstance.typeManager = typeManager.AsFaithfulSemaTypeManager()
        semaInstance.globalOptions = invocation.globalOptions
        semaInstance.kind = kind
        semaInstance.compileStrategy = getCompileStrategy().strategyKind
        semaInstance.buildTrie = buildTrie
        semaInstance.frontendDumpActionIsTypeCheck = invocation.frontendOptions.dumpAction == DumpAction.TYPE_CHECK
        semaInstance.diag = Some(diag.AsBasicDiagnosticEngine())
        for (pkg in srcPkgs) {
            semaInstance.sourcePackages.add(pkg)
        }
        semaInstance.importManager = Some(importManager)
        semaInstance.cacheSemaUsage = Some({ info: SemanticInfo => CacheSemaUsage(info) })
        SeedFaithfulSemaResolvedImports(semaInstance)
        let checker = FaithfulSemaTypeChecker(Some(semaInstance))
        checker.TypeCheckForPackages(pkgs)
        faithfulSemaInstance = Some(semaInstance)
        return diag.GetErrorCount() == 0
    }

    private func SeedFaithfulSemaResolvedImports(semaInstance: FaithfulSemaCompilerInstance): Unit {
        for (pkg in srcPkgs) {
            if (let Some(packageDecl) <- importManager.GetPackageDecl(pkg.fullPackageName)) {
                semaInstance.AddResolvedPackageDecl(pkg.fullPackageName, packageDecl)
            }
        }
        for (importedPackage in importManager.GetAllImportedPackages()) {
            if (let Some(packageDecl) <- importManager.GetPackageDecl(importedPackage.fullPackageName)) {
                semaInstance.packageDecls.add(packageDecl)
                semaInstance.importedPackageDecls.add(packageDecl)
                semaInstance.AddResolvedPackageDecl(importedPackage.fullPackageName, packageDecl)
            } else {
                let packageDecl = RealASTPackageDecl(importedPackage)
                semaInstance.packageDecls.add(packageDecl)
                semaInstance.importedPackageDecls.add(packageDecl)
                semaInstance.AddResolvedPackageDecl(importedPackage.fullPackageName, packageDecl)
            }
        }
        for (pkg in srcPkgs) {
            for (file in pkg.files) {
                for (importSpec in file.imports) {
                    let packageName = importManager.GetPackageNameByImport(importSpec)
                    if (!packageName.isEmpty()) {
                        semaInstance.AddResolvedImportPackageName(importSpec, packageName,
                            importManager.IsImportPackage(importSpec))
                    }
                }
                for (group in importManager.GetImportedDecls(file)) {
                    semaInstance.AddResolvedImportedDecls(file.fileHash, group.name, group.decls)
                }
                let usedMacroDeclsMap = importManager.GetUsedMacroDecls(file)
                for (macroPackageName in usedMacroDeclsMap.keys()) {
                    if (let Some(decls) <- usedMacroDeclsMap.get(macroPackageName)) {
                        semaInstance.AddResolvedUsedMacroDecls(file.indexOfPackage, macroPackageName, decls)
                    }
                }
            }
        }
        for (srcPkg in srcPkgs) {
            let members = importManager.GetPackageMembers(srcPkg.fullPackageName)
            for (name in members.keys()) {
                if (let Some(decls) <- members.get(name)) {
                    semaInstance.AddResolvedCjoPackageMemberDecls(srcPkg.fullPackageName, name, decls)
                }
            }
        }
        for (importedPackage in importManager.GetAllImportedPackages()) {
            let members = importManager.GetPackageMembers(importedPackage.fullPackageName)
            for (name in members.keys()) {
                if (let Some(decls) <- members.get(name)) {
                    semaInstance.AddResolvedCjoPackageMemberDecls(importedPackage.fullPackageName, name, decls)
                }
            }
        }
        for (srcPkg in srcPkgs) {
            for (importedPackage in importManager.GetAllImportedPackages()) {
                let members = importManager.GetPackageMembers(srcPkg.fullPackageName, importedPackage.fullPackageName)
                for (name in members.keys()) {
                    if (let Some(decls) <- members.get(name)) {
                        semaInstance.AddResolvedPackageMemberDecls(importedPackage.fullPackageName, name, decls)
                    }
                }
            }
        }
        for (implicitPackage in importManager.GetAllImportedPackages()) {
            for (file in implicitPackage.files) {
                for (decl in file.exportedInternalDecls) {
                    if (decl.TestAttr(Attribute.IMPLICIT_USED)) {
                        semaInstance.AddResolvedImplicitPackageMemberDecl(implicitPackage.fullPackageName,
                            decl.identifier.Val(), decl)
                    }
                }
            }
        }
    }

    public func GenerateCHIRForPkg(pkg: Package): Bool {
        if (pkg.files.isEmpty()) {
            return true
        }
        RegisterMacroCallDiagInfos(diag, pkg)
        let realASTPkg = match (realASTPkgs.get(pkg.fullPackageName)) {
            case Some(value) => value
            case None =>
                diag.Diagnose(DiagCategory.CHIR, PackageDiagnosticPosition(pkg),
                    "missing real AST package for '" + pkg.fullPackageName + "'")
                return false
        }
        if (let Some(realPkg) <- BuildRealCHIRForASTPackage(this, realASTPkg)) {
            chirData.AppendNewRealPackage(realPkg)
            chirInfo.varInitDepMap.clear()
            for ((rawMangledName, initFuncName) in GetVarInitDepMap(realPkg)) {
                chirInfo.varInitDepMap[rawMangledName] = initFuncName
            }
        } else {
            if (diag.GetErrorCount() != 0) {
                return false
            }
            diag.Diagnose(DiagCategory.CHIR, PackageDiagnosticPosition(pkg),
                "unsupported construct in package '" + pkg.fullPackageName +
                "' (not yet implemented in real pipeline)")
            return false
        }
        let chirPkg = CHIRPackage(pkg.fullPackageName)
        chirPkg.fileCount = pkg.files.size
        for (file in pkg.files) {
            for (decl in file.decls) {
                collectCHIRDeclSummary(chirPkg, decl)
            }
        }
        for (decl in pkg.srcImportedNonGenericDecls) {
            collectCHIRDeclSummary(chirPkg, decl)
        }
        chirPkg.declCount = chirPkg.mangleNames.size
        chirData.AppendNewPackage(chirPkg)
        chirData.SetImplicitFuncs(chirPkg, chirPkg.implicitFuncs)
        chirData.SetConstVarInitFuncs(chirPkg, chirPkg.constVarInitFuncs)
        return true
    }

    public func PerformCHIRCompilation(): Bool {
        typeManager.ReleasePostSemaCaches()
        FreeIdleMemoryToOS()
        chirData.ClearRealPackages()
        var ret = true
        let sourcePackagesCHIR = GetSourcePackages()
        let pkgsOrderedCHIR = packageManager.GetBuildOrders(sourcePackagesCHIR)
        let emitted = HashSet<String>()
        for (group in pkgsOrderedCHIR) {
            if (group.isEmpty()) {
                continue
            }
            let wanted = group[0].fullPackageName
            for (pkg in sourcePackagesCHIR) {
                if (pkg.fullPackageName == wanted && !emitted.contains(pkg.fullPackageName)) {
                    ret = ret && GenerateCHIRForPkg(pkg)
                    emitted.add(pkg.fullPackageName)
                }
            }
        }
        for (pkg in sourcePackagesCHIR) {
            if (!emitted.contains(pkg.fullPackageName)) {
                ret = ret && GenerateCHIRForPkg(pkg)
            }
        }
        diag.EmitCategoryDiagnostics(DiagCategory.CHIR)
        return ret
    }

    public func DumpTokens(): Bool {
        var ret = true
        for (filePath in srcFilePaths) {
            let readResult = ReadFileContent(filePath)
            if (!readResult[0]) {
                diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION,
                    "failed to read source file '" + filePath + "': " + readResult[2])
                ret = false
                continue
            }
            let fileID = GetSourceManager().AddSource(GetAbsPath(filePath) ?? filePath, readResult[1])
            let lexer = CangjieLexer(fileID, readResult[1], diag.AsBasicDiagnosticEngine(), GetSourceManager())
            while (true) {
                let tok = lexer.Next()
                if (tok.kind == CangjieTokenKind.END) {
                    break
                }
                let position = "<" + filePath + ":" + tok.Begin().line.toString() + ":" +
                    tok.Begin().column.toString() + ">"
                if (tok.kind == CangjieTokenKind.NL) {
                    println((if (tok.equalsValue("\n")) { "\\n" } else { "\\r\\n" }) + " " +
                        TokenKindValue(tok.kind) + " " + position)
                } else if (tok.kind == CangjieTokenKind.COMMENT) {
                    println(TokenKindValue(tok.kind) + " " + position)
                } else {
                    println(tok.Value() + " " + TokenKindValue(tok.kind) + " " + position)
                }
            }
        }
        return ret
    }

    public func DumpSymbols(): Unit {
        PrintSymbolTable(this)
    }

    public func DumpMacro(): Unit {
        println("Dump tokens after macro expansion.")
        println("==== Start Dumping ====\n")
        for (tokens in tokensEvalInMacro) {
            println(tokens)
        }
    }

    public func PerformCodeGen(enableIncrement!: Bool = false,
        cachedMangleMap!: CachedMangleMap = CachedMangleMap()): Bool {
        if (diag.GetErrorCount() != 0) {
            return false
        }
        if (let Some(pkg) <- chirData.GetCurrentCHIRPackage()) {
            chirData.ActivateCodegenFuncsForPackage(pkg)
        }
        return GenPackageModules(this, enableIncrement, cachedMangleMap)
    }

    public func PerformCjoSaving(): Bool {
        return true
    }

    public func PerformResultsSaving(): Bool {
        return true
    }

    public func GetPackages(): ArrayList<Package> {
        return pkgs
    }

    public func GetSourcePackages(): ArrayList<Package> {
        let out = ArrayList<Package>()
        for (pkg in srcPkgs) {
            out.add(pkg)
        }
        return out
    }

    public func GetSourceManager(): SourceManager {
        return sm
    }

    public func GetASTContextByPackage(pkg: Package): Option<ASTContext> {
        return pkgCtxMap.get(pkg.fullPackageName)
    }

    public func GetDepPkgInfo(): ArrayList<String> {
        return depPackageInfo
    }

    public func ImportPackages(): Bool {
        if (cangjieHome.isEmpty()) {
            if (!DetectCangjieHome()) {
                return false
            }
        }
        if (cangjieModules.isEmpty()) {
            if (!DetectCangjieModules()) {
                return false
            }
        }
        AddSourceToMember()
        if (invocation.globalOptions.scanDepPkg) {
            importManager.UpdateSearchPath(cangjieModules)
            depPackageInfo.clear()
            let generated = if (!invocation.globalOptions.inputCjoFile.isEmpty()) {
                importManager.GeneratePkgDepInfoByCjo(invocation.globalOptions.inputCjoFile)
            } else {
                importManager.GeneratePkgDepInfo(pkgs)
            }
            for (info in generated) {
                depPackageInfo.add(info)
            }
            return true
        }
        if (!importManager.BuildIndex(cangjieModules, invocation.globalOptions, pkgs)) {
            return false
        }
        MergePackages()
        return ModularizeCompilation()
    }

    public func GetExtendDecls(queryType: ExtendMemberQueryType): ArrayList<ExtendDecl> {
        let semaTypeManager = typeManager.AsFaithfulSemaTypeManager()
        match (queryType) {
            case ByTy(ty) => return semaTypeManager.GetAllExtendsByTy(ty)
            case ByInheritableDecl(decl) => return semaTypeManager.GetDeclExtends(decl)
        }
    }

    private func CollectInheritMember(id: InheritableDecl, members: ArrayList<Decl>): Unit {
        for (superType in id.inheritedTypes) {
            if (let Some(target) <- superType.GetTarget()) {
                if (let Some(targetDecl) <- (target as InheritableDecl)) {
                    CollectInheritMember(targetDecl, members)
                }
            }
        }
        if (id.astKind != ASTKind.INTERFACE_DECL) {
            return
        }
        for (m in id.GetMemberDecls()) {
            if (!m.TestAttr(Attribute.ABSTRACT)) {
                members.add(m)
            }
        }
    }

    public func GetAllVisibleExtendMembers(queryType: ExtendMemberQueryType, curFile: File): ArrayList<Decl> {
        let extends = GetExtendDecls(queryType)
        let members = ArrayList<Decl>()
        let exprTy: Option<Ty> = match (queryType) {
            case ByTy(ty) => Some(ty)
            case ByInheritableDecl(decl) => decl.GetTy()
        }
        if (!Ty.IsTyCorrect(exprTy)) {
            return ArrayList<Decl>()
        }
        let realExprTy = exprTy.getOrThrow()
        for (e in extends) {
            if (!importManager.IsExtendAccessible(curFile, e, None)) {
                continue
            }
            let extendMember = e.GetMemberDecls()
            if (curFile.curPackage.getOrThrow().fullPackageName == e.fullPackageName) {
                for (m in extendMember) {
                    members.add(m)
                }
            } else {
                for (m in extendMember) {
                    if (importManager.IsExtendMemberAccessible(curFile, m, realExprTy, None)) {
                        members.add(m)
                    }
                }
            }
            CollectInheritMember(e, members)
            TypeCheckReferenceRemoveTargetNotMeetExtendConstraint(
                typeManager.AsFaithfulSemaTypeManager(), Some(realExprTy), members)
        }
        return members
    }

    public func GetGivenReferenceTarget(ctx: ASTContext, scopeName: String, exprName: String, hasLocalDecl: Bool): Candidate {
        let _ = scopeName
        let _ = hasLocalDecl
        let out = Candidate()
        for (sym in ctx.symbolTable) {
            if (sym.name == exprName) {
                if (let Some(node) <- sym.node) {
                    if (let Some(decl) <- (node as Decl)) {
                        out.decls.add(decl)
                    }
                }
            }
        }
        return out
    }

    public func UpdateAndWriteCachedInfoToDisk(updateCachedInfo: () -> Unit): Bool {
        if (!ShouldWriteCacheFile()) {
            return true
        }
        updateCachedInfo()
        return WriteCachedInfo()
    }

    public func UpdateMangleNameForCachedInfo(): Unit {
        for ((rawMangle, topCache) in cachedInfo.curPkgASTCache) {
            UpdateTopLevelDeclMangleNameForCachedInfo(rawMangleName2DeclMap, rawMangle, topCache)
        }
        for ((rawMangle, topCache) in cachedInfo.importedASTCache) {
            UpdateTopLevelDeclMangleNameForCachedInfo(rawMangleName2DeclMap, rawMangle, topCache)
        }
    }

    public func UpdateCachedInfo(): Unit {
        UpdateMangleNameForCachedInfo()
    }

    public func GetCHIRContext(): CHIRContext {
        return chirData.GetCHIRContext()
    }

    public func GetAllCHIRPackages(): ArrayList<CHIRPackage> {
        return chirData.GetAllCHIRPackages()
    }

    public func FreeCHIRData(): Unit {
        chirData.GetCHIRContext().packages.clear()
    }

    public func HasTypeChecker(): Bool {
        return hasTypeCheckerFlag
    }

    public func IsBuildTrie(): Bool {
        return buildTrie
    }

    public func SetBuildTrie(flag: Bool): Unit {
        buildTrie = flag
    }

    public func DeserializeCHIR(): Bool {
        let chirBuilder = ChirBuilder(chirData.GetRealCHIRContext())
        let phase = CoreBox<ChirToCHIRPhase>(ChirToCHIRPhase.RAW)
        ChirDeserializer.Deserialize(invocation.frontendOptions.chirDeserializePath, chirBuilder, phase)
        ChirPrinter.PrintCHIRSerializeInfo(phase.value, "deserialized.chir")
        ChirPrinter.PrintPackage(chirData.GetRealCHIRContext().GetCurPackage().getOrThrow(), "deserialized.chir")
        return true
    }

    public func RefreshASTContexts(): Unit {
        MergePackages()
    }

    private func AddSourceToMember(): Unit {
        pkgs.clear()
        for (pkg in GetSourcePackages()) {
            pkgs.add(pkg)
        }
    }

    private func getCompileStrategy(): CompileStrategy {
        if (let Some(strategy) <- compileStrategy) {
            return strategy
        }
        let strategy = FullCompileStrategy(this)
        compileStrategy = Some(strategy)
        return strategy
    }

    private func MergePackages(): Unit {
        pkgCtxMap.clear()
        for (pkg in srcPkgs) {
            if (pkgCtxMap.contains(pkg.fullPackageName)) {
                pkgCtxMap.remove(pkg.fullPackageName)
            }
            pkgCtxMap.add(pkg.fullPackageName, ASTContext(pkg))
        }
    }

    private func DetectCangjieHome(): Bool {
        if (invocation.globalOptions.environment.cangjieHome.hasValue) {
            cangjieHome = invocation.globalOptions.environment.cangjieHome.value
            return true
        }
        if (!invocation.globalOptions.cangjieHome.isEmpty()) {
            cangjieHome = invocation.globalOptions.cangjieHome
            return true
        }
        if (invocation.globalOptions.executablePath.isEmpty()) {
            diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION,
                "failed to detect CANGJIE_HOME: can not resolve executable path")
            return false
        }
        let exeAbs = GetAbsPath(invocation.globalOptions.executablePath) ?? invocation.globalOptions.executablePath
        cangjieHome = JoinPath(GetDirPath(exeAbs), "..")
        if (!FileExist(cangjieHome) || !FileExist(JoinPath(cangjieHome, "modules"))) {
            diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION,
                "failed to detect CANGJIE_HOME: invalid cjc home")
            return false
        }
        return true
    }

    private func DetectCangjieModules(): Bool {
        if (cangjieHome.isEmpty()) {
            diag.AsBasicDiagnosticEngine().DiagnoseRefactor(
                DiagKindRefactor.frontend_failed_to_detect_cangjie_modules,
                MakeRange(DEFAULT_POSITION, DEFAULT_POSITION), arguments: ["cangjie home is empty"]).Emit()
            return false
        }
        let libPathName = invocation.globalOptions.GetCangjieLibTargetPathName()
        if (libPathName.isEmpty()) {
            diag.AsBasicDiagnosticEngine().DiagnoseRefactor(
                DiagKindRefactor.frontend_failed_to_detect_cangjie_modules,
                MakeRange(DEFAULT_POSITION, DEFAULT_POSITION), arguments: ["target library path name is empty"]).Emit()
            return false
        }
        cangjieModules = JoinPath(JoinPath(cangjieHome, "modules"), libPathName)
        if (!FileExist(cangjieModules)) {
            diag.AsBasicDiagnosticEngine().DiagnoseRefactor(
                DiagKindRefactor.frontend_failed_to_detect_cangjie_modules,
                MakeRange(DEFAULT_POSITION, DEFAULT_POSITION),
                arguments: ["target library path is not exist : " + cangjieModules]).Emit()
            return false
        }
        return true
    }

    private func ModularizeCompilation(): Bool {
        for (bcPkg in invocation.globalOptions.bcPackageNames) {
            if (!importManager.AnalyzeDepStdPkgsOfBC(bcPkg)) {
                return false
            }
        }
        for (objFile in importManager.GetUsedSTDLibFiles(DepType.DIRECT)) {
            invocation.globalOptions.directBuiltinDependencies.add(objFile)
        }
        for (objFile in importManager.GetUsedSTDLibFiles(DepType.INDIRECT)) {
            invocation.globalOptions.indirectBuiltinDependencies.add(objFile)
        }
        return packageManager.ResolveDependence(pkgs)
    }

    public func CacheCompileArgs(): Unit {
        cachedInfo.compileArgs.clear()
        for (arg in invocation.globalOptions.ToSerialized()) { cachedInfo.compileArgs.add(arg) }
    }

    // C++ src/Frontend/CompilerInstance.cpp:510-529.
    private func CacheSemaUsage(info: SemanticInfo): Unit {
        for ((decl, usage) in cachedInfo.semaInfo.usages) {
            if (decl.toBeCompiled) {
                continue
            }
            var usageDecl = decl
            if (let Some(mainDecl) <- (decl as MainDecl)) {
                if (let Some(desugarDecl) <- mainDecl.desugarDecl) {
                    usageDecl = desugarDecl
                }
            } else if (let Some(macroDecl) <- (decl as MacroDecl)) {
                if (let Some(desugarDecl) <- macroDecl.desugarDecl) {
                    usageDecl = desugarDecl
                }
            }
            if (info.usages.contains(usageDecl)) {
                info.usages[usageDecl] = usage
            }
        }
        cachedInfo.semaInfo = info
    }


    private func WriteCachedInfo(): Bool {
        if (srcPkgs.isEmpty()) {
            return true
        }
        // IncrementalScopeAnalysis.cpp:473-474 updates this cache before the existing writer consumes it.
        cachedInfo.curPkgASTCache.clear()
        for ((mangle, declCache) in astCacheInfo) { cachedInfo.curPkgASTCache[mangle] = declCache }
        let path = invocation.globalOptions.GenerateCachedPathName(srcPkgs[0].fullPackageName, CACHED_AST_EXTENSION)
        return WriteCache(srcPkgs[0], cachedInfo, order, path)
    }

    private func ShouldWriteCacheFile(): Bool {
        if (!invocation.globalOptions.enIncrementalCompilation) {
            return false
        }
        if (invocation.globalOptions.printVersionOnly || invocation.globalOptions.showUsage) {
            InternalError("'printVersionOnly' or 'showUsage' cannot be true.")
        }
        if (invocation.frontendOptions.dumpAction != DumpAction.NO_ACTION) {
            return false
        }
        if (invocation.globalOptions.IsEmitCHIREnable()) {
            return false
        }
        if (invocation.globalOptions.compileCjd) {
            return false
        }
        if (srcPkgs.size != 1) {
            InternalError("source packages should only have one element.")
        }
        if (!invocation.globalOptions.compilePackage && invocation.globalOptions.srcFiles.isEmpty() &&
            !invocation.globalOptions.inputObjs.isEmpty()) {
            return false
        }
        if (srcPkgs[0].IsEmpty() || kind == IncreKind.NO_CHANGE) {
            return false
        }
        return true
    }

    private func PrepareManglerContexts(baseMangler: RealBaseMangler, adapter: RealMangleAstAdapter): Unit {
        for (pkg in GetPackages()) {
            let pkgName = RealManglerContext.ReduceUnitTestPackageName(pkg.fullPackageName)
            let ctx = if (let Some(value) <- baseMangler.manglerCtxTable.get(pkgName)) {
                value
            } else {
                baseMangler.PrepareContextForPackage(adapter.ConvertPackage(pkg))
            }
            adapter.CollectLocalDecls(ctx, pkg)
        }
        for (pkg in importManager.GetAllImportedPackages()) {
            let pkgName = RealManglerContext.ReduceUnitTestPackageName(pkg.fullPackageName)
            let ctx = if (let Some(value) <- baseMangler.manglerCtxTable.get(pkgName)) {
                value
            } else {
                baseMangler.PrepareContextForPackage(adapter.ConvertPackage(pkg))
            }
            adapter.CollectLocalDecls(ctx, pkg)
        }
    }

    private func ManglingHelpFunction(baseMangler: RealBaseMangler, adapter: RealMangleAstAdapter): Unit {
        let topDecls = ArrayList<(String, Decl)>()
        let deduplicatedEmplace = { decl: Decl, pkgName: String =>
            if (decl.TestAttr(Attribute.IMPORTED) && !decl.isUsedImports) {
                return
            }
            for (topDecl in topDecls) {
                if (topDecl[0] == pkgName && refEq(topDecl[1], decl)) {
                    return
                }
            }
            topDecls.add((pkgName, decl))
        }

        for (pkg in GetPackages()) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    deduplicatedEmplace(decl, pkg.fullPackageName)
                }
            }
            for (decl in pkg.genericInstantiatedDecls) {
                deduplicatedEmplace(decl, pkg.fullPackageName)
            }
        }
        for (pkg in importManager.GetAllImportedPackages()) {
            if (!pkg.TestAttr(Attribute.IMPORTED)) {
                continue
            }
            for (file in pkg.files) {
                for (decl in file.decls) {
                    deduplicatedEmplace(decl, pkg.fullPackageName)
                }
                for (decl in file.exportedInternalDecls) {
                    deduplicatedEmplace(decl, pkg.fullPackageName)
                }
            }
            for (decl in pkg.genericInstantiatedDecls) {
                if (decl.IsNominalDecl()) {
                    deduplicatedEmplace(decl, pkg.fullPackageName)
                }
            }
        }
        for (topDecl in topDecls) {
            mangleDeclTree(baseMangler, adapter, topDecl[0], topDecl[1])
        }
    }

    private func mangleDeclTree(
        baseMangler: RealBaseMangler,
        adapter: RealMangleAstAdapter,
        pkgName: String,
        decl: Decl
    ): Unit {
        let prefix = ArrayList<Node>()
        let pendingDecls = ArrayList<PendingMangledDecl>()
        let pendingLambdas = ArrayList<PendingMangledLambda>()
        let pre = { node: Node =>
            let filteredPrefix = getMangleFilteredPrefix(prefix)
            let convertedPrefix = convertManglePrefix(adapter, filteredPrefix)
            let action = if (let Some(curDecl) <- (node as Decl)) {
                curDecl.fullPackageName = pkgName
                if (curDecl.astKind == ASTKind.MAIN_DECL) {
                    VisitAction.WALK_CHILDREN
                } else if (curDecl.astKind == ASTKind.MACRO_DECL) {
                    if (let Some(desugarDecl) <- curDecl.GetDesugarDecl()) {
                        desugarDecl.mangledName = baseMangler.Mangle(desugarDecl)
                    }
                    VisitAction.WALK_CHILDREN
                } else if (!Ty.IsTyCorrect(curDecl.GetTy())) {
                    VisitAction.SKIP_CHILDREN
                } else {
                    let convertedDecl = adapter.ConvertDecl(curDecl)
                    pendingDecls.add(PendingMangledDecl(curDecl, convertedDecl,
                        baseMangler.Mangle(convertedDecl, convertedPrefix)))
                    VisitAction.WALK_CHILDREN
                }
            } else if (let Some(lambda) <- (node as LambdaExpr)) {
                if (lambda.TestAttr(Attribute.GENERIC) || !Ty.IsTyCorrect(lambda.GetTy())) {
                    VisitAction.SKIP_CHILDREN
                } else {
                    let convertedLambda = adapter.ConvertLambdaExpr(lambda)
                    pendingLambdas.add(PendingMangledLambda(lambda, convertedLambda,
                        baseMangler.MangleLambda(convertedLambda, convertedPrefix)))
                    VisitAction.WALK_CHILDREN
                }
            } else if (let Some(_) <- (node as Annotation)) {
                VisitAction.SKIP_CHILDREN
            } else {
                VisitAction.WALK_CHILDREN
            }
            prefix.add(node)
            action
        }
        let post = { _: Node =>
            prefix.remove(at: prefix.size - 1)
            VisitAction.KEEP_DECISION
        }
        Walker(decl, visitPre: pre, visitPost: post).Walk()
        for (pending in pendingDecls) {
            pending.astDecl.mangledName = pending.mangledName
            pending.mangleDecl.mangledName = pending.mangledName
            if (mangledName2DeclMap.contains(pending.mangledName)) {
                mangledName2DeclMap.remove(pending.mangledName)
            }
            mangledName2DeclMap.add(pending.mangledName, pending.astDecl)
        }
        for (pending in pendingLambdas) {
            pending.astLambda.mangledName = pending.mangledName
            pending.mangleLambda.mangledName = pending.mangledName
        }
    }

    private func getMangleFilteredPrefix(prefix: ArrayList<Node>): ArrayList<Node> {
        let filteredPrefix = ArrayList<Node>()
        for (node in prefix) {
            if (filteredPrefix.size != 0) {
                if (let Some(expr) <- (filteredPrefix[filteredPrefix.size - 1] as Expr)) {
                    if (let Some(nodeExpr) <- (node as Expr)) {
                        if (let Some(desugarExpr) <- expr.desugarExpr) {
                            if (refEq(desugarExpr, nodeExpr)) {
                                filteredPrefix.remove(at: filteredPrefix.size - 1)
                            }
                        }
                    }
                }
            }
            filteredPrefix.add(node)
        }
        filteredPrefix
    }

    private func convertManglePrefix(adapter: RealMangleAstAdapter, prefix: ArrayList<Node>): ArrayList<RealMangleDecl> {
        let convertedPrefix = ArrayList<RealMangleDecl>()
        for (node in prefix) {
            if (let Some(convertedNode) <- adapter.ConvertNode(node)) {
                convertedPrefix.add(convertedNode)
            }
        }
        convertedPrefix
    }

    private func collectCHIRDeclSummary(chirPkg: CHIRPackage, decl: Decl): Unit {
        if (decl.TestAttr(Attribute.IMPORTED) && !decl.isUsedImports) {
            return
        }
        let name = if (decl.mangledName.isEmpty()) {
            "_C" + (chirPkg.name + "." + decl.identifier.Val()).replace(".", "_")
        } else {
            decl.mangledName
        }
        chirPkg.mangleNames.add(name)
        if (decl.IsFunc()) {
            if (!chirPkg.implicitFuncs.contains(name)) {
                chirPkg.implicitFuncs.add(name, ASTKindName(decl.astKind))
            }
        } else if (decl.astKind == ASTKind.VAR_DECL || decl.astKind == ASTKind.PROP_DECL) {
            chirPkg.constVarInitFuncs.add(name + ".init")
        }
        for (member in decl.GetMemberDecls()) {
            collectCHIRDeclSummary(chirPkg, member)
        }
    }
}

private func appendGenericParamList(builder: StringBuilder, values: ArrayList<GenericParamDecl>): Unit {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(",")
        }
        builder.append(values[idx].identifier.Val())
        idx++
    }
}

private func IsNeedSaveIncrCompilationLogFile(globalOpts: GlobalOptions, frontOpts: FrontendOptions): Bool {
    if (!globalOpts.enIncrementalCompilation) {
        return false
    }
    if (globalOpts.scanDepPkg) {
        return false
    }
    if (frontOpts.dumpAction != DumpAction.NO_ACTION) {
        return false
    }
    if (globalOpts.compileCjd) {
        return false
    }
    return true
}

private func PrintTestOnlySourceFiles(srcPkgs: ArrayList<Package>): Unit {
    print("Source files to compile for the test-only mode: {")
    var emitted = false
    for (pkg in srcPkgs) {
        for (srcFile in pkg.files) {
            if (emitted) {
                print(", ")
            }
            print(pkg.fullPackageName + "::" + srcFile.fileName)
            emitted = true
        }
    }
    println("}")
}

private var astDumpDir: String = ""
private var astDumpDirInitialized: Bool = false
private var astDumpFileNum: Int64 = 0

private func DumpASTToScreen(srcPkgs: ArrayList<Package>): Unit {
    for (pkg in srcPkgs) {
        print(PrintNode(pkg))
    }
}

private func DumpAST(srcPkgs: ArrayList<Package>, outputOfProduct: String, prefix: String, dumpToScreen!: Bool = false): Unit {
    if (srcPkgs.isEmpty()) {
        return
    }
    if (dumpToScreen) {
        DumpASTToScreen(srcPkgs)
        return
    }
    let pkgName = srcPkgs[0].fullPackageName
    if (!astDumpDirInitialized) {
        astDumpDir = if (IsDir(outputOfProduct)) {
            JoinPath(outputOfProduct, pkgName + "_AST")
        } else {
            GetFileBase(outputOfProduct) + "_AST"
        }
        if (FileExist(astDumpDir)) {
            let _ = RemoveDirectoryRecursively(astDumpDir)
        }
        if (!CreateDirs(astDumpDir + DIR_SEPARATOR)) {
            return
        }
        astDumpDirInitialized = true
        astDumpFileNum = 0
    }
    let realDirPath = GetAbsPath(astDumpDir)
    if (let None <- realDirPath) {
        return
    }
    let dumpPath = JoinPath(realDirPath.getOrThrow(), astDumpFileNum.toString() + "_" + prefix + "_ast.txt")
    let rendered = PrintNode(srcPkgs[0])
    if (WriteFileContent(dumpPath, rendered)) {
        astDumpFileNum++
    }
}
