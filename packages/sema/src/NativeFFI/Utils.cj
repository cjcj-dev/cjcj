package cjcj::sema.NativeFFI

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.LambdaPattern as BasicLambdaPattern
import cjcj::mangle.BaseMangler
import cjcj::modules.ImportManager
import cjcj::option.GetFileName as OptionGetFileName
import cjcj::option.IsDir as OptionIsDir
import cjcj::sema.TypeManager
import cjcj::utils.{CJC_ABORT, CJC_ABORT_WITH_MSG, CJC_ASSERT, CJC_ASSERT_WITH_MSG, CJC_NULLPTR_CHECK}

public let NSSTRING_CLASS_IDENT: String = "NSString"
public let NSOBJECT_CLASS_IDENT: String = "NSObject"
public let TOSTRING_METHOD_IDENT: String = "toString"
public let INIT_IDENT: String = "init"
private let STD_LIB_STRING_IDENT: String = "String"
private let INTEROP_JARRAY_NAME: String = "JArray"
private let INTEROP_JAVA_LANG_PACKAGE: String = "java.lang"
private let JAVA_ARRAY_GET_FOR_REF_TYPES: String = "$javaarrayget"
private let JAVA_ARRAY_SET_FOR_REF_TYPES: String = "$javaarrayset"
private let ARRAY_SUBSCRIPT_IDENT: String = "[]"
private let ARRAY_LENGTH_IDENT: String = "length"

public enum ArrayOperationKind {
    | CREATE
    | GET
    | SET
    | GET_LENGTH
}

private func ArrayOperationKindIndex(kind: ArrayOperationKind): Int64 {
    return match (kind) {
        case ArrayOperationKind.CREATE => 0
        case ArrayOperationKind.GET => 1
        case ArrayOperationKind.SET => 2
        case ArrayOperationKind.GET_LENGTH => 3
    }
}

extend ArrayOperationKind <: Equatable<ArrayOperationKind> {
    public operator func ==(right: ArrayOperationKind): Bool {
        return ArrayOperationKindIndex(this) == ArrayOperationKindIndex(right)
    }

    public operator func !=(right: ArrayOperationKind): Bool {
        return !(this == right)
    }
}

public class GenericConfigInfo {
    public var declSymbolName: String
    public var declInstName: String
    public let instTypes: ArrayList<(String, String)> = ArrayList<(String, String)>()
    public let funcNames: HashSet<String> = HashSet<String>()

    public init(name: String, declInstName: String, insts: ArrayList<(String, String)>, funcs: HashSet<String>) {
        declSymbolName = name
        this.declInstName = declInstName
        for (inst in insts) {
            instTypes.add(inst)
        }
        for (funcName in funcs) {
            funcNames.add(funcName)
        }
    }
}

public func GetParamTys(params: FuncParamList): ArrayList<Ty> {
    let paramTys = ArrayList<Ty>()
    for (param in params.params) {
        if (let Some(ty) <- param.GetTy()) {
            paramTys.add(ty)
        }
    }
    return paramTys
}

public func CreateThisRef(target: Option<Decl>, ty: Option<Ty>, curFile: Option<File>): RefExpr {
    let thisRef = RefExpr()
    thisRef.isThis = true
    thisRef.ref.identifier = SrcIdentifier("this")
    thisRef.ref.target = target
    thisRef.curFile = curFile
    if (let Some(value) <- ty) {
        thisRef.SetTy(value)
    }
    return thisRef
}

public func CreateThisRef(target: Decl, ty: Ty, curFile: File): RefExpr {
    return CreateThisRef(Some(target), Some(ty), Some(curFile))
}

public func CreateSuperRef(target: Option<Decl>, ty: Option<Ty>): RefExpr {
    let superRef = RefExpr()
    superRef.isSuper = true
    superRef.ref.identifier = SrcIdentifier("super")
    superRef.ref.target = target
    if (let Some(value) <- ty) {
        superRef.SetTy(value)
    }
    return superRef
}

public func CreateSuperRef(target: Decl, ty: Ty): RefExpr {
    return CreateSuperRef(Some(target), Some(ty))
}

public func CreateThisCall(target: Decl, baseTarget: FuncDecl, funcTy: Ty, curFile: File): CallExpr {
    return CreateThisCall(target, baseTarget, funcTy, curFile, ArrayList<FuncArg>())
}

public func CreateThisCall(target: Decl, baseTarget: FuncDecl, funcTy: Ty, curFile: File,
    args: ArrayList<FuncArg>): CallExpr {
    let callExpr = CreateCallExpr(CreateThisRef(baseTarget, funcTy, curFile), args)
    callExpr.callKind = CallKind.CALL_OBJECT_CREATION
    if (let Some(targetTy) <- target.GetTy()) {
        callExpr.SetTy(targetTy)
    }
    callExpr.resolvedFunction = baseTarget
    return callExpr
}

