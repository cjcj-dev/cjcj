package cangjie_compiler::mangle

import std.collection.*
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.CustomTypeDef
import cangjie_compiler::chir.MangleCHIRType as ChirMangleCHIRType
import cangjie_compiler::chir.ManglePrimitive as ChirManglePrimitive
import cangjie_compiler::chir.StripCangjiePrefix as ChirStripCangjiePrefix
import cangjie_compiler::chir.GetTypeArgsQualifiedName as ChirGetTypeArgsQualifiedName
import cangjie_compiler::chir.GetTypeQualifiedName as ChirGetTypeQualifiedName
import cangjie_compiler::chir.GetTypeQualifiedNameOfCustomType as ChirGetTypeQualifiedNameOfCustomType
import cangjie_compiler::chir.GetCustomTypeIdentifier as ChirGetCustomTypeIdentifier
import cangjie_compiler::chir.GetCustomTypeDefIdentifier as ChirGetCustomTypeDefIdentifier

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
    return ChirStripCangjiePrefix(identifier)
}

public func ManglePrimitive(kind: TypeKind): String {
    return ChirManglePrimitive(kind)
}

public func MangleCHIRType(t: Type): String {
    return ChirMangleCHIRType(t)
}

public func MangleCHIRType(t: Type, genericsTypeStack: ArrayList<String>, useGenericName!: Bool = false): String {
    return ChirMangleCHIRType(t, genericsTypeStack, useGenericName: useGenericName)
}

public func GetTypeArgsQualifiedName(typeArgs: ArrayList<Type>, forNameFieldOfTi!: Bool = false): String {
    return ChirGetTypeArgsQualifiedName(typeArgs, forNameFieldOfTi: forNameFieldOfTi)
}

public func GetTypeQualifiedName(t: Type, forNameFieldOfTi!: Bool = false): String {
    return ChirGetTypeQualifiedName(t, forNameFieldOfTi: forNameFieldOfTi)
}

public func GetTypeQualifiedNameOfCustomType(typeInfo: CustomType, forNameFieldOfTi!: Bool = false): String {
    return ChirGetTypeQualifiedNameOfCustomType(typeInfo, forNameFieldOfTi: forNameFieldOfTi)
}

public func GetCustomTypeIdentifier(typeInfo: CustomType): String {
    return ChirGetCustomTypeIdentifier(typeInfo)
}

public func GetCustomTypeDefIdentifier(def: CustomTypeDef): String {
    return ChirGetCustomTypeDefIdentifier(def)
}
