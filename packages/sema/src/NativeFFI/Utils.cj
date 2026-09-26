package cjcj::sema.NativeFFI

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::mangle.{BaseMangler, MangleType}
import cjcj::modules.SemaImportManager
import cjcj::option.GetFileName as OptionGetFileName
import cjcj::option.IsDir as OptionIsDir
import cjcj::sema.{CreateThrowException, TypeManager, GenerateTypeMapping}
import cjcj::sema.Desugar.AfterTypeCheck.LookupEnumMember
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

// C++ src/Sema/NativeFFI/Utils.h:115-148. Function-pointer member, not a declared FuncDecl.
public func CreateMemberCall(typeManager: TypeManager, receiver: Expr, vd: VarDecl,
    args!: ArrayList<FuncArg> = ArrayList<FuncArg>()): CallExpr {
    let _ = typeManager
    CJC_NULLPTR_CHECK(receiver.GetTy())
    let vdTy = vd.GetTy().getOrThrow()
    CJC_ASSERT(vdTy.IsFunc() || vdTy.IsCFunc())
    let funcTy = (vdTy as FuncTy).getOrThrow()
    CJC_ASSERT(funcTy.paramTys.size == args.size)
    let memberAccess = CreateMemberAccess(receiver, vd)
    if (vdTy.IsCFunc()) {
        memberAccess.EnableAttr(Attribute.UNSAFE)
    }
    CopyBasicInfo(receiver, memberAccess)
    memberAccess.SetTy(funcTy)
    let call = CreateCallExpr(memberAccess, args, None, Some(funcTy.retTy), CallKind.CALL_FUNCTION_PTR)
    if (vdTy.IsCFunc()) {
        call.EnableAttr(Attribute.UNSAFE)
    }
    return call
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

// C++ src/Sema/NativeFFI/Utils.cpp:130-135.
// C++ caches this lookup in a function-local static. Cangjie has no equivalent construct;
// repeated core-declaration lookup returns the same declaration during one compilation.
public func GetStringDecl(importManager: SemaImportManager): StructDecl {
    let decl = importManager.GetCoreDecl<StructDecl>(STD_LIB_STRING_IDENT)
    CJC_NULLPTR_CHECK(decl)
    return decl.getOrThrow()
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

// C++ src/Sema/NativeFFI/Utils.cpp:145-152.
public func WrapUnitLambdaExpr(typeManager: TypeManager, nodes: ArrayList<Node>,
    lambdaParams!: ArrayList<FuncParam> = ArrayList<FuncParam>()): LambdaExpr {
    nodes.add(CreateUnitExpr(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
    return WrapReturningLambdaExpr(typeManager, nodes, lambdaParams: lambdaParams)
}

public func WrapReturningLambdaExpr(typeManager: TypeManager, nodes: ArrayList<Node>,
    lambdaParams!: ArrayList<FuncParam> = ArrayList<FuncParam>()): LambdaExpr {
    CJC_ASSERT(!nodes.isEmpty())
    let retTy = nodes[nodes.size - 1].GetTy().getOrThrow()
    let paramTys = LambdaParamTys(lambdaParams)
    let paramLists = ArrayList<FuncParamList>()
    // C++ Utils.cpp:237 moves OwnedPtr params into Create.h:95. The one-argument overload clones.
    paramLists.add(CreateFuncParamList(lambdaParams, None))
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

// C++ src/Mangle/BaseMangler.cpp:258-296. This package-local extension avoids
// colliding with cjcj::mangle.MangleType while preserving the C++ receiver.
extend BaseMangler {
    public func MangleType(ty: Ty): String {
        if (ty.kind == TypeKind.TYPE) {
            return ""
        }
        return MangleAstSemanticType(ty)
    }
}

public func GetMangledMethodName(mangler: BaseMangler, params: ArrayList<FuncParam>, methodName: String): String {
    var name = methodName
    for (param in params) {
        let paramTy = param.GetTy().getOrThrow()
        name += mangler.MangleType(paramTy).replace(".", "_")
    }
    return name
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

public func GetExceptionDecl(importManager: SemaImportManager): ClassDecl {
    let exceptionDecl = importManager.GetCoreDecl<ClassDecl>("Exception")
    CJC_NULLPTR_CHECK(exceptionDecl)
    let exceptionClassDecl = exceptionDecl.getOrThrow() as ClassDecl
    if (let None <- exceptionClassDecl) {
        CJC_ABORT_WITH_MSG("'Exception' declaration expected to be 'ClassDecl'")
    }
    return exceptionClassDecl.getOrThrow()
}

// C++ src/Sema/NativeFFI/Utils.cpp:758-770.
public func CreateThrowExceptionCall(importManager: SemaImportManager, typeManager: TypeManager,
    msg: String, curFile: File): ThrowExpr {
    let exceptionArgs = ArrayList<Expr>()
    let exceptionMsg = WithinFile(CreateLitConstExpr(LitConstKind.STRING, msg,
        GetStringDecl(importManager).GetTy().getOrThrow()), curFile)
    exceptionArgs.add(exceptionMsg)
    let exception = GetExceptionDecl(importManager)
    return CreateThrowException(exception, exceptionArgs, curFile, typeManager)
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

// Upstream a51ced71, NativeFFI/Utils.cpp:176-203.
private func GetGetPointerAddressIntrinsicDecl(importManager: SemaImportManager): FuncDecl {
    return importManager.GetCoreDecl<FuncDecl>("getPointerAddress").getOrThrow()
}
// C++ src/Sema/NativeFFI/Utils.cpp:140-173.
private func UnwrapAliasTy(ty: Ty): Ty {
    var current = ty
    while (let Some(aliasTy) <- (current as TypeAliasTy)) {
        let decl = aliasTy.declPtr.getOrThrow()
        current = decl.typeNode.getOrThrow().GetTy().getOrThrow()
    }
    return current
}

public func CreateReadPointerCall(importManager: SemaImportManager, typeManager: TypeManager, pointer: Expr): Expr {
    let ptrTy = UnwrapAliasTy(pointer.GetTy().getOrThrow())
    CJC_ASSERT(ptrTy.IsPointer())
    let fd = importManager.GetCoreDecl<FuncDecl>("readPointer").getOrThrow()
    let ref = WithinFile<RefExpr>(CreateRefExpr(fd), pointer.curFile)
    ref.instTys.add(ptrTy)
    ref.SetTy(typeManager.GetInstantiatedTy(fd.GetTy().getOrThrow(), GenerateTypeMapping(fd, ref.instTys)))
    let int64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    let zero = WithinFile<LitConstExpr>(CreateLitConstExpr(LitConstKind.INTEGER, "0", int64Ty), pointer.curFile)
    let elemTy = ptrTy.typeArgs[0]
    let args = ArrayList<FuncArg>()
    args.add(CreateFuncArg((ASTCloner.Clone(pointer) as Expr).getOrThrow()))
    args.add(CreateFuncArg(zero))
    let call = CreateCallExpr(ref, args, Some(fd), Some(elemTy), CallKind.CALL_INTRINSIC_FUNCTION)
    call.EnableAttr(Attribute.UNSAFE)
    call.SetTy(elemTy)
    return call
}

public func CreateGetPointerAddressCall(importManager: SemaImportManager, typeManager: TypeManager, pointer: Expr): Expr {
    CJC_ASSERT(pointer.GetTy().getOrThrow().IsPointer())
    let fd = GetGetPointerAddressIntrinsicDecl(importManager)
    let ref = WithinFile<RefExpr>(CreateRefExpr(fd), pointer.curFile)
    ref.instTys.add(pointer.GetTy().getOrThrow().typeArgs[0])
    let uintTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UINT_NATIVE)
    ref.SetTy(typeManager.GetFunctionTy([pointer.GetTy().getOrThrow()], uintTy))
    let args = ArrayList<FuncArg>()
    args.add(CreateFuncArg((ASTCloner.Clone(pointer) as Expr).getOrThrow()))
    let call = CreateCallExpr(ref, args, Some(fd), Some(uintTy), CallKind.CALL_INTRINSIC_FUNCTION)
    call.EnableAttr(Attribute.UNSAFE)
    return call
}
public func CreateIsPtrNullCheckCall(importManager: SemaImportManager, typeManager: TypeManager, pointer: Expr): Expr {
    let uintTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UINT_NATIVE)
    let call = CreateGetPointerAddressCall(importManager, typeManager, pointer)
    let zero = WithinFile<LitConstExpr>(CreateLitConstExpr(LitConstKind.INTEGER, "0", uintTy), pointer.curFile)
    let comparison = CreateBinaryExpr(call, zero, TokenKind.EQUAL)
    comparison.SetTy(TypeManager.GetBoolTy())
    return comparison
}

// Upstream fbf15ec8, NativeFFI/Utils.cpp:491-568.
public func FFIGetOptionTy(importManager: SemaImportManager, typeManager: TypeManager, ty: Ty): Ty {
    return typeManager.GetEnumTy(FFIGetOptionDecl(importManager), typeArgs: [ty])
}
public func FFIGetOptionDecl(importManager: SemaImportManager): EnumDecl {
    return importManager.GetCoreDecl<EnumDecl>("Option").getOrThrow()
}
public func FFIGetOptionSomeDecl(importManager: SemaImportManager): Decl {
    return LookupEnumMember(FFIGetOptionDecl(importManager), "Some").getOrThrow()
}
public func FFIGetOptionNoneDecl(importManager: SemaImportManager): Decl {
    return LookupEnumMember(FFIGetOptionDecl(importManager), "None").getOrThrow()
}
public func FFICreateOptionSomeRef(importManager: SemaImportManager, typeManager: TypeManager, ty: Ty): Expr {
    let ref = CreateRefExpr(FFIGetOptionSomeDecl(importManager))
    ref.SetTy(typeManager.GetFunctionTy([ty], FFIGetOptionTy(importManager, typeManager, ty)))
    return ref
}
public func FFICreateOptionNoneRef(importManager: SemaImportManager, typeManager: TypeManager, ty: Ty): Expr {
    let ref = CreateRefExpr(FFIGetOptionNoneDecl(importManager))
    ref.SetTy(FFIGetOptionTy(importManager, typeManager, ty))
    return ref
}
public func FFICreateOptionSomeCall(importManager: SemaImportManager, typeManager: TypeManager, expr: Expr, ty: Ty): Expr {
    let args = ArrayList<FuncArg>(); args.add(CreateFuncArg(expr))
    let call = CreateCallExpr(FFICreateOptionSomeRef(importManager, typeManager, ty), args)
    call.SetTy(FFIGetOptionTy(importManager, typeManager, ty))
    call.resolvedFunction = FFIGetOptionSomeDecl(importManager) as FuncDecl
    call.callKind = CallKind.CALL_DECLARED_FUNCTION
    return call
}