public func CreateSuperCall(target: Decl, baseTarget: FuncDecl, funcTy: Ty): CallExpr {
    let callExpr = CreateCallExpr(CreateSuperRef(baseTarget, funcTy), ArrayList<FuncArg>())
    callExpr.callKind = CallKind.CALL_SUPER_FUNCTION
    if (let Some(targetTy) <- target.GetTy()) {
        callExpr.SetTy(targetTy)
    }
    callExpr.resolvedFunction = baseTarget
    return callExpr
}

public func CreateUnitType(curFile: Option<File>): PrimitiveType {
    let unitType = PrimitiveType()
    unitType.str = "Unit"
    unitType.kind = TypeKind.TYPE_UNIT
    unitType.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
    unitType.curFile = curFile
    return unitType
}

public func CreateUnitType(curFile: File): PrimitiveType {
    return CreateUnitType(Some(curFile))
}

public func CreateType(ty: Ty): Type {
    let typeNode = Type()
    typeNode.SetTy(ty)
    return typeNode
}

public func CreateFuncType(ty: FuncTy): FuncType {
    let typeNode = FuncType()
    typeNode.SetTy(ty)
    for (paramTy in ty.paramTys) {
        typeNode.paramTypes.add(CreateType(paramTy))
    }
    typeNode.retType = CreateType(ty.retTy)
    return typeNode
}

public func WithinFile<T>(node: T, curFile: Option<File>): T where T <: Node {
    CJC_NULLPTR_CHECK(curFile)
    node.curFile = curFile
    return node
}

public func WithinFile<T>(node: T, curFile: File): T where T <: Node {
    return WithinFile<T>(node, Some(curFile))
}

private func WrapArg(funcArgs: ArrayList<FuncArg>, e: FuncArg): Unit {
    funcArgs.add(e)
}

private func WrapArg(funcArgs: ArrayList<FuncArg>, e: Expr): Unit {
    funcArgs.add(CreateFuncArg(e))
}

public func CreateCall(fd: Option<FuncDecl>, curFile: Option<File>,
    args!: ArrayList<FuncArg> = ArrayList<FuncArg>()): Option<CallExpr> {
    if (let None <- fd) {
        return None
    }

    let funcDecl = fd.getOrThrow()
    let funcTy = (funcDecl.GetTy().getOrThrow() as FuncTy).getOrThrow()
    return CreateCallExpr(WithinFile<RefExpr>(CreateRefExpr(funcDecl), curFile), args, fd, funcTy.retTy,
        CallKind.CALL_DECLARED_FUNCTION)
}

public func CreateCall(fd: FuncDecl, curFile: File,
    args!: ArrayList<FuncArg> = ArrayList<FuncArg>()): CallExpr {
    return CreateCall(Some(fd), Some(curFile), args: args).getOrThrow()
}

public func CreateCall(fd: FuncDecl, curFile: File, arg: Expr): CallExpr {
    let funcArgs = ArrayList<FuncArg>()
    WrapArg(funcArgs, arg)
    return CreateCall(fd, curFile, args: funcArgs)
}

public func CreateCall(fd: FuncDecl, curFile: File, arg: FuncArg): CallExpr {
    let funcArgs = ArrayList<FuncArg>()
    WrapArg(funcArgs, arg)
    return CreateCall(fd, curFile, args: funcArgs)
}

public func CreateCall(fd: FuncDecl, curFile: File, first: Expr, second: Expr): CallExpr {
    let funcArgs = ArrayList<FuncArg>()
    WrapArg(funcArgs, first)
    WrapArg(funcArgs, second)
    return CreateCall(fd, curFile, args: funcArgs)
}

public func CreateCall(fd: FuncDecl, curFile: File, first: Expr, second: Expr, third: Expr): CallExpr {
    let funcArgs = ArrayList<FuncArg>()
    WrapArg(funcArgs, first)
    WrapArg(funcArgs, second)
    WrapArg(funcArgs, third)
    return CreateCall(fd, curFile, args: funcArgs)
}

public func CreateMemberCall(receiver: Option<Expr>, fd: Option<FuncDecl>,
    args!: ArrayList<FuncArg> = ArrayList<FuncArg>()): Option<CallExpr> {
    CJC_NULLPTR_CHECK(receiver)
    CJC_NULLPTR_CHECK(fd)
    let funcDecl = fd.getOrThrow()
    let funcTy = (funcDecl.GetTy().getOrThrow() as FuncTy).getOrThrow()
    let memberAccess = CreateMemberAccess(receiver.getOrThrow(), funcDecl)
    if (let Some(baseExpr) <- memberAccess.baseExpr) {
        CopyBasicInfo(baseExpr, memberAccess)
    }
    return CreateCallExpr(memberAccess, args, fd, funcTy.retTy, CallKind.CALL_DECLARED_FUNCTION)
}

