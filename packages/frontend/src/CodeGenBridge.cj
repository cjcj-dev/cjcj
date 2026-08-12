package cjcj::frontend

import std.collection.*
import cjcj::basic.Linkage as BasicLinkage
import cjcj::chir.Apply as ChirApply
import cjcj::chir.ApplyWithException as ChirApplyWithException
import cjcj::chir.AnalysisWrapper
import cjcj::chir.AnnotationChecker
import cjcj::chir.ArrayListConstStartOpt
import cjcj::chir.ArrayLambdaOpt
import cjcj::chir.Attribute as ChirAttribute
import cjcj::chir.Block as ChirBlock
import cjcj::chir.CHIRBuilder as ChirBuilder
import cjcj::chir.CHIRPrinter as ChirCHIRPrinter
import cjcj::chir.CHIRSerializer
import cjcj::chir.CHIRType
import cjcj::chir.CHIRTypeCache
import cjcj::chir.CallGraphAnalysis
import cjcj::chir.BCHIR
import cjcj::chir.ClosureConversion
import cjcj::chir.ConstAnalysisWrapper
import cjcj::chir.ConstEvalPass
import cjcj::chir.ConstPropagation
import cjcj::chir.CustomTypeDef as ChirCustomTypeDef
import cjcj::chir.DeadCodeElimination
import cjcj::chir.DebugLocation as ChirDebugLocation
import cjcj::chir.Devirtualization as ChirDevirtualization
import cjcj::chir.DevirtualizationInfo
import cjcj::chir.ExprKind as ChirExprKind
import cjcj::chir.FaithfulAST2CHIR
import cjcj::chir.FuncCallContext as ChirFuncCallContext
import cjcj::chir.FuncKind as ChirFuncKind
import cjcj::chir.FuncSigInfo as ChirFuncSigInfo
import cjcj::chir.Function as ChirFunction
import cjcj::chir.FunctionInline
import cjcj::chir.GlobalVar as ChirGlobalVar
import cjcj::chir.GlobalValue as ChirGlobalValue
import cjcj::chir.GetRefToArrayElem
import cjcj::chir.INVALID_LOCATION as CHIR_INVALID_LOCATION
import cjcj::chir.MergeBlocks
import cjcj::chir.MergeEffectMap
import cjcj::chir.NoHeapAllocChecker
import cjcj::chir.NoWriteBarrierRecChecker
import cjcj::chir.OptFuncRetType
import cjcj::chir.OptEffectCHIRMap as ChirOptEffectCHIRMap
import cjcj::chir.Package as RealCHIRPackage
import cjcj::chir.UnreachableBranchCheck
import cjcj::chir.RedundantFutureRemoval
import cjcj::chir.RedundantGetOrThrowElimination
import cjcj::chir.RedundantLoadElimination
import cjcj::chir.RangeAnalysis
import cjcj::chir.RangeDomain
import cjcj::chir.RangePropagation
import cjcj::chir.ReplaceSrcCodeImportedVal
import cjcj::chir.IsTrackedGVForRangeAnalysis
import cjcj::chir.rangeStateGlobals
import cjcj::chir.ReplaceUsesWithWrapper
import cjcj::chir.SanitizerCoverage
import cjcj::chir.ShouldReportUnusedCodeWarnings
import cjcj::chir.Terminator as ChirTerminator
import cjcj::chir.TypeAnalysis
import cjcj::chir.TypeDomain
import cjcj::chir.TypeValue
import cjcj::chir.globalState as typeAnalysisGlobals
import cjcj::chir.ToCHIRPhase
import cjcj::chir.UnitUnify
import cjcj::chir.UselessAllocateElimination
import cjcj::chir.VarInitCheck
import cjcj::chir.Value as ChirValue
import cjcj::ast.Package as RealASTPackage
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::codegen.CHIRData as CodegenCHIRData
import cjcj::incremental_compilation.{CachedMangleMap, OptEffectStrMap, VirtualWrapperDepMap}
import cjcj::codegen.ClearPackageModules
import cjcj::codegen.GenPackageModules as CodegenGenPackageModules
import cjcj::codegen.LLVMModuleHandle as LLVMModuleHandle
import cjcj::codegen.SavePackageModule
import cjcj::meta_transformation.TryRunCHIRMetaTransforms
import cjcj::option.OptimizationFlag
import cjcj::option.CandidateEmitCHIRPhase
import cjcj::option.OutputMode
import cjcj::option.TempFileInfo
import cjcj::option.{TempFileKind, TempFileManager}
import cjcj::utils.CFFI_FUNC_SUFFIX
import cjcj::utils.CHIR_READABLE_FILE_EXTENSION
import cjcj::utils.CHIR_SERIALIZATION_FILE_EXTENSION
import cjcj::utils.CJC_ASSERT
import cjcj::utils.DEFAULT_PACKAGE_NAME
import cjcj::utils.FileUtil
import cjcj::utils.ProfileRecorder
import cjcj::utils.REFLECT_PACKAGE_NAME
import cjcj::utils.{TaskQueue, TaskResult}

// C++: CHIR/CHIR.cpp:55-92.
private func FlattenEffectMap(effectMap: ChirOptEffectCHIRMap): Unit {
    let newEffectMap = ChirOptEffectCHIRMap()
    for ((source, affected) in effectMap) {
        let flattened = HashSet<ChirValue>()
        let stack = ArrayList<ChirValue>()
        for (node in affected) {
            flattened.add(node)
            stack.add(node)
        }
        while (!stack.isEmpty()) {
            let current = stack.remove(at: stack.size - 1)
            if (let Some(patch) <- effectMap.get(current)) {
                for (node in patch) {
                    flattened.add(node)
                    stack.add(node)
                }
            }
        }
        newEffectMap[source] = flattened
    }
    effectMap.clear()
    for ((source, affected) in newEffectMap) {
        effectMap[source] = affected
    }
}

// C++: CHIR/CHIR.cpp:94-102.
private func IsDesugaredNoneStaticConstructor(value: ChirValue): Bool {
    if (!value.IsFuncWithBody()) {
        return false
    }
    let function = (value as ChirFunction).getOrThrow()
    return function.TestAttr(ChirAttribute.COMPILER_ADD) && !function.TestAttr(ChirAttribute.STATIC) &&
        (function.GetFuncKind() == ChirFuncKind.CLASS_CONSTRUCTOR ||
            function.GetFuncKind() == ChirFuncKind.STRUCT_CONSTRUCTOR)
}

// C++: CHIR/CHIR.cpp:104-111.
private func GetNoneStaticMemberVars(def: ChirCustomTypeDef): HashSet<String> {
    let vars = HashSet<String>()
    for (info in def.GetDirectInstanceVars()) {
        vars.add(info.rawMangledName)
    }
    return vars
}

// C++: CHIR/CHIR.cpp:113-116.
private func GetRawMangledName(value: ChirValue): String {
    return (value as ChirGlobalValue).getOrThrow().GetRawMangledName()
}

// C++: CHIR/CHIR.cpp:118-128.
private func GetRawMangledNameSet(values: HashSet<ChirValue>): HashSet<String> {
    let result = HashSet<String>()
    for (value in values) {
        let name = GetRawMangledName(value)
        if (!name.isEmpty()) {
            result.add(name)
        }
    }
    return result
}

