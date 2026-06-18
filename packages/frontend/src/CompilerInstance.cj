package cangjie_compiler::frontend

import cangjie_compiler::ast.AddCurFile
import cangjie_compiler::ast.Package as RealASTPackage
import cangjie_compiler::parse.DiagnosticEngine as ParseDiagnosticEngine
import cangjie_compiler::parse.Parser as RealParser
import cangjie_compiler::meta_transformation.MetaTransformPluginBuilder
import cangjie_compiler::meta_transformation.NativeMetaTransformPlugin
import std.collection.*

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
    public let optEffectMap: HashMap<String, String> = HashMap<String, String>()
    public let ccOutFuncsRawMangle: HashSet<String> = HashSet<String>()
    public let varInitDepMap: HashMap<String, String> = HashMap<String, String>()
    public init() {}
}

public class CompilerInstance {
    public let invocation: CompilerInvocation
    public var cangjieHome: String = ""
    public var cangjieModules: String = ""
    public let srcFilePaths: ArrayList<String> = ArrayList<String>()
    public let srcDirs: HashSet<String> = HashSet<String>()
    public let diag: DiagnosticEngine
    public let cachedInfo: CompilationCache = CompilationCache()
    public let chirInfo: CHIRInfo = CHIRInfo()
    public let metaTransformPluginBuilder: MetaTransformPluginBuilder = MetaTransformPluginBuilder()
    public let sm: SourceManager = SourceManager()
    public let typeManager: TypeManager = TypeManager()
    public let importManager: ImportManager
    public let packageManager: PackageManager
    public let testManager: TestManager = TestManager()
    public var gim: Option<GenericInstantiationManager> = None
    public var compileOnePackageFromSrcFiles: Bool = false
    public var loadSrcFilesFromCache: Bool = false
    public let bufferCache: HashMap<String, SrcCodeCacheInfo> = HashMap<String, SrcCodeCacheInfo>()
    public let tokensEvalInMacro: ArrayList<String> = ArrayList<String>()
    public var currentPkg: Option<Package> = None
    public let mangler: BaseMangler = BaseMangler()
    public let mangledName2DeclMap: HashMap<String, Decl> = HashMap<String, Decl>()
    public var releaseCHIRMemory: Bool = true
    public var needToOptString: Bool = false
    public var needToOptGenericDecl: Bool = false
    public var isCJLint: Bool = false
    public var buildTrie: Bool = true
    public let srcPkgs: ArrayList<Package> = ArrayList<Package>()
    public let realASTPkgs: HashMap<String, RealASTPackage> = HashMap<String, RealASTPackage>()
    public let chirData: CHIRData = CHIRData()
    private let pkgs: ArrayList<Package> = ArrayList<Package>()
    private let pkgCtxMap: HashMap<String, ASTContext> = HashMap<String, ASTContext>()
    private let depPackageInfo: ArrayList<String> = ArrayList<String>()
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
        importManager = ImportManager(diag)
        packageManager = PackageManager(importManager)
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
        loadedPluginPaths.clear()
        CloseLoadedNativeMetaTransformPlugins()
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
        let ret = getCompileStrategy().Parse()
        if (!srcPkgs.isEmpty()) {
            let globalOpts = invocation.globalOptions
            srcPkgs[0].noSubPkg = globalOpts.noSubPkg
            if (IsNeedSaveIncrCompilationLogFile(globalOpts, invocation.frontendOptions)) {
                let incrLogPath = globalOpts.GenerateCachedPathName(srcPkgs[0].fullPackageName, CACHED_LOG_EXTENSION)
                let _ = WriteFileContent(incrLogPath, "")
            }
            if (globalOpts.NeedDumpASTToFile()) {
                DumpAST(GetSourcePackages(), globalOpts.output, "parse")
            }
        }
        if (ret) {
            CaptureRealASTPackagesIfEnabled()
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
        if (let Some(macroDecl) <- (decl as MacroExpandDecl)) {
            if (let Some(expanded) <- macroDecl.invocation.decl) {
                if (macroDecl.invocation.identifier == "APILevel") {
                    ensureAPILevelAnnotationForDecl(expanded, macroDecl.invocation)
                }
                out.add(expanded)
                return out
            }
        }
        out.add(decl)
        return out
    }