public func CreateMemberCall(receiver: Expr, fd: FuncDecl,
    args!: ArrayList<FuncArg> = ArrayList<FuncArg>()): CallExpr {
    return CreateMemberCall(Some(receiver), Some(fd), args: args).getOrThrow()
}

public func CreateMemberCall(receiver: Expr, fd: FuncDecl, arg: Expr): CallExpr {
    let funcArgs = ArrayList<FuncArg>()
    WrapArg(funcArgs, arg)
    return CreateMemberCall(receiver, fd, args: funcArgs)
}

public func CreateMemberCall(receiver: Expr, fd: FuncDecl, arg: FuncArg): CallExpr {
    let funcArgs = ArrayList<FuncArg>()
    WrapArg(funcArgs, arg)
    return CreateMemberCall(receiver, fd, args: funcArgs)
}

public func CreateBoolMatch(selector: Expr, trueBranch: Expr, falseBranch: Expr, ty: Ty): Expr {
    let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
    let truePattern = ConstPattern()
    truePattern.literal = CreateLitConstExpr(LitConstKind.BOOL, "true", boolTy)
    truePattern.SetTy(boolTy)

    let falsePattern = ConstPattern()
    falsePattern.literal = CreateLitConstExpr(LitConstKind.BOOL, "false", boolTy)
    falsePattern.SetTy(boolTy)

    let matchCases = ArrayList<MatchCase>()
    matchCases.add(CreateMatchCase(truePattern, trueBranch))
    matchCases.add(CreateMatchCase(falsePattern, falseBranch))
    let matchExpr = CreateMatchExpr(selector, matchCases, ty)
    AddCurFile(matchExpr, file: selector.curFile)
    return matchExpr
}

public func GetStringDecl(importManager: ImportManager): StructDecl {
    let decl = importManager.GetCoreDecl(STD_LIB_STRING_IDENT)
    CJC_NULLPTR_CHECK(decl)
    return (decl.getOrThrow() as StructDecl).getOrThrow()
}

private func LambdaParamTys(params: ArrayList<FuncParam>): ArrayList<Ty> {
    let paramTys = ArrayList<Ty>()
    for (param in params) {
        paramTys.add(param.GetTy().getOrThrow())
    }
    return paramTys
}

private func BuildReturningLambdaBody(nodes: ArrayList<Node>, retTy: Ty): (ArrayList<Node>, Expr) {
    let bodyNodes = ArrayList<Node>()
    for (idx in 0..nodes.size - 1) {
        bodyNodes.add(nodes[idx])
    }
    CJC_ASSERT((nodes[nodes.size - 1] as Expr).isSome())
    let lastExpr = (nodes[nodes.size - 1] as Expr).getOrThrow()
    var retValue = lastExpr
    if (let Some(cloned) <- (ASTCloner.Clone(lastExpr) as Expr)) {
        retValue = cloned
    }
    let unsafeNodes = ArrayList<Node>()
    unsafeNodes.add(retValue)
    let unsafeBlock = CreateBlock(unsafeNodes, retTy)
    unsafeBlock.EnableAttr(Attribute.UNSAFE)
    return (bodyNodes, unsafeBlock)
}

public func WrapReturningLambdaCall(typeManager: TypeManager, nodes: ArrayList<Node>): CallExpr {
    CJC_ASSERT_WITH_MSG(!nodes.isEmpty(), "cannot create lambda with empty body")
    let retTy = nodes[nodes.size - 1].GetTy().getOrThrow()
    let lambda = WrapReturningLambdaExpr(typeManager, nodes)
    return CreateCallExpr(lambda, ArrayList<FuncArg>(), None, retTy, CallKind.CALL_INVALID)
}

public func WrapReturningLambdaExpr(typeManager: TypeManager, nodes: ArrayList<Node>,
    lambdaParams!: ArrayList<FuncParam> = ArrayList<FuncParam>()): LambdaExpr {
    CJC_ASSERT(!nodes.isEmpty())
    let retTy = nodes[nodes.size - 1].GetTy().getOrThrow()
    let paramTys = LambdaParamTys(lambdaParams)
    let paramLists = ArrayList<FuncParamList>()
    paramLists.add(CreateFuncParamList(lambdaParams))
    let lambdaTy = typeManager.GetFunctionTy(paramTys.toArray(), retTy)
    let curFile: Option<File> = nodes[0].curFile

    let bodyParts = BuildReturningLambdaBody(nodes, retTy)
    let body = CreateBlock(bodyParts[0], retTy)
    let funcBody = CreateFuncBody(paramLists, None, body, lambdaTy)
    let retExpr = CreateReturnExpr(bodyParts[1], funcBody)
    retExpr.SetTy(TypeManager.GetNothingTy())
    if (let Some(value) <- funcBody.body) {
        value.body.add(retExpr)
    }
    let lambda = CreateLambdaExpr(funcBody)
    lambda.curFile = curFile
    lambda.SetTy(lambdaTy)
    return lambda
}

