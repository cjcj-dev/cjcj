package cangjie_compiler::frontend

import std.collection.*
import cangjie_compiler::chir.Attribute as ChirAttribute
import cangjie_compiler::chir.CHIRBuilder as ChirBuilder
import cangjie_compiler::chir.CHIRPrinter as ChirCHIRPrinter
import cangjie_compiler::chir.CHIRType
import cangjie_compiler::chir.CHIRTypeCache
import cangjie_compiler::chir.FaithfulAST2CHIR
import cangjie_compiler::chir.FuncKind as ChirFuncKind
import cangjie_compiler::chir.Function as ChirFunction
import cangjie_compiler::chir.InstantiateGenericFunctionsForPackage
import cangjie_compiler::chir.Package as RealCHIRPackage
import cangjie_compiler::ast.Package as RealASTPackage
import cangjie_compiler::codegen.CHIRData as CodegenCHIRData
import cangjie_compiler::codegen.ClearPackageModules
import cangjie_compiler::codegen.GenPackageModules
import cangjie_compiler::codegen.LLVMModuleHandle as LLVMModuleHandle
import cangjie_compiler::codegen.SavePackageModule
import cangjie_compiler::meta_transformation.TryRunCHIRMetaTransforms
import cangjie_compiler::option.MaybeUInt64

public func BuildRealCHIRForASTPackage(instance: CompilerInstance, pkg: RealASTPackage): Option<RealCHIRPackage> {
    let builder = ChirBuilder(instance.chirData.GetRealCHIRContext())
    let chirType = CHIRType(builder, CHIRTypeCache())
    let ast2chir = FaithfulAST2CHIR(builder, chirType, importedPkgs: instance.importManager.GetAllImportedPackages())
    if (!ast2chir.ToCHIRPackage(pkg)) {
        return None
    }
    let lowered = match (ast2chir.GetPackage()) {
        case Some(value) => value
        case None => return None
    }
    InstantiateGenericFunctionsForPackage(builder, lowered)
    let pluginResult = TryRunCHIRMetaTransforms(instance.metaTransformPluginBuilder, builder, lowered)
    if (!pluginResult.succeed) {
        instance.diag.DiagnoseRefactor(DiagKindRefactor.plugin_throws_exception, DEFAULT_POSITION)
        return None
    }
    if (instance.invocation.globalOptions.NeedDumpCHIRToScreen()) {
        print(ChirCHIRPrinter().PrintPackage(lowered))
    }
    return Some(lowered)
}

public func EmitRealCodeGenForCompilerInstance(instance: CompilerInstance): Bool {
    if (instance.diag.GetErrorCount() != 0) {
        return false
    }
    let realPackages = instance.chirData.GetAllRealCHIRPackages()
    if (realPackages.isEmpty()) {
        return true
    }
    let packagesToEmit = BuildRealCodeGenPackages(realPackages)
    let codegenOptions = ConvertFrontendOptionsToCodegenOptions(instance.invocation.globalOptions)
    let savedAPC = codegenOptions.aggressiveParallelCompile
    if (ShouldEmitSingleExplicitBitcodeOutput(codegenOptions)) {
        codegenOptions.aggressiveParallelCompile = MaybeUInt64(1u64)
    }
    if (instance.invocation.globalOptions.enIncrementalCompilation) {
        instance.cachedInfo.bitcodeFilesName.clear()
    }
    var emittedAll = true
    var packageIndex: Int64 = 0
    while (packageIndex < packagesToEmit.size) {
        let realPackage = packagesToEmit[packageIndex]
        instance.chirData.SetCurrentRealCHIRPackage(Some(realPackage))
        let codegenData = CodegenCHIRData(instance.chirData.GetRealCHIRContext(), realPackage)
        let packageModules = GenPackageModules(codegenData, codegenOptions,
            instance.invocation.globalOptions.enIncrementalCompilation)
        emittedAll = emitPackageModules(instance, realPackage, packageModules, packageIndex) && emittedAll
        ClearPackageModules(packageModules)
        packageIndex++
    }
    codegenOptions.aggressiveParallelCompile = savedAPC
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

private func ShouldEmitSingleExplicitBitcodeOutput(options: GlobalOptions): Bool {
    return !options.output.isEmpty() && !IsDir(options.output) && options.output.endsWith(".bc")
}

private func emitPackageModules(
    instance: CompilerInstance,
    pkg: RealCHIRPackage,
    modules: ArrayList<LLVMModuleHandle>,
    packageIndex: Int64
): Bool {
    if (modules.isEmpty()) {
        instance.diag.Diagnose(DiagCategory.OTHER, DEFAULT_POSITION,
            "codegen produced no LLVM module for package '" + pkg.GetName() + "'")
        return false
    }
    var ok = true
    var moduleIndex: Int64 = 0
    while (moduleIndex < modules.size) {
        let path = outputPathForModule(instance.invocation.globalOptions, pkg, modules[moduleIndex],
            packageIndex, moduleIndex, modules.size)
        var saved = false
        if (!ensureOutputDirectory(path)) {
            instance.diag.Diagnose(DiagCategory.OTHER, DEFAULT_POSITION,
                "failed to create output directory for bitcode file '" + path + "'")
            ok = false
        } else if (!SavePackageModule(modules[moduleIndex], path)) {
            instance.diag.Diagnose(DiagCategory.OTHER, DEFAULT_POSITION,
                "failed to write LLVM bitcode file '" + path + "'")
            ok = false
        } else {
            saved = true
        }
        if (saved && instance.invocation.globalOptions.enIncrementalCompilation) {
            instance.cachedInfo.bitcodeFilesName.add(outputCacheNameForModule(pkg, modules[moduleIndex], moduleIndex))
        }
        moduleIndex++
    }
    return ok
}

private func outputPathForModule(
    options: GlobalOptions,
    pkg: RealCHIRPackage,
    module: LLVMModuleHandle,
    packageIndex: Int64,
    moduleIndex: Int64,
    moduleCount: Int64
): String {
    if (packageIndex == 0 && moduleCount == 1 && !options.output.isEmpty() && !IsDir(options.output)) {
        return options.output
    }
    let moduleName = outputCacheNameForModule(pkg, module, moduleIndex)
    return options.GenerateCachedPathNameForCodeGen(moduleName, ".bc")
}

private func outputCacheNameForModule(
    pkg: RealCHIRPackage,
    module: LLVMModuleHandle,
    moduleIndex: Int64
): String {
    let moduleName = if (module.name.isEmpty()) {
        pkg.GetName() + "." + moduleIndex.toString()
    } else {
        module.name
    }
    return moduleName
}

private func ensureOutputDirectory(path: String): Bool {
    let dir = GetDirPath(path)
    if (dir.isEmpty() || dir == ".") {
        return true
    }
    if (FileExist(dir)) {
        return IsDir(dir)
    }
    return CreateDirs(dir + DIR_SEPARATOR)
}
