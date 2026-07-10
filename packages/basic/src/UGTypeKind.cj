package cjcj::basic

public enum UGTypeKind {
    | UG_CLASS
    | UG_INTERFACE
    | UG_RAWARRAY
    | UG_FUNC
    | UG_COMMON_ENUM
    | UG_WEAKREF
    | UG_INTEROP_FOREIGN_PROXY
    | UG_INTEROP_EXPORTED_REF
    | UG_GENERIC_CUSTOM
    | UG_GENERIC
    | UG_NOTHING
    | UG_UNIT
    | UG_BOOLEAN
    | UG_RUNE
    | UG_UINT8
    | UG_UINT16
    | UG_UINT32
    | UG_UINT64
    | UG_UINT_NATIVE
    | UG_INT8
    | UG_INT16
    | UG_INT32
    | UG_INT64
    | UG_INT_NATIVE
    | UG_FLOAT16
    | UG_FLOAT32
    | UG_FLOAT64
    | UG_CSTRING
    | UG_CPOINTER
    | UG_CFUNC
    | UG_VARRAY
    | UG_TUPLE
    | UG_STRUCT
    | UG_ENUM
}

public func UGTypeKindValue(kind: UGTypeKind): Int64 {
    return match (kind) {
        case UGTypeKind.UG_CLASS => -128
        case UGTypeKind.UG_INTERFACE => -127
        case UGTypeKind.UG_RAWARRAY => -126
        case UGTypeKind.UG_FUNC => -125
        case UGTypeKind.UG_COMMON_ENUM => -124
        case UGTypeKind.UG_WEAKREF => -123
        case UGTypeKind.UG_INTEROP_FOREIGN_PROXY => -122
        case UGTypeKind.UG_INTEROP_EXPORTED_REF => -121
        case UGTypeKind.UG_GENERIC_CUSTOM => -2
        case UGTypeKind.UG_GENERIC => -1
        case UGTypeKind.UG_NOTHING => 0
        case UGTypeKind.UG_UNIT => 1
        case UGTypeKind.UG_BOOLEAN => 2
        case UGTypeKind.UG_RUNE => 3
        case UGTypeKind.UG_UINT8 => 4
        case UGTypeKind.UG_UINT16 => 5
        case UGTypeKind.UG_UINT32 => 6
        case UGTypeKind.UG_UINT64 => 7
        case UGTypeKind.UG_UINT_NATIVE => 8
        case UGTypeKind.UG_INT8 => 9
        case UGTypeKind.UG_INT16 => 10
        case UGTypeKind.UG_INT32 => 11
        case UGTypeKind.UG_INT64 => 12
        case UGTypeKind.UG_INT_NATIVE => 13
        case UGTypeKind.UG_FLOAT16 => 14
        case UGTypeKind.UG_FLOAT32 => 15
        case UGTypeKind.UG_FLOAT64 => 16
        case UGTypeKind.UG_CSTRING => 17
        case UGTypeKind.UG_CPOINTER => 18
        case UGTypeKind.UG_CFUNC => 19
        case UGTypeKind.UG_VARRAY => 20
        case UGTypeKind.UG_TUPLE => 21
        case UGTypeKind.UG_STRUCT => 22
        case UGTypeKind.UG_ENUM => 23
    }
}
