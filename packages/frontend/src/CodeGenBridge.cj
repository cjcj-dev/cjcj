package cangjie_compiler::frontend

import std.collection.*
import cangjie_compiler::chir.AccessLevel as ChirAccessLevel
import cangjie_compiler::chir.AST2CHIR as ChirAST2CHIR
import cangjie_compiler::chir.AST2CHIRFunctionSpec as ChirFunctionSpec
import cangjie_compiler::chir.AST2CHIRGlobalSpec as ChirGlobalSpec
import cangjie_compiler::chir.AST2CHIRMemberVarSpec as ChirMemberVarSpec
import cangjie_compiler::chir.AST2CHIRNominalKind as ChirNominalKind
import cangjie_compiler::chir.AST2CHIRNominalSpec as ChirNominalSpec
import cangjie_compiler::chir.AST2CHIRPackageSpec as ChirPackageSpec
import cangjie_compiler::chir.Attribute as ChirAttribute
import cangjie_compiler::chir.CHIRBuilder as ChirBuilder
import cangjie_compiler::chir.CHIRContext as ChirContext
import cangjie_compiler::chir.FuncKind as ChirFuncKind
import cangjie_compiler::chir.Package as RealCHIRPackage
import cangjie_compiler::chir.Type as ChirType
import cangjie_compiler::codegen.CHIRData as CodegenCHIRData
import cangjie_compiler::codegen.ClearPackageModules
import cangjie_compiler::codegen.GenPackageModules
import cangjie_compiler::codegen.LLVMModuleHandle as LLVMModuleHandle
import cangjie_compiler::codegen.SavePackageModule
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions
import cangjie_compiler::option.MaybeString as OptionMaybeString
import cangjie_compiler::option.MaybeUInt64 as OptionMaybeUInt64

public func BuildRealCHIRForFrontendPackage(instance: CompilerInstance, pkg: Package): Option<RealCHIRPackage> {
    let builder = ChirBuilder(instance.chirData.GetRealCHIRContext())
    let packageSpec = buildRealPackageSpec(pkg, builder.context)
    let lowered = ChirAST2CHIR(builder).LowerPackage(packageSpec).pkg
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
    let codegenOptions = ConvertFrontendOptionsToCodegenOptions(instance.invocation.globalOptions)
    var emittedAll = true
    var packageIndex: Int64 = 0
    while (packageIndex < realPackages.size) {
        let realPackage = realPackages[packageIndex]
        instance.chirData.SetCurrentRealCHIRPackage(Some(realPackage))
        let codegenData = CodegenCHIRData(instance.chirData.GetRealCHIRContext(), realPackage)
        let packageModules = GenPackageModules(codegenData, codegenOptions,
            instance.invocation.globalOptions.enIncrementalCompilation)
        emittedAll = emitPackageModules(instance, realPackage, packageModules, packageIndex) && emittedAll
        ClearPackageModules(packageModules)
        packageIndex++
    }
    return emittedAll
}

