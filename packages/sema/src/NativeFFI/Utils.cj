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
            return refExpr.isThis && call.callKind == CallKind.CALL_OBJECT_CREATION
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

public func SelfhostPortStatus_NativeFFI_Utils(): Bool {
    return true
}
