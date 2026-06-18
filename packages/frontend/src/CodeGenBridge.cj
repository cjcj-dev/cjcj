package cangjie_compiler::frontend

import std.collection.*
import std.convert.*
import cangjie_compiler::chir.AccessLevel as ChirAccessLevel
import cangjie_compiler::chir.AST2CHIR as ChirAST2CHIR
import cangjie_compiler::chir.AST2CHIRFunctionSpec as ChirFunctionSpec
import cangjie_compiler::chir.AST2CHIRGlobalSpec as ChirGlobalSpec
import cangjie_compiler::chir.AST2CHIRMemberVarSpec as ChirMemberVarSpec
import cangjie_compiler::chir.AST2CHIRNominalKind as ChirNominalKind
import cangjie_compiler::chir.AST2CHIRNominalSpec as ChirNominalSpec
import cangjie_compiler::chir.AST2CHIRPackageSpec as ChirPackageSpec
import cangjie_compiler::chir.AST2CHIRStmtSpec as ChirStmtSpec
import cangjie_compiler::chir.Attribute as ChirAttribute
import cangjie_compiler::chir.CHIRBuilder as ChirBuilder
import cangjie_compiler::chir.CHIRPrinter as ChirCHIRPrinter
import cangjie_compiler::chir.CHIRContext as ChirContext
import cangjie_compiler::chir.FuncKind as ChirFuncKind
import cangjie_compiler::chir.Package as RealCHIRPackage
import cangjie_compiler::chir.Type as ChirType
import cangjie_compiler::codegen.CHIRData as CodegenCHIRData
import cangjie_compiler::codegen.ClearPackageModules
import cangjie_compiler::codegen.GenPackageModules
import cangjie_compiler::codegen.LLVMModuleHandle as LLVMModuleHandle
import cangjie_compiler::codegen.SavePackageModule
import cangjie_compiler::option.MaybeUInt64

public func BuildRealCHIRForFrontendPackage(instance: CompilerInstance, pkg: Package): Option<RealCHIRPackage> {
    let builder = ChirBuilder(instance.chirData.GetRealCHIRContext())
    let packageSpec = buildRealPackageSpec(pkg, builder.context)
    let lowered = ChirAST2CHIR(builder).LowerPackage(packageSpec).pkg
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
    let codegenOptions = ConvertFrontendOptionsToCodegenOptions(instance.invocation.globalOptions)
    let savedAPC = codegenOptions.aggressiveParallelCompile
    if (ShouldEmitSingleExplicitBitcodeOutput(codegenOptions)) {
        codegenOptions.aggressiveParallelCompile = MaybeUInt64(1u64)
    }
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
    codegenOptions.aggressiveParallelCompile = savedAPC
    return emittedAll
}

public func ConvertFrontendOptionsToCodegenOptions(options: GlobalOptions): GlobalOptions {
    return options
}

