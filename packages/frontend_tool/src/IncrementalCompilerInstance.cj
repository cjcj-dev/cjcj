package cjcj::frontend_tool

import std.collection.*
import cjcj::basic.{Errorln, StringConvertor}
import cjcj::codegen.{getZExtValue, LLVMContextHandle, LLVMGetMDNodeOperands,
    LLVMGetNamedMetadataOperandValues, LLVMParseIRFile}
import cjcj::frontend.*
import cjcj::incremental_compilation.{CachedMangleMap, CompilationCache, DeleteRecompiledNodesInCHIROptEffectMap,
    DeleteRemovedNodesInCHIROptEffectMap, IncreKind, IncreResult, IncrementalScopeAnalysis,
    IncrementalScopeAnalysisArgs, MergeCHIROptEffectMap}
import cjcj::sema.{CollectChangedStructTypes, CollectCompilerAddedDeclUsage, CollectRemovedMangles,
    CollectRemovedManglesForReCompile, HandleCtorForIncr, MarkIncrementalCheckForCtor}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, IncrementalCompilationLogger}
import cjcj::option.OutputMode
import cjcj::option.TempFileInfo
import cjcj::utils.FileUtil
import cjcj::utils.ProfileRecorder

public class IncrementalCompilerInstance <: DefaultCompilerInstance {
    public let cacheMangles: CachedMangleMap = CachedMangleMap()
    public let changedTypes: HashSet<StructTy> = HashSet<StructTy>()
    public var kind: IncreKind = IncreKind.INVALID
    private let declsToBeReCompiled: HashSet<Decl> = HashSet<Decl>()
    private let rawIncrRemovedDecls: ArrayList<String> = ArrayList<String>()

    public init(invocation: CompilerInvocation, diag: DiagnosticEngine) {
        super(invocation, diag)
    }

    // C++: FrontendTool/IncrementalCompilerInstance.cpp:51-96.
    private func SaveCompilationResult(result: IncreResult): Unit {
        kind = result.kind
        core.rawMangleName2DeclMap = result.mangle2decl
        if (kind == IncreKind.ROLLBACK || kind == IncreKind.INCR) {
            if (kind == IncreKind.ROLLBACK) {
                declsToBeReCompiled.clear()
            }
            core.cachedInfo = result.cacheInfo
            core.CacheCompileArgs()
            declsToBeReCompiled.clear()
            for (decl in result.declsToRecompile) { declsToBeReCompiled.add(decl) }
            rawIncrRemovedDecls.clear()
            for (removed in result.deleted) { rawIncrRemovedDecls.add(removed) }
            core.mangledName2DeclMap.clear()
            for ((mangle, decl) in result.mangle2decl) {
                if (!decl.TestAttr(Attribute.IMPORTED)) {
                    core.mangledName2DeclMap[mangle] = decl
                }
            }
            for (changed in declsToBeReCompiled) {
                if (changed.TestAttr(Attribute.IMPORTED) &&
                    (changed.IsFunc() || IsGlobalOrStaticVar(changed))) {
                    cacheMangles.EmplaceImportedInlineDeclPtr(changed)
                } else {
                    CollectRemovedManglesForReCompile(changed, core.cachedInfo.semaInfo,
                        cacheMangles.incrRemovedDecls)
                }
            }
            for (removed in rawIncrRemovedDecls) {
                CollectRemovedMangles(removed, core.cachedInfo.semaInfo, cacheMangles.incrRemovedDecls)
            }
            for (typeMangle in result.reBoxedTypes) {
                CollectRemovedMangles(typeMangle, core.cachedInfo.semaInfo, cacheMangles.incrRemovedDecls)
            }
        } else if (kind == IncreKind.NO_CHANGE) {
            core.cachedInfo.bitcodeFilesName.clear()
            for (fileName in result.cacheInfo.bitcodeFilesName) {
                core.cachedInfo.bitcodeFilesName.add(fileName)
            }
        } else if (kind == IncreKind.EMPTY_PKG) {
            return
        } else {
            CJC_ABORT()
        }
        core.kind = kind
    }

    public override func InitCompilerInstance(): Bool {
        return core.InitCompilerInstance()
    }