// C++: CHIR/CHIR.cpp:130-166.
private func UpdateOptEffectMapBecauseOfInit(oldMap: ChirOptEffectCHIRMap, newMap: OptEffectStrMap): Unit {
    let sources = ArrayList<ChirValue>()
    for ((source, _) in oldMap) {
        sources.add(source)
    }
    for (source in sources) {
        let affected = oldMap.get(source) ?? continue
        let effectedNodePatch = HashSet<String>()
        let affectedValues = ArrayList<ChirValue>()
        for (value in affected) {
            affectedValues.add(value)
        }
        for (value in affectedValues) {
            if (IsDesugaredNoneStaticConstructor(value)) {
                let parentClass = (value as ChirFunction).getOrThrow().GetParentCustomTypeDef().getOrThrow()
                for (member in GetNoneStaticMemberVars(parentClass)) {
                    effectedNodePatch.add(member)
                }
                affected.remove(value)
            }
        }
        if (!effectedNodePatch.isEmpty()) {
            let keyName = GetRawMangledName(source)
            if (!keyName.isEmpty()) {
                if (!newMap.contains(keyName)) {
                    newMap[keyName] = HashSet<String>()
                }
                for (member in effectedNodePatch) {
                    newMap[keyName].add(member)
                }
            }
        }
        if (IsDesugaredNoneStaticConstructor(source)) {
            let parentClass = (source as ChirFunction).getOrThrow().GetParentCustomTypeDef().getOrThrow()
            let effectedSet = GetRawMangledNameSet(affected)
            for (member in effectedNodePatch) {
                effectedSet.add(member)
            }
            for (member in GetNoneStaticMemberVars(parentClass)) {
                if (!newMap.contains(member)) {
                    newMap[member] = HashSet<String>()
                }
                for (effected in effectedSet) {
                    newMap[member].add(effected)
                }
            }
            oldMap.remove(source)
        }
    }
}

// C++: CHIR/CHIR.cpp:168-186.
private func DropOutIllegalString(newMap: OptEffectStrMap): Unit {
    let sources = ArrayList<String>()
    for ((source, _) in newMap) {
        sources.add(source)
    }
    for (source in sources) {
        let affected = newMap.get(source) ?? continue
        let affectedNames = ArrayList<String>()
        for (name in affected) {
            affectedNames.add(name)
        }
        for (name in affectedNames) {
            if (name.isEmpty() || name == source || name == "$BOX") {
                affected.remove(name)
            }
        }
        if (source.isEmpty() || source == "$BOX" || affected.isEmpty()) {
            newMap.remove(source)
        }
    }
}

// C++: CHIR/CHIR.cpp:188-200.
private func UpdateEffectMapToString(oldMap: ChirOptEffectCHIRMap, newMap: OptEffectStrMap): Unit {
    try (recorder = ProfileRecorder("CHIR", "UpdateEffectMapToString")) {
        FlattenEffectMap(oldMap)
        UpdateOptEffectMapBecauseOfInit(oldMap, newMap)
        for ((source, affected) in oldMap) {
            let keyName = GetRawMangledName(source)
            if (!keyName.isEmpty()) {
                if (!newMap.contains(keyName)) {
                    newMap[keyName] = HashSet<String>()
                }
                for (name in GetRawMangledNameSet(affected)) {
                    newMap[keyName].add(name)
                }
            }
        }
        DropOutIllegalString(newMap)
    }
}

public func BuildRealCHIRForASTPackage(instance: CompilerInstance, pkg: RealASTPackage): Option<RealCHIRPackage> {
    let convertor = ToCHIR(instance, pkg)
    let result = convertor.Run()
    if (result.isSome()) {
        instance.chirInfo.optEffectMap.clear()
        for ((source, affected) in convertor.GetOptEffectMap()) {
            instance.chirInfo.optEffectMap[source] = affected
        }
        instance.chirInfo.curVirtFuncWrapDep.clear()
        for ((rawMangledName, wrapper) in convertor.GetCurVirtualFuncWrapperDepForIncr()) {
            instance.chirInfo.curVirtFuncWrapDep[rawMangledName] = wrapper
        }
        instance.chirInfo.delVirtFuncWrapForIncr.clear()
        for ((rawMangledName, wrapper) in convertor.GetDeleteVirtualFuncWrapperForIncr()) {
            instance.chirInfo.delVirtFuncWrapForIncr[rawMangledName] = wrapper
        }
        instance.chirInfo.ccOutFuncsRawMangle.clear()
        for (rawMangledName in convertor.GetCCOutFuncsRawMangle()) {
            instance.chirInfo.ccOutFuncsRawMangle.add(rawMangledName)
        }
    }
    return result
}

// C++: CHIR/CHIR.cpp:1037-1054.
private func EmitCHIR(outputPath: String, pkg: RealCHIRPackage, phase: ToCHIRPhase, dump: Bool): Unit {
    let path = if (FileUtil.IsDir(outputPath)) {
        FileUtil.JoinPath(outputPath, pkg.GetName() + CHIR_SERIALIZATION_FILE_EXTENSION)
    } else {
        outputPath
    }
    CHIRSerializer.Serialize(pkg, path, phase)
    if (dump) {
        let dumpFileName = FileUtil.GetFileNameWithoutExtension(path) +
            "_Emit_Debug" + CHIR_READABLE_FILE_EXTENSION
        ChirCHIRPrinter.PrintCHIRSerializeInfo(phase, dumpFileName)
        ChirCHIRPrinter.PrintPackage(pkg, dumpFileName)
    }
}

private class ToCHIR {
    private static var clearDumpDir: Bool = false

    private let instance: CompilerInstance
    private var pkg: Option<RealASTPackage>
    private let outputPath: String
    private let builder: ChirBuilder
    private let effectMap: ChirOptEffectCHIRMap = ChirOptEffectCHIRMap()
    private let strEffectMap: OptEffectStrMap = OptEffectStrMap()
    private let curVirtFuncWrapDep: VirtualWrapperDepMap = VirtualWrapperDepMap()
    private let delVirtFuncWrapForIncr: VirtualWrapperDepMap = VirtualWrapperDepMap()
    private let ccOutFuncsRawMangle: HashSet<String> = HashSet<String>()
    private var maybeUnreachable: HashMap<ChirBlock, ChirTerminator> = HashMap<ChirBlock, ChirTerminator>()
    private var chirPkg: Option<RealCHIRPackage> = None
    private var debugFileIndex: UInt64 = 0u64
    private var isComputingAnnos: Bool = false

    public init(instance: CompilerInstance, pkg: RealASTPackage) {
        this.instance = instance
        this.pkg = Some(pkg)
        this.outputPath = instance.invocation.globalOptions.output
        this.builder = ChirBuilder(instance.chirData.getOrThrow().GetRealCHIRContext())
    }