private func ShouldEmitSingleExplicitBitcodeOutput(options: GlobalOptions): Bool {
    return !options.output.isEmpty() && !IsDir(options.output) && options.output.endsWith(".bc")
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
    var sourceReturnType: Option<Type> = None
    var hasSourceLiteralReturn = false
    var sourceLiteralReturnKind = FRONTEND_LITERAL_UNKNOWN
    var sourceLiteralReturnValue = ""
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        for (param in funcDecl.funcBody.params) {
            paramTypes.add(lowerValueType(context, param.typeNode))
        }
        sourceReturnType = funcDecl.funcBody.retType
        hasSourceLiteralReturn = funcDecl.funcBody.hasLiteralReturn
        sourceLiteralReturnKind = funcDecl.funcBody.literalReturnKind
        sourceLiteralReturnValue = funcDecl.funcBody.literalReturnValue
    }
    var hasSourceRealBody = false
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        hasSourceRealBody = funcDecl.funcBody.hasRealBody
    }
    let fnName = stableMangledName(pkg, decl)
    // When a real body is present the return type comes straight from the parsed retType
    // (Int64 here) via lowerValueType, bypassing the literal-return special casing. The frontend
    // summary parser does not reliably populate retType, so when it is absent we infer Unit vs
    // Int64 from the body itself: a body with a value-returning `return <expr>` is Int64; one with
    // no value-returning return (e.g. `main() { ...; println(s) }`) is Unit. This matches the body's
    // emitted terminator (Exit(Some) -> ret i64 vs Exit(None) -> ret void).
    let returnTy = if (hasSourceRealBody) {
        match (sourceReturnType) {
            case Some(_) => lowerValueType(context, sourceReturnType)
            case None => if (realBodyReturnsValue(decl)) {
                context.GetInt64Ty()
            } else {
                context.GetUnitTy()
            }
        }
    } else {
        lowerFunctionReturnType(context, sourceReturnType, hasSourceLiteralReturn, sourceLiteralReturnKind,
            sourceLiteralReturnValue)
    }
    let fnSpec = ChirFunctionSpec(fnName, paramTypes, returnTy,
        srcCodeIdentifier: decl.identifier.Val(), rawMangledName: fnName,
        packageName: pkg.fullPackageName, funcKind: toChirFuncKind(decl), emitBody: true)
    if (hasSourceRealBody) {
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            applyRealBody(fnSpec, funcDecl.funcBody)
        }
    } else if (hasSourceLiteralReturn) {
        setLiteralReturn(fnSpec, sourceLiteralReturnKind, sourceLiteralReturnValue)
    }
    applyDeclAttributes(decl, fnSpec)
    if (!sourceFileKey.isEmpty()) {
        fnSpec.SetSourceFileKey(sourceFileKey)
    }
    if (let Some(namedFuncDecl) <- (decl as FuncDecl)) {
        for (paramDecl in namedFuncDecl.funcBody.params) {
            let paramName = if (paramDecl.identifier.Empty()) { "%arg" } else { paramDecl.identifier.Val() }
            fnSpec.AddParamName(paramName)
        }
        var printIdx = 0
        // Suppress the entry-block side-channel string prints when the body was promoted to the real
        // path: the real body now emits ALL of its prints (literal and runtime) as ordered in-body
        // calls, so forwarding printStrings here would double-print the literal ones.
        let suppressSideChannel = hasSourceRealBody
        for (printString in namedFuncDecl.funcBody.printStrings) {
            if (suppressSideChannel) {
                break
            }
            let newline = if (printIdx < namedFuncDecl.funcBody.printNewlines.size) {
                namedFuncDecl.funcBody.printNewlines[printIdx]
            } else {
                true
            }
            let isInt = if (printIdx < namedFuncDecl.funcBody.printIsInt.size) {
                namedFuncDecl.funcBody.printIsInt[printIdx]
            } else {
                false
            }
            fnSpec.AddPrintString(printString, newline: newline, isInt: isInt)
            printIdx++
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
        // String on the real body-lowering path is modeled as a CString (i8*) value, so String params
        // and String return types lower to CString -- keeping the whole real-body String signature
        // consistent with how literals, concat, and prints materialize String values.
        if (typeNode.name == "String") { return context.GetCStringTy() }
        if (typeNode.name == "Unit" || typeNode.name == "()") { return context.GetUnitTy() }
    }
    return context.GetInt64Ty()
}

private func lowerFunctionReturnType(
    context: ChirContext,
    sourceReturnType: Option<Type>,
    hasLiteralReturn: Bool,
    literalReturnKind: Int64,
    literalReturnValue: String
): ChirType {
    if (hasLiteralReturn) {
        if (literalReturnCanLower(literalReturnKind, literalReturnValue, sourceReturnType)) {
            if (let Some(_) <- sourceReturnType) {
                return lowerValueType(context, sourceReturnType)
            }
            return inferLiteralReturnType(context, literalReturnKind)
        }
    }
    if (let None <- sourceReturnType) {
        return context.GetUnitTy()
    }
    return context.GetVoidTy()
}

private func inferLiteralReturnType(context: ChirContext, literalReturnKind: Int64): ChirType {
    if (literalReturnKind == FRONTEND_LITERAL_BOOL) { return context.GetBoolTy() }
    if (literalReturnKind == FRONTEND_LITERAL_INT) { return context.GetInt64Ty() }
    if (literalReturnKind == FRONTEND_LITERAL_FLOAT) { return context.GetFloat64Ty() }
    if (literalReturnKind == FRONTEND_LITERAL_UNIT) { return context.GetUnitTy() }
    if (literalReturnKind == FRONTEND_LITERAL_RUNE) { return context.GetRuneTy() }
    return context.GetUnitTy()
}