    public override func PerformIncrementalScopeAnalysis(): Bool {
        let recorder = ProfileRecorder("Main Stage", "AST Diff")
        CJC_ASSERT(core.srcPkgs.size == 1)
        let sourcePackage = core.srcPkgs[0]
        if (!core.CalculateASTCache()) {
            recorder.close()
            return true
        }
        let options = invocation.globalOptions
        if (!options.pluginPaths.isEmpty()) {
            kind = IncreKind.ROLLBACK
            diag.Warn(DiagCategory.OTHER, DEFAULT_POSITION,
                "`--incremental-compile` is incompatible with `--plugin` and will be ignored.")
            core.kind = kind
            recorder.close()
            return true
        }
        if (!core.declsWithDuplicatedRawMangleName.isEmpty()) {
            kind = IncreKind.ROLLBACK
            IncrementalCompilationLogger.GetInstance().LogLn(
                "illegal source code leads to duplicated raw mangle name, roll back to full compilation")
            core.kind = kind
            recorder.close()
            return true
        }
        let args = IncrementalScopeAnalysisArgs(core.rawMangleName2DeclMap, core.astCacheInfo, sourcePackage,
            options, core.importManager, core.cachedInfo, core.fileMap, core.directExtends)
        let result = IncrementalScopeAnalysis(args)
        if (result.kind == IncreKind.INCR) {
            if (!CheckCachedBitcodeInfo(sourcePackage.fullPackageName, options)) {
                result.kind = IncreKind.ROLLBACK
            } else {
                for (mangle in result.deletedMangleNames) { cacheMangles.incrRemovedDecls.add(mangle) }
            }
        }
        if (result.kind == IncreKind.NO_CHANGE) {
            for (srcPkg in core.GetSourcePackages()) {
                options.UpdateCachedDirName(srcPkg.fullPackageName)
            }
            if (!options.IsLTOEnabled() && !CheckCachedObjFile(options, result.cacheInfo)) {
                result.kind = IncreKind.ROLLBACK
            }
            if (options.IsLTOEnabled() && !CheckCachedBitcodeInfoForLTO(options, result.cacheInfo)) {
                result.kind = IncreKind.ROLLBACK
            }
        }
        result.Dump()
        SaveCompilationResult(result)
        recorder.close()
        return true
    }

    public override func PerformSema(): Bool {
        LogIncrementalStageDecision("Semantic", "no change, skip sema", "full sema", "incremental sema")
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        if (kind == IncreKind.ROLLBACK) {
            return super.PerformSema()
        }
        for (srcPkg in core.GetSourcePackages()) {
            srcPkg.EnableAttr(Attribute.INCRE_COMPILE)
            HandleCtorForIncr(srcPkg, core.mangledName2DeclMap, core.cachedInfo.semaInfo)
            for (mangle in core.importManager.LoadCachedTypeForPackage(srcPkg, core.mangledName2DeclMap)) {
                cacheMangles.incrRemovedDecls.add(mangle)
            }
        }
        MarkIncrementalCheckForCtor(declsToBeReCompiled)
        for ((_, decl) in core.mangledName2DeclMap) {
            if (!decl.toBeCompiled && !IsInDeclWithAttribute(decl, Attribute.GENERIC) &&
                Ty.IsTyCorrect(decl.GetTy()) &&
                (decl.astKind != ASTKind.FUNC_DECL || !decl.TestAttr(Attribute.DEFAULT))) {
                if (!decl.IsNominalDecl() && decl.astKind != ASTKind.PROP_DECL) {
                    decl.EnableAttr(Attribute.IS_CHECK_VISITED)
                    decl.EnableAttr(Attribute.INITIALIZED)
                    decl.EnableAttr(Attribute.INITIALIZATION_CHECKED)
                    decl.EnableAttr(Attribute.INCRE_COMPILE)
                }
                if (let Some(funcDecl) <- (decl as FuncDecl)) {
                    if (let Some(funcBody) <- funcDecl.funcBody) {
                        funcBody.body = None
                    }
                } else if (let Some(varDecl) <- (decl as VarDecl)) {
                    if (varDecl.initializer.isSome()) {
                        varDecl.EnableAttr(Attribute.DEFAULT)
                        if (HasSimpleInitialiser(varDecl)) {
                            varDecl.DisableAttr(Attribute.IS_CHECK_VISITED)
                        }
                    }
                }
            }
        }
        return super.PerformSema()
    }

    public override func PerformOverflowStrategy(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformOverflowStrategy()
    }

    public override func PerformDesugarAfterSema(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformDesugarAfterSema()
    }