    public func PerformIncrementalScopeAnalysis(): Bool {
        if (invocation.globalOptions.compileCjd) {
            return true
        }
        CalculateASTCache()
        return true
    }

    public func CalculateASTCache(): Bool {
        CacheCompileArgs()
        cachedInfo.fileSummaries.clear()
        cachedInfo.declSummaries.clear()
        if (srcPkgs.isEmpty()) {
            return false
        }
        if (diag.GetErrorCount() != 0) {
            return false
        }
        if (srcPkgs[0].IsEmpty()) {
            return false
        }
        for (pkg in srcPkgs) {
            for (file in pkg.files) {
                cachedInfo.fileSummaries.add(pkg.fullPackageName + "|" + file.filePath + "|" + file.fileHash.toString())
                for (decl in file.decls) {
                    collectDeclCacheSummary(pkg, file, decl)
                }
            }
        }
        return !srcPkgs.isEmpty() && diag.GetErrorCount() == 0
    }

    public func PerformSema(): Bool {
        let ret = getCompileStrategy().Sema()
        hasTypeCheckerFlag = true
        if (!srcPkgs.isEmpty() && invocation.globalOptions.NeedDumpASTToFile()) {
            DumpAST(GetSourcePackages(), invocation.globalOptions.output, "sema")
        }
        return ret
    }

    public func PerformDesugarAfterSema(): Bool {
        testManager.MarkDeclsForTestIfNeeded(GetSourcePackages())
        getCompileStrategy().DesugarAfterSema()
        if (!srcPkgs.isEmpty() && invocation.globalOptions.NeedDumpASTToFile()) {
            DumpAST(GetSourcePackages(), invocation.globalOptions.output, "desugar")
        }
        return true
    }

