package cangjie_compiler::sema.NativeFFI

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::option.GetFileName as OptionGetFileName
import cangjie_compiler::option.IsDir as OptionIsDir
import cangjie_compiler::sema.TypeManager

public let NSSTRING_CLASS_IDENT: String = "NSString"
public let NSOBJECT_CLASS_IDENT: String = "NSObject"
public let TOSTRING_METHOD_IDENT: String = "toString"
public let INIT_IDENT: String = "init"
private let STD_LIB_STRING_IDENT: String = "String"

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
    return match (configType) {
        case "Int" => TypeKind.TYPE_INT64
        case "Int8" => TypeKind.TYPE_INT8
        case "Int16" => TypeKind.TYPE_INT16
        case "Int32" => TypeKind.TYPE_INT32
        case "Int64" => TypeKind.TYPE_INT64
        case "IntNative" => TypeKind.TYPE_INT_NATIVE
        case "UInt8" => TypeKind.TYPE_UINT8
        case "UInt16" => TypeKind.TYPE_UINT16
        case "UInt32" => TypeKind.TYPE_UINT32
        case "UInt64" => TypeKind.TYPE_UINT64
        case "UIntNative" => TypeKind.TYPE_UINT_NATIVE
        case "Float16" => TypeKind.TYPE_FLOAT16
        case "Float32" => TypeKind.TYPE_FLOAT32
        case "Float64" => TypeKind.TYPE_FLOAT64
        case "Bool" => TypeKind.TYPE_BOOLEAN
        case "Boolean" => TypeKind.TYPE_BOOLEAN
        case "Unit" => TypeKind.TYPE_UNIT
        case _ => TypeKind.TYPE_INVALID
    }
}

public func GetTyByName(typeName: String): Ty {
    let typeKind = GetActualTypeKind(typeName)
    if (typeKind == TypeKind.TYPE_INVALID) {
        return TypeManager.GetInvalidTy()
    }
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
    if (typeKind == TypeKind.TYPE_INVALID) {
        return InvalidType(INVALID_POSITION)
    }
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
    typeManager: TypeManager): Ty {
    let actualTypeArgs = ArrayList<Ty>()
    if (let Some(declTy) <- decl.GetTy()) {
        for (typeArg in declTy.typeArgs) {
            if (let Some(actualTy) <- actualTyArgMap.get(typeArg.name)) {
                actualTypeArgs.add(actualTy)
            }
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
    return decl.GetTy() ?? TypeManager.GetInvalidTy()
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

public func SelfhostPortStatus_NativeFFI_Utils(): Bool {
    return true
}