    public override func PerformGenericInstantiation(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        let ret = super.PerformGenericInstantiation()
        if (ret) {
            for (srcPkg in core.GetSourcePackages()) {
                for (ty in CollectChangedStructTypes(srcPkg, declsToBeReCompiled)) { changedTypes.add(ty) }
                IterateAllExportableDecls(srcPkg, { decl =>
                    if (!decl.IsExportedDecl() && decl.linkage == Linkage.EXTERNAL && !decl.mangledName.isEmpty()) {
                        cacheMangles.newExternalDecls.add(decl.mangledName)
                    }
                })
            }
        }
        return ret
    }

    public override func PerformMangling(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        let success = super.PerformMangling()
        if (success) {
            cacheMangles.UpdateImportedInlineDeclsMangle()
        }
        return success
    }

    public override func PerformCHIRCompilation(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        let ret = super.PerformCHIRCompilation()
        for (ty in core.chirInfo.ccTys) { changedTypes.add(ty) }
        if (kind == IncreKind.INCR) {
            UpdateIncrRemovedDeclsForVirtualFuncDep(cacheMangles, rawIncrRemovedDecls,
                core.cachedInfo.virtualFuncDep, core.chirInfo.delVirtFuncWrapForIncr)
            UpdateIncrRemovedDeclsForVarInitDep(cacheMangles, rawIncrRemovedDecls,
                core.cachedInfo.varInitDepMap)
        }
        return ret
    }

    // C++: FrontendTool/IncrementalCompilerInstance.cpp:376-404.
    public override func UpdateCachedInfo(): Unit {
        core.UpdateMangleNameForCachedInfo()
        UpdateCHIROptEffectMap()
        if (kind == IncreKind.ROLLBACK) {
            core.cachedInfo.virtualFuncDep.clear()
            for ((raw, wrapper) in core.chirInfo.curVirtFuncWrapDep) {
                core.cachedInfo.virtualFuncDep[raw] = wrapper
            }
            core.cachedInfo.ccOutFuncs.clear()
            for (mangle in core.chirInfo.ccOutFuncsRawMangle) { core.cachedInfo.ccOutFuncs.add(mangle) }
            core.cachedInfo.varInitDepMap.clear()
            for ((raw, init) in core.chirInfo.varInitDepMap) { core.cachedInfo.varInitDepMap[raw] = init }
        } else if (kind == IncreKind.INCR) {
            for ((raw, _) in core.chirInfo.delVirtFuncWrapForIncr) {
                core.cachedInfo.virtualFuncDep.remove(raw)
            }
            for ((raw, wrapper) in core.chirInfo.curVirtFuncWrapDep) {
                core.cachedInfo.virtualFuncDep[raw] = wrapper
            }
            for (raw in rawIncrRemovedDecls) { core.cachedInfo.varInitDepMap.remove(raw) }
            for ((raw, init) in core.chirInfo.varInitDepMap) { core.cachedInfo.varInitDepMap[raw] = init }
            for (mangle in core.chirInfo.ccOutFuncsRawMangle) { core.cachedInfo.ccOutFuncs.add(mangle) }
        }
        for (pkg in core.GetSourcePackages()) {
            CollectCompilerAddedDeclUsage(pkg, core.cachedInfo.semaInfo)
        }
    }

    // C++: FrontendTool/IncrementalCompilerInstance.cpp:414-421.
    private func UpdateCHIROptEffectMap(): Unit {
        DeleteRemovedNodesInCHIROptEffectMap(rawIncrRemovedDecls, core.cachedInfo.chirOptInfo)
        DeleteRecompiledNodesInCHIROptEffectMap(declsToBeReCompiled, core.cachedInfo.chirOptInfo)
        MergeCHIROptEffectMap(core.chirInfo.optEffectMap, core.cachedInfo.chirOptInfo,
            core.rawMangleName2DeclMap)
    }

    public override func PerformCodeGen(): Bool {
        if (kind == IncreKind.NO_CHANGE) {
            for (srcPkg in core.GetSourcePackages()) {
                LoadCachedCodegenResult()
                invocation.globalOptions.UpdateCachedDirName(srcPkg.fullPackageName)
            }
            return true
        }
        return CodegenOnePackage(kind == IncreKind.INCR, cachedMangleMap: cacheMangles)
    }

    public override func PerformCjoSaving(): Bool {
        LogCjoSavingDecision()
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        return super.PerformCjoSaving()
    }