public func ConvertFrontendOptionsToCodegenOptions(options: GlobalOptions): OptionGlobalOptions {
    let converted = OptionGlobalOptions()
    converted.frontendMode = options.frontendMode
    converted.cangjieHome = options.cangjieHome
    converted.output = options.output
    if (let Some(outDir) <- options.outputDir.value) {
        converted.outputDir = OptionMaybeString(outDir)
    }
    converted.executablePath = options.executablePath
    converted.moduleSrcPath = options.moduleSrcPath
    converted.inputCjoFile = options.inputCjoFile
    converted.compilePackage = options.compilePackage
    converted.parseTest = options.parseTest
    converted.compileTestsOnly = options.compileTestsOnly
    converted.enableAddCommentToAst = options.enableAddCommentToAst
    converted.compileCjd = options.compileCjd
    converted.noSubPkg = options.noSubPkg
    converted.scanDepPkg = options.scanDepPkg
    converted.enableInteropCJMapping = options.enableInteropCJMapping
    converted.interopCJPackageConfigPath = options.interopCJPackageConfigPath
    converted.chirDeserialize = options.chirDeserialize
    converted.chirDeserializePath = options.chirDeserializePath
    converted.dumpCHIR = options.dumpCHIR
    converted.dumpAST = options.dumpAST
    converted.dumpToScreen = options.dumpToScreen
    converted.dumpAll = options.dumpAll
    converted.enableVerbose = options.enableVerbose
    converted.enableMacroInLSP = options.enableMacroInLSP
    converted.enIncrementalCompilation = options.enIncrementalCompilation
    converted.cjdbMode = options.cjdbMode
    converted.printVersionOnly = options.printVersionOnly
    converted.showUsage = options.showUsage
    converted.enableCompileDebug = options.enableCompileDebug
    converted.displayLineInfo = options.displayLineInfo
    converted.interpreter = options.interpreter
    converted.overflowStrategy = options.overflowStrategy
    converted.compilationCachedPath = options.compilationCachedPath
    converted.compilationCachedDir = options.compilationCachedDir
    converted.compilationCachedFileName = options.compilationCachedFileName
    converted.jobs = OptionMaybeUInt64(UInt64(options.GetJobs()))
    copyStrings(options.packagePaths, converted.packagePaths)
    copyStrings(options.srcFiles, converted.srcFiles)
    copyStrings(options.inputObjs, converted.inputObjs)
    copyStrings(options.importPaths, converted.importPaths)
    copyStrings(options.pluginPaths, converted.pluginPaths)
    copyStrings(options.commonPartCjos, converted.commonPartCjos)
    copyStrings(options.commonPartChirs, converted.commonPartChirs)
    copyStrings(options.bcPackageNames, converted.bcPackageNames)
    copyStringSet(options.directBuiltinDependencies, converted.directBuiltinDependencies)
    copyStringSet(options.indirectBuiltinDependencies, converted.indirectBuiltinDependencies)
    copyStringMap(options.passedWhenKeyValue, converted.passedWhenKeyValue)
    copyStrings(options.passedWhenCfgPaths, converted.passedWhenCfgPaths)
    return converted
}

private func buildRealPackageSpec(pkg: Package, context: ChirContext): ChirPackageSpec {
    let packageSpec = ChirPackageSpec(pkg.fullPackageName)
    packageSpec.SetAccessLevel(toChirAccessLevel(pkg.accessible))
    for (file in pkg.files) {
        let fileName = if (file.filePath.isEmpty()) { file.fileName } else { file.filePath }
        packageSpec.RegisterSourceFile(UInt32(file.begin.fileID), fileName)
        for (decl in file.decls) {
            addDeclToPackageSpec(packageSpec, pkg, decl, context, None, fileName)
        }
    }
    for (instDecl in pkg.genericInstantiatedDecls) {
        addDeclToPackageSpec(packageSpec, pkg, instDecl, context, None, "")
    }
    return packageSpec
}

private func addDeclToPackageSpec(
    packageSpec: ChirPackageSpec,
    pkg: Package,
    decl: Decl,
    context: ChirContext,
    owner: Option<ChirNominalSpec>,
    sourceFileKey: String
): Unit {
    if (decl.IsFunc()) {
        let fnSpec = buildFunctionSpec(pkg, decl, context, sourceFileKey)
        if (let Some(ownerSpec) <- owner) {
            ownerSpec.AddMethod(fnSpec)
        } else {
            packageSpec.AddFunction(fnSpec)
        }
        return
    }
    if (decl.astKind == ASTKind.VAR_DECL || decl.astKind == ASTKind.PROP_DECL) {
        if (let Some(ownerForVar) <- owner) {
            ownerForVar.AddInstanceVar(buildMemberVarSpec(pkg, decl, context, sourceFileKey))
        } else {
            packageSpec.AddGlobal(buildGlobalSpec(pkg, decl, context))
        }
        return
    }
    if (decl.IsNominalDecl() || decl.astKind == ASTKind.EXTEND_DECL) {
        let nominalSpec = buildNominalSpec(pkg, decl, context, sourceFileKey)
        for (member in decl.members) {
            addDeclToPackageSpec(packageSpec, pkg, member, context, Some(nominalSpec), sourceFileKey)
        }
        packageSpec.AddType(nominalSpec)
        return
    }
    for (memberOnlyDecl in decl.members) {
        addDeclToPackageSpec(packageSpec, pkg, memberOnlyDecl, context, owner, sourceFileKey)
    }
}