public func IsJArray(decl: Decl): Bool {
    if ((decl as ClassLikeDecl).isNone()) {
        return false
    }
    if (!decl.TestAttr(Attribute.JAVA_MIRROR)) {
        return false
    }
    if (decl.identifier.Val() != INTEROP_JARRAY_NAME || decl.fullPackageName != INTEROP_JAVA_LANG_PACKAGE) {
        return false
    }
    if (let Some(attr) <- GetSingleArgumentAnnotationValue(decl, AstAnnotationKind.JAVA_MIRROR)) {
        return attr == ARRAY_SUBSCRIPT_IDENT
    }
    return false
}

public func IsJArray(ty: Ty): Bool {
    if (let Some(classLikeTy) <- (ty as ClassLikeTy)) {
        if (let Some(decl) <- classLikeTy.commonDecl) {
            return IsJArray(decl)
        }
    }
    return false
}

public func GetArrayOperationKind(decl: Decl): ArrayOperationKind {
    CJC_ASSERT(IsJArray(decl.outerDecl.getOrThrow()))
    if (let Some(propDecl) <- (decl as PropDecl)) {
        if (propDecl.identifier.Val() == ARRAY_LENGTH_IDENT) {
            return ArrayOperationKind.GET_LENGTH
        }
    }
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        let funcName = funcDecl.identifier.Val()
        if (funcName == ARRAY_SUBSCRIPT_IDENT) {
            let paramsNumber = funcDecl.funcBody.getOrThrow().paramLists[0].params.size
            if (paramsNumber == 1) {
                return ArrayOperationKind.GET
            } else if (paramsNumber == 2) {
                return ArrayOperationKind.SET
            }
        }
        if (funcName == JAVA_ARRAY_GET_FOR_REF_TYPES) {
            return ArrayOperationKind.GET
        }
        if (funcName == JAVA_ARRAY_SET_FOR_REF_TYPES) {
            return ArrayOperationKind.SET
        }
    }
    CJC_ABORT()
    return ArrayOperationKind.GET
}

public func GetCangjieLibName(outputLibPath: String, fullPackageName: String, trimmed!: Bool = true): String {
    if (OptionIsDir(outputLibPath)) {
        return fullPackageName
    }
    let outputFileName = OptionGetFileName(outputLibPath)
    let libPrefix = "lib"
    if (outputFileName.startsWith(libPrefix)) {
        if (!trimmed) {
            return outputFileName
        }
        if (let Some(extIdx) <- outputFileName.lastIndexOf(".")) {
            return outputFileName[libPrefix.size..extIdx]
        }
        return fullPackageName
    }
    return fullPackageName
}

public func GetAnnotation(decl: Decl, annotationKind: AstAnnotationKind): Option<Annotation> {
    for (annotation in decl.annotations) {
        if (annotation.kind == annotationKind) {
            return Some(annotation)
        }
    }
    return None
}

public func GetForeignNameAnnotation(decl: Decl): Option<Annotation> {
    return GetAnnotation(decl, AstAnnotationKind.FOREIGN_NAME)
}

public func GetSingleArgumentAnnotationValue(target: Decl, annotationKind: AstAnnotationKind): Option<String> {
    for (annotation in target.annotations) {
        if (annotation.kind != annotationKind) {
            continue
        }
        if (annotation.args.size != 1) {
            break
        }
        if (let Some(expr) <- annotation.args[0].expr) {
            if (let Some(lit) <- (expr as LitConstExpr)) {
                return Some(lit.stringValue)
            }
        }
        break
    }
    return None
}

public func GetObjCMirrorForeignName(target: ClassLikeDecl): String {
    if (let Some(customName) <- GetSingleArgumentAnnotationValue(target, AstAnnotationKind.OBJ_C_MIRROR)) {
        return customName
    }
    return target.identifier.Val()
}

public func IsSuperConstructorCall(call: CallExpr): Bool {
    if (let Some(base) <- call.baseFunc) {
        if (let Some(refExpr) <- (base as RefExpr)) {
            return refExpr.isSuper && call.callKind == CallKind.CALL_SUPER_FUNCTION
        }
    }
    return false
}