    public func Run(): Option<RealCHIRPackage> {
        let chirType = CHIRType(builder, CHIRTypeCache())
        let ast2chir = FaithfulAST2CHIR(builder, chirType, instance.GetSourceManager(),
            gim: instance.gim,
            importedPkgs: instance.importManager.getOrThrow().GetAllImportedPackages(),
            directImportedPkgs: instance.importManager.getOrThrow().GetCurImportedPackages(pkg.getOrThrow().fullPackageName),
            overrideSrcFuncResolver: Some({ funcDecl =>
                match (instance.faithfulSemaInstance) {
                    case Some(semaInstance) => semaInstance.typeManager.GetTopOverriddenFuncDecl(Some(funcDecl))
                    case None => None
                }
            }),
            opts: instance.invocation.globalOptions,
            kind: instance.kind,
            cachedInfo: instance.cachedInfo,
            curVirtFuncWrapDep: curVirtFuncWrapDep,
            delVirtFuncWrapForIncr: delVirtFuncWrapForIncr,
            chirWFC: instance.invocation.globalOptions.chirWFC,
            chirOptOverO2: instance.invocation.globalOptions.IsCHIROptimizationLevelOverO2(),
            diag: Some(instance.diag.AsBasicDiagnosticEngine()))
        if (!ast2chir.ToCHIRPackage(pkg.getOrThrow()) || instance.diag.GetErrorCount() != 0) {
            return None
        }
        let lowered = match (ast2chir.GetPackage()) {
            case Some(value) => value
            case None => return None
        }
        let srcCodeImportedFuncs = ast2chir.GetSrcCodeImportedFuncs()
        let srcCodeImportedVars = ast2chir.GetSrcCodeImportedVars()
        let initFuncsForConstVar = ast2chir.GetInitFuncsForConstVar()
        maybeUnreachable = ast2chir.GetMaybeUnreachableBlocks()
        chirPkg = Some(lowered)
        DumpCHIRToFile("AST_CHIR")
        ClearASTResources()
        // C++: CHIR/CHIR.cpp:1133-1140 ToCHIR::Run.
        if (instance.invocation.globalOptions.outputMode == OutputMode.CHIR) {
            let fileName = FileUtil.JoinPath(outputPath, lowered.GetName()) + CHIR_SERIALIZATION_FILE_EXTENSION
            CHIRSerializer.Serialize(lowered, fileName, ToCHIRPhase.RAW)
            return Some(lowered)
        }
        var pluginPackage = lowered
        if (!PerformPlugin(pluginPackage, srcCodeImportedFuncs, srcCodeImportedVars, initFuncsForConstVar)) {
            return None
        }
        pluginPackage = chirPkg.getOrThrow()
        DumpCHIRToFile("Canonicalization")
        if (instance.invocation.globalOptions.emitCHIRPhase == CandidateEmitCHIRPhase.RAW) {
            EmitCHIR(outputPath, pluginPackage, ToCHIRPhase.RAW,
                instance.invocation.globalOptions.NeedDumpCHIR())
            return Some(pluginPackage)
        }
        if (!RulesChecking(pluginPackage, builder, instance.invocation.globalOptions,
            instance.diag.AsBasicDiagnosticEngine(), effectMap, maybeUnreachable)) {
            return None
        }
        RunOptimizationPass(pluginPackage)
        let closure = ClosureConversion(builder, opts: instance.invocation.globalOptions,
            srcCodeImportedFuncs: srcCodeImportedFuncs)
        closure.RunOnPackage(pluginPackage)
        // C++: CHIR/CHIR.cpp:253-255.
        ccOutFuncsRawMangle.clear()
        for (rawMangledName in closure.GetCCOutFuncsRawMangle()) {
            ccOutFuncsRawMangle.add(rawMangledName)
        }
        // C++: CHIR/CHIR.cpp:255 ToCHIR::DoClosureConversion.
        DumpCHIRToFile("ClosureConversion")
        if (!RunConstantEvaluation(pluginPackage, builder, instance.diag.AsBasicDiagnosticEngine(),
            instance.invocation.globalOptions, initFuncsForConstVar)) {
            return None
        }
        ReplaceSrcCodeImportedVal(pluginPackage).Run(srcCodeImportedFuncs, srcCodeImportedVars,
            closure.GetUselessClassDef(), closure.GetUselessLambda())
        // C++: CHIR/CHIR.cpp:1178-1181.
        if (!AnnotationChecker(pluginPackage, instance.diag.AsBasicDiagnosticEngine()).Run()) {
            return None
        }
        // C++: CHIR/CHIR.cpp:1183.
        RunSanitizerCoverage()
        if (instance.invocation.globalOptions.enIncrementalCompilation) {
            UpdateEffectMapToString(effectMap, strEffectMap)
        }
        EraseDebugExpr()
        CFFIFuncWrapper()
        if (instance.invocation.globalOptions.NeedDumpCHIRToScreen()) {
            ChirCHIRPrinter.PrintPackage(pluginPackage)
        }
        if (instance.invocation.globalOptions.emitCHIRPhase == CandidateEmitCHIRPhase.OPT) {
            EmitCHIR(outputPath, pluginPackage, ToCHIRPhase.OPT,
                instance.invocation.globalOptions.NeedDumpCHIR())
        } else if (instance.invocation.globalOptions.saveTemps) {
            let tempFileInfo = TempFileManager.Instance().CreateNewFileInfo(
                TempFileInfo(fileName: pluginPackage.GetName()), TempFileKind.O_CHIR)
            CHIRSerializer.Serialize(pluginPackage, tempFileInfo.filePath, ToCHIRPhase.OPT)
        }
        builder.MergeAllocatedInstance()
        return Some(pluginPackage)
    }

    // C++: CHIR/CHIR.cpp:1254-1279 ToCHIR::PerformPlugin.
    private func PerformPlugin(
        currentPackage: RealCHIRPackage,
        srcCodeImportedFuncs: ArrayList<ChirFunction>,
        srcCodeImportedVars: ArrayList<ChirGlobalVar>,
        initFuncsForConstVar: ArrayList<ChirFunction>
    ): Bool {
        if (instance.invocation.globalOptions.pluginPaths.isEmpty()) {
            return true
        }
        try (recorder = ProfileRecorder("CHIR", "PerformPlugin")) {
            var succeed = true
            try {
                if (instance.metaTransformPluginBuilder.IsCppPlugin()) {
                    succeed = TryRunCHIRMetaTransforms(instance.metaTransformPluginBuilder, builder, currentPackage)
                } else {
                    succeed = ExecuteCjPlugins(currentPackage, srcCodeImportedFuncs, srcCodeImportedVars,
                        initFuncsForConstVar)
                }
            } catch (e: Exception) {
                succeed = false
            }
            if (!succeed) {
                instance.diag.DiagnoseRefactor(DiagKindRefactor.plugin_throws_exception, DEFAULT_POSITION)
            } else {
                DumpCHIRToFile("PLUGIN")
            }
            return succeed
        }
    }

    // C++: CHIR/CHIR.cpp:1225-1251 ToCHIR::ExecuteCjPlugins.
    private func ExecuteCjPlugins(
        currentPackage: RealCHIRPackage,
        srcCodeImportedFuncs: ArrayList<ChirFunction>,
        srcCodeImportedVars: ArrayList<ChirGlobalVar>,
        initFuncsForConstVar: ArrayList<ChirFunction>
    ): Bool {
        let executePlugin = ExecutePlugin(builder)
        if (!executePlugin.SerializePackage(currentPackage)) {
            return false
        }
        if (!executePlugin.Execute(instance.invocation.globalOptions.pluginPaths[0])) {
            return false
        }
        if (let Some(newPackage) <- executePlugin.DeserializePluginResult(
            srcCodeImportedFuncs, srcCodeImportedVars, initFuncsForConstVar, maybeUnreachable)) {
            chirPkg = Some(newPackage)
        } else {
            return false
        }
        return executePlugin.FreeCachedData()
    }

    // C++: CHIR/CHIR.cpp:1376-1391 ToCHIR::ClearASTResources.
    private func ClearASTResources(): Unit {
        if (instance.invocation.globalOptions.outputMode == OutputMode.CHIR) {
            return
        }
        if (instance.isCJLint) {
            return
        }
        // C++ CHIR.cpp:1381-1384 delays clearing when multiple packages share the compiler instance.
        // Selfhost supports that mode directly, so clear after the final package conversion instead.
        if (instance.realASTPkgs.size > 1) {
            return
        }
        try (recorder = ProfileRecorder("AST to CHIR Translation", "ClearASTResources")) {
            pkg = None
            instance.DestroyASTResources()
        }
    }

    public func GetOptEffectMap(): OptEffectStrMap {
        return strEffectMap
    }

