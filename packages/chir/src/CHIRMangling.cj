package cjcj::chir

import cjcj::basic.Linkage as BasicLinkage
import std.collection.*
import std.sort.*
import cjcj::utils.{CJC_ASSERT, OverflowStrategy, Stoi}

private let MANGLE_CANGJIE_PREFIX: String = "_C"
private let MANGLE_NESTED_PREFIX: String = "N"
private let MANGLE_SUFFIX: String = "E"
private let MANGLE_CFUNC_PREFIX: String = "FC"
private let MANGLE_GENERAL_FUNC_PREFIX: String = "F0"
private let MANGLE_TYPE_STRUCT_PREFIX: String = "R"
private let MANGLE_TYPE_CLASS_PREFIX: String = "C"
private let MANGLE_TYPE_ARRAY_PREFIX: String = "A"
private let MANGLE_FUNC_PARAM_TYPE_PREFIX: String = "H"
private let MANGLE_VOID_TY_SUFFIX: String = "v"
private let MANGLE_POINTER_PREFIX: String = "P"
private let MANGLE_VARRAY_PREFIX: String = "V"
private let MANGLE_TUPLE_PREFIX: String = "T"
private let MANGLE_DOLLAR_PREFIX: String = "$"
private let MANGLE_WILDCARD_PREFIX: String = "_"
private let MANGLE_LT_PREFIX: String = "<"
private let MANGLE_GT_PREFIX: String = ">"
private let MANGLE_PREFIX_LEN: Int64 = 2

private let MANGLE_VIRTUAL_PREFIX: String = "_CV"
private let MANGLE_MUTABLE_PREFIX: String = "_CM"
private let MANGLE_CHIR_FUNC_PREFIX: String = "_CC"
private let MANGLE_CHIR_EXTEND_PREFIX: String = "$X"
private let MANGLE_INSTANTIATE_PREFIX: String = "_CI"
private let MANGLE_CHIR_LAMBDA_PREFIX: String = "_CL"
private let MANGLE_OPERATOR_PREFIX: String = "_CO"
private let MANGLE_ANNOTATION_LAMBDA_PREFIX: String = "_CA"
private let MANGLE_CLOSURE_GENERIC_PREFIX: String = "$Cg"
private let MANGLE_CLOSURE_INSTANTIATE_PREFIX: String = "$Ci"
private let MANGLE_CLOSURE_FUNC_PREFIX: String = "$Cf"
private let MANGLE_CLOSURE_LAMBDA_PREFIX: String = "$Cl"
private let MANGLE_CLOSURE_WRAPPER_PREFIX: String = "$Cw"
private let MANGLE_ABSTRACT_INST_PREFIX: String = "$i"
private let MANGLE_ABSTRACT_GENERIC_PREFIX: String = "$vg"
private let MANGLE_ABSTRACT_INSTANTIATED_PREFIX: String = "$vi"
private let MANGLE_CHIR_GENERIC_SUFFIX: String = "$g"

private let MANGLE_CHIR_GENERIC_PREFIX: String = "G"
private let MANGLE_ARRAY_SLICE_PREFIX: String = "S_"
private let MANGLE_CLOSURE_STR: String = "Closure"
private let MANGLE_UNIT_STR: String = "Unit"
private let MANGLE_CSTRING_STR: String = "CString"
private let MANGLE_RAWARR_STR: String = "RawArray"
private let MANGLE_VARR_STR: String = "VArray"
private let MANGLE_CPTR_STR: String = "CPointer"
private let MANGLE_TUPLE_STR: String = "Tuple"
private let MANGLE_BOX_STR: String = "Box"

private func StartsWith(value: String, prefix: String): Bool {
    return value.size >= prefix.size && value[0..prefix.size] == prefix
}

public func ReplaceManglePrefixWith(mangledName: String, newPrefix: String): String {
    if (StartsWith(mangledName, MANGLE_CANGJIE_PREFIX)) {
        return newPrefix + mangledName[MANGLE_PREFIX_LEN..]
    }
    throw IllegalArgumentException("Mangle name has no _C prefix to be replaced: " + mangledName)
}