    public func PerformGenericInstantiation(): Bool {
        if (let None <- gim) {
            gim = Some(GenericInstantiationManager(this))
        }
        for (pkg in srcPkgs) {
            collectGenericInstantiations(pkg)
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
        mangler.lambdaCounter = cachedInfo.lambdaCounter
        ManglingHelpFunction(mangler)
        cachedInfo.lambdaCounter = mangler.lambdaCounter
        if (!srcPkgs.isEmpty() && invocation.globalOptions.NeedDumpAST()) {
            DumpAST(GetSourcePackages(), invocation.globalOptions.output, "mangle", dumpToScreen: invocation.globalOptions.dumpToScreen)
        }
        return true
    }

    public func IsRealPipelineEnabled(): Bool {
        return EnvFlagEnabled("CJ_REAL_PIPELINE")
    }

    public func IsRealPipelineVerbose(): Bool {
        return EnvFlagEnabled("CJ_REAL_PIPELINE_VERBOSE")
    }

    private func EnvFlagEnabled(name: String): Bool {
        let value = invocation.globalOptions.environment.allVariables.get(name) ?? ""
        return value == "1" || value == "true" || value == "TRUE" || value == "on" || value == "yes"
    }

    private func CaptureRealASTPackagesIfEnabled(): Unit {
        realASTPkgs.clear()
        if (!IsRealPipelineEnabled()) {
            return
        }
        for (pkg in srcPkgs) {
            if (let Some(realPkg) <- ParseRealASTPackageForFacadePackage(pkg)) {
                realASTPkgs[pkg.fullPackageName] = realPkg
            } else if (IsRealPipelineVerbose()) {
                eprintln("[real-pipeline] failed to build real AST package for '" +
                    pkg.fullPackageName + "'; falling back")
            }
        }
    }

    private func ParseRealASTPackageForFacadePackage(pkg: Package): Option<RealASTPackage> {
        let realPkg = RealASTPackage(pkg.fullPackageName)
        realPkg.noSubPkg = pkg.noSubPkg
        realPkg.needExported = pkg.needExported
        for (file in pkg.files) {
            let fileID = file.begin.fileID
            let source = sm.GetSource(fileID)
            if (source.buffer.isEmpty()) {
                return None
            }
            let parseDiag = ParseDiagnosticEngine()
            let parser = RealParser(fileID, source.buffer, parseDiag, sm)
            let realFile = parser.ParseTopLevel()
            if (parseDiag.HasError()) {
                return None
            }
            realFile.filePath = file.filePath
            realFile.fileName = file.fileName
            realFile.fileHash = file.fileHash
            realFile.begin = file.begin
            realFile.end = file.end
            realFile.curPackage = Some(realPkg)
            realFile.indexOfPackage = UInt64(realPkg.files.size)
            realPkg.files.add(realFile)
        }
        AddCurFile(realPkg)
        return Some(realPkg)
    }

    public func GenerateCHIRForPkg(pkg: Package): Bool {
        if (pkg.files.isEmpty()) {
            return true
        }
        var usedRealASTPath = false
        if (IsRealPipelineEnabled()) {
            if (let Some(realASTPkg) <- realASTPkgs.get(pkg.fullPackageName)) {
                if (let Some(realPkg) <- BuildRealCHIRForASTPackage(this, realASTPkg)) {
                    chirData.AppendNewRealPackage(realPkg)
                    usedRealASTPath = true
                    if (IsRealPipelineVerbose()) {
                        eprintln("[real-pipeline] lowered main via real AST2CHIR")
                    }
                } else {
                    if (diag.GetErrorCount() != 0) {
                        return false
                    }
                    if (IsRealPipelineVerbose()) {
                        eprintln("[real-pipeline] unsupported real AST shape for package '" +
                            pkg.fullPackageName + "'; falling back")
                    }
                }
            } else if (IsRealPipelineVerbose()) {
                eprintln("[real-pipeline] no stored real AST package for '" + pkg.fullPackageName + "'; falling back")
            }
        }
        if (!usedRealASTPath) {
            if (let Some(realPkg) <- BuildRealCHIRForFrontendPackage(this, pkg)) {
                chirData.AppendNewRealPackage(realPkg)
            } else {
                return false
            }
        }
        let chirPkg = CHIRPackage(pkg.fullPackageName)
        chirPkg.fileCount = pkg.files.size
        for (file in pkg.files) {
            for (decl in file.decls) {
                collectCHIRDeclSummary(chirPkg, decl)
            }
        }
        chirPkg.declCount = chirPkg.mangleNames.size
        chirData.AppendNewPackage(chirPkg)
        chirData.SetImplicitFuncs(chirPkg, chirPkg.implicitFuncs)
        chirData.SetConstVarInitFuncs(chirPkg, chirPkg.constVarInitFuncs)
        return true
    }

    public func PerformCHIRCompilation(): Bool {
        typeManager.ReleasePostSemaCaches()
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
            let lexer = FrontendLexer(fileID, readResult[1], diag, GetSourceManager())
            while (true) {
                let tok = lexer.Next()
                if (tok.kind == FrontendTokenKind.END) {
                    break
                }
                let position = "<" + filePath + ":" + tok.Begin().line.toString() + ":" +
                    tok.Begin().column.toString() + ">"
                if (tok.kind == FrontendTokenKind.NL) {
                    println((if (tok.value == "\n") { "\\n" } else { "\\r\\n" }) + " " +
                        tok.KindName() + " " + position)
                } else if (tok.kind == FrontendTokenKind.COMMENT) {
                    println(tok.KindName() + " " + position)
                } else {
                    println(tok.value + " " + tok.KindName() + " " + position)
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

    public func PerformCodeGen(): Bool {
        if (diag.GetErrorCount() != 0) {
            return false
        }
        if (let Some(pkg) <- chirData.GetCurrentCHIRPackage()) {
            chirData.ActivateCodegenFuncsForPackage(pkg)
        }
        return EmitRealCodeGenForCompilerInstance(this)
    }

    public func PerformCjoSaving(): Bool {
        if (srcPkgs.isEmpty()) {
            return true
        }
        let pkg = srcPkgs[0]
        let path = invocation.globalOptions.GenerateCachedPathName(pkg.fullPackageName, SERIALIZED_FILE_EXTENSION)
        if (!WriteFileContent(path, RenderPackageSummaryJson(pkg))) {
            diag.Warn(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION, "failed to write CJO summary: " + path)
        }
        return true
    }

    public func PerformResultsSaving(): Bool {
        if (srcPkgs.isEmpty()) {
            return true
        }
        let pkg = srcPkgs[0]
        let path = invocation.globalOptions.GenerateCachedPathName(pkg.fullPackageName, ".frontend.json")
        if (!WriteFileContent(path, RenderFrontendResultsJson(this))) {
            diag.Warn(DiagCategory.OTHER, DEFAULT_POSITION, "failed to write frontend results: " + path)
        }
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

    public func GetExtendDecls(typeName: String): ArrayList<ExtendDecl> {
        let out = ArrayList<ExtendDecl>()
        for (pkg in GetPackages()) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                        if (let Some(extendedType) <- extendDecl.extendedType) {
                            if (extendedType.name == typeName) {
                                out.add(extendDecl)
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    public func GetAllVisibleExtendMembers(typeName: String, curFile: File): ArrayList<Decl> {
        let _ = curFile
        let out = ArrayList<Decl>()
        for (extendDecl in GetExtendDecls(typeName)) {
            for (member in extendDecl.members) {
                out.add(member)
            }
        }
        return out
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

    public func UpdateAndWriteCachedInfoToDisk(): Bool {
        if (!ShouldWriteCacheFile()) {
            return true
        }
        UpdateCachedInfo()
        return WriteCachedInfo()
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
        if (!invocation.frontendOptions.chirDeserialize || invocation.frontendOptions.chirDeserializePath.isEmpty()) {
            return false
        }
        let readResult = ReadFileContent(invocation.frontendOptions.chirDeserializePath)
        if (!readResult[0]) {
            diag.Diagnose(DiagCategory.CHIR, DEFAULT_POSITION,
                "failed to deserialize CHIR: " + readResult[2])
            return false
        }
        let chirPkg = CHIRPackage(GetFileName(invocation.frontendOptions.chirDeserializePath))
        chirPkg.fileCount = SplitLines(readResult[1]).size
        chirPkg.declCount = 0
        chirData.AppendNewPackage(chirPkg)
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
            pkgCtxMap.add(pkg.fullPackageName, ASTContext(diag, pkg))
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
            diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION,
                "failed to detect Cangjie modules: cangjie home is empty")
            return false
        }
        let libPathName = invocation.globalOptions.GetCangjieLibTargetPathName()
        if (libPathName.isEmpty()) {
            diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION,
                "failed to detect Cangjie modules: target library path name is empty")
            return false
        }
        cangjieModules = JoinPath(JoinPath(cangjieHome, "modules"), libPathName)
        if (!FileExist(cangjieModules)) {
            diag.Diagnose(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION,
                "failed to detect Cangjie modules: target library path is not exist: " + cangjieModules)
            return false
        }
        return true
    }

    private func ModularizeCompilation(): Bool {
        return packageManager.ResolveDependence(pkgs)
    }

    private func CacheCompileArgs(): Unit {
        cachedInfo.compileArgs = JoinSerializedOptionFields(invocation.globalOptions.ToSerialized())
    }

    private func UpdateCachedInfo(): Unit {
        ()
    }

    private func WriteCachedInfo(): Bool {
        if (srcPkgs.isEmpty()) {
            return true
        }
        let path = invocation.globalOptions.GenerateCachedPathName(srcPkgs[0].fullPackageName, CACHED_AST_EXTENSION)
        return WriteFileContent(path, cachedInfo.compileArgs)
    }

    private func ShouldWriteCacheFile(): Bool {
        if (!invocation.globalOptions.enIncrementalCompilation) {
            return false
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
            return false
        }
        if (srcPkgs[0].IsEmpty()) {
            return false
        }
        return true
    }

    private func ManglingHelpFunction(baseMangler: BaseMangler): Unit {
        let seen = HashSet<String>()
        for (pkg in GetPackages()) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    mangleDeclTree(baseMangler, pkg.fullPackageName, decl, seen)
                }
            }
            for (decl in pkg.genericInstantiatedDecls) {
                mangleDeclTree(baseMangler, pkg.fullPackageName, decl, seen)
            }
        }
        for (pkg in importManager.GetAllImportedPackages()) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    if (decl.isUsedImports || !decl.TestAttr("IMPORTED")) {
                        mangleDeclTree(baseMangler, pkg.fullPackageName, decl, seen)
                    }
                }
                for (decl in file.exportedInternalDecls) {
                    if (decl.isUsedImports || !decl.TestAttr("IMPORTED")) {
                        mangleDeclTree(baseMangler, pkg.fullPackageName, decl, seen)
                    }
                }
            }
            for (decl in pkg.genericInstantiatedDecls) {
                if (decl.IsNominalDecl()) {
                    mangleDeclTree(baseMangler, pkg.fullPackageName, decl, seen)
                }
            }
        }
    }

