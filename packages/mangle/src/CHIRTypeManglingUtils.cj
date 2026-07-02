package cangjie_compiler::mangle

import std.collection.*
import cangjie_compiler::chir.*

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

func MangleArraySliceType(t: Type, genericsTypeStack: ArrayList<String>, useGenericName: Bool): String {
    let typeArgs = t.GetTypeArgs()
    return MANGLE_ARRAY_SLICE_PREFIX + MangleCHIRType(typeArgs[0], genericsTypeStack, useGenericName: useGenericName) +
        MANGLE_SUFFIX
}

private func IdentifierForMangledCHIRType(def: CustomTypeDef): String {
    return StripCangjiePrefix(CustomTypeDefMangledIdentifier(def))
}

private func CustomTypeDefMangledIdentifier(def: CustomTypeDef): String {
    let identifier = def.GetIdentifier()
    if (StartsWith(identifier, MANGLE_AT_PREFIX)) {
        return identifier[MANGLE_CHAR_LEN..]
    }
    return identifier
}

private func CustomTypeDefIdentifierForQualifiedName(def: CustomTypeDef): String {
    let srcCodeIdentifier = def.GetSrcCodeIdentifier()
    if (!srcCodeIdentifier.isEmpty() && !def.TestAttr(Attribute.PRIVATE)) {
        return srcCodeIdentifier
    }
    return CustomTypeDefMangledIdentifier(def)
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
        return MANGLE_TYPE_ARRAY_PREFIX + DecimalToManglingNumber("${rawArrayTy.GetDims()}") +
            MangleCHIRType(rawArrayTy.GetElementType(), genericsTypeStack, useGenericName: useGenericName)
    }
    if (let Some(refTy) <- (t as RefType)) {
        return MangleCHIRType(refTy.GetBaseType(), genericsTypeStack, useGenericName: useGenericName)
    }
    if (let Some(varrayTy) <- (t as VArrayType)) {
        return MANGLE_VARRAY_PREFIX + DecimalToManglingNumber("${varrayTy.size}") +
            MangleCHIRType(varrayTy.GetElementType(), genericsTypeStack, useGenericName: useGenericName)
    }
    if (let Some(cPointerTy) <- (t as CPointerType)) {
        return MANGLE_POINTER_PREFIX + MangleCHIRType(cPointerTy.GetElementType(), genericsTypeStack,
            useGenericName: useGenericName)
    }
    if (let Some(genericTy) <- (t as GenericType)) {
        return MangleGenericTypeByName(genericTy.GetSrcCodeIdentifier(), genericsTypeStack, useGenericName)
    }
    return UnsupportedCHIRType(t.GetTypeKind(), "Unexpected type to be mangled")
}

public func GetTypeArgsQualifiedName(typeArgs: ArrayList<Type>, forNameFieldOfTi!: Bool = false): String {
    let parts = ArrayList<String>()
    for (typeArg in typeArgs) {
        parts.add(GetTypeQualifiedName(typeArg, forNameFieldOfTi: forNameFieldOfTi))
    }
    return String.join(parts.toArray(), delimiter: ",")
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
    if (let Some(cPointerTy) <- (t as CPointerType)) {
        return MANGLE_CPTR_STR + MANGLE_LT_PREFIX + GetTypeQualifiedName(cPointerTy.GetElementType(),
            forNameFieldOfTi: forNameFieldOfTi) + MANGLE_GT_PREFIX
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

private func PackageNameForQualifiedName(def: CustomTypeDef): String {
    let packageOwner = if (let Some(genericDecl) <- def.GetGenericDecl()) { genericDecl } else { def }
    var packageName = packageOwner.GetPackageName()
    if (let Some(pos) <- packageName.indexOf("::")) {
        packageName = packageName[0..pos] + "/" + packageName[pos + 2..]
    }
    return packageName
}

public func GetTypeQualifiedNameOfCustomType(typeInfo: CustomType, forNameFieldOfTi!: Bool = false): String {
    let def = typeInfo.GetCustomTypeDef()
    if (def.GetAnnotation("IsAutoEnvGenericBase").isSome()) {
        let typeArgs = typeInfo.GetGenericArgs()
        if (typeArgs.isEmpty()) {
            throw IllegalArgumentException("AutoEnv generic base type has no type arguments")
        }
        let paramTypes = ArrayList<Type>()
        var idx = 0
        while (idx + 1 < typeArgs.size) {
            paramTypes.add(typeArgs[idx])
            idx++
        }
        let params = GetTypeArgsQualifiedName(paramTypes, forNameFieldOfTi: true)
        let returnType = GetTypeQualifiedName(typeArgs[typeArgs.size - 1], forNameFieldOfTi: true)
        return MANGLE_CLOSURE_STR + MANGLE_LT_PREFIX + "(${params})->" + returnType + MANGLE_GT_PREFIX
    }
    var out = PackageNameForQualifiedName(def) + ":" + GetCustomTypeIdentifier(typeInfo)
    let typeArgs = typeInfo.GetGenericArgs()
    if (!typeArgs.isEmpty()) {
        out += MANGLE_LT_PREFIX + GetTypeArgsQualifiedName(typeArgs, forNameFieldOfTi: forNameFieldOfTi) +
            MANGLE_GT_PREFIX
    }
    return out
}

public func GetCustomTypeIdentifier(typeInfo: CustomType): String {
    return GetCustomTypeDefIdentifier(typeInfo.GetCustomTypeDef())
}

public func GetCustomTypeDefIdentifier(def: CustomTypeDef): String {
    return CustomTypeDefIdentifierForQualifiedName(def)
}