    public func GetCurVirtualFuncWrapperDepForIncr(): VirtualWrapperDepMap {
        return curVirtFuncWrapDep
    }

    public func GetDeleteVirtualFuncWrapperForIncr(): VirtualWrapperDepMap {
        return delVirtFuncWrapForIncr
    }

    public func GetCCOutFuncsRawMangle(): HashSet<String> {
        return ccOutFuncsRawMangle
    }

    // C++: CHIR/CHIR.cpp:589-598 ToCHIR::RunSanitizerCoverage.
    private func RunSanitizerCoverage(): Unit {
        let opts = instance.invocation.globalOptions
        if (!opts.IsSancovOptionEnabled()) {
            return
        }
        try (recorder = ProfileRecorder("CHIR", "Sanitizer Coverage")) {
            let sanCovOpt = SanitizerCoverage(opts, builder)
            let _ = sanCovOpt.RunOnPackage(chirPkg.getOrThrow(), instance.diag.AsBasicDiagnosticEngine(),
                opts.chirDebugOptimizer)
            DumpCHIRToFile("Sanitizer_Coverage")
        }
    }

    private func DumpCHIRToFile(suffix: String, needCheckFlag!: Bool = true): Unit {
        let opts = instance.invocation.globalOptions
        if (needCheckFlag && !opts.NeedDumpCHIRToFile()) {
            return
        }
        CJC_ASSERT(chirPkg.isSome())
        let currentPackage = chirPkg.getOrThrow()
        CJC_ASSERT(!CHIR_READABLE_FILE_EXTENSION.isEmpty())
        let extension = if (CHIR_READABLE_FILE_EXTENSION[0] == b'.') {
            CHIR_READABLE_FILE_EXTENSION[1..]
        } else {
            CHIR_READABLE_FILE_EXTENSION
        }
        if (!opts.computeAnnotationsDebug && isComputingAnnos) {
            return
        }
        var fileName = debugFileIndex.toString() + "_"
        debugFileIndex++
        if (isComputingAnnos) {
            fileName += "ComputeAnnotations_"
        }
        fileName += suffix + "." + extension
        let debugDir = if (FileUtil.IsDir(outputPath)) {
            FileUtil.JoinPath(outputPath, currentPackage.GetName() + "_CHIR")
        } else {
            FileUtil.GetFileBase(outputPath) + "_CHIR"
        }
        if (!ToCHIR.clearDumpDir) {
            if (FileUtil.FileExist(debugDir)) {
                FileUtil.RemoveDirectoryRecursively(debugDir)
            }
            ToCHIR.clearDumpDir = true
        }
        let fullPath = FileUtil.JoinPath(debugDir, fileName)
        if (!FileUtil.FileExist(fullPath)) {
            FileUtil.CreateDirs(fullPath)
        }
        ChirCHIRPrinter.PrintPackage(currentPackage, fullPath)
        if (suffix == "Broken_CHIR") {
            println("broken chir dump to file: " + fullPath)
        }
    }

    // C++ CHIR.cpp:416-427.
    private func RunArrayListConstStartOpt(currentPackage: RealCHIRPackage): Unit {
        let options = instance.invocation.globalOptions
        if (!options.IsCHIROptimizationLevelOverO2()) {
            return
        }
        try (recorder = ProfileRecorder("CHIR Opt", "ArrayListOpt")) {
            let functionInline = FunctionInline(builder, options.optimizationLevel, options.chirDebugOptimizer)
            let pass = ArrayListConstStartOpt(builder, options, functionInline)
            pass.RunOnPackage(currentPackage)
            MergeEffectMap(pass.GetEffectMap(), effectMap)
            DumpCHIRToFile("RunArrayListConstStartOpt")
        }
    }

    private func RunOptimizationPass(currentPackage: RealCHIRPackage): Unit {
        try (recorder = ProfileRecorder("CHIR", "CHIR Opt")) {
            let options = instance.invocation.globalOptions
            OptFuncRetType(currentPackage, builder).Unit2Void()
            RunArrayListConstStartOpt(currentPackage)
            if (options.IsCHIROptimizationLevelOverO2()) {
                UnitUnify(builder).RunOnPackage(currentPackage, isDebug: options.chirDebugOptimizer)
            }
            let devirtInfo = CollectDevirtualizationInfo(currentPackage)
            if (options.cjcjOptimization) {
                // The cjcj-only round runs after FaithfulAST2CHIR has materialized generic instances and before
                // FunctionInline can consume them. It reuses the official Devirtualization pipeline below.
                Devirtualization(currentPackage, devirtInfo, instantiatedOnly: true, inlineFrozen: false)
            }
            RunFunctionInline(currentPackage, devirtInfo)
            if (options.IsOptimizationExisted(OptimizationFlag.REDUNDANT_LOAD)) {
                RedundantLoadElimination().RunOnPackage(currentPackage, isDebug: options.chirDebugOptimizer)
            }
            if (options.enableChirRGetOrThrowE) {
                RedundantGetOrThrowElimination().RunOnPackage(currentPackage, isDebug: options.chirDebugOptimizer)
            }
            RunRangePropagation(currentPackage)
            if (options.IsCHIROptimizationLevelOverO2()) {
                UselessAllocateElimination.RunOnPackage(currentPackage, isDebug: options.chirDebugOptimizer)
            }
            Devirtualization(currentPackage, devirtInfo)
            RunArrayLambdaOpt(currentPackage)
            if (options.IsOptimizationExisted(OptimizationFlag.REDUNDANT_FUTURE)) {
                RedundantFutureRemoval(currentPackage, isDebug: options.chirDebugOptimizer).RunOnPackage()
            }
            if (options.IsCHIROptimizationLevelOverO2() && !options.interpFullBchir) {
                GetRefToArrayElem.RunOnPackage(currentPackage, builder)
            }
        }
    }

    private func RunArrayLambdaOpt(currentPackage: RealCHIRPackage): Unit {
        let options = instance.invocation.globalOptions
        if (!options.IsOptimizationExisted(OptimizationFlag.ARRAY_LAMBDA_OPT)) {
            return
        }
        try (recorder = ProfileRecorder("CHIR Opt", "ArrayLambdaOpt")) {
            ArrayLambdaOpt(builder).RunOnPackage(currentPackage, options.chirDebugOptimizer)
            DumpCHIRToFile("ArrayLambdaOpt")
        }
    }