private func literalReturnCanLower(literalReturnKind: Int64, literalReturnValue: String, sourceReturnType: Option<Type>): Bool {
    if (let Some(typeNode) <- sourceReturnType) {
        let typeName = typeNode.name
        if (literalReturnKind == FRONTEND_LITERAL_BOOL) { return isBoolTypeName(typeName) }
        if (literalReturnKind == FRONTEND_LITERAL_INT) {
            return isIntegerTypeName(typeName) && tryParseIntLiteral(literalReturnValue).isSome()
        }
        if (literalReturnKind == FRONTEND_LITERAL_FLOAT) {
            return isFloatTypeName(typeName) && tryParseFloatLiteral(literalReturnValue).isSome()
        }
        if (literalReturnKind == FRONTEND_LITERAL_UNIT) { return isUnitTypeName(typeName) }
        if (literalReturnKind == FRONTEND_LITERAL_RUNE) { return isRuneTypeName(typeName) }
        return false
    }
    if (literalReturnKind == FRONTEND_LITERAL_INT) {
        return tryParseIntLiteral(literalReturnValue).isSome()
    }
    if (literalReturnKind == FRONTEND_LITERAL_FLOAT) {
        return tryParseFloatLiteral(literalReturnValue).isSome()
    }
    return literalReturnKind == FRONTEND_LITERAL_BOOL || literalReturnKind == FRONTEND_LITERAL_UNIT ||
        literalReturnKind == FRONTEND_LITERAL_RUNE
}

// Hand the frontend FuncBody's real-body statement spec tree (built directly by the real-parser
// adapter in RealParseBridge.cj) to the CHIR function spec and enable the real body. The tree is
// already in CHIR's recursive AST2CHIRStmtSpec form, so no per-statement translation is needed.
// Does the real body of `decl` contain a value-returning `return <expr>` (possibly nested in an
// `if`/`while`)? Used to infer Unit vs Int64 when the frontend summary did not record a return type.
private func realBodyReturnsValue(decl: Decl): Bool {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        return stmtsReturnValue(funcDecl.funcBody.realStatements)
    }
    return false
}

private func stmtsReturnValue(stmts: ArrayList<ChirStmtSpec>): Bool {
    for (stmt in stmts) {
        if (stmt.IsReturn() && stmt.expr.isSome()) {
            return true
        }
        if (stmt.IsIf() || stmt.IsWhile() || stmt.IsFor()) {
            if (stmtsReturnValue(stmt.thenBody) || stmtsReturnValue(stmt.elseBody)) {
                return true
            }
        }
    }
    return false
}

private func applyRealBody(fnSpec: ChirFunctionSpec, funcBody: FuncBody): Unit {
    fnSpec.EnableRealBody()
    for (stmt in funcBody.realStatements) {
        fnSpec.AddBodyStatement(stmt)
    }
}

private func setLiteralReturn(fnSpec: ChirFunctionSpec, literalReturnKind: Int64, literalReturnValue: String): Unit {
    if (literalReturnKind == FRONTEND_LITERAL_BOOL) {
        fnSpec.SetBoolLiteralReturn(literalReturnValue == "true")
        return
    }
    if (literalReturnKind == FRONTEND_LITERAL_INT) {
        if (let Some(parsedIntValue) <- tryParseIntLiteral(literalReturnValue)) {
            fnSpec.SetIntLiteralReturn(parsedIntValue)
        }
        return
    }
    if (literalReturnKind == FRONTEND_LITERAL_FLOAT) {
        if (let Some(parsedFloatValue) <- tryParseFloatLiteral(literalReturnValue)) {
            fnSpec.SetFloatLiteralReturn(parsedFloatValue)
        }
        return
    }
    if (literalReturnKind == FRONTEND_LITERAL_UNIT) {
        fnSpec.SetUnitLiteralReturn()
    }
}

private func tryParseIntLiteral(value: String): Option<Int64> {
    let normalized = value.replace("_", "")
    try {
        return Some(Int64.parse(normalized))
    } catch (e: Exception) {
        return None
    }
}

private func tryParseFloatLiteral(value: String): Option<Float64> {
    let normalized = value.replace("_", "")
    try {
        return Some(Float64.parse(normalized))
    } catch (e: Exception) {
        return None
    }
}

private func isBoolTypeName(name: String): Bool {
    return name == "Bool" || name == "bool"
}

private func isRuneTypeName(name: String): Bool {
    return name == "Rune" || name == "rune"
}

private func isUnitTypeName(name: String): Bool {
    return name == "Unit" || name == "()"
}

private func isIntegerTypeName(name: String): Bool {
    return name == "Int8" || name == "int8" || name == "Int16" || name == "int16" ||
        name == "Int32" || name == "int32" || name == "Int64" || name == "Int" || name == "int64" ||
        name == "UInt8" || name == "uint8" || name == "UInt16" || name == "uint16" ||
        name == "UInt32" || name == "uint32" || name == "UInt64" || name == "uint64"
}

private func isFloatTypeName(name: String): Bool {
    return name == "Float16" || name == "float16" || name == "Float32" || name == "float32" ||
        name == "Float64" || name == "float64"
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