private func OperatorTypeMangle(name: String): Option<String> {
    return match (name) {
        case "[]" => "ix"
        case "!" => "nt"
        case "-" => "ng"
        case "**" => "pw"
        case "*" => "ml"
        case "/" => "dv"
        case "%" => "rm"
        case "+" => "pl"
        case "<<" => "ls"
        case ">>" => "rs"
        case "<" => "lt"
        case ">" => "gt"
        case "<=" => "le"
        case ">=" => "ge"
        case "==" => "eq"
        case "!=" => "ne"
        case "&" => "an"
        case "^" => "eo"
        case "|" => "or"
        case "()" => "cl"
        case _ => None
    }
}

private func DecimalToManglingNumber(decimal: String): String {
    let base62Chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    for (ch in decimal.toArray()) {
        if (!IsDigit(ch)) {
            return ""
        }
    }
    if (let Some(parsed) <- Stoi(decimal)) {
        var num = parsed - 1
        if (num < 0) {
            return MANGLE_WILDCARD_PREFIX
        }
        var base62 = if (num > 0) { "" } else { "0" }
        while (num > 0) {
            let idx = num % base62Chars.size
            base62 += base62Chars[idx..idx + 1]
            num /= base62Chars.size
        }
        return base62 + MANGLE_WILDCARD_PREFIX
    }
    return ""
}

private func IsDigit(ch: Byte): Bool {
    return ch >= b'0' && ch <= b'9'
}

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
    return StripCangjiePrefix(def.GetIdentifierWithoutPrefix())
}