    // C++ CHIR.cpp:349-386.
    private func Devirtualization(currentPackage: RealCHIRPackage, devirtInfo: DevirtualizationInfo,
        instantiatedOnly!: Bool = false, inlineFrozen!: Bool = true): Unit {
        let options = instance.invocation.globalOptions
        if (!options.IsOptimizationExisted(OptimizationFlag.DEVIRTUALIZATION) ||
            options.enIncrementalCompilation) {
            return
        }
        try (recorder = ProfileRecorder("CHIR Opt", "Devirtualization")) {
            devirtInfo.FreshRetMap()
            devirtInfo.CollectConstMemberVarType()
            let funcs = ArrayList<ChirFunction>()
            for (fn in ChirDevirtualization.CollectContainInvokeExprFuncs(currentPackage)) {
                let parentInstantiated = if (let Some(parent) <- fn.GetParentCustomTypeDef()) {
                    parent.TestAttr(ChirAttribute.GENERIC_INSTANTIATED)
                } else {
                    false
                }
                if (!instantiatedOnly || fn.TestAttr(ChirAttribute.GENERIC_INSTANTIATED) || parentInstantiated) {
                    funcs.add(fn)
                }
            }
            if (funcs.isEmpty()) {
                return
            }
            let threadNum = Int64(options.GetJobs())
            TypeValue.SetCHIRBuilder(builder)
            let typeAnalysisWrapper = AnalysisWrapper<TypeAnalysis, TypeDomain>(builder,
                { analysisPackage: RealCHIRPackage, analysisBuilder: ChirBuilder =>
                    TypeAnalysis.InitialiseLetGVState(analysisPackage, analysisBuilder, typeAnalysisGlobals,
                        { globalVar => TypeAnalysis.IsTrackedGV(globalVar) })
                })
            let devirt = ChirDevirtualization(typeAnalysisWrapper, devirtInfo)
            if (instantiatedOnly) {
                TypeAnalysis.InitialiseLetGVState(currentPackage, builder, typeAnalysisGlobals,
                    { globalVar => TypeAnalysis.IsTrackedGV(globalVar) })
                for (fn in funcs) {
                    let result = typeAnalysisWrapper.RunOnFunc(fn, options.chirDebugOptimizer,
                        { instantiatedFn: ChirFunction, analysisBuilder: ChirBuilder, isDebug: Bool =>
                            TypeAnalysis(instantiatedFn, analysisBuilder, isDebug, devirtInfo)
                        })
                    devirt.AppendFrozenFuncState(fn, result)
                }
            } else {
                typeAnalysisWrapper.RunOnPackage(currentPackage, options.chirDebugOptimizer, threadNum,
                    { fn: ChirFunction, analysisBuilder: ChirBuilder, isDebug: Bool =>
                        TypeAnalysis(fn, analysisBuilder, isDebug, devirtInfo)
                    })
            }
            devirt.RunOnFuncs(funcs, builder, options.chirDebugOptimizer)
            if (!devirt.GetFrozenInstFuns().isEmpty()) {
                let frozenFuncs = devirt.GetFrozenInstFuns()
                for (fn in frozenFuncs) {
                    let result = typeAnalysisWrapper.RunOnFunc(fn, options.chirDebugOptimizer,
                        { frozenFn: ChirFunction, analysisBuilder: ChirBuilder, isDebug: Bool =>
                            TypeAnalysis(frozenFn, analysisBuilder, isDebug, devirtInfo)
                        })
                    devirt.AppendFrozenFuncState(fn, result)
                }
                devirt.RunOnFuncs(frozenFuncs, builder, options.chirDebugOptimizer)
                if (inlineFrozen) {
                    let pass = FunctionInline(builder, options.optimizationLevel, options.chirDebugOptimizer)
                    for (fn in frozenFuncs) {
                        pass.Run(fn)
                    }
                }
            }
            DumpCHIRToFile("Devirtualization")
        }
    }

    // C++ CHIR.h:80-96.
    private func ConstructSubBuilders(threadNum: Int64, funcNum: Int64): ArrayList<ChirBuilder> {
        let results = ArrayList<TaskResult<ChirBuilder>>()
        let builderTaskQueue = TaskQueue(threadNum)
        var index: Int64 = 0
        while (index < funcNum) {
            let builderIndex = index
            results.add(builderTaskQueue.AddTask<ChirBuilder>({ =>
                ChirBuilder(builder.context, threadIdx: builderIndex)
            }))
            index++
        }
        builderTaskQueue.RunAndWaitForAllTasksCompleted()
        let builderList = ArrayList<ChirBuilder>()
        for (result in results) {
            builderList.add(result.get())
        }
        return builderList
    }

    // C++ CHIR.cpp:525-570.
    private func RunRangePropagation(currentPackage: RealCHIRPackage): Unit {
        let options = instance.invocation.globalOptions
        if (!options.IsCHIROptimizationLevelOverO2()) {
            return
        }
        try (recorder = ProfileRecorder("CHIR Opt", "Range Propagation")) {
            let rangeAnalysisWrapper = AnalysisWrapper<RangeAnalysis, RangeDomain>(builder,
                { analysisPackage: RealCHIRPackage, analysisBuilder: ChirBuilder =>
                    RangeAnalysis.InitialiseLetGVState(analysisPackage, analysisBuilder, rangeStateGlobals,
                        { globalVar => IsTrackedGVForRangeAnalysis(globalVar) })
                })
            let threadNum = Int64(options.GetJobs())
            rangeAnalysisWrapper.RunOnPackage(currentPackage, options.chirDebugOptimizer, threadNum,
                { funcValue: ChirFunction, analysisBuilder: ChirBuilder, isDebug: Bool =>
                    RangeAnalysis(funcValue, analysisBuilder, instance.diag.AsBasicDiagnosticEngine(),
                        isDebug: isDebug)
                })
            let dce = DeadCodeElimination(builder, instance.diag.AsBasicDiagnosticEngine(), currentPackage)
            if (threadNum == 1) {
                let rangePropagation = RangePropagation(builder, rangeAnalysisWrapper,
                    instance.diag.AsBasicDiagnosticEngine(), options.enIncrementalCompilation)
                rangePropagation.RunOnPackage(currentPackage, options.chirDebugOptimizer)
                MergeEffectMap(rangePropagation.GetEffectMap(), effectMap)
                dce.UnreachableBlockElimination(rangePropagation.GetFuncsNeedRemoveBlocks(),
                    isDebug: options.chirDebugOptimizer)
            } else {
                let globalFuncs = currentPackage.GetGlobalFuncsWithBody()
                let funcNum = globalFuncs.size
                let builderList = ConstructSubBuilders(threadNum, funcNum)
                let taskQueue = TaskQueue(threadNum)
                let propagationList = ArrayList<RangePropagation>()
                var index: Int64 = 0
                while (index < funcNum) {
                    let funcValue = globalFuncs[index]
                    let rangePropagation = RangePropagation(builderList[index], rangeAnalysisWrapper,
                        instance.diag.AsBasicDiagnosticEngine(), options.enIncrementalCompilation)
                    let _ = taskQueue.AddTask<Unit>({ =>
                        rangePropagation.RunOnFunc(funcValue, options.chirDebugOptimizer)
                    })
                    propagationList.add(rangePropagation)
                    index++
                }
                taskQueue.RunAndWaitForAllTasksCompleted()
                for (rangePropagation in propagationList) {
                    MergeEffectMap(rangePropagation.GetEffectMap(), effectMap)
                    dce.UnreachableBlockElimination(rangePropagation.GetFuncsNeedRemoveBlocks(),
                        isDebug: options.chirDebugOptimizer)
                }
                for (subBuilder in builderList) {
                    subBuilder.MergeAllocatedInstance()
                }
                builder.context.MergeTypes()
            }
            DumpCHIRToFile("RangePropagation")
        }
        RunMergingBlocks(currentPackage, "CHIR Opt", "MergingBlockAfterRangeAnalysis")
    }

    private func CollectDevirtualizationInfo(currentPackage: RealCHIRPackage): DevirtualizationInfo {
        var result: Option<DevirtualizationInfo> = None
        try (recorder = ProfileRecorder("CHIR Opt", "Collect Devirt Info")) {
            let options = instance.invocation.globalOptions
            let devirtInfo = DevirtualizationInfo(currentPackage, options)
            if (options.IsOptimizationExisted(OptimizationFlag.FUNC_INLINING) ||
                (options.IsOptimizationExisted(OptimizationFlag.DEVIRTUALIZATION) &&
                    !options.enIncrementalCompilation)) {
                devirtInfo.CollectInfo()
            }
            result = devirtInfo
        }
        return result.getOrThrow()
    }