public func IsThisConstructorCall(call: CallExpr): Bool {
    if (let Some(base) <- call.baseFunc) {
        if (let Some(refExpr) <- (base as RefExpr)) {
            return refExpr.isThis && call.callKind == CallKind.CALL_DECLARED_FUNCTION
        }
    }
    return false
}

public func IsObjCGeneratedNSStringCtor(target: Decl): Bool {
    if (let Some(funcDecl) <- (target as FuncDecl)) {
        if (funcDecl.identifier.Val() != INIT_IDENT ||
            !funcDecl.TestAttr(Attribute.CONSTRUCTOR) || !funcDecl.TestAttr(Attribute.COMPILER_ADD)) {
            return false
        }
        if (let Some(body) <- funcDecl.funcBody) {
            if (body.paramLists.isEmpty()) {
                return false
            }
            let params = body.paramLists[0].params
            if (params.size != 1) {
                return false
            }
            if (let Some(typeNode) <- params[0].typeNode) {
                if (let Some(refType) <- (typeNode as RefType)) {
                    return refType.ref.identifier.Val() == STD_LIB_STRING_IDENT
                }
                return typeNode.ToString() == STD_LIB_STRING_IDENT
            }
        }
    }
    return false
}

public func IsObjCGeneratedNSObjectToString(target: Decl): Bool {
    if (let Some(funcDecl) <- (target as FuncDecl)) {
        if (funcDecl.identifier.Val() != TOSTRING_METHOD_IDENT ||
            !funcDecl.TestAttr(Attribute.COMPILER_ADD)) {
            return false
        }
        if (let Some(body) <- funcDecl.funcBody) {
            if (body.paramLists.isEmpty()) {
                return false
            }
            return body.paramLists[0].params.isEmpty()
        }
    }
    return false
}

public func IsObjCGeneratedMember(target: Decl): Bool {
    if (let Some(outer) <- target.outerDecl) {
        if (let Some(classLikeDecl) <- (outer as ClassLikeDecl)) {
            let foreignName = GetObjCMirrorForeignName(classLikeDecl)
            return (foreignName == NSSTRING_CLASS_IDENT && IsObjCGeneratedNSStringCtor(target)) ||
                (foreignName == NSOBJECT_CLASS_IDENT && IsObjCGeneratedNSObjectToString(target))
        }
    }
    return false
}

public func GetMangledMethodName(mangler: BaseMangler, params: ArrayList<FuncParam>, methodName: String,
    typeManager: TypeManager, genericConfig!: Option<GenericConfigInfo> = None): String {
    var name = methodName
    for (param in params) {
        let rawParamTy = param.GetTy().getOrThrow()
        var paramTy = rawParamTy
        if (let Some(config) <- genericConfig) {
            if (rawParamTy.HasGeneric()) {
                paramTy = GetGenericInstTy(config, rawParamTy, typeManager)
            }
        }
        name += mangler.MangleAstSemanticType(paramTy).replace(".", "_")
    }
    return name
}

public func IsCJMappingGeneric(decl: Decl): Bool {
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        if (!classDecl.TestAnyAttr(Attribute.ABSTRACT, Attribute.OPEN)) {
            if (let Some(ty) <- classDecl.GetTy()) {
                return ty.HasGeneric()
            }
        }
        return false
    }
    if ((decl as StructDecl).isSome() || (decl as EnumDecl).isSome() || (decl as InterfaceDecl).isSome()) {
        if (let Some(ty) <- decl.GetTy()) {
            return ty.HasGeneric()
        }
    }
    return false
}

public func SplitAndTrim(value: String): ArrayList<String> {
    let out = ArrayList<String>()
    if (value.indexOf(",").isNone()) {
        out.add(value)
        return out
    }
    for (part in value.split(",")) {
        out.add(part.trimAscii())
    }
    return out
}

public func JoinVector(values: ArrayList<String>, delimiter: String): String {
    let builder = StringBuilder()
    for (idx in 0..values.size) {
        if (idx > 0) {
            builder.append(delimiter)
        }
        builder.append(values[idx])
    }
    return builder.toString()
}

public func InitGenericConfigs(file: File, decl: Decl, genericConfigs: ArrayList<GenericConfigInfo>,
    isGenericGlueCode: Box<Bool>): Unit {
    let curPackage = file.curPackage.getOrThrow()
    for ((declSymbolName, innerMap) in curPackage.allowedInteropCJGenericInstantiations) {
        if (declSymbolName != decl.identifier.Val()) {
            continue
        }
        for ((typeStr, args) in innerMap) {
            let funcNames = args.symbols
            let actualTypes = SplitAndTrim(typeStr)
            let instTypes = ArrayList<(String, String)>()
            let typeArgs = decl.GetTy().getOrThrow().typeArgs
            for (idx in 0..typeArgs.size) {
                instTypes.add((typeArgs[idx].name, actualTypes[idx]))
            }
            let declName = decl.identifier.Val()
            let declWInstStr = declName + JoinVector(actualTypes, "")
            genericConfigs.add(GenericConfigInfo(declName, declWInstStr, instTypes, funcNames))
            if (!isGenericGlueCode.value) {
                isGenericGlueCode.value = true
            }
        }
    }
}

