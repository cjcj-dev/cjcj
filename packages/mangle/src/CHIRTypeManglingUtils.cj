package cangjie_compiler::mangle

import std.collection.*

public enum CHIRTypeKind {
    | TYPE_INVALID
    | TYPE_INT8
    | TYPE_INT16
    | TYPE_INT32
    | TYPE_INT64
    | TYPE_INT_NATIVE
    | TYPE_UINT8
    | TYPE_UINT16
    | TYPE_UINT32
    | TYPE_UINT64
    | TYPE_UINT_NATIVE
    | TYPE_FLOAT16
    | TYPE_FLOAT32
    | TYPE_FLOAT64
    | TYPE_RUNE
    | TYPE_BOOLEAN
    | TYPE_UNIT
    | TYPE_NOTHING
    | TYPE_CSTRING
    | TYPE_VOID
    | TYPE_TUPLE
    | TYPE_STRUCT
    | TYPE_ENUM
    | TYPE_FUNC
    | TYPE_CLASS
    | TYPE_RAWARRAY
    | TYPE_REFTYPE
    | TYPE_VARRAY
    | TYPE_CPOINTER
    | TYPE_GENERIC
    | TYPE_BOXTYPE
}

private func CHIRTypeKindIndex(kind: CHIRTypeKind): Int64 {
    return match (kind) {
        case CHIRTypeKind.TYPE_INVALID => 0
        case CHIRTypeKind.TYPE_INT8 => 1
        case CHIRTypeKind.TYPE_INT16 => 2
        case CHIRTypeKind.TYPE_INT32 => 3
        case CHIRTypeKind.TYPE_INT64 => 4
        case CHIRTypeKind.TYPE_INT_NATIVE => 5
        case CHIRTypeKind.TYPE_UINT8 => 6
        case CHIRTypeKind.TYPE_UINT16 => 7
        case CHIRTypeKind.TYPE_UINT32 => 8
        case CHIRTypeKind.TYPE_UINT64 => 9
        case CHIRTypeKind.TYPE_UINT_NATIVE => 10
        case CHIRTypeKind.TYPE_FLOAT16 => 11
        case CHIRTypeKind.TYPE_FLOAT32 => 12
        case CHIRTypeKind.TYPE_FLOAT64 => 13
        case CHIRTypeKind.TYPE_RUNE => 14
        case CHIRTypeKind.TYPE_BOOLEAN => 15
        case CHIRTypeKind.TYPE_UNIT => 16
        case CHIRTypeKind.TYPE_NOTHING => 17
        case CHIRTypeKind.TYPE_CSTRING => 18
        case CHIRTypeKind.TYPE_VOID => 19
        case CHIRTypeKind.TYPE_TUPLE => 20
        case CHIRTypeKind.TYPE_STRUCT => 21
        case CHIRTypeKind.TYPE_ENUM => 22
        case CHIRTypeKind.TYPE_FUNC => 23
        case CHIRTypeKind.TYPE_CLASS => 24
        case CHIRTypeKind.TYPE_RAWARRAY => 25
        case CHIRTypeKind.TYPE_REFTYPE => 26
        case CHIRTypeKind.TYPE_VARRAY => 27
        case CHIRTypeKind.TYPE_CPOINTER => 28
        case CHIRTypeKind.TYPE_GENERIC => 29
        case CHIRTypeKind.TYPE_BOXTYPE => 30
    }
}

extend CHIRTypeKind <: Equatable<CHIRTypeKind> {
    public operator func ==(right: CHIRTypeKind): Bool {
        return CHIRTypeKindIndex(this) == CHIRTypeKindIndex(right)
    }

    public operator func !=(right: CHIRTypeKind): Bool {
        return !(this == right)
    }
}

public class CHIRType {
    public var kind: CHIRTypeKind
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

    public init(kind: CHIRTypeKind) {
        this.kind = kind
    }