    public override func PerformResultsSaving(): Bool {
        if (kind == IncreKind.NO_CHANGE || kind == IncreKind.EMPTY_PKG) {
            return true
        }
        let ret = super.PerformResultsSaving()
        if (ret) {
            return SaveIncrementalSignatures()
        }
        return ret
    }

    private func LogIncrementalStageDecision(
        stageName: String,
        noChangeMessage: String,
        rollbackMessage: String,
        incrementalMessage: String
    ): Unit {
        let logger = IncrementalCompilationLogger.GetInstance()
        if (!logger.IsEnable()) {
            return
        }
        let message = if (kind == IncreKind.NO_CHANGE) {
            noChangeMessage
        } else if (kind == IncreKind.ROLLBACK) {
            rollbackMessage
        } else if (kind == IncreKind.INCR) {
            incrementalMessage
        } else if (kind == IncreKind.EMPTY_PKG) {
            "empty pkg, skip " + stageName
        } else {
            "invalid incremental state for " + stageName
        }
        logger.LogLn(message)
    }

    private func LogCjoSavingDecision(): Unit {
        let logger = IncrementalCompilationLogger.GetInstance()
        if (!logger.IsEnable()) {
            return
        }
        let message = if (kind == IncreKind.NO_CHANGE) {
            "no change, skip cjo saving"
        } else if (kind == IncreKind.EMPTY_PKG) {
            "empty pkg, skip cjo saving"
        } else if (invocation.globalOptions.outputMode == OutputMode.CHIR) {
            " chir output mode, skip cjo saving"
        } else {
            "incremental cjo saving"
        }
        logger.LogLn(message)
    }

    private func LoadCachedCodegenResult(): Unit {
        for (fileName in core.cachedInfo.bitcodeFilesName) {
            let cachePath = invocation.globalOptions.GenerateCachedPathNameForCodeGen(fileName, ".bc")
            let bcFileInfo = TempFileInfo(fileName: fileName, filePath: cachePath, isFrontendOutput: true)
            invocation.globalOptions.frontendOutputFiles.add(bcFileInfo)
        }
    }

    private func LogIncrementalAnalysisResult(): Unit {
        let logger = IncrementalCompilationLogger.GetInstance()
        if (!logger.IsEnable()) {
            return
        }
        if (kind == IncreKind.ROLLBACK) {
            logger.LogLn("incremental compile result kind: rollback")
        } else if (kind == IncreKind.EMPTY_PKG) {
            logger.LogLn("incremental compile result kind: empty package")
        } else if (kind == IncreKind.NO_CHANGE) {
            logger.LogLn("incremental compile result kind: no change")
        } else if (kind == IncreKind.INCR) {
            let delimiter = MakeIncrementalDumpDelimiter()
            logger.LogLn(delimiter)
            logger.LogLn("incremental compilation triggered")
            logger.LogLn("begin dump incremental compile result:")
            LogStringSetWithCount("changed decls to recompile: ", "the changed decl after Spreading is:",
                declsToBeReCompiled)
            logger.LogLn(delimiter)
            LogStringListWithCount("deleted decls: ", "the deleted decl is:", rawIncrRemovedDecls)
            logger.LogLn(delimiter)
            LogStringSetWithCount("changed files to recompile: ", "the changed file summary is:",
                filesToBeReCompiled)
            LogStringListWithCount("deleted files: ", "the deleted file summary is:", rawIncrRemovedFiles)
            logger.LogLn(delimiter)
        } else {
            logger.LogLn("incremental compile result kind: invalid")
        }
    }

    private func CollectChangedTypeNames(): Unit {
        changedTypes.clear()
        for (pkg in core.GetSourcePackages()) {
            for (file in pkg.files) {
                for (decl in file.decls) {
                    CollectStructNames(pkg, file, decl)
                }
            }
        }
    }

    private func CollectStructNames(pkg: Package, file: File, decl: Decl): Unit {
        let declSummary = EscapeCacheLine(BuildDeclCacheSummary(pkg, file, decl))
        if (decl.astKind == ASTKind.STRUCT_DECL &&
            (kind != IncreKind.INCR || declsToBeReCompiled.contains(declSummary))) {
            changedTypes.add(decl.identifier.Val())
        }
        for (member in decl.GetMemberDecls()) {
            CollectStructNames(pkg, file, member)
        }
    }