private func buildFunctionSpec(pkg: Package, decl: Decl, context: ChirContext, sourceFileKey: String): ChirFunctionSpec {
    let paramTypes = ArrayList<ChirType>()
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        for (param in funcDecl.funcBody.params) {
            paramTypes.add(lowerValueType(context, param.typeNode))
        }
    }
    let fnName = stableMangledName(pkg, decl)
    let fnSpec = ChirFunctionSpec(fnName, paramTypes, context.GetVoidTy(),
        srcCodeIdentifier: decl.identifier.Val(), rawMangledName: fnName,
        packageName: pkg.fullPackageName, funcKind: toChirFuncKind(decl), emitBody: true)
    applyDeclAttributes(decl, fnSpec)
    if (!sourceFileKey.isEmpty()) {
        fnSpec.SetSourceFileKey(sourceFileKey)
    }
    if (let Some(namedFuncDecl) <- (decl as FuncDecl)) {
        for (paramDecl in namedFuncDecl.funcBody.params) {
            let paramName = if (paramDecl.identifier.Empty()) { "%arg" } else { paramDecl.identifier.Val() }
            fnSpec.AddParamName(paramName)
        }
    }
    return fnSpec
}

private func buildGlobalSpec(pkg: Package, decl: Decl, context: ChirContext): ChirGlobalSpec {
    let globalName = stableMangledName(pkg, decl)
    let globalSpec = ChirGlobalSpec(globalName, lowerDeclValueType(context, decl),
        srcCodeIdentifier: decl.identifier.Val(), rawMangledName: globalName, packageName: pkg.fullPackageName)
    applyDeclAttributes(decl, globalSpec)
    return globalSpec
}

private func buildMemberVarSpec(
    pkg: Package,
    decl: Decl,
    context: ChirContext,
    sourceFileKey: String
): ChirMemberVarSpec {
    let memberName = if (decl.identifier.Empty()) { stableMangledName(pkg, decl) } else { decl.identifier.Val() }
    let memberSpec = ChirMemberVarSpec(memberName, lowerDeclValueType(context, decl),
        rawMangledName: stableMangledName(pkg, decl))
    applyDeclAttributes(decl, memberSpec)
    if (!sourceFileKey.isEmpty()) {
        memberSpec.SetSourceFileKey(sourceFileKey)
    }
    return memberSpec
}