private func CustomTypeDefIdentifierForQualifiedName(def: CustomTypeDef): String {
    CJC_ASSERT(!def.GetType().getOrThrow().IsAutoEnvBase())
    let srcCodeIdentifier = def.GetSrcCodeIdentifier()
    let linkType = def.Get<LinkTypeInfo, BasicLinkage>()
    if (srcCodeIdentifier.isEmpty() || (def.TestAttr(Attribute.PRIVATE) && linkType == BasicLinkage.INTERNAL)) {
        return def.GetIdentifierWithoutPrefix()
    }
    return srcCodeIdentifier
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

public func GenerateVirtualFuncMangleName(rawFunc: Function, customTypeDef: CustomTypeDef,
    parentTy: ClassType, isVirtual: Bool): String {
    let prefix = if (isVirtual) { MANGLE_VIRTUAL_PREFIX } else { MANGLE_MUTABLE_PREFIX }
    var out = ReplaceManglePrefixWith(rawFunc.GetIdentifierWithoutPrefix(), prefix)
    let customTyGenericTypeStack = ArrayList<String>()
    for (genericType in customTypeDef.GetGenericTypeParams()) {
        customTyGenericTypeStack.add(genericType.GetSrcCodeIdentifier())
    }
    if (customTypeDef.IsExtend()) {
        out += MANGLE_CHIR_EXTEND_PREFIX + MangleCHIRType(customTypeDef.GetType().getOrThrow(),
            customTyGenericTypeStack)
        let implementTypes = ArrayList<String>()
        for (ty in customTypeDef.GetImplementedInterfaceTys()) {
            implementTypes.add(MangleCHIRType(ty, customTyGenericTypeStack))
        }
        sort(implementTypes, by: { left: String, right: String =>
            if (left < right) {
                Ordering.LT
            } else if (left > right) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        for (implementType in implementTypes) {
            out += implementType
        }
        out += "${customTypeDef.GetPackageName().size}" + customTypeDef.GetPackageName()
    } else {
        out += MANGLE_DOLLAR_PREFIX + ReplaceManglePrefixWith(customTypeDef.GetIdentifierWithoutPrefix(), "")
    }
    out += MANGLE_DOLLAR_PREFIX + MangleCHIRType(parentTy, customTyGenericTypeStack)
    return out
}

public func GenerateInstantiateFuncMangleName(baseName: String, instTysInFunc: ArrayList<Type>): String {
    var out = ReplaceManglePrefixWith(baseName, MANGLE_INSTANTIATE_PREFIX) + MANGLE_DOLLAR_PREFIX
    if (instTysInFunc.isEmpty()) {
        out += MANGLE_VOID_TY_SUFFIX
    } else {
        for (paramTy in instTysInFunc) {
            out += MangleCHIRType(paramTy)
        }
    }
    return out
}

public func GenerateLambdaFuncMangleName(baseFunc: Function, counter: Int64): String {
    return ReplaceManglePrefixWith(baseFunc.GetIdentifierWithoutPrefix(), MANGLE_CHIR_LAMBDA_PREFIX) +
        MANGLE_DOLLAR_PREFIX + "${counter}" + MANGLE_WILDCARD_PREFIX
}

public func OverflowStrategyToString(ovf: OverflowStrategy): String {
    return match (ovf) {
        case OverflowStrategy.WRAPPING => "&"
        case OverflowStrategy.THROWING => "~"
        case _ => "%"
    }
}

public func GenerateOverflowOperatorFuncMangleName(name: String, ovf: OverflowStrategy, isBinary: Bool,
    typeInfo: BuiltinType): String {
    var out = MANGLE_OPERATOR_PREFIX + OverflowStrategyToString(ovf)
    if (let Some(op) <- OperatorTypeMangle(name)) {
        out += op
    } else {
        throw IllegalArgumentException("Unsupported name for overflow operator mangling: " + name)
    }
    out += MANGLE_FUNC_PARAM_TYPE_PREFIX + MangleCHIRType(typeInfo)
    if (isBinary) {
        out += MangleCHIRType(typeInfo)
    }
    return out
}

public func GenerateAnnotationFuncMangleName(name: String): String {
    return MANGLE_CANGJIE_PREFIX + "AF" + name[MANGLE_PREFIX_LEN + 1..]
}

public func GenerateGenericBaseClassMangleName(paramNum: Int64): String {
    return MANGLE_CLOSURE_GENERIC_PREFIX + "${paramNum}" + MANGLE_WILDCARD_PREFIX
}

public func GenerateInstantiatedBaseClassMangleName(funcType: FuncType): String {
    return MANGLE_CLOSURE_INSTANTIATE_PREFIX + MangleCHIRType(funcType)
}

public func GenerateGlobalImplClassMangleName(function: Function): String {
    return ReplaceManglePrefixWith(function.GetIdentifierWithoutPrefix(), MANGLE_CLOSURE_FUNC_PREFIX)
}

public func GenerateLambdaImplClassMangleName(function: Lambda, count: Int64): String {
    return ReplaceManglePrefixWith(function.GetIdentifier(), MANGLE_CLOSURE_LAMBDA_PREFIX) +
        MANGLE_DOLLAR_PREFIX + "${count}"
}

public func GenerateWrapperClassMangleName(def: ClassDef): String {
    return MANGLE_CLOSURE_WRAPPER_PREFIX + def.GetIdentifierWithoutPrefix()
}

public func GenerateGenericAbstractFuncMangleName(def: ClassDef): String {
    return MANGLE_CHIR_FUNC_PREFIX + def.GetIdentifier() + MANGLE_ABSTRACT_GENERIC_PREFIX
}

public func GenerateInstantiatedAbstractFuncMangleName(def: ClassDef): String {
    return MANGLE_CHIR_FUNC_PREFIX + def.GetIdentifier() + MANGLE_ABSTRACT_INSTANTIATED_PREFIX
}

public func GenerateGenericOverrideFuncMangleName(function: Function): String {
    return ReplaceManglePrefixWith(function.GetIdentifierWithoutPrefix(), MANGLE_CHIR_FUNC_PREFIX) +
        MANGLE_CHIR_GENERIC_SUFFIX
}

public func GenerateInstOverrideFuncMangleName(function: Function): String {
    return ReplaceManglePrefixWith(function.GetIdentifierWithoutPrefix(), MANGLE_CHIR_FUNC_PREFIX) +
        MANGLE_ABSTRACT_INST_PREFIX
}

public func GenerateWrapperClassGenericOverrideFuncMangleName(def: ClassDef): String {
    return MANGLE_CHIR_FUNC_PREFIX + def.GetIdentifierWithoutPrefix() + MANGLE_CHIR_GENERIC_SUFFIX
}

public func GenerateWrapperClassInstOverrideFuncMangleName(def: ClassDef): String {
    return MANGLE_CHIR_FUNC_PREFIX + def.GetIdentifierWithoutPrefix() + MANGLE_ABSTRACT_INST_PREFIX
}