    private func mangleDeclTree(baseMangler: BaseMangler, pkgName: String, decl: Decl, seen: HashSet<String>): Unit {
        let key = pkgName + "::" + decl.identifier.Val() + "::" + ASTKindName(decl.astKind)
        if (seen.contains(key)) {
            return
        }
        seen.add(key)
        decl.fullPackageName = pkgName
        decl.mangledName = baseMangler.Mangle(decl)
        if (mangledName2DeclMap.contains(decl.mangledName)) {
            mangledName2DeclMap.remove(decl.mangledName)
        }
        mangledName2DeclMap.add(decl.mangledName, decl)
        for (member in decl.members) {
            mangleDeclTree(baseMangler, pkgName, member, seen)
        }
    }

    private func ensureAPILevelAnnotationForDecl(decl: Decl, invocation: MacroInvocation): Unit {
        for (anno in decl.annotations) {
            if (anno.identifier.Val() == "APILevel") {
                return
            }
        }
        let anno = Annotation()
        anno.identifier = SrcIdentifier("APILevel")
        anno.kind = AnnotationKind.CUSTOM
        var lastIdentifier = ""
        for (attr in invocation.attrs) {
            if (attr.kind == FrontendTokenKind.IDENTIFIER) {
                lastIdentifier = attr.value
            } else if (attr.kind == FrontendTokenKind.STRING_LITERAL || attr.kind == FrontendTokenKind.INTEGER_LITERAL ||
                attr.kind == FrontendTokenKind.BOOL_LITERAL) {
                if (lastIdentifier.isEmpty()) {
                    anno.args.add(attr.value)
                } else {
                    anno.args.add(lastIdentifier + ":" + attr.value)
                }
            }
        }
        decl.annotations.add(anno)
    }