public func GetActualTypeKind(configType: String): TypeKind {
    let typeKind: Option<TypeKind> = match (configType) {
        case "Int" => Some(TypeKind.TYPE_INT64)
        case "Int8" => Some(TypeKind.TYPE_INT8)
        case "Int16" => Some(TypeKind.TYPE_INT16)
        case "Int32" => Some(TypeKind.TYPE_INT32)
        case "Int64" => Some(TypeKind.TYPE_INT64)
        case "IntNative" => Some(TypeKind.TYPE_INT_NATIVE)
        case "UInt8" => Some(TypeKind.TYPE_UINT8)
        case "UInt16" => Some(TypeKind.TYPE_UINT16)
        case "UInt32" => Some(TypeKind.TYPE_UINT32)
        case "UInt64" => Some(TypeKind.TYPE_UINT64)
        case "UIntNative" => Some(TypeKind.TYPE_UINT_NATIVE)
        case "Float16" => Some(TypeKind.TYPE_FLOAT16)
        case "Float32" => Some(TypeKind.TYPE_FLOAT32)
        case "Float64" => Some(TypeKind.TYPE_FLOAT64)
        case "Bool" => Some(TypeKind.TYPE_BOOLEAN)
        case "Boolean" => Some(TypeKind.TYPE_BOOLEAN)
        case "Unit" => Some(TypeKind.TYPE_UNIT)
        case _ => None
    }
    CJC_ASSERT(typeKind.isSome())
    return typeKind.getOrThrow()
}

public func GetTyByName(typeName: String): Ty {
    let typeKind = GetActualTypeKind(typeName)
    return TypeManager.GetPrimitiveTy(typeKind)
}

public func GetPrimitiveType(typeName: String, typeKind: TypeKind): PrimitiveType {
    let typeNode = PrimitiveType()
    typeNode.str = typeName
    typeNode.kind = typeKind
    typeNode.SetTy(TypeManager.GetPrimitiveTy(typeKind))
    return typeNode
}

public func GetTypeByName(typeName: String): Type {
    let typeKind = GetActualTypeKind(typeName)
    return GetPrimitiveType(typeName, typeKind)
}

public func GetGenericActualType(config: GenericConfigInfo, genericName: String): String {
    for (inst in config.instTypes) {
        if (inst[0] == genericName) {
            return inst[1]
        }
    }
    return ""
}

public func GetGenericInstTy(config: GenericConfigInfo, genericName: String): Ty {
    let actualTypeName = GetGenericActualType(config, genericName)
    if (actualTypeName.isEmpty()) {
        return Ty.GetInitialTy()
    }
    return GetTyByName(actualTypeName)
}

public func GetGenericInstType(config: GenericConfigInfo, genericName: String): Type {
    let actualTypeName = GetGenericActualType(config, genericName)
    return GetTypeByName(actualTypeName)
}

public func GetGenericInstTy(config: GenericConfigInfo, genericTy: Ty, typeManager: TypeManager): Ty {
    if (genericTy.kind == TypeKind.TYPE_GENERICS) {
        return GetGenericInstTy(config, genericTy.name)
    }
    if (let Some(funcTy) <- (genericTy as FuncTy)) {
        let paramTys = ArrayList<Ty>()
        for (paramTy in funcTy.paramTys) {
            if (paramTy.HasGeneric()) {
                paramTys.add(GetGenericInstTy(config, paramTy, typeManager))
            } else {
                paramTys.add(paramTy)
            }
        }
        let retTy = if (funcTy.retTy.HasGeneric()) {
            GetGenericInstTy(config, funcTy.retTy, typeManager)
        } else {
            funcTy.retTy
        }
        return typeManager.GetFunctionTy(paramTys.toArray(), retTy)
    }
    if (let Some(tupleTy) <- (genericTy as TupleTy)) {
        let elements = ArrayList<Ty>()
        for (arg in tupleTy.typeArgs) {
            if (arg.IsGeneric()) {
                elements.add(GetGenericInstTy(config, arg.name))
            } else {
                elements.add(arg)
            }
        }
        return typeManager.GetTupleTy(elements.toArray())
    }
    return genericTy
}