    private func BuildDeclCacheSummary(pkg: Package, file: File, decl: Decl): String {
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
            AppendCacheGenericParamList(builder, generic.typeParameters)
        }
        return builder.toString()
    }

    private func SaveIncrementalSignatures(): Bool {
        if (currentCacheText.isEmpty()) {
            currentCacheText = RenderFrontendToolIncrementalCache()
        }
        var ret = true
        let cachePath = GetFrontendToolIncrementalCachePath()
        if (!cachePath.isEmpty()) {
            if (!FileUtil.WriteToFile(cachePath, currentCacheText)) {
                diag.Warn(DiagCategory.IMPORT_PACKAGE, DEFAULT_POSITION,
                    "failed to write FrontendTool incremental cache: " + cachePath)
                ret = false
            }
        }
        for (pkg in core.GetSourcePackages()) {
            if (pkg.IsEmpty()) {
                continue
            }
            let cjoPath = invocation.globalOptions.GenerateCachedPathName(
                pkg.fullPackageName, SERIALIZED_FILE_EXTENSION)
            let data = SerializePackageToCjoFlatBuffer(pkg, "", core.importManager.GetCjoManager(),
                invocation.globalOptions.enableCompileDebug, invocation.globalOptions.optimizationLevel,
                diag: diag, exportContent: true, exportForIncr: true, exportFuncBody: true)
            ret = FileUtil.WriteBufferToASTFile(cjoPath, data) && ret
        }
        return ret
    }

    private func AnalyseCurrentFrontendCache(): IncreKind {
        currentCacheText = RenderFrontendToolIncrementalCache()
        let cachePath = GetFrontendToolIncrementalCachePath()
        if (cachePath.isEmpty()) {
            LogIncrementalRollback("load cached info failed, roll back to full compilation")
            return IncreKind.ROLLBACK
        }
        if (!FileExist(cachePath)) {
            LogIncrementalRollback("load cached info failed, roll back to full compilation")
            return IncreKind.ROLLBACK
        }
        let readResult = ReadFileContent(cachePath)
        if (!readResult[0]) {
            LogIncrementalRollback("load cached info failed, roll back to full compilation")
            return IncreKind.ROLLBACK
        }
        let previousCache = readResult[1]
        if (GetCacheLineValue(previousCache, "version:") != "1") {
            LogIncrementalRollback("cached FrontendTool incremental cache version changed, roll back to full compilation")
            return IncreKind.ROLLBACK
        }
        if (previousCache == currentCacheText) {
            return IncreKind.NO_CHANGE
        }
        if (GetCacheLineValue(previousCache, "args:") != EscapeCacheLine(core.cachedInfo.compileArgs.toString())) {
            LogIncrementalRollback("compile args changed, roll back to full compilation")
            return IncreKind.ROLLBACK
        }
        let changedFiles = CollectCacheDelta(previousCache, currentCacheText)
        return if (declsToBeReCompiled.isEmpty() && rawIncrRemovedDecls.isEmpty() && !changedFiles) {
            IncreKind.NO_CHANGE
        } else {
            IncreKind.INCR
        }
    }

    private func GetFrontendToolIncrementalCachePath(): String {
        let pkgs = core.GetSourcePackages()
        if (pkgs.isEmpty()) {
            return ""
        }
        return invocation.globalOptions.GenerateCachedPathName(pkgs[0].fullPackageName, ".frontend_tool.incr")
    }

    private func RenderFrontendToolIncrementalCache(): String {
        let builder = StringBuilder()
        builder.append("version:1\n")
        builder.append("args:" + EscapeCacheLine(core.cachedInfo.compileArgs.toString()) + "\n")
        for (pkg in core.GetSourcePackages()) {
            for (file in pkg.files) {
                let fileSummary = pkg.fullPackageName + "|" + file.filePath + "|" + file.fileHash.toString()
                builder.append("file:" + EscapeCacheLine(fileSummary) + "\n")
                let decls = ArrayList<Decl>()
                for (decl in file.decls) { decls.add(decl) }
                var idx: Int64 = 0
                while (idx < decls.size) {
                    let decl = decls[idx]
                    builder.append("decl:" + EscapeCacheLine(BuildDeclCacheSummary(pkg, file, decl)) + "\n")
                    for (member in decl.GetMemberDecls()) { decls.add(member) }
                    idx++
                }
            }
        }
        return builder.toString()
    }

    private func CollectCacheDelta(previousCache: String, newCache: String): Bool {
        var filesChanged = false
        let previousFiles = CollectCacheLines(previousCache, "file:")
        let newFiles = CollectCacheLines(newCache, "file:")
        for (oldFile in previousFiles) {
            if (!newFiles.contains(oldFile)) {
                rawIncrRemovedFiles.add(oldFile)
                filesChanged = true
            }
        }
        for (newFile in newFiles) {
            if (!previousFiles.contains(newFile)) {
                filesToBeReCompiled.add(newFile)
                filesChanged = true
            }
        }
        let previousDecls = CollectCacheLines(previousCache, "decl:")
        let newDecls = CollectCacheLines(newCache, "decl:")
        for (oldDecl in previousDecls) {
            if (!newDecls.contains(oldDecl)) {
                rawIncrRemovedDecls.add(oldDecl)
            }
        }
        for (newDecl in newDecls) {
            if (!previousDecls.contains(newDecl)) {
                declsToBeReCompiled.add(newDecl)
            }
        }
        return filesChanged
    }
}