    private func collectDeclCacheSummary(pkg: Package, file: File, decl: Decl): Unit {
        cachedInfo.declSummaries.add(makeDeclSummary(pkg, file, decl))
        for (member in decl.members) {
            collectDeclCacheSummary(pkg, file, member)
        }
    }

    private func makeDeclSummary(pkg: Package, file: File, decl: Decl): String {
        let builder = StringBuilder()
        builder.append(pkg.fullPackageName)
        builder.append("|")
        builder.append(file.filePath)
        builder.append("|")
        builder.append(ASTKindName(decl.astKind))
        builder.append("|")
        builder.append(decl.identifier.Val())
        builder.append("|")
        builder.append(decl.begin.line.toString())
        builder.append(":")
        builder.append(decl.begin.column.toString())
        builder.append("-")
        builder.append(decl.end.line.toString())
        builder.append(":")
        builder.append(decl.end.column.toString())
        if (let Some(generic) <- decl.generic) {
            builder.append("|generic:")
            appendStringList(builder, generic.typeParameters)
        }
        return builder.toString()
    }

    private func collectGenericInstantiations(pkg: Package): Unit {
        let seen = HashSet<String>()
        for (existing in pkg.genericInstantiatedDecls) {
            seen.add(genericDeclKey(pkg.fullPackageName, existing))
        }
        for (file in pkg.files) {
            for (decl in file.decls) {
                collectGenericDecl(pkg, decl, seen)
            }
        }
    }