public func GetGenericInstType(config: GenericConfigInfo, genericTy: Ty, typeManager: TypeManager): Type {
    let instantiatedTy = GetGenericInstTy(config, genericTy, typeManager)
    if (instantiatedTy.IsPrimitive()) {
        return GetPrimitiveType(instantiatedTy.String(), instantiatedTy.kind)
    }
    if (let Some(funcTy) <- (instantiatedTy as FuncTy)) {
        let funcType = FuncType()
        funcType.SetTy(instantiatedTy)
        for (paramTy in funcTy.paramTys) {
            funcType.paramTypes.add(GetGenericInstType(config, paramTy, typeManager))
        }
        funcType.retType = GetGenericInstType(config, funcTy.retTy, typeManager)
        return funcType
    }
    if (instantiatedTy.IsTuple()) {
        let tupleType = TupleType()
        tupleType.SetTy(instantiatedTy)
        return tupleType
    }
    return InvalidType(INVALID_POSITION)
}

public func ReplaceGenericTyForFuncTy(ty: Ty, config: GenericConfigInfo, typeManager: TypeManager): Ty {
    if (!ty.HasGeneric()) {
        return ty
    }
    return GetGenericInstTy(config, ty, typeManager)
}

public func ReplaceGenericTyForFunc(funcDecl: FuncDecl, config: GenericConfigInfo, typeManager: TypeManager): Unit {
    if (let None <- funcDecl.funcBody) {
        return
    }
    let body = funcDecl.funcBody.getOrThrow()
    if (let Some(retTypeNode) <- body.retType) {
        if (let Some(retTy) <- retTypeNode.GetTy()) {
            if (retTy.HasGeneric()) {
                body.retType = GetGenericInstType(config, retTy, typeManager)
            }
        }
    }

    let paramTys = ArrayList<Ty>()
    if (!body.paramLists.isEmpty()) {
        for (param in body.paramLists[0].params) {
            if (let Some(paramTy) <- param.GetTy()) {
                if (paramTy.HasGeneric()) {
                    let actualTypeNode = GetGenericInstType(config, paramTy, typeManager)
                    let actualTy = GetGenericInstTy(config, paramTy, typeManager)
                    param.typeNode = actualTypeNode
                    param.SetTy(actualTy)
                    paramTys.add(actualTy)
                } else {
                    paramTys.add(paramTy)
                }
            }
        }
    }

    let tmpTypeArgs = ArrayList<Ty>()
    if (let Some(funcTy) <- funcDecl.GetTy()) {
        for (typeArg in funcTy.typeArgs) {
            if (typeArg.HasGeneric()) {
                tmpTypeArgs.add(GetGenericInstTy(config, typeArg, typeManager))
            } else {
                tmpTypeArgs.add(typeArg)
            }
        }
    }
    let retTyForFunc = if (let Some(retTypeNode) <- body.retType) {
        retTypeNode.GetTy() ?? TypeManager.GetInvalidTy()
    } else {
        TypeManager.GetInvalidTy()
    }
    let newFuncTy = typeManager.GetFunctionTy(paramTys.toArray(), retTyForFunc)
    for (typeArg in tmpTypeArgs) {
        newFuncTy.typeArgs.add(typeArg)
    }
    funcDecl.SetTy(newFuncTy)
}

public func GetArgsAndRetGenericActualTyVector(config: GenericConfigInfo, ctor: FuncDecl,
    actualTyArgMap: HashMap<String, Ty>, funcTyParams: ArrayList<Ty>, actualPrimitiveType: ArrayList<Type>,
    typeManager: TypeManager): Unit {
    if (let Some(outerDecl) <- ctor.outerDecl) {
        if (let Some(outerTy) <- outerDecl.GetTy()) {
            for (argTy in outerTy.typeArgs) {
                if (argTy.IsGeneric()) {
                    let actualRetTy = GetGenericInstTy(config, argTy, typeManager)
                    actualTyArgMap.add(argTy.name, actualRetTy)
                    actualPrimitiveType.add(GetTypeByName(actualRetTy.String()))
                }
            }
        }
    }
    if (let Some(body) <- ctor.funcBody) {
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                if (let Some(paramTy) <- param.GetTy()) {
                    if (paramTy.HasGeneric()) {
                        let actualTy = GetGenericInstTy(config, paramTy, typeManager)
                        if (actualTy.kind != TypeKind.TYPE_INITIAL) {
                            funcTyParams.add(actualTy)
                        } else {
                            funcTyParams.add(paramTy)
                        }
                    } else {
                        funcTyParams.add(paramTy)
                    }
                }
            }
        }
    }
}