// C++: FrontendTool/IncrementalCompilerInstance.cpp:427-441.
private func UpdateIncrRemovedDeclsForVirtualFuncDep(cacheMangles: CachedMangleMap,
    rawIncrRemovedDecls: ArrayList<String>, virtualFuncDep: VirtualWrapperDepMap,
    delVirtFuncWrapForIncr: VirtualWrapperDepMap): Unit {
    let logger = IncrementalCompilationLogger.GetInstance()
    for (deletedRaw in rawIncrRemovedDecls) {
        if (let Some(wrapper) <- virtualFuncDep.get(deletedRaw)) {
            logger.LogLn("[delVirDep][remove] raw: " + deletedRaw + " mg: " + wrapper)
            cacheMangles.incrRemovedDecls.add(wrapper)
        }
    }
    for ((deletedRaw, deleted) in delVirtFuncWrapForIncr) {
        logger.LogLn("[delVirDep][change] raw: " + deletedRaw + " mg: " + deleted)
        cacheMangles.incrRemovedDecls.add(deleted)
    }
}

// C++: FrontendTool/IncrementalCompilerInstance.cpp:442-452.
private func UpdateIncrRemovedDeclsForVarInitDep(cacheMangles: CachedMangleMap,
    rawIncrRemovedDecls: ArrayList<String>, varInitDepMap: VarInitDepMap): Unit {
    let logger = IncrementalCompilationLogger.GetInstance()
    for (deletedRaw in rawIncrRemovedDecls) {
        if (let Some(init) <- varInitDepMap.get(deletedRaw)) {
            logger.LogLn("[delVarInitDep][remove] raw: " + deletedRaw + " mg: " + init)
            cacheMangles.incrRemovedDecls.add(init)
        }
    }
}

// C++: FrontendTool/IncrementalCompilerInstance.cpp:252-264.
private func HasSimpleInitialiser(decl: VarDecl): Bool {
    let initializer = decl.initializer ?? return false
    if (let Some(litConst) <- (initializer as LitConstExpr)) {
        return litConst.kind != LitConstKind.JSTRING && litConst.kind != LitConstKind.UNIT
    }
    return false
}

private func GetCachedSplitNum(cachedCodeGenPath: String): Option<UInt64> {
    var splitNum: Option<UInt64> = None
    @When[os == "Windows"]
    let tempPath = StringConvertor.NormalizeStringToUTF8(cachedCodeGenPath)
    @When[os == "Windows"]
    let path = if (let Some(value) <- tempPath) {
        value
    } else {
        CJC_ASSERT(false)
        cachedCodeGenPath
    }
    @When[os != "Windows"]
    let path = cachedCodeGenPath
    try (context = LLVMContextHandle.Create()) {
        let parseResult = LLVMParseIRFile(context, path, name: path)
        if (!parseResult.ok) {
            Errorln("Illegal cached codegen info detected during incremental compilation.")
            return splitNum
        }
        try (module = parseResult.module) {
            for (mdNode in LLVMGetNamedMetadataOperandValues(module, "splitNum")) {
                let operands = LLVMGetMDNodeOperands(mdNode)
                splitNum = getZExtValue(operands[0])
            }
        }
    }
    return splitNum
}

