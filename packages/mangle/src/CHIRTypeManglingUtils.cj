package cangjie_compiler::mangle

import std.collection.*
import cangjie_compiler::chir.*

public class CHIRType {
    public var kind: TypeKind
    public var name: String = ""
    public var identifierWithoutPrefix: String = ""
    public var srcCodeIdentifier: String = ""
    public var packageName: String = ""
    public let genericArgs: ArrayList<CHIRType> = ArrayList<CHIRType>()
    public let typeArgs: ArrayList<CHIRType> = ArrayList<CHIRType>()
    public let paramTypes: ArrayList<CHIRType> = ArrayList<CHIRType>()
    public var returnType: Option<CHIRType> = None
    public var elementType: Option<CHIRType> = None
    public var baseType: Option<CHIRType> = None
    public var dims: UInt64 = 0u64
    public var size: Int64 = 0
    public var isCFunc: Bool = false
    public var isAutoEnvGenericBase: Bool = false
    public var isAutoEnvInstBase: Bool = false
    public var isAutoEnvBase: Bool = false
    public var isPrivate: Bool = false
    public var isInternalLinkage: Bool = false

    public init(kind: TypeKind) {
        this.kind = kind
    }

    public init(kind: TypeKind, name: String) {
        this.kind = kind
        this.name = name
    }

    public func IsPrimitive(): Bool {
        return ManglePrimitive(kind) != ""
    }

    public func ToString(): String {
        if (!name.isEmpty()) {
            return name
        }
        return match (kind) {
            case TypeKind.TYPE_INT8 => "Int8"
            case TypeKind.TYPE_INT16 => "Int16"
            case TypeKind.TYPE_INT32 => "Int32"
            case TypeKind.TYPE_INT64 => "Int64"
            case TypeKind.TYPE_INT_NATIVE => "IntNative"
            case TypeKind.TYPE_UINT8 => "UInt8"
            case TypeKind.TYPE_UINT16 => "UInt16"
            case TypeKind.TYPE_UINT32 => "UInt32"
            case TypeKind.TYPE_UINT64 => "UInt64"
            case TypeKind.TYPE_UINT_NATIVE => "UIntNative"
            case TypeKind.TYPE_FLOAT16 => "Float16"
            case TypeKind.TYPE_FLOAT32 => "Float32"
            case TypeKind.TYPE_FLOAT64 => "Float64"
            case TypeKind.TYPE_RUNE => "Rune"
            case TypeKind.TYPE_BOOLEAN => "Bool"
            case TypeKind.TYPE_UNIT => "Unit"
            case TypeKind.TYPE_NOTHING => "Nothing"
            case TypeKind.TYPE_CSTRING => "CString"
            case TypeKind.TYPE_VOID => "Unit"
            case _ => "Invalid"
        }
    }
}

public let MANGLE_CHIR_GENERIC_PREFIX: String = "G"
public let MANGLE_ARRAY_SLICE_PREFIX: String = "S_"
public let MANGLE_CLOSURE_STR: String = "Closure"
public let MANGLE_UNIT_STR: String = "Unit"
public let MANGLE_CSTRING_STR: String = "CString"
public let MANGLE_RAWARR_STR: String = "RawArray"
public let MANGLE_VARR_STR: String = "VArray"
public let MANGLE_CPTR_STR: String = "CPointer"
public let MANGLE_TUPLE_STR: String = "Tuple"
public let MANGLE_BOX_STR: String = "Box"

public func StripCangjiePrefix(identifier: String): String {
    if (identifier.size >= MANGLE_PREFIX_LEN) {
        return identifier[MANGLE_PREFIX_LEN..]
    }
    return identifier
}

public func ManglePrimitive(kind: TypeKind): String {
    return match (kind) {
        case TypeKind.TYPE_INT8 => "a"
        case TypeKind.TYPE_INT16 => "s"
        case TypeKind.TYPE_INT32 => "i"
        case TypeKind.TYPE_INT64 => "l"
        case TypeKind.TYPE_INT_NATIVE => "q"
        case TypeKind.TYPE_UINT8 => "h"
        case TypeKind.TYPE_UINT16 => "t"
        case TypeKind.TYPE_UINT32 => "j"
        case TypeKind.TYPE_UINT64 => "m"
        case TypeKind.TYPE_UINT_NATIVE => "r"
        case TypeKind.TYPE_FLOAT16 => "Dh"
        case TypeKind.TYPE_FLOAT32 => "f"
        case TypeKind.TYPE_FLOAT64 => "d"
        case TypeKind.TYPE_RUNE => "c"
        case TypeKind.TYPE_BOOLEAN => "b"
        case TypeKind.TYPE_UNIT => "u"
        case TypeKind.TYPE_NOTHING => "n"
        case TypeKind.TYPE_CSTRING => "k"
        case TypeKind.TYPE_VOID => "u"
        case _ => ""
    }
}

