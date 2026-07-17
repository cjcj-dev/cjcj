package cjcj::frontend

import std.collection.*
import cjcj::basic.Linkage as BasicLinkage
import cjcj::chir.Apply as ChirApply
import cjcj::chir.ApplyWithException as ChirApplyWithException
import cjcj::chir.AnalysisWrapper
import cjcj::chir.AnnotationChecker
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
import cjcj::chir.DevirtualizationInfo
import cjcj::chir.ExprKind as ChirExprKind
import cjcj::chir.FaithfulAST2CHIR
import cjcj::chir.FuncCallContext as ChirFuncCallContext
import cjcj::chir.FuncKind as ChirFuncKind
import cjcj::chir.FuncSigInfo as ChirFuncSigInfo
import cjcj::chir.Function as ChirFunction
import cjcj::chir.FunctionInline
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
import cjcj::chir.IsTrackedGVForRangeAnalysis
import cjcj::chir.rangeStateGlobals
import cjcj::chir.ReplaceUsesWithWrapper
import cjcj::chir.SanitizerCoverage
import cjcj::chir.ShouldReportUnusedCodeWarnings
import cjcj::chir.Terminator as ChirTerminator
import cjcj::chir.ToCHIRPhase
import cjcj::chir.UnitUnify
import cjcj::chir.UpdateMemberVarPath
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

private class ToCHIR {
    private static var clearDumpDir: Bool = false