    private func collectGenericDecl(pkg: Package, decl: Decl, seen: HashSet<String>): Unit {
        if (declHasGenericShape(decl)) {
            let key = genericDeclKey(pkg.fullPackageName, decl)
            if (!seen.contains(key)) {
                seen.add(key)
                pkg.genericInstantiatedDecls.add(decl)
            }
        }
        for (member in decl.members) {
            collectGenericDecl(pkg, member, seen)
        }
    }

    private func declHasGenericShape(decl: Decl): Bool {
        if (let Some(generic) <- decl.generic) {
            if (!generic.typeParameters.isEmpty()) {
                return true
            }
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(generic) <- funcDecl.funcBody.generic) {
                return !generic.typeParameters.isEmpty()
            }
        }
        return false
    }

    private func genericDeclKey(pkgName: String, decl: Decl): String {
        return pkgName + "|" + ASTKindName(decl.astKind) + "|" + decl.identifier.Val() + "|" +
            decl.begin.line.toString() + ":" + decl.begin.column.toString()
    }

    private func collectCHIRDeclSummary(chirPkg: CHIRPackage, decl: Decl): Unit {
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
        for (member in decl.members) {
            collectCHIRDeclSummary(chirPkg, member)
        }
    }
}

private func RenderPackageSummaryJson(pkg: Package): String {
    let builder = StringBuilder()
    builder.append("{\n")
    builder.append("  \"package\": \"" + EscapeJson(pkg.fullPackageName) + "\",\n")
    builder.append("  \"files\": [\n")
    var fileIdx: Int64 = 0
    while (fileIdx < pkg.files.size) {
        if (fileIdx > 0) {
            builder.append(",\n")
        }
        appendFileSummaryJson(builder, pkg.files[fileIdx])
        fileIdx++
    }
    builder.append("\n  ],\n")
    builder.append("  \"genericInstantiatedDecls\": [")
    var genIdx: Int64 = 0
    while (genIdx < pkg.genericInstantiatedDecls.size) {
        if (genIdx > 0) {
            builder.append(", ")
        }
        builder.append("\"" + EscapeJson(pkg.genericInstantiatedDecls[genIdx].identifier.Val()) + "\"")
        genIdx++
    }
    builder.append("]\n")
    builder.append("}\n")
    return builder.toString()
}

private func RenderFrontendResultsJson(ci: CompilerInstance): String {
    let builder = StringBuilder()
    builder.append("{\n")
    builder.append("  \"compileArgs\": \"" + EscapeJson(ci.cachedInfo.compileArgs) + "\",\n")
    builder.append("  \"diagnostics\": {\n")
    builder.append("    \"errors\": " + ci.diag.GetErrorCount().toString() + ",\n")
    builder.append("    \"warnings\": " + ci.diag.GetWarningCount().toString() + "\n")
    builder.append("  },\n")
    builder.append("  \"sourcePackages\": [")
    let pkgs = ci.GetSourcePackages()
    var pkgIdx: Int64 = 0
    while (pkgIdx < pkgs.size) {
        if (pkgIdx > 0) {
            builder.append(", ")
        }
        builder.append("\"" + EscapeJson(pkgs[pkgIdx].fullPackageName) + "\"")
        pkgIdx++
    }
    builder.append("],\n")
    builder.append("  \"cache\": {\n")
    builder.append("    \"files\": ")
    appendStringArrayJson(builder, ci.cachedInfo.fileSummaries)
    builder.append(",\n")
    builder.append("    \"decls\": ")
    appendStringArrayJson(builder, ci.cachedInfo.declSummaries)
    builder.append("\n")
    builder.append("  },\n")
    builder.append("  \"chirPackages\": [")
    let chirPkgs = ci.GetAllCHIRPackages()
    var chirIdx: Int64 = 0
    while (chirIdx < chirPkgs.size) {
        if (chirIdx > 0) {
            builder.append(", ")
        }
        builder.append("\"" + EscapeJson(chirPkgs[chirIdx].name) + "\"")
        chirIdx++
    }
    builder.append("]\n")
    builder.append("}\n")
    return builder.toString()
}