private func IdentifierForMangledCHIRType(def: CustomTypeDef): String {
    return StripCangjiePrefix(CustomTypeDefIdentifierForTypeMangle(def))
}

private func CustomTypeDefIdentifierForTypeMangle(def: CustomTypeDef): String {
    let identifier = def.GetIdentifier()
    if (StartsWith(identifier, MANGLE_AT_PREFIX)) {
        return identifier[MANGLE_CHAR_LEN..]
    }
    return identifier
}

private func MangleGenericTypeByName(srcCodeIdentifier: String, genericsTypeStack: ArrayList<String>,
    useGenericName: Bool): String {
    if (useGenericName) {
        return MANGLE_CHIR_GENERIC_PREFIX + srcCodeIdentifier + "\n"
    }
    var idx = genericsTypeStack.size - 1
    while (idx >= 0) {
        if (genericsTypeStack[idx] == srcCodeIdentifier) {
            return MANGLE_CHIR_GENERIC_PREFIX + DecimalToManglingNumber("${idx}")
        }
        idx--
    }
    throw IllegalArgumentException("Using undeclared generic type: " + srcCodeIdentifier)
}

private func UnsupportedCHIRType(kind: TypeKind, context: String): String {
    throw IllegalArgumentException(context + ": " + TypeKindName(kind))
}

public func MangleCHIRType(t: Type): String {
    let genericsTypeStack = ArrayList<String>()
    return MangleCHIRType(t, genericsTypeStack)
}

public func MangleCHIRType(t: Type, genericsTypeStack: ArrayList<String>, useGenericName!: Bool = false): String {
    let primitive = ManglePrimitive(t.GetTypeKind())
    if (!primitive.isEmpty()) {
        return primitive
    }
    if (let Some(tupleTy) <- (t as TupleType)) {
        let items = tupleTy.GetTypeArgs()
        var out = MANGLE_TUPLE_PREFIX + DecimalToManglingNumber("${items.size}")
        for (item in items) {
            out += MangleCHIRType(item, genericsTypeStack, useGenericName: useGenericName)
        }
        return out + MANGLE_SUFFIX
    }
    if (let Some(structTy) <- (t as StructType)) {
        var out = MANGLE_TYPE_STRUCT_PREFIX + IdentifierForMangledCHIRType(structTy.GetCustomTypeDef())
        for (arg in structTy.GetGenericArgs()) {
            out += MangleCHIRType(arg, genericsTypeStack, useGenericName: useGenericName)
        }
        return out
    }
    if (let Some(enumTy) <- (t as EnumType)) {
        var out = MANGLE_NESTED_PREFIX + IdentifierForMangledCHIRType(enumTy.GetCustomTypeDef())
        for (arg in enumTy.GetGenericArgs()) {
            out += MangleCHIRType(arg, genericsTypeStack, useGenericName: useGenericName)
        }
        return out
    }
    if (let Some(classTy) <- (t as ClassType)) {
        var out = MANGLE_TYPE_CLASS_PREFIX + IdentifierForMangledCHIRType(classTy.GetCustomTypeDef())
        for (arg in classTy.GetGenericArgs()) {
            out += MangleCHIRType(arg, genericsTypeStack, useGenericName: useGenericName)
        }
        return out
    }
    if (let Some(funcTy) <- (t as FuncType)) {
        var out = if (funcTy.IsCFunc()) { MANGLE_CFUNC_PREFIX } else { MANGLE_GENERAL_FUNC_PREFIX }
        var retTy = MangleCHIRType(funcTy.GetReturnType(), genericsTypeStack, useGenericName: useGenericName)
        if (retTy.isEmpty()) {
            retTy = MANGLE_VOID_TY_SUFFIX
        }
        out += retTy
        let params = funcTy.GetParamTypes()
        if (params.isEmpty()) {
            return out + MANGLE_VOID_TY_SUFFIX + MANGLE_SUFFIX
        }
        for (param in params) {
            out += MangleCHIRType(param, genericsTypeStack, useGenericName: useGenericName)
        }
        return out + MANGLE_SUFFIX
    }
    if (let Some(rawArrayTy) <- (t as RawArrayType)) {
        return MANGLE_TYPE_ARRAY_PREFIX + DecimalToManglingNumber("1") +
            MangleCHIRType(rawArrayTy.GetElementType(), genericsTypeStack, useGenericName: useGenericName)
    }
    if (let Some(refTy) <- (t as RefType)) {
        return MangleCHIRType(refTy.GetBaseType(), genericsTypeStack, useGenericName: useGenericName)
    }
    if (let Some(varrayTy) <- (t as VArrayType)) {
        return MANGLE_VARRAY_PREFIX + DecimalToManglingNumber("${varrayTy.size}") +
            MangleCHIRType(varrayTy.GetElementType(), genericsTypeStack, useGenericName: useGenericName)
    }
    if (t.GetTypeKind() == TypeKind.TYPE_CPOINTER) {
        let args = t.GetTypeArgs()
        if (!args.isEmpty()) {
            return MANGLE_POINTER_PREFIX + MangleCHIRType(args[0], genericsTypeStack, useGenericName: useGenericName)
        }
        return UnsupportedCHIRType(t.GetTypeKind(), "CPointer type has no element type")
    }
    if (let Some(genericTy) <- (t as GenericType)) {
        return MangleGenericTypeByName(genericTy.GetSrcCodeIdentifier(), genericsTypeStack, useGenericName)
    }
    return UnsupportedCHIRType(t.GetTypeKind(), "Unexpected type to be mangled")
}