    public init(kind: CHIRTypeKind, name: String) {
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
            case CHIRTypeKind.TYPE_INT8 => "Int8"
            case CHIRTypeKind.TYPE_INT16 => "Int16"
            case CHIRTypeKind.TYPE_INT32 => "Int32"
            case CHIRTypeKind.TYPE_INT64 => "Int64"
            case CHIRTypeKind.TYPE_INT_NATIVE => "IntNative"
            case CHIRTypeKind.TYPE_UINT8 => "UInt8"
            case CHIRTypeKind.TYPE_UINT16 => "UInt16"
            case CHIRTypeKind.TYPE_UINT32 => "UInt32"
            case CHIRTypeKind.TYPE_UINT64 => "UInt64"
            case CHIRTypeKind.TYPE_UINT_NATIVE => "UIntNative"
            case CHIRTypeKind.TYPE_FLOAT16 => "Float16"
            case CHIRTypeKind.TYPE_FLOAT32 => "Float32"
            case CHIRTypeKind.TYPE_FLOAT64 => "Float64"
            case CHIRTypeKind.TYPE_RUNE => "Rune"
            case CHIRTypeKind.TYPE_BOOLEAN => "Bool"
            case CHIRTypeKind.TYPE_UNIT => "Unit"
            case CHIRTypeKind.TYPE_NOTHING => "Nothing"
            case CHIRTypeKind.TYPE_CSTRING => "CString"
            case CHIRTypeKind.TYPE_VOID => "Unit"
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

public func ManglePrimitive(kind: CHIRTypeKind): String {
    return match (kind) {
        case CHIRTypeKind.TYPE_INT8 => "a"
        case CHIRTypeKind.TYPE_INT16 => "s"
        case CHIRTypeKind.TYPE_INT32 => "i"
        case CHIRTypeKind.TYPE_INT64 => "l"
        case CHIRTypeKind.TYPE_INT_NATIVE => "q"
        case CHIRTypeKind.TYPE_UINT8 => "h"
        case CHIRTypeKind.TYPE_UINT16 => "t"
        case CHIRTypeKind.TYPE_UINT32 => "j"
        case CHIRTypeKind.TYPE_UINT64 => "m"
        case CHIRTypeKind.TYPE_UINT_NATIVE => "r"
        case CHIRTypeKind.TYPE_FLOAT16 => "Dh"
        case CHIRTypeKind.TYPE_FLOAT32 => "f"
        case CHIRTypeKind.TYPE_FLOAT64 => "d"
        case CHIRTypeKind.TYPE_RUNE => "c"
        case CHIRTypeKind.TYPE_BOOLEAN => "b"
        case CHIRTypeKind.TYPE_UNIT => "u"
        case CHIRTypeKind.TYPE_NOTHING => "n"
        case CHIRTypeKind.TYPE_CSTRING => "k"
        case CHIRTypeKind.TYPE_VOID => "u"
        case _ => ""
    }
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
    if (t.kind == CHIRTypeKind.TYPE_TUPLE) {
        var out = MANGLE_TUPLE_PREFIX + DecimalToManglingNumber("${t.typeArgs.size}")
        for (arg in t.typeArgs) {
            out += MangleCHIRType(arg, genericsTypeStack, useGenericName: useGenericName)
        }
        return out + MANGLE_SUFFIX
    }
    if (t.kind == CHIRTypeKind.TYPE_STRUCT || t.kind == CHIRTypeKind.TYPE_ENUM || t.kind == CHIRTypeKind.TYPE_CLASS) {
        let prefix = if (t.kind == CHIRTypeKind.TYPE_STRUCT) {
            MANGLE_TYPE_STRUCT_PREFIX
        } else if (t.kind == CHIRTypeKind.TYPE_ENUM) {
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
    if (t.kind == CHIRTypeKind.TYPE_FUNC) {
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
    if (t.kind == CHIRTypeKind.TYPE_RAWARRAY) {
        if (let Some(elem) <- t.elementType) {
            return MANGLE_TYPE_ARRAY_PREFIX + DecimalToManglingNumber("${t.dims}") +
                MangleCHIRType(elem, genericsTypeStack, useGenericName: useGenericName)
        }
    }
    if (t.kind == CHIRTypeKind.TYPE_REFTYPE) {
        if (let Some(base) <- t.baseType) {
            return MangleCHIRType(base, genericsTypeStack, useGenericName: useGenericName)
        }
    }
    if (t.kind == CHIRTypeKind.TYPE_VARRAY) {
        if (let Some(elem) <- t.elementType) {
            return MANGLE_VARRAY_PREFIX + DecimalToManglingNumber("${t.size}") +
                MangleCHIRType(elem, genericsTypeStack, useGenericName: useGenericName)
        }
    }
    if (t.kind == CHIRTypeKind.TYPE_CPOINTER) {
        if (let Some(elem) <- t.elementType) {
            return MANGLE_POINTER_PREFIX + MangleCHIRType(elem, genericsTypeStack, useGenericName: useGenericName)
        }
    }
    if (t.kind == CHIRTypeKind.TYPE_GENERIC) {
        if (useGenericName) {
            return MANGLE_CHIR_GENERIC_PREFIX + t.srcCodeIdentifier + "\n"
        }
        var idx = genericsTypeStack.size - 1
        while (idx >= 0) {
            if (genericsTypeStack[idx] == t.srcCodeIdentifier) {
                return MANGLE_CHIR_GENERIC_PREFIX + DecimalToManglingNumber("${idx}")
            }
            idx--
        }
        return MANGLE_CHIR_GENERIC_PREFIX + DecimalToManglingNumber("0")
    }
    return ""
}

public func GetTypeArgsQualifiedName(typeArgs: ArrayList<CHIRType>, forNameFieldOfTi!: Bool = false): String {
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
    if (t.kind == CHIRTypeKind.TYPE_RAWARRAY) {
        if (let Some(elem) <- t.elementType) {
            return MANGLE_RAWARR_STR + MANGLE_LT_PREFIX + GetTypeQualifiedName(elem,
                forNameFieldOfTi: forNameFieldOfTi) + MANGLE_GT_PREFIX
        }
    }
    if (t.kind == CHIRTypeKind.TYPE_REFTYPE) {
        if (let Some(base) <- t.baseType) {
            return GetTypeQualifiedName(base, forNameFieldOfTi: forNameFieldOfTi)
        }
    }
    if (t.kind == CHIRTypeKind.TYPE_VARRAY) {
        if (let Some(elem) <- t.elementType) {
            return MANGLE_VARR_STR + MANGLE_LT_PREFIX + GetTypeQualifiedName(elem,
                forNameFieldOfTi: forNameFieldOfTi) + "," + "${t.size}" + MANGLE_GT_PREFIX
        }
    }
    if (t.kind == CHIRTypeKind.TYPE_CPOINTER) {
        if (let Some(elem) <- t.elementType) {
            return MANGLE_CPTR_STR + MANGLE_LT_PREFIX + GetTypeQualifiedName(elem,
                forNameFieldOfTi: forNameFieldOfTi) + MANGLE_GT_PREFIX
        }
    }
    if (t.kind == CHIRTypeKind.TYPE_CSTRING) {
        return MANGLE_CSTRING_STR
    }
    if (t.kind == CHIRTypeKind.TYPE_TUPLE) {
        return MANGLE_TUPLE_STR + MANGLE_LT_PREFIX + GetTypeArgsQualifiedName(t.typeArgs,
            forNameFieldOfTi: forNameFieldOfTi) + MANGLE_GT_PREFIX
    }
    if (t.kind == CHIRTypeKind.TYPE_STRUCT || t.kind == CHIRTypeKind.TYPE_ENUM || t.kind == CHIRTypeKind.TYPE_CLASS) {
        return GetTypeQualifiedNameOfCustomType(t, forNameFieldOfTi: forNameFieldOfTi)
    }
    if (t.kind == CHIRTypeKind.TYPE_FUNC) {
        let params = GetTypeArgsQualifiedName(t.paramTypes, forNameFieldOfTi: forNameFieldOfTi)
        let ret = if (let Some(returnType) <- t.returnType) {
            GetTypeQualifiedName(returnType, forNameFieldOfTi: forNameFieldOfTi)
        } else {
            MANGLE_UNIT_STR
        }
        return "(${params})->" + ret
    }
    if (t.kind == CHIRTypeKind.TYPE_GENERIC) {
        return t.srcCodeIdentifier
    }
    if (t.kind == CHIRTypeKind.TYPE_VOID) {
        return MANGLE_UNIT_STR
    }
    if (t.kind == CHIRTypeKind.TYPE_BOXTYPE) {
        if (let Some(base) <- t.baseType) {
            let typeQualifiedName = GetTypeQualifiedName(base, forNameFieldOfTi: forNameFieldOfTi)
            return if (forNameFieldOfTi) { typeQualifiedName } else {
                MANGLE_BOX_STR + MANGLE_LT_PREFIX + typeQualifiedName + MANGLE_GT_PREFIX
            }
        }
    }
    return ""
}

public func GetTypeQualifiedNameOfCustomType(typeInfo: CHIRType, forNameFieldOfTi!: Bool = false): String {
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

public func GetCustomTypeIdentifier(typeInfo: CHIRType): String {
    return GetCustomTypeDefIdentifier(typeInfo)
}

public func GetCustomTypeDefIdentifier(def: CHIRType): String {
    if (def.srcCodeIdentifier.isEmpty() || (def.isPrivate && def.isInternalLinkage)) {
        return def.identifierWithoutPrefix
    }
    return def.srcCodeIdentifier
}