    private let instance: CompilerInstance
    private let pkg: RealASTPackage
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
        this.pkg = pkg
        this.outputPath = instance.invocation.globalOptions.output
        this.builder = ChirBuilder(instance.chirData.GetRealCHIRContext())
    }

    public func Run(): Option<RealCHIRPackage> {
        let chirType = CHIRType(builder, CHIRTypeCache())
        let ast2chir = FaithfulAST2CHIR(builder, chirType, instance.GetSourceManager(),
            gim: instance.gim,
            importedPkgs: instance.importManager.GetAllImportedPackages(),
            directImportedPkgs: instance.importManager.GetCurImportedPackages(pkg.fullPackageName),
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
        if (!ast2chir.ToCHIRPackage(pkg)) {
            return None
        }
        let lowered = match (ast2chir.GetPackage()) {
            case Some(value) => value
            case None => return None
        }
        instance.chirData.SetImplicitFuncs(lowered, ast2chir.GetImplicitFuncs())
        maybeUnreachable = ast2chir.GetMaybeUnreachableBlocks()
        chirPkg = Some(lowered)
        DumpCHIRToFile("AST_CHIR")
        // C++: CHIR/CHIR.cpp:1133-1140 ToCHIR::Run.
        if (instance.invocation.globalOptions.outputMode == OutputMode.CHIR) {
            let fileName = FileUtil.JoinPath(outputPath, lowered.GetName()) + CHIR_SERIALIZATION_FILE_EXTENSION
            CHIRSerializer.Serialize(lowered, fileName, ToCHIRPhase.RAW)
            return Some(lowered)
        }
        if (!RulesChecking(lowered, builder, instance.invocation.globalOptions,
            instance.diag.AsBasicDiagnosticEngine(), effectMap, maybeUnreachable)) {
            return None
        }
        RunOptimizationPass(lowered)
        if (!TryRunCHIRMetaTransforms(instance.metaTransformPluginBuilder, builder, lowered)) {
            instance.diag.DiagnoseRefactor(DiagKindRefactor.plugin_throws_exception, DEFAULT_POSITION)
            return None
        }
        let closure = ClosureConversion(builder, opts: instance.invocation.globalOptions,
            srcCodeImportedFuncs: ast2chir.GetSrcCodeImportedFuncs())
        closure.RunOnPackage(lowered)
        // C++: CHIR/CHIR.cpp:253-255.
        ccOutFuncsRawMangle.clear()
        for (rawMangledName in closure.GetCCOutFuncsRawMangle()) {
            ccOutFuncsRawMangle.add(rawMangledName)
        }
        if (!RunConstantEvaluation(lowered, builder, instance.diag.AsBasicDiagnosticEngine(),
            instance.invocation.globalOptions, ast2chir.GetInitFuncsForConstVar())) {
            return None
        }
        ast2chir.ReplaceSrcCodeImportedValAfterClosureConversion(lowered, closure.GetUselessClassDef(),
            closure.GetUselessLambda())
        // C++: CHIR/CHIR.cpp:1178-1181.
        if (!AnnotationChecker(lowered, instance.diag.AsBasicDiagnosticEngine()).Run()) {
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
            ChirCHIRPrinter.PrintPackage(lowered)
        }
        builder.MergeAllocatedInstance()
        return Some(lowered)
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

    private func RunOptimizationPass(currentPackage: RealCHIRPackage): Unit {
        try (recorder = ProfileRecorder("CHIR", "CHIR Opt")) {
            let options = instance.invocation.globalOptions
            OptFuncRetType(currentPackage, builder).Unit2Void()
            // C++ 此处有 RunArrayListConstStartOpt，selfhost 未移植，待补。
            if (options.IsCHIROptimizationLevelOverO2()) {
                UnitUnify(builder).RunOnPackage(currentPackage, isDebug: options.chirDebugOptimizer)
            }
            let devirtInfo = CollectDevirtualizationInfo(currentPackage)
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
            // GAP_TODO: Devirtualization is unported; C++ call is CHIR.cpp:648.
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
    // Canonicalize member-var paths over the whole package before analysis, mirroring C++
    // ToCHIR::Canonicalization() at CHIR.cpp:1150 ("after this pass, the CHIR is ready for
    // analysis and optimization"). Generic instantiation adds function bodies after
    // FaithfulAST2CHIR ran UpdateMemberVarPath, so their GetElementByName/StoreElementByName/
    // FieldByName nodes would otherwise reach ConstAnalysis (memory-major but unhandled).
    UpdateMemberVarPath(builder).RunOnPackage(pkg)
    DeadCodeElimination(builder, diag, pkg).UnreachableBlockWarningReporter(pkg,
        Int64(options.GetJobs()), maybeUnreachable)
    DeadCodeElimination(builder).ClearUnreachableMarkBlock(pkg)
    MergeBlocks().RunOnPackage(pkg, builder, enableCompileDebug: options.enableCompileDebug,
        enableCoverage: options.enableCoverage)
    DeadCodeElimination(builder).NothingTypeExprElimination(pkg, isDebug: options.chirDebugOptimizer)
    let wrapper = ConstAnalysisWrapper(builder)
    wrapper.RunOnPackage(pkg, diag, isDebug: options.chirDebugOptimizer)
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
    let cp = ConstPropagation(builder: Some(builder), wrapper: wrapper, opts: options)
    MergeEffectMap(cp.GetEffectMap(), effectMap)
    cp.RunOnPackage(pkg, isDebug: options.chirDebugOptimizer, isCJLint: false)
    DeadCodeElimination(builder).UnreachableBlockElimination(cp.GetFuncsNeedRemoveBlocks(),
        isDebug: options.chirDebugOptimizer)
    return diag.GetErrorCount() == 0
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
    cachedMangleMap: CachedMangleMap): Bool {
    if (instance.diag.GetErrorCount() != 0) {
        return false
    }
    let realPackages = instance.chirData.GetAllRealCHIRPackages()
    if (realPackages.isEmpty()) {
        return true
    }
    let packagesToEmit = BuildRealCodeGenPackages(realPackages)
    let codegenOptions = ConvertFrontendOptionsToCodegenOptions(instance.invocation.globalOptions)
    codegenOptions.frontendOutputFiles.clear()
    if (instance.invocation.globalOptions.enIncrementalCompilation) {
        instance.cachedInfo.bitcodeFilesName.clear()
    }
    var emittedAll = true
    var packageIndex: Int64 = 0
    while (packageIndex < packagesToEmit.size) {
        let realPackage = packagesToEmit[packageIndex]
        instance.chirData.SetCurrentRealCHIRPackage(Some(realPackage))
        instance.invocation.globalOptions.UpdateCachedDirName(realPackage.GetName())
        let codegenData = CodegenCHIRData(instance.chirData.GetRealCHIRContext(), realPackage)
        for ((mangledName, fn) in instance.chirData.GetImplicitFuncs(realPackage)) {
            codegenData.AddImplicitFunc(mangledName, fn)
        }
        let noHeapAllocChecker = NoHeapAllocChecker(instance.diag.AsBasicDiagnosticEngine())
        noHeapAllocChecker.RunOnPackage(realPackage)
        let noWriteBarrierRecChecker = NoWriteBarrierRecChecker(instance.diag.AsBasicDiagnosticEngine())
        noWriteBarrierRecChecker.RunOnPackage(realPackage)
        let packageModules = CodegenGenPackageModules(codegenData, codegenOptions, enableIncrement,
            noHeapAllocChecker, noWriteBarrierRecChecker, cachedMangleMap: cachedMangleMap)
        if (instance.diag.GetErrorCount() != 0) {
            instance.diag.EmitCategoryDiagnostics(DiagCategory.CHIR)
            ClearPackageModules(packageModules)
            return false
        }
        emittedAll = emitPackageModules(instance, realPackage, packageModules) && emittedAll
        ClearPackageModules(packageModules)
        packageIndex++
    }
    return emittedAll
}

private func BuildRealCodeGenPackages(realPackages: ArrayList<RealCHIRPackage>): ArrayList<RealCHIRPackage> {
    if (realPackages.size <= 1) {
        return realPackages
    }
    let mainPackageIndex = FindUniqueRealMainPackageIndex(realPackages)
    if (mainPackageIndex < 0) {
        return realPackages
    }
    let out = ArrayList<RealCHIRPackage>()
    out.add(MergeRealCHIRPackagesForSingleCodegenOutput(realPackages, mainPackageIndex))
    return out
}

private func FindUniqueRealMainPackageIndex(realPackages: ArrayList<RealCHIRPackage>): Int64 {
    var found: Int64 = -1
    var index: Int64 = 0
    while (index < realPackages.size) {
        if (RealPackageHasMainEntry(realPackages[index])) {
            if (found >= 0) {
                return -1
            }
            found = index
        }
        index++
    }
    return found
}

private func RealPackageHasMainEntry(pkg: RealCHIRPackage): Bool {
    for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
        if (fn.GetFuncKind() == ChirFuncKind.MAIN_ENTRY) {
            return true
        }
    }
    return false
}

private func MergeRealCHIRPackagesForSingleCodegenOutput(realPackages: ArrayList<RealCHIRPackage>,
    mainPackageIndex: Int64): RealCHIRPackage {
    let mainPackage = realPackages[mainPackageIndex]
    let merged = RealCHIRPackage(mainPackage.GetName())
    merged.SetPackageAccessLevel(mainPackage.GetPackageAccessLevel())
    let bodyFunctionNames = HashSet<String>()
    let allFunctionNames = HashSet<String>()
    for (pkg in realPackages) {
        AddRealPackageTypes(merged, pkg)
        AddRealPackageGlobals(merged, pkg)
    }
    AddRealPackageBodyFunctionsExceptMain(merged, realPackages, mainPackageIndex, bodyFunctionNames,
        allFunctionNames)
    AddRealPackageBodyFunctions(merged, mainPackage, bodyFunctionNames, allFunctionNames)
    AddRealPackageImportedFunctionDeclarations(merged, realPackages, bodyFunctionNames, allFunctionNames)
    return merged
}

private func AddRealPackageBodyFunctionsExceptMain(merged: RealCHIRPackage,
    realPackages: ArrayList<RealCHIRPackage>, mainPackageIndex: Int64, bodyFunctionNames: HashSet<String>,
    allFunctionNames: HashSet<String>): Unit {
    var index: Int64 = 0
    while (index < realPackages.size) {
        if (index != mainPackageIndex) {
            AddRealPackageBodyFunctions(merged, realPackages[index], bodyFunctionNames, allFunctionNames)
        }
        index++
    }
}

private func AddRealPackageBodyFunctions(merged: RealCHIRPackage, pkg: RealCHIRPackage,
    bodyFunctionNames: HashSet<String>, allFunctionNames: HashSet<String>): Unit {
    for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
        if (fn.GetBody().isSome() && !fn.TestAttr(ChirAttribute.IMPORTED)) {
            AddRealPackageFunctionOnce(merged, fn, allFunctionNames)
            bodyFunctionNames.add(fn.GetIdentifier())
        }
    }
}

private func AddRealPackageImportedFunctionDeclarations(merged: RealCHIRPackage,
    realPackages: ArrayList<RealCHIRPackage>, bodyFunctionNames: HashSet<String>,
    allFunctionNames: HashSet<String>): Unit {
    for (pkg in realPackages) {
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            if (fn.TestAttr(ChirAttribute.IMPORTED) && !bodyFunctionNames.contains(fn.GetIdentifier())) {
                AddRealPackageFunctionOnce(merged, fn, allFunctionNames)
            }
        }
    }
}