    private func RunFunctionInline(currentPackage: RealCHIRPackage, devirtInfo: DevirtualizationInfo): Unit {
        let options = instance.invocation.globalOptions
        if (!options.IsOptimizationExisted(OptimizationFlag.FUNC_INLINING)) {
            return
        }
        try (recorder = ProfileRecorder("CHIR Opt", "FunctionInline")) {
            let callGraphAnalysis = CallGraphAnalysis(currentPackage, devirtInfo)
            callGraphAnalysis.DoCallGraphAnalysis(options.chirDebugOptimizer)
            let pass = FunctionInline(builder, options.optimizationLevel, options.chirDebugOptimizer)
            for (functionOption in callGraphAnalysis.postOrderSCCFunctionlist) {
                if (let Some(fn) <- functionOption) {
                    if (fn.GetSrcCodeIdentifier() == "$toAny" ||
                        fn.GetFuncKind() == ChirFuncKind.ANNOFACTORY_FUNC) {
                        continue
                    }
                    pass.Run(fn)
                }
            }
            MergeEffectMap(pass.GetEffectMap(), effectMap)
            DumpCHIRToFile("FunctionInline")
        }
        RunMergingBlocks(currentPackage, "CHIR Opt", "MergingBlockAfterInline")
        UselessFuncElimination(currentPackage, "CHIR Opt")
    }

    private func RunMergingBlocks(currentPackage: RealCHIRPackage, firstName: String, secondName: String): Unit {
        try (recorder = ProfileRecorder(firstName, secondName)) {
            let options = instance.invocation.globalOptions
            MergeBlocks().RunOnPackage(currentPackage, builder, enableCompileDebug: options.enableCompileDebug,
                enableCoverage: options.enableCoverage)
            DumpCHIRToFile(secondName)
        }
    }

    private func UselessFuncElimination(currentPackage: RealCHIRPackage, passName: String): Unit {
        let options = instance.invocation.globalOptions
        if (!options.IsCHIROptimizationLevelOverO2() || options.enableCoverage ||
            options.enIncrementalCompilation || currentPackage.GetName() == REFLECT_PACKAGE_NAME) {
            return
        }
        try (recorder = ProfileRecorder(passName, "UselessFuncElimination")) {
            DeadCodeElimination(builder, instance.diag.AsBasicDiagnosticEngine(), currentPackage)
                .UselessFuncElimination(currentPackage, options)
            DumpCHIRToFile("UselessFuncElimination")
        }
    }

    private func EraseDebugExpr(): Unit {
        try (recorder = ProfileRecorder("CHIR", "EraseUselessDebugExpr")) {
            for (`func` in chirPkg.getOrThrow().GetGlobalFuncsWithBody()) {
                for (block in `func`.GetBody().getOrThrow().GetBlocks()) {
                    for (expr in block.GetExpressions()) {
                        if (expr.GetExprKind() == ChirExprKind.DEBUGEXPR &&
                            (expr.GetOperand(0).IsGlobal() || expr.GetOperand(0).IsCompileTimeValue())) {
                            expr.RemoveSelfFromBlock()
                        }
                    }
                }
            }
            DumpCHIRToFile("EraseUselessDebugExpr")
        }
    }

    private func CFFIFuncWrapper(): Unit {
        try (recorder = ProfileRecorder("CHIR", "CFFIFuncWrapper")) {
            let currentPackage = chirPkg.getOrThrow()
            let cfuncs = ArrayList<ChirFunction>()
            let foreignFuncs = ArrayList<ChirFunction>()
            for (curFunc in currentPackage.GetGlobalFuncsWithBody()) {
                if (curFunc.GetType().getOrThrow().IsCFunc()) {
                    cfuncs.add(curFunc)
                }
            }
            for (foreignFunc in currentPackage.GetGlobalFuncsWithoutBody()) {
                if (foreignFunc.GetType().getOrThrow().IsCFunc()) {
                    CJC_ASSERT(foreignFunc.IsImportedFunc())
                    foreignFuncs.add(foreignFunc)
                }
            }
            for (curFunc in cfuncs) {
                if (curFunc.GetLinkTypeInfo() != BasicLinkage.EXTERNAL) {
                    if (!IsAllApply(curFunc)) {
                        let (wrapperFunc, res) = DoCFFIFuncWrapper(curFunc, false, isExternal: false)
                        ReplaceUsesWithWrapper(curFunc, res, wrapperFunc)
                    }
                    continue
                }
                let (wrapperFunc, res) = DoCFFIFuncWrapper(curFunc, false)
                if (!IsAllApply(curFunc)) {
                    ReplaceUsesWithWrapper(curFunc, res, wrapperFunc)
                }
            }
            for (curFunc in foreignFuncs) {
                if (curFunc.GetLinkTypeInfo() != BasicLinkage.EXTERNAL) {
                    continue
                }
                let isForeign = curFunc.TestAttr(ChirAttribute.FOREIGN)
                let (wrapperFunc, res) = DoCFFIFuncWrapper(curFunc, isForeign)
                let funcPkgName = if (curFunc.GetPackageName().isEmpty()) {
                    currentPackage.GetName()
                } else {
                    curFunc.GetPackageName()
                }
                if (funcPkgName != currentPackage.GetName()) {
                    ReplaceUsesWithWrapper(curFunc, res, wrapperFunc, isForeign: true)
                }
            }
            DumpCHIRToFile("CFFIFuncWrapper")
        }
    }
    private func DoCFFIFuncWrapper(curFunc: ChirFunction, isForeign: Bool,
        isExternal!: Bool = true): (ChirValue, Option<ChirApply>) {
        let currentPackage = chirPkg.getOrThrow()
        var ident = curFunc.GetSrcCodeIdentifier()
        if (curFunc.IsLambda()) {
            ident = curFunc.GetIdentifierWithoutPrefix()
            if (let Some(pos) <- ident.indexOf(CFFI_FUNC_SUFFIX)) {
                ident = ident[0..pos] + ident[pos + CFFI_FUNC_SUFFIX.size..]
            }
        }
        let funcPkgName = if (curFunc.GetPackageName().isEmpty()) {
            currentPackage.GetName()
        } else {
            curFunc.GetPackageName()
        }
        if (isForeign || (curFunc.TestAttr(ChirAttribute.PRIVATE) && isExternal)) {
            ident = funcPkgName + ":" + ident
        }
        if (funcPkgName != currentPackage.GetName()) {
            let wrapperFunc = builder.CreateFunction(curFunc.GetFuncType().getOrThrow(), ident,
                srcCodeIdentifier: ident, rawMangledName: "", packageName: funcPkgName,
                genericTypeParams: curFunc.GetGenericTypeParams())
            wrapperFunc.EnableAttr(ChirAttribute.IMPORTED)
            wrapperFunc.SetCFFIWrapper(true)
            return (wrapperFunc, None)
        }
        let wrapperFunc = builder.CreateFunction(curFunc.GetFuncType().getOrThrow(), ident,
            srcCodeIdentifier: ident, rawMangledName: "", packageName: funcPkgName)
        wrapperFunc.SetDebugLocation(curFunc.GetDebugLocation())
        wrapperFunc.SetFuncKind(curFunc.GetFuncKind())
        if (wrapperFunc.IsLambda()) {
            let originalLambdaInfo = ChirFuncSigInfo(curFunc.GetOriginalLambdaType().getOrThrow(),
                funcName: curFunc.GetSrcCodeIdentifier(), genericTypeParams: curFunc.GetGenericTypeParams())
            wrapperFunc.SetOriginalLambdaInfo(originalLambdaInfo)
        }
        let body = builder.CreateBlockGroup(wrapperFunc)
        wrapperFunc.SetCFFIWrapper(true)
        curFunc.EnableAttr(ChirAttribute.NO_INLINE)
        curFunc.SetLinkTypeInfo(BasicLinkage.INTERNAL)
        wrapperFunc.InitBody(body)
        wrapperFunc.EnableAttr(ChirAttribute.COMPILER_ADD)
        let linkage = if (isExternal) { BasicLinkage.EXTERNAL } else { BasicLinkage.INTERNAL }
        wrapperFunc.SetLinkTypeInfo(linkage)
        let args = ArrayList<ChirValue>()
        let curFuncType = curFunc.GetFuncType().getOrThrow()
        for (paramTy in curFuncType.GetParamTypes()) {
            builder.CreateParameter(paramTy, CHIR_INVALID_LOCATION, wrapperFunc)
        }
        for (item in wrapperFunc.GetParams()) {
            args.add(item)
        }
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let retType = curFunc.GetReturnType().getOrThrow()
        let res = builder.CreateApply(retType, curFunc, ChirFuncCallContext(args: args), entry)
        res.SetDebugLocation(curFunc.GetDebugLocation())
        let retAlloc = builder.CreateAllocate(builder.context.GetRefTy(retType), retType, entry)
        retAlloc.SetDebugLocation(ChirDebugLocation())
        wrapperFunc.SetReturnValue(retAlloc.GetResult().getOrThrow())
        builder.CreateStore(res.GetResult().getOrThrow(), retAlloc.GetResult().getOrThrow(), entry)
        builder.CreateExit(None, entry)
        return (wrapperFunc, Some(res))
    }