public func MangleCHIRType(t: CHIRType): String {
    let genericsTypeStack = ArrayList<String>()
    return MangleCHIRType(t, genericsTypeStack)
}

public func MangleCHIRType(t: CHIRType, genericsTypeStack: ArrayList<String>, useGenericName!: Bool = false): String {
    let primitive = ManglePrimitive(t.kind)
    if (!primitive.isEmpty()) {
        return primitive
    }
    if (t.kind == TypeKind.TYPE_TUPLE) {
        var out = MANGLE_TUPLE_PREFIX + DecimalToManglingNumber("${t.typeArgs.size}")
        for (arg in t.typeArgs) {
            out += MangleCHIRType(arg, genericsTypeStack, useGenericName: useGenericName)
        }
        return out + MANGLE_SUFFIX
    }
    if (t.kind == TypeKind.TYPE_STRUCT || t.kind == TypeKind.TYPE_ENUM || t.kind == TypeKind.TYPE_CLASS) {
        let prefix = if (t.kind == TypeKind.TYPE_STRUCT) {
            MANGLE_TYPE_STRUCT_PREFIX
        } else if (t.kind == TypeKind.TYPE_ENUM) {
            MANGLE_NESTED_PREFIX
        } else {
            MANGLE_TYPE_CLASS_PREFIX
        }
        var out = prefix + StripCangjiePrefix(t.identifierWithoutPrefix)
        for (arg in t.genericArgs) {
            out += MangleCHIRType(arg, genericsTypeStack, useGenericName: useGenericName)
        }
        return out
    }
    if (t.kind == TypeKind.TYPE_FUNC) {
        var out = if (t.isCFunc) { MANGLE_CFUNC_PREFIX } else { MANGLE_GENERAL_FUNC_PREFIX }
        var retTy = if (let Some(ret) <- t.returnType) {
            MangleCHIRType(ret, genericsTypeStack, useGenericName: useGenericName)
        } else {
            MANGLE_VOID_TY_SUFFIX
        }
        if (retTy.isEmpty()) {
            retTy = MANGLE_VOID_TY_SUFFIX
        }
        out += retTy
        if (t.paramTypes.isEmpty()) {
            return out + MANGLE_VOID_TY_SUFFIX + MANGLE_SUFFIX
        }
        for (param in t.paramTypes) {
            out += MangleCHIRType(param, genericsTypeStack, useGenericName: useGenericName)
        }
        return out + MANGLE_SUFFIX
    }
    if (t.kind == TypeKind.TYPE_RAWARRAY) {
        if (let Some(elem) <- t.elementType) {
            return MANGLE_TYPE_ARRAY_PREFIX + DecimalToManglingNumber("${t.dims}") +
                MangleCHIRType(elem, genericsTypeStack, useGenericName: useGenericName)
        }
        return UnsupportedCHIRType(t.kind, "RawArray type has no element type")
    }
    if (t.kind == TypeKind.TYPE_REFTYPE) {
        if (let Some(base) <- t.baseType) {
            return MangleCHIRType(base, genericsTypeStack, useGenericName: useGenericName)
        }
        return UnsupportedCHIRType(t.kind, "Ref type has no base type")
    }
    if (t.kind == TypeKind.TYPE_VARRAY) {
        if (let Some(elem) <- t.elementType) {
            return MANGLE_VARRAY_PREFIX + DecimalToManglingNumber("${t.size}") +
                MangleCHIRType(elem, genericsTypeStack, useGenericName: useGenericName)
        }
        return UnsupportedCHIRType(t.kind, "VArray type has no element type")
    }
    if (t.kind == TypeKind.TYPE_CPOINTER) {
        if (let Some(elem) <- t.elementType) {
            return MANGLE_POINTER_PREFIX + MangleCHIRType(elem, genericsTypeStack, useGenericName: useGenericName)
        }
        return UnsupportedCHIRType(t.kind, "CPointer type has no element type")
    }
    if (t.kind == TypeKind.TYPE_GENERIC) {
        return MangleGenericTypeByName(t.srcCodeIdentifier, genericsTypeStack, useGenericName)
    }
    return UnsupportedCHIRType(t.kind, "Unexpected type to be mangled")
}

