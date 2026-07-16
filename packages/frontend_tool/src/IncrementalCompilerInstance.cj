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
            for ((raw, initFunc) in core.chirInfo.varInitDepMap) {
                core.cachedInfo.varInitDepMap[raw] = initFunc
            }
        } else if (kind == IncreKind.INCR) {
            for ((raw, _) in core.chirInfo.delVirtFuncWrapForIncr) {
                core.cachedInfo.virtualFuncDep.remove(raw)
            }
            for ((raw, wrapper) in core.chirInfo.curVirtFuncWrapDep) {
                core.cachedInfo.virtualFuncDep[raw] = wrapper
            }
            for (raw in rawIncrRemovedDecls) { core.cachedInfo.varInitDepMap.remove(raw) }
            for ((raw, initFunc) in core.chirInfo.varInitDepMap) {
                core.cachedInfo.varInitDepMap[raw] = initFunc
            }
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
        var ret = true
        for (srcPkg in core.GetSourcePackages()) {
            if (invocation.globalOptions.outputMode == OutputMode.CHIR) {
                ret = ret && SaveCjo(srcPkg)
            }
            if (ret && !srcPkg.IsEmpty()) {
                let cachedCjo = invocation.globalOptions.GenerateCachedPathName(
                    srcPkg.fullPackageName, SERIALIZED_FILE_EXTENSION)
                ret = ret && FileUtil.WriteBufferToASTFile(cachedCjo,
                    core.importManager.ExportASTSignature(srcPkg))
            }
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
        if (let Some(initFunc) <- varInitDepMap.get(deletedRaw)) {
            logger.LogLn("[delVarInitDep][remove] raw: " + deletedRaw + " mg: " + initFunc)
            cacheMangles.incrRemovedDecls.add(initFunc)
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