    private func IsAllApply(curFunc: ChirFunction): Bool {
        let users = curFunc.GetUsers()
        var index: Int64 = 0
        while (index < users.size) {
            if (users[index].GetExprKind() != ChirExprKind.APPLY &&
                users[index].GetExprKind() != ChirExprKind.APPLY_WITH_EXCEPTION) {
                return false
            }
            if (users[index].GetExprKind() == ChirExprKind.APPLY) {
                let applyNode = (users[index] as ChirApply).getOrThrow()
                if (!refEq(applyNode.GetCallee(), curFunc)) {
                    return false
                }
            }
            if (users[index].GetExprKind() == ChirExprKind.APPLY_WITH_EXCEPTION) {
                let applyNode = (users[index] as ChirApplyWithException).getOrThrow()
                if (!refEq(applyNode.GetCallee(), curFunc)) {
                    return false
                }
            }
            index++
        }
        return true
    }
}

private func RulesChecking(pkg: RealCHIRPackage, builder: ChirBuilder, options: GlobalOptions,
    diag: BasicDiagnosticEngine, effectMap: ChirOptEffectCHIRMap,
    maybeUnreachable: HashMap<ChirBlock, ChirTerminator>): Bool {
    DeadCodeElimination(builder, diag, pkg).UnreachableBlockWarningReporter(pkg,
        Int64(options.GetJobs()), maybeUnreachable)
    DeadCodeElimination(builder).ClearUnreachableMarkBlock(pkg)
    MergeBlocks().RunOnPackage(pkg, builder, enableCompileDebug: options.enableCompileDebug,
        enableCoverage: options.enableCoverage)
    DeadCodeElimination(builder).NothingTypeExprElimination(pkg, isDebug: options.chirDebugOptimizer)
    let wrapper = ConstAnalysisWrapper(builder)
    // C++ CHIR.cpp:475-480 ToCHIR::RunConstantAnalysis.
    wrapper.RunOnPackage(pkg, diag, Int64(options.GetJobs()), isDebug: options.chirDebugOptimizer)
    if (!RunVarInitChecking(pkg, diag, options.GetJobs())) {
        return false
    }
    UnreachableBranchCheck(wrapper, diag, pkg.GetName()).RunOnPackage(pkg, Int64(options.GetJobs()))
    DeadCodeElimination(builder).UnreachableBlockEliminationForPackage(pkg, isDebug: options.chirDebugOptimizer)
    MergeBlocks().RunOnPackage(pkg, builder, enableCompileDebug: options.enableCompileDebug,
        enableCoverage: options.enableCoverage)
    if (ShouldReportUnusedCodeWarnings()) {
        DeadCodeElimination(builder, diag, pkg).ReportUnusedCode(pkg, options)
    }
    if (options.IsCHIROptimizationLevelOverO2() && !options.enableCoverage &&
        !options.enIncrementalCompilation && pkg.GetName() != REFLECT_PACKAGE_NAME) {
        DeadCodeElimination(builder, diag, pkg).UselessFuncElimination(pkg, options)
    }
    if (options.IsCHIROptimizationLevelOverO2()) {
        DeadCodeElimination(builder).RunOnPackage(pkg)
    }
    RunConstantPropagation(pkg, builder, options, wrapper, effectMap)
    return diag.GetErrorCount() == 0
}

// C++ CHIR.h:80-96 ToCHIR::ConstructSubBuilders.
private func ConstructSubBuilders(builder: ChirBuilder, threadNum: Int64,
    funcNum: Int64): ArrayList<ChirBuilder> {
    let results = ArrayList<TaskResult<ChirBuilder>>()
    let builderTaskQueue = TaskQueue(threadNum)
    var index: Int64 = 0
    while (index < funcNum) {
        let builderIndex = index
        results.add(builderTaskQueue.AddTask<ChirBuilder>({ =>
            ChirBuilder(builder.context, threadIdx: builderIndex)
        }))
        index++
    }
    builderTaskQueue.RunAndWaitForAllTasksCompleted()
    let builderList = ArrayList<ChirBuilder>()
    for (result in results) {
        builderList.add(result.get())
    }
    return builderList
}

// C++ CHIR.cpp:481-519 ToCHIR::RunConstantPropagation.
private func RunConstantPropagation(pkg: RealCHIRPackage, builder: ChirBuilder, options: GlobalOptions,
    wrapper: ConstAnalysisWrapper, effectMap: ChirOptEffectCHIRMap): Unit {
    let threadNum = Int64(options.GetJobs())
    let dce = DeadCodeElimination(builder)
    if (threadNum == 1) {
        let cp = ConstPropagation(builder: Some(builder), wrapper: wrapper, opts: options)
        MergeEffectMap(cp.GetEffectMap(), effectMap)
        cp.RunOnPackage(pkg, isDebug: options.chirDebugOptimizer, isCJLint: false)
        dce.UnreachableBlockElimination(cp.GetFuncsNeedRemoveBlocks(),
            isDebug: options.chirDebugOptimizer)
    } else {
        let globalFuncs = pkg.GetGlobalFuncsWithBody()
        let funcNum = globalFuncs.size
        let builderList = ConstructSubBuilders(builder, threadNum, funcNum)
        let taskQueue = TaskQueue(threadNum)
        let cpList = ArrayList<ConstPropagation>()
        var index: Int64 = 0
        while (index < funcNum) {
            let funcValue = globalFuncs[index]
            let cp = ConstPropagation(builder: Some(builderList[index]), wrapper: wrapper, opts: options)
            let _ = taskQueue.AddTask<Unit>({ =>
                cp.RunOnFunc(funcValue, isDebug: options.chirDebugOptimizer, isCJLint: false)
            })
            cpList.add(cp)
            index++
        }
        taskQueue.RunAndWaitForAllTasksCompleted()
        for (cp in cpList) {
            MergeEffectMap(cp.GetEffectMap(), effectMap)
            dce.UnreachableBlockElimination(cp.GetFuncsNeedRemoveBlocks(),
                isDebug: options.chirDebugOptimizer)
        }
        for (subBuilder in builderList) {
            subBuilder.MergeAllocatedInstance()
        }
        builder.context.MergeTypes()
    }
}