public func GetTypeArgsQualifiedName(typeArgs: ArrayList<CHIRType>, forNameFieldOfTi!: Bool = false): String {
    let parts = ArrayList<String>()
    for (typeArg in typeArgs) {
        parts.add(GetTypeQualifiedName(typeArg, forNameFieldOfTi: forNameFieldOfTi))
    }
    return String.join(parts.toArray(), delimiter: ",")
}

public func GetTypeArgsQualifiedName(typeArgs: ArrayList<Type>, forNameFieldOfTi!: Bool = false): String {
    let parts = ArrayList<String>()
    for (typeArg in typeArgs) {
        parts.add(GetTypeQualifiedName(typeArg, forNameFieldOfTi: forNameFieldOfTi))
    }
    return String.join(parts.toArray(), delimiter: ",")
}

public func GetTypeQualifiedName(t: CHIRType, forNameFieldOfTi!: Bool = false): String {
    if (t.IsPrimitive()) {
        return t.ToString()
    }
    if (t.kind == TypeKind.TYPE_RAWARRAY) {
        if (let Some(elem) <- t.elementType) {
            return MANGLE_RAWARR_STR + MANGLE_LT_PREFIX + GetTypeQualifiedName(elem,
                forNameFieldOfTi: forNameFieldOfTi) + MANGLE_GT_PREFIX
        }
        return UnsupportedCHIRType(t.kind, "RawArray type has no element type")
    }
    if (t.kind == TypeKind.TYPE_REFTYPE) {
        if (let Some(base) <- t.baseType) {
            return GetTypeQualifiedName(base, forNameFieldOfTi: forNameFieldOfTi)
        }
        return UnsupportedCHIRType(t.kind, "Ref type has no base type")
    }
    if (t.kind == TypeKind.TYPE_VARRAY) {
        if (let Some(elem) <- t.elementType) {
            return MANGLE_VARR_STR + MANGLE_LT_PREFIX + GetTypeQualifiedName(elem,
                forNameFieldOfTi: forNameFieldOfTi) + "," + "${t.size}" + MANGLE_GT_PREFIX
        }
        return UnsupportedCHIRType(t.kind, "VArray type has no element type")
    }
    if (t.kind == TypeKind.TYPE_CPOINTER) {
        if (let Some(elem) <- t.elementType) {
            return MANGLE_CPTR_STR + MANGLE_LT_PREFIX + GetTypeQualifiedName(elem,
                forNameFieldOfTi: forNameFieldOfTi) + MANGLE_GT_PREFIX
        }
        return UnsupportedCHIRType(t.kind, "CPointer type has no element type")
    }
    if (t.kind == TypeKind.TYPE_CSTRING) {
        return MANGLE_CSTRING_STR
    }
    if (t.kind == TypeKind.TYPE_TUPLE) {
        return MANGLE_TUPLE_STR + MANGLE_LT_PREFIX + GetTypeArgsQualifiedName(t.typeArgs,
            forNameFieldOfTi: forNameFieldOfTi) + MANGLE_GT_PREFIX
    }
    if (t.kind == TypeKind.TYPE_STRUCT || t.kind == TypeKind.TYPE_ENUM || t.kind == TypeKind.TYPE_CLASS) {
        return GetTypeQualifiedNameOfCustomType(t, forNameFieldOfTi: forNameFieldOfTi)
    }
    if (t.kind == TypeKind.TYPE_FUNC) {
        let params = GetTypeArgsQualifiedName(t.paramTypes, forNameFieldOfTi: forNameFieldOfTi)
        let ret = if (let Some(returnType) <- t.returnType) {
            GetTypeQualifiedName(returnType, forNameFieldOfTi: forNameFieldOfTi)
        } else {
            MANGLE_UNIT_STR
        }
        return "(${params})->" + ret
    }
    if (t.kind == TypeKind.TYPE_GENERIC) {
        return t.srcCodeIdentifier
    }
    if (t.kind == TypeKind.TYPE_VOID) {
        return MANGLE_UNIT_STR
    }
    if (t.kind == TypeKind.TYPE_BOXTYPE) {
        if (let Some(base) <- t.baseType) {
            let typeQualifiedName = GetTypeQualifiedName(base, forNameFieldOfTi: forNameFieldOfTi)
            return if (forNameFieldOfTi) { typeQualifiedName } else {
                MANGLE_BOX_STR + MANGLE_LT_PREFIX + typeQualifiedName + MANGLE_GT_PREFIX
            }
        }
        return UnsupportedCHIRType(t.kind, "Box type has no base type")
    }
    return UnsupportedCHIRType(t.kind, "Unexpected type for qualified name")
}