private func buildNominalSpec(
    pkg: Package,
    decl: Decl,
    context: ChirContext,
    sourceFileKey: String
): ChirNominalSpec {
    let nominalName = if (decl.identifier.Empty()) { stableMangledName(pkg, decl) } else { decl.identifier.Val() }
    let nominalSpec = ChirNominalSpec(toChirNominalKind(decl), nominalName,
        packageName: pkg.fullPackageName, srcCodeIdentifier: decl.identifier.Val(),
        rawMangledName: stableMangledName(pkg, decl))
    applyDeclAttributes(decl, nominalSpec)
    if (!sourceFileKey.isEmpty()) {
        nominalSpec.SetSourceFileKey(sourceFileKey)
    }
    if (let Some(extendDecl) <- (decl as ExtendDecl)) {
        nominalSpec.SetExtendedType(lowerValueType(context, extendDecl.extendedType))
    }
    return nominalSpec
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
        if (!ensureOutputDirectory(path)) {
            instance.diag.Diagnose(DiagCategory.OTHER, DEFAULT_POSITION,
                "failed to create output directory for bitcode file '" + path + "'")
            ok = false
        } else if (!SavePackageModule(modules[moduleIndex], path)) {
            instance.diag.Diagnose(DiagCategory.OTHER, DEFAULT_POSITION,
                "failed to write LLVM bitcode file '" + path + "'")
            ok = false
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
    let moduleName = if (module.name.isEmpty()) {
        pkg.GetName() + "." + moduleIndex.toString()
    } else {
        module.name
    }
    return options.GenerateCachedPathNameForCodeGen(moduleName, ".bc")
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

private func lowerDeclValueType(context: ChirContext, decl: Decl): ChirType {
    if (let Some(varDecl) <- (decl as VarDecl)) {
        return lowerValueType(context, varDecl.typeNode)
    }
    return context.GetInt64Ty()
}

private func lowerValueType(context: ChirContext, sourceType: Option<Type>): ChirType {
    if (let Some(typeNode) <- sourceType) {
        if (typeNode.name == "Bool" || typeNode.name == "bool") { return context.GetBoolTy() }
        if (typeNode.name == "Rune" || typeNode.name == "rune") { return context.GetRuneTy() }
        if (typeNode.name == "Int8" || typeNode.name == "int8") { return context.GetInt8Ty() }
        if (typeNode.name == "Int16" || typeNode.name == "int16") { return context.GetInt16Ty() }
        if (typeNode.name == "Int32" || typeNode.name == "int32") { return context.GetInt32Ty() }
        if (typeNode.name == "Int64" || typeNode.name == "Int" || typeNode.name == "int64") {
            return context.GetInt64Ty()
        }
        if (typeNode.name == "UInt8" || typeNode.name == "uint8") { return context.GetUInt8Ty() }
        if (typeNode.name == "UInt16" || typeNode.name == "uint16") { return context.GetUInt16Ty() }
        if (typeNode.name == "UInt32" || typeNode.name == "uint32") { return context.GetUInt32Ty() }
        if (typeNode.name == "UInt64" || typeNode.name == "uint64") { return context.GetUInt64Ty() }
        if (typeNode.name == "Float16" || typeNode.name == "float16") { return context.GetFloat16Ty() }
        if (typeNode.name == "Float32" || typeNode.name == "float32") { return context.GetFloat32Ty() }
        if (typeNode.name == "Float64" || typeNode.name == "float64") { return context.GetFloat64Ty() }
        if (typeNode.name == "CString") { return context.GetCStringTy() }
        if (typeNode.name == "Unit" || typeNode.name == "()") { return context.GetUnitTy() }
    }
    return context.GetInt64Ty()
}

private func stableMangledName(pkg: Package, decl: Decl): String {
    if (decl.astKind == ASTKind.MAIN_DECL) {
        return "user.main"
    }
    if (!decl.mangledName.isEmpty()) {
        return decl.mangledName
    }
    let identifier = if (decl.identifier.Empty()) {
        ASTKindName(decl.astKind) + "_" + decl.begin.line.toString() + "_" + decl.begin.column.toString()
    } else {
        decl.identifier.Val()
    }
    return "_C" + (pkg.fullPackageName + "." + identifier).replace(".", "_").replace("::", "_")
}

private func toChirAccessLevel(level: AccessLevel): ChirAccessLevel {
    return match (level) {
        case AccessLevel.PUBLIC => ChirAccessLevel.PUBLIC
        case AccessLevel.PROTECTED => ChirAccessLevel.PROTECTED
        case AccessLevel.INTERNAL => ChirAccessLevel.INTERNAL
        case AccessLevel.PRIVATE => ChirAccessLevel.INTERNAL
    }
}

private func toChirNominalKind(decl: Decl): ChirNominalKind {
    if (decl.astKind == ASTKind.CLASS_DECL) { return ChirNominalKind.CLASS }
    if (decl.astKind == ASTKind.INTERFACE_DECL) { return ChirNominalKind.INTERFACE }
    if (decl.astKind == ASTKind.STRUCT_DECL) { return ChirNominalKind.STRUCT }
    if (decl.astKind == ASTKind.ENUM_DECL) { return ChirNominalKind.ENUM }
    return ChirNominalKind.EXTEND
}

private func toChirFuncKind(decl: Decl): ChirFuncKind {
    if (decl.astKind == ASTKind.MAIN_DECL) { return ChirFuncKind.MAIN_ENTRY }
    if (decl.astKind == ASTKind.MACRO_DECL) { return ChirFuncKind.MACRO_FUNC }
    if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL) { return ChirFuncKind.PRIMAL_CLASS_CONSTRUCTOR }
    return ChirFuncKind.DEFAULT
}

private func applyDeclAttributes(decl: Decl, spec: ChirFunctionSpec): Unit {
    addVisibilityAttributes(decl, spec)
    addCommonAttributes(decl, spec)
}

private func applyDeclAttributes(decl: Decl, spec: ChirGlobalSpec): Unit {
    addVisibilityAttributes(decl, spec)
    addCommonAttributes(decl, spec)
}

private func applyDeclAttributes(decl: Decl, spec: ChirNominalSpec): Unit {
    addVisibilityAttributes(decl, spec)
    addCommonAttributes(decl, spec)
}

private func applyDeclAttributes(decl: Decl, spec: ChirMemberVarSpec): Unit {
    addVisibilityAttributes(decl, spec)
    addCommonAttributes(decl, spec)
}

private func addVisibilityAttributes(decl: Decl, spec: ChirFunctionSpec): Unit {
    if (decl.IsExportedDecl()) { spec.AddAttribute(ChirAttribute.PUBLIC) } else { spec.AddAttribute(ChirAttribute.PRIVATE) }
}

private func addVisibilityAttributes(decl: Decl, spec: ChirGlobalSpec): Unit {
    if (decl.IsExportedDecl()) { spec.AddAttribute(ChirAttribute.PUBLIC) } else { spec.AddAttribute(ChirAttribute.PRIVATE) }
}

private func addVisibilityAttributes(decl: Decl, spec: ChirNominalSpec): Unit {
    if (decl.IsExportedDecl()) { spec.AddAttribute(ChirAttribute.PUBLIC) } else { spec.AddAttribute(ChirAttribute.PRIVATE) }
}

private func addVisibilityAttributes(decl: Decl, spec: ChirMemberVarSpec): Unit {
    if (decl.IsExportedDecl()) { spec.AddAttribute(ChirAttribute.PUBLIC) } else { spec.AddAttribute(ChirAttribute.PRIVATE) }
}

private func addCommonAttributes(decl: Decl, spec: ChirFunctionSpec): Unit {
    if (decl.TestAttr("FOREIGN") || decl.TestAttr("C")) { spec.AddAttribute(ChirAttribute.FOREIGN) }
    if (decl.TestAttr("STATIC")) { spec.AddAttribute(ChirAttribute.STATIC) }
    if (decl.TestAttr("MUT")) { spec.AddAttribute(ChirAttribute.MUT) }
}

private func addCommonAttributes(decl: Decl, spec: ChirGlobalSpec): Unit {
    if (decl.TestAttr("STATIC")) { spec.AddAttribute(ChirAttribute.STATIC) }
    if (decl.TestAttr("CONST")) { spec.AddAttribute(ChirAttribute.CONST) }
}

private func addCommonAttributes(decl: Decl, spec: ChirNominalSpec): Unit {
    if (decl.TestAttr("ABSTRACT")) { spec.AddAttribute(ChirAttribute.ABSTRACT) }
    if (decl.TestAttr("GENERIC_INSTANTIATED")) { spec.AddAttribute(ChirAttribute.GENERIC_INSTANTIATED) }
}

private func addCommonAttributes(decl: Decl, spec: ChirMemberVarSpec): Unit {
    if (decl.TestAttr("STATIC")) { spec.AddAttribute(ChirAttribute.STATIC) }
    if (decl.TestAttr("CONST")) { spec.AddAttribute(ChirAttribute.CONST) }
}

private func copyStrings(source: ArrayList<String>, target: ArrayList<String>): Unit {
    for (value in source) {
        target.add(value)
    }
}

private func copyStringSet(source: HashSet<String>, target: HashSet<String>): Unit {
    for (value in source) {
        target.add(value)
    }
}

private func copyStringMap(source: HashMap<String, String>, target: HashMap<String, String>): Unit {
    for ((key, value) in source) {
        target.add(key, value)
    }
}