private func CheckCachedBitcode(packageName: String, splitNum: UInt64, globalOp: GlobalOptions): Bool {
    if (splitNum == 0u64) {
        return false
    }
    var i = 0u64
    while (i < splitNum) {
        let cachedBcPath = globalOp.GenerateCachedPathNameForCodeGen(
            i.toString() + "-" + packageName, "_cache.bc")
        if (!FileUtil.FileExist(cachedBcPath)) {
            IncrementalCompilationLogger.GetInstance().LogLn(
                "the cached bitcode file is lost." + cachedBcPath + " index " + i.toString())
            return false
        }
        i++
    }
    return true
}

private func CheckCachedBitcodeInfo(packageName: String, options: GlobalOptions): Bool {
    let cgCachePath = options.GenerateCachedPathNameForCodeGen(packageName, ".cgCache")
    if (!FileUtil.FileExist(cgCachePath)) {
        IncrementalCompilationLogger.GetInstance().LogLn(
            "load cached codegen info failed, roll back to full compilation")
        return false
    }
    let splitNum = GetCachedSplitNum(cgCachePath)
    if (splitNum.isNone()) {
        IncrementalCompilationLogger.GetInstance().LogLn(
            "get cached split num failed, roll back to full compilation")
        return false
    }
    let bcCachedGood = CheckCachedBitcode(packageName, splitNum.getOrThrow(), options)
    if (!bcCachedGood) {
        IncrementalCompilationLogger.GetInstance().LogLn(
            "load cached bitcode file failed, roll back to full compilation")
        return false
    }
    return true
}

private func CheckCachedObjFile(options: GlobalOptions, cachedInfo: CompilationCache): Bool {
    let logger = IncrementalCompilationLogger.GetInstance()
    for (fileName in cachedInfo.bitcodeFilesName) {
        let objFile = options.GetHashedObjFileName(fileName) + ".o"
        if (!FileUtil.FileExist(objFile)) {
            logger.LogLn("cached obj file not exist, roll back to full compilation")
            return false
        }
    }
    return true
}

private func CheckCachedBitcodeInfoForLTO(options: GlobalOptions, cachedInfo: CompilationCache): Bool {
    let logger = IncrementalCompilationLogger.GetInstance()
    for (fileName in cachedInfo.bitcodeFilesName) {
        let objFile = options.GetHashedObjFileName(FileUtil.GetFileNameWithoutExtension(fileName)) + ".bc"
        if (!FileUtil.FileExist(objFile)) {
            logger.LogLn("load cached bitcode file for opt failed, roll back to full compilation")
            return false
        }
    }
    return true
}

private func LogIncrementalRollback(message: String): Unit {
    let logger = IncrementalCompilationLogger.GetInstance()
    if (logger.IsEnable()) {
        logger.LogLn(message)
    }
}

private func CollectCacheLines(cacheText: String, prefix: String): HashSet<String> {
    let out = HashSet<String>()
    for (line in SplitLines(cacheText)) {
        if (line.startsWith(prefix)) {
            out.add(line[prefix.size..])
        }
    }
    return out
}

private func GetCacheLineValue(cacheText: String, prefix: String): String {
    for (line in SplitLines(cacheText)) {
        if (line.startsWith(prefix)) {
            return line[prefix.size..]
        }
    }
    return ""
}

private func EscapeCacheLine(text: String): String {
    return text.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r")
}

private func AppendCacheGenericParamList(builder: StringBuilder, values: ArrayList<GenericParamDecl>): Unit {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            builder.append(",")
        }
        builder.append(values[idx].identifier.Val())
        idx++
    }
}

private func LogStringSetWithCount(title: String, entryPrefix: String, values: HashSet<String>): Unit {
    if (values.isEmpty()) {
        return
    }
    let logger = IncrementalCompilationLogger.GetInstance()
    logger.LogLn(title + values.size.toString())
    for (value in values) {
        logger.LogLn(entryPrefix + value)
    }
}

private func LogStringListWithCount(title: String, entryPrefix: String, values: ArrayList<String>): Unit {
    if (values.isEmpty()) {
        return
    }
    let logger = IncrementalCompilationLogger.GetInstance()
    logger.LogLn(title + values.size.toString())
    for (value in values) {
        logger.LogLn(entryPrefix + value)
    }
}

private func MakeIncrementalDumpDelimiter(): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < 50) {
        builder.append("=")
        idx++
    }
    return builder.toString()
}