public func GetTypeQualifiedName(t: Type, forNameFieldOfTi!: Bool = false): String {
    if (!ManglePrimitive(t.GetTypeKind()).isEmpty()) {
        if (t.GetTypeKind() == TypeKind.TYPE_VOID) {
            return MANGLE_UNIT_STR
        }
        return t.ToString()
    }
    if (let Some(rawArrayTy) <- (t as RawArrayType)) {
        return MANGLE_RAWARR_STR + MANGLE_LT_PREFIX + GetTypeQualifiedName(rawArrayTy.GetElementType(),
            forNameFieldOfTi: forNameFieldOfTi) + MANGLE_GT_PREFIX
    }
    if (let Some(refTy) <- (t as RefType)) {
        return GetTypeQualifiedName(refTy.GetBaseType(), forNameFieldOfTi: forNameFieldOfTi)
    }
    if (let Some(varrayTy) <- (t as VArrayType)) {
        return MANGLE_VARR_STR + MANGLE_LT_PREFIX + GetTypeQualifiedName(varrayTy.GetElementType(),
            forNameFieldOfTi: forNameFieldOfTi) + "," + "${varrayTy.size}" + MANGLE_GT_PREFIX
    }
    if (t.GetTypeKind() == TypeKind.TYPE_CPOINTER) {
        let args = t.GetTypeArgs()
        if (!args.isEmpty()) {
            return MANGLE_CPTR_STR + MANGLE_LT_PREFIX + GetTypeQualifiedName(args[0],
                forNameFieldOfTi: forNameFieldOfTi) + MANGLE_GT_PREFIX
        }
        return UnsupportedCHIRType(t.GetTypeKind(), "CPointer type has no element type")
    }
    if (t.GetTypeKind() == TypeKind.TYPE_CSTRING) {
        return MANGLE_CSTRING_STR
    }
    if (let Some(tupleTy) <- (t as TupleType)) {
        return MANGLE_TUPLE_STR + MANGLE_LT_PREFIX + GetTypeArgsQualifiedName(tupleTy.GetTypeArgs(),
            forNameFieldOfTi: forNameFieldOfTi) + MANGLE_GT_PREFIX
    }
    if (let Some(customTy) <- (t as CustomType)) {
        return GetTypeQualifiedNameOfCustomType(customTy, forNameFieldOfTi: forNameFieldOfTi)
    }
    if (let Some(funcTy) <- (t as FuncType)) {
        let params = GetTypeArgsQualifiedName(funcTy.GetParamTypes(), forNameFieldOfTi: forNameFieldOfTi)
        return "(${params})->" + GetTypeQualifiedName(funcTy.GetReturnType(), forNameFieldOfTi: forNameFieldOfTi)
    }
    if (let Some(genericTy) <- (t as GenericType)) {
        return genericTy.GetSrcCodeIdentifier()
    }
    if (t.GetTypeKind() == TypeKind.TYPE_VOID) {
        return MANGLE_UNIT_STR
    }
    if (let Some(boxTy) <- (t as BoxType)) {
        let typeQualifiedName = GetTypeQualifiedName(boxTy.GetBaseType(), forNameFieldOfTi: forNameFieldOfTi)
        return if (forNameFieldOfTi) { typeQualifiedName } else {
            MANGLE_BOX_STR + MANGLE_LT_PREFIX + typeQualifiedName + MANGLE_GT_PREFIX
        }
    }
    return UnsupportedCHIRType(t.GetTypeKind(), "Unexpected type for qualified name")
}