private func appendFileSummaryJson(builder: StringBuilder, file: File): Unit {
    builder.append("    {\n")
    builder.append("      \"path\": \"" + EscapeJson(file.filePath) + "\",\n")
    builder.append("      \"hash\": \"" + file.fileHash.toString() + "\",\n")
    if (let Some(packageSpec) <- file.packageSpec) {
        builder.append("      \"packageSpec\": \"" + EscapeJson(packageSpec.GetPackageName()) + "\",\n")
    } else {
        builder.append("      \"packageSpec\": \"\",\n")
    }
    builder.append("      \"imports\": ")
    let imports = ArrayList<String>()
    for (importSpec in file.imports) {
        imports.add(GetImportedItemFullName(importSpec.content))
    }
    appendStringArrayJson(builder, imports)
    builder.append(",\n")
    builder.append("      \"decls\": [")
    var declIdx: Int64 = 0
    while (declIdx < file.decls.size) {
        if (declIdx > 0) {
            builder.append(", ")
        }
        builder.append("\"" + EscapeJson(ASTKindName(file.decls[declIdx].astKind) + ":" +
            file.decls[declIdx].identifier.Val()) + "\"")
        declIdx++
    }
    builder.append("]\n")
    builder.append("    }")
}

private func appendStringArrayJson(builder: StringBuilder, values: ArrayList<String>): Unit {
    builder.append("[")
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(", ")
        }
        builder.append("\"" + EscapeJson(values[idx]) + "\"")
        idx++
    }
    builder.append("]")
}

private func appendStringList(builder: StringBuilder, values: ArrayList<String>): Unit {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(",")
        }
        builder.append(values[idx])
        idx++
    }
}

private func JoinSerializedOptionFields(values: Array<String>): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(",")
        }
        builder.append(values[idx])
        idx++
    }
    return builder.toString()
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
        println(RenderPackageTree(pkg))
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
    let rendered = RenderPackageTree(srcPkgs[0])
    if (WriteFileContent(dumpPath, rendered)) {
        astDumpFileNum++
    }
}

private func RenderPackageTree(pkg: Package): String {
    let builder = StringBuilder()
    builder.append("Package(" + pkg.fullPackageName + ")\n")
    for (file in pkg.files) {
        builder.append("  File(" + file.filePath + ")\n")
        if (let Some(packageSpec) <- file.packageSpec) {
            builder.append("    package " + packageSpec.GetPackageName() + "\n")
        }
        for (importSpec in file.imports) {
            builder.append("    import " + GetImportedItemFullName(importSpec.content) + "\n")
        }
        for (decl in file.decls) {
            appendDecl(builder, decl, 2)
        }
    }
    return builder.toString()
}

private func appendDecl(builder: StringBuilder, decl: Decl, indent: Int64): Unit {
    var spaces = ""
    var idx: Int64 = 0
    while (idx < indent) {
        spaces += "  "
        idx++
    }
    builder.append(spaces + ASTKindName(decl.astKind) + " " + decl.identifier.Val())
    if (!decl.mangledName.isEmpty()) {
        builder.append(" [" + decl.mangledName + "]")
    }
    builder.append("\n")
    for (member in decl.members) {
        appendDecl(builder, member, indent + 1)
    }
}