public func GetInstantyForGenericTy(decl: Decl, actualTyArgMap: HashMap<String, Ty>,
    typeManager: TypeManager): Option<Ty> {
    let actualTypeArgs = ArrayList<Ty>()
    for (typeArg in decl.GetTy().getOrThrow().typeArgs) {
        if (let Some(actualTy) <- actualTyArgMap.get(typeArg.name)) {
            actualTypeArgs.add(actualTy)
        }
    }
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        return typeManager.GetClassTy(classDecl, actualTypeArgs.toArray())
    }
    if (let Some(structDecl) <- (decl as StructDecl)) {
        return typeManager.GetStructTy(structDecl, actualTypeArgs.toArray())
    }
    if (let Some(enumDecl) <- (decl as EnumDecl)) {
        return typeManager.GetEnumTy(enumDecl, typeArgs: actualTypeArgs.toArray())
    }
    if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
        return typeManager.GetInterfaceTy(interfaceDecl, actualTypeArgs.toArray())
    }
    return None
}

public func GetExceptionDecl(importManager: ImportManager): ClassDecl {
    let exceptionDecl = importManager.GetCoreDecl("Exception")
    CJC_NULLPTR_CHECK(exceptionDecl)
    let exceptionClassDecl = exceptionDecl.getOrThrow() as ClassDecl
    if (let None <- exceptionClassDecl) {
        CJC_ABORT_WITH_MSG("'Exception' declaration expected to be 'ClassDecl'")
    }
    return exceptionClassDecl.getOrThrow()
}

public func IsGenericParam(ty: Ty, decl: Decl, config: GenericConfigInfo): Bool {
    if (!IsCJMappingGeneric(decl) || !ty.HasGeneric()) {
        return false
    }
    if (ty.IsGeneric()) {
        return !GetGenericActualType(config, ty.name).isEmpty()
    }
    if (ty.IsTuple()) {
        for (typeArg in ty.typeArgs) {
            if (typeArg.HasGeneric() && !IsGenericParam(typeArg, decl, config)) {
                return false
            }
        }
        return true
    }
    if (let Some(funcTy) <- (ty as FuncTy)) {
        for (paramTy in funcTy.paramTys) {
            if (paramTy.HasGeneric() && !IsGenericParam(paramTy, decl, config)) {
                return false
            }
        }
        if (funcTy.retTy.HasGeneric()) {
            return IsGenericParam(funcTy.retTy, decl, config)
        }
        return true
    }
    return false
}

public func IsVisibalFunc(funcDecl: FuncDecl, decl: Decl, config: GenericConfigInfo): Bool {
    var hasGenericParam = false
    if (let Some(body) <- funcDecl.funcBody) {
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                if (let Some(paramTy) <- param.GetTy()) {
                    if (IsGenericParam(paramTy, decl, config)) {
                        hasGenericParam = true
                        break
                    }
                }
            }
        }
        if (!hasGenericParam) {
            if (let Some(retType) <- body.retType) {
                if (let Some(retTy) <- retType.GetTy()) {
                    hasGenericParam = IsGenericParam(retTy, decl, config)
                }
            }
        }
    }
    if (!hasGenericParam) {
        return true
    }
    return config.funcNames.contains(funcDecl.identifier.Val())
}

public func GetCjMappingTupleName(tupleTy: Ty): String {
    if (!tupleTy.IsTuple()) {
        return ""
    }
    let builder = StringBuilder()
    builder.append("TupleOf")
    for (typeArg in tupleTy.typeArgs) {
        builder.append(typeArg.String())
    }
    return builder.toString()
}

public func GetLambdaJavaClassName(ty: Ty): String {
    if (let Some(funcTy) <- (ty as FuncTy)) {
        let builder = StringBuilder()
        for (paramTy in funcTy.paramTys) {
            builder.append(paramTy.String())
        }
        builder.append("To")
        builder.append(funcTy.retTy.String())
        return builder.toString()
    }
    return ""
}

public func GetLambdaJavaClassName(pattern: BasicLambdaPattern): String {
    let builder = StringBuilder()
    for (paramType in pattern.parameterTypes) {
        builder.append(paramType)
    }
    builder.append("To")
    builder.append(pattern.returnType)
    return builder.toString()
}

public func AreParamTypeKindsValid(fd: FuncDecl, typeKinds: ArrayList<TypeKind>): Bool {
    if (let Some(body) <- fd.funcBody) {
        if (body.paramLists.isEmpty()) {
            return typeKinds.isEmpty()
        }
        let params = body.paramLists[0].params
        if (params.size != typeKinds.size) {
            return false
        }
        for (idx in 0..typeKinds.size) {
            if (let Some(paramTy) <- params[idx].GetTy()) {
                if (paramTy.kind != typeKinds[idx]) {
                    return false
                }
            } else {
                return false
            }
        }
        return true
    }
    return false
}