public func GetTypeQualifiedNameOfCustomType(typeInfo: CHIRType, forNameFieldOfTi!: Bool = false): String {
    if (typeInfo.isAutoEnvInstBase) {
        throw IllegalArgumentException("AutoEnv instantiated base type cannot be printed as a custom type name.")
    }
    if (typeInfo.isAutoEnvGenericBase) {
        if (!typeInfo.genericArgs.isEmpty()) {
            let paramTypes = ArrayList<CHIRType>()
            var idx: Int64 = 0
            while (idx + 1 < typeInfo.genericArgs.size) {
                paramTypes.add(typeInfo.genericArgs[idx])
                idx++
            }
            let ret = typeInfo.genericArgs[typeInfo.genericArgs.size - 1]
            return MANGLE_CLOSURE_STR + MANGLE_LT_PREFIX + "(" + GetTypeArgsQualifiedName(paramTypes,
                forNameFieldOfTi: true) + ")->" + GetTypeQualifiedName(ret, forNameFieldOfTi: true) +
                MANGLE_GT_PREFIX
        }
        throw IllegalArgumentException("AutoEnv generic base type has no function signature type arguments.")
    }
    var packageName = typeInfo.packageName
    if (let Some(pos) <- packageName.indexOf("::")) {
        packageName = packageName[0..pos] + "/" + packageName[pos + 2..]
    }
    var out = packageName + ":" + GetCustomTypeIdentifier(typeInfo)
    if (!typeInfo.genericArgs.isEmpty()) {
        out += MANGLE_LT_PREFIX + GetTypeArgsQualifiedName(typeInfo.genericArgs,
            forNameFieldOfTi: forNameFieldOfTi) + MANGLE_GT_PREFIX
    }
    return out
}

private func PackageNameForQualifiedName(def: CustomTypeDef): String {
    var packageName = def.GetPackageName()
    if (let Some(pos) <- packageName.indexOf("::")) {
        packageName = packageName[0..pos] + "/" + packageName[pos + 2..]
    }
    return packageName
}

public func GetTypeQualifiedNameOfCustomType(typeInfo: CustomType, forNameFieldOfTi!: Bool = false): String {
    let def = typeInfo.GetCustomTypeDef()
    var out = PackageNameForQualifiedName(def) + ":" + GetCustomTypeIdentifier(typeInfo)
    let typeArgs = typeInfo.GetGenericArgs()
    if (!typeArgs.isEmpty()) {
        out += MANGLE_LT_PREFIX + GetTypeArgsQualifiedName(typeArgs, forNameFieldOfTi: forNameFieldOfTi) +
            MANGLE_GT_PREFIX
    }
    return out
}

public func GetCustomTypeIdentifier(typeInfo: CHIRType): String {
    return GetCustomTypeDefIdentifier(typeInfo)
}

public func GetCustomTypeIdentifier(typeInfo: CustomType): String {
    return GetCustomTypeDefIdentifier(typeInfo.GetCustomTypeDef())
}

public func GetCustomTypeDefIdentifier(def: CHIRType): String {
    if (def.isAutoEnvBase) {
        throw IllegalArgumentException("AutoEnv base type has no source custom type identifier.")
    }
    if (def.srcCodeIdentifier.isEmpty() || (def.isPrivate && def.isInternalLinkage)) {
        return def.identifierWithoutPrefix
    }
    return def.srcCodeIdentifier
}

public func GetCustomTypeDefIdentifier(def: CustomTypeDef): String {
    return CustomTypeDefIdentifierForTypeMangle(def)
}