private func RunVarInitChecking(pkg: RealCHIRPackage, diag: BasicDiagnosticEngine, jobs: UInt64): Bool {
    let vic = VarInitCheck(diag)
    let _ = vic.RunOnPackage(pkg, threadNum: Int64(jobs))
    return diag.GetErrorCount() == 0
}

private func RunConstantEvaluation(pkg: RealCHIRPackage, builder: ChirBuilder, diag: BasicDiagnosticEngine,
    options: GlobalOptions, initFuncsForConstVar: ArrayList<ChirFunction>): Bool {
    if (!options.IsConstEvalEnabled() || options.enIncrementalCompilation || !options.commonPartCjos.isEmpty()) {
        return true
    }
    let bchirPackages = ArrayList<BCHIR>()
    ConstEvalPass(builder, diag, opts: options).RunOnPackage(pkg, initFuncsForConstVar, bchirPackages)
    return true
}

public func GenPackageModules(instance: CompilerInstance, enableIncrement: Bool,
    cachedMangleMap: CachedMangleMap): ArrayList<LLVMModuleHandle> {
    let llvmModules = ArrayList<LLVMModuleHandle>()
    if (instance.diag.GetErrorCount() != 0) {
        return llvmModules
    }
    let currentRealPackage = instance.chirData.getOrThrow().GetCurrentRealCHIRPackage()
    if (let None <- currentRealPackage) {
        return llvmModules
    }
    let realPackage = currentRealPackage.getOrThrow()
    let codegenOptions = ConvertFrontendOptionsToCodegenOptions(instance.invocation.globalOptions)
    instance.invocation.globalOptions.UpdateCachedDirName(realPackage.GetName())
    let codegenData = CodegenCHIRData(instance.chirData.getOrThrow().GetRealCHIRContext(), realPackage)
    let noHeapAllocChecker = NoHeapAllocChecker(instance.diag.AsBasicDiagnosticEngine())
    noHeapAllocChecker.RunOnPackage(realPackage)
    let noWriteBarrierRecChecker = NoWriteBarrierRecChecker(instance.diag.AsBasicDiagnosticEngine())
    noWriteBarrierRecChecker.RunOnPackage(realPackage)
    let packageModules = CodegenGenPackageModules(codegenData, codegenOptions, enableIncrement,
        noHeapAllocChecker, noWriteBarrierRecChecker, cachedMangleMap: cachedMangleMap)
    if (instance.diag.GetErrorCount() != 0) {
        instance.diag.EmitCategoryDiagnostics(DiagCategory.CHIR)
        ClearPackageModules(packageModules)
        return llvmModules
    }
    return packageModules
}

// C++: FrontendTool/DefaultCompilerInstance.cpp:252-299.
public func EmitLLVMSimilarBytecode(instance: CompilerInstance, enableIncrement: Bool,
    cachedMangleMap: CachedMangleMap): Bool {
    let curPackage = instance.chirData.getOrThrow().GetCurrentRealCHIRPackage()
    if (let None <- curPackage) {
        return true
    }
    let fullPackageName = curPackage.getOrThrow().GetName()
    let llvmModules = GenPackageModules(instance, enableIncrement, cachedMangleMap)
    if (instance.diag.GetErrorCount() != 0) {
        ClearPackageModules(llvmModules)
        return false
    }

    let recorder = ProfileRecorder("CodeGen", "Save bc file")
    instance.invocation.globalOptions.UpdateCachedDirName(fullPackageName)
    if (llvmModules.size == 1) {
        let filePath = GenerateBCFilePathAndUpdateToInvocation(
            instance.invocation.globalOptions, TempFileKind.T_BC, fullPackageName, "")
        if (filePath.isEmpty()) {
            ClearPackageModules(llvmModules)
            recorder.close()
            return false
        }
        let _ = SavePackageModule(llvmModules[0], filePath)
    } else {
        let taskQueueSaveBitcode = TaskQueue(llvmModules.size)
        let allBCFilePath = ArrayList<String>()
        var index: Int64 = 0
        while (index < llvmModules.size) {
            let filePath = GenerateBCFilePathAndUpdateToInvocation(instance.invocation.globalOptions,
                TempFileKind.T_BC, fullPackageName, index.toString())
            if (filePath.isEmpty()) {
                ClearPackageModules(llvmModules)
                recorder.close()
                return false
            }
            allBCFilePath.add(filePath)
            index++
        }
        index = 0
        while (index < llvmModules.size) {
            let module = llvmModules[index]
            let bcFilePath = allBCFilePath[index]
            let _ = taskQueueSaveBitcode.AddTask<Unit>({ =>
                let _ = SavePackageModule(module, bcFilePath)
            })
            index++
        }
        taskQueueSaveBitcode.RunAndWaitForAllTasksCompleted()
    }
    ClearPackageModules(llvmModules)

    if (instance.invocation.globalOptions.enIncrementalCompilation) {
        let fileName = GenerateFileName(instance.invocation.globalOptions, fullPackageName, "")
        if (instance.GetAllCHIRPackages().size > 1) {
            instance.cachedInfo.bitcodeFilesName.add(fileName)
        } else {
            instance.cachedInfo.bitcodeFilesName.clear()
            instance.cachedInfo.bitcodeFilesName.add(fileName)
        }
    }
    recorder.close()
    return true
}

public func ConvertFrontendOptionsToCodegenOptions(options: GlobalOptions): GlobalOptions {
    return options
}

public func GetVarInitDepMap(chirPkg: RealCHIRPackage): HashMap<String, String> {
    let dep = HashMap<String, String>()
    for (globalVar in chirPkg.GetGlobalVarsWithInit()) {
        if (globalVar.GetRawMangledName().isEmpty()) {
            continue
        }
        if (let Some(initFunc) <- globalVar.GetInitFunc()) {
            dep[globalVar.GetRawMangledName()] = initFunc.GetIdentifierWithoutPrefix()
        }
    }
    return dep
}

// C++: FrontendTool/DefaultCompilerInstance.cpp:128-143.
private func GenerateFileName(options: GlobalOptions, fullPackageName: String, idx: String): String {
    let pkgNameSuffix = FileUtil.ToCjoFileName(fullPackageName)
    let prefix = if (idx.isEmpty()) { "" } else { idx + "-" }
    if (options.compilePackage) {
        return prefix + pkgNameSuffix
    }
    if (fullPackageName != DEFAULT_PACKAGE_NAME) {
        return prefix + pkgNameSuffix
    }
    CJC_ASSERT(!options.srcFiles.isEmpty())
    return prefix + FileUtil.GetFileNameWithoutExtension(options.srcFiles[0])
}

// C++: FrontendTool/DefaultCompilerInstance.cpp:145-164.
private func GenerateBCFilePathAndUpdateToInvocation(options: GlobalOptions, kind: TempFileKind,
    pkgName: String, idx: String): String {
    let fileName = GenerateFileName(options, pkgName, idx)
    let bcFileInfo = TempFileManager.Instance().CreateNewFileInfo(
        TempFileInfo(fileName: fileName, isFrontendOutput: true), kind)
    options.frontendOutputFiles.add(bcFileInfo)
    let bcFilePath = bcFileInfo.filePath
    if (FileUtil.FileExist(bcFilePath) && !FileUtil.Remove(bcFilePath)) {
        eprintln("error: The file " + bcFilePath +
            " already exists, but it fails to be removed before being updated.")
        return ""
    }
    let dir = FileUtil.GetDirPath(bcFilePath)
    if (!FileUtil.FileExist(dir) && FileUtil.CreateDirs(dir + "/") != 0) {
        eprintln("error: The directory " + dir + " fails to be created before creating " + bcFilePath)
        return ""
    }
    if (TempFileManager.Instance().IsDeleted()) {
        return ""
    }
    return bcFilePath
}