private func AddRealPackageFunctionOnce(merged: RealCHIRPackage, fn: ChirFunction,
    allFunctionNames: HashSet<String>): Unit {
    let name = fn.GetIdentifier()
    if (allFunctionNames.contains(name)) {
        return
    }
    allFunctionNames.add(name)
    merged.AddGlobalFunc(fn)
}

private func AddRealPackageGlobals(merged: RealCHIRPackage, pkg: RealCHIRPackage): Unit {
    for (globalVar in pkg.GetGlobalVars()) {
        if (merged.TryGetGlobalVar(globalVar.GetIdentifier()).isNone()) {
            merged.AddGlobalVar(globalVar)
        }
    }
    if (merged.GetPackageInitFunc().isNone()) {
        if (let Some(initFn) <- pkg.GetPackageInitFunc()) {
            merged.SetPackageInitFunc(initFn)
        }
    }
    if (merged.GetPackageLiteralInitFunc().isNone()) {
        if (let Some(literalInitFn) <- pkg.GetPackageLiteralInitFunc()) {
            merged.SetPackageLiteralInitFunc(literalInitFn)
        }
    }
}

private func AddRealPackageTypes(merged: RealCHIRPackage, pkg: RealCHIRPackage): Unit {
    for (item in pkg.GetStructs()) {
        if (merged.TryGetStructDef(item.GetIdentifier()).isNone()) {
            merged.AddStruct(item)
        }
    }
    for (item in pkg.GetImportedStructs()) {
        if (merged.TryGetStructDef(item.GetIdentifier()).isNone()) {
            merged.AddImportedStruct(item)
        }
    }
    for (item in pkg.GetClasses()) {
        if (merged.TryGetClassDef(item.GetIdentifier()).isNone()) {
            merged.AddClass(item)
        }
    }
    for (item in pkg.GetImportedClasses()) {
        if (merged.TryGetClassDef(item.GetIdentifier()).isNone()) {
            merged.AddImportedClass(item)
        }
    }
    for (item in pkg.GetEnums()) {
        if (merged.TryGetEnumDef(item.GetIdentifier()).isNone()) {
            merged.AddEnum(item)
        }
    }
    for (item in pkg.GetImportedEnums()) {
        if (merged.TryGetEnumDef(item.GetIdentifier()).isNone()) {
            merged.AddImportedEnum(item)
        }
    }
    for (item in pkg.GetExtends()) {
        if (merged.TryGetExtendDef(item.GetIdentifier()).isNone()) {
            merged.AddExtend(item)
        }
    }
    for (item in pkg.GetImportedExtends()) {
        if (merged.TryGetExtendDef(item.GetIdentifier()).isNone()) {
            merged.AddImportedExtend(item)
        }
    }
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

private func emitPackageModules(
    instance: CompilerInstance,
    pkg: RealCHIRPackage,
    modules: ArrayList<LLVMModuleHandle>
): Bool {
    if (modules.isEmpty()) {
        instance.diag.Diagnose(DiagCategory.OTHER, DEFAULT_POSITION,
            "codegen produced no LLVM module for package '" + pkg.GetName() + "'")
        return false
    }
    var ok = true
    var moduleIndex: Int64 = 0
    while (moduleIndex < modules.size) {
        let idx = if (modules.size == 1) { "" } else { moduleIndex.toString() }
        let path = GenerateBCFilePathAndUpdateToInvocation(
            instance.invocation.globalOptions, TempFileKind.T_BC, pkg.GetName(), idx)
        if (path.isEmpty()) {
            ok = false
        } else if (!SavePackageModule(modules[moduleIndex], path)) {
            instance.diag.Diagnose(DiagCategory.OTHER, DEFAULT_POSITION,
                "failed to write LLVM bitcode file '" + path + "'")
            ok = false
        }
        moduleIndex++
    }
    if (ok && instance.invocation.globalOptions.enIncrementalCompilation) {
        instance.cachedInfo.bitcodeFilesName.add(GenerateFileName(instance.invocation.globalOptions, pkg.GetName(), ""))
    }
    return ok
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
