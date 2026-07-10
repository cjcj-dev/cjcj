package cjcj::ast

public enum TypeKind {
    | TYPE_INVALID
    | TYPE_UNIT
    | TYPE_INT8
    | TYPE_INT16
    | TYPE_INT32
    | TYPE_INT64
    | TYPE_INT_NATIVE
    | TYPE_IDEAL_INT
    | TYPE_UINT8
    | TYPE_UINT16
    | TYPE_UINT32
    | TYPE_UINT64
    | TYPE_UINT_NATIVE
    | TYPE_FLOAT16
    | TYPE_FLOAT32
    | TYPE_FLOAT64
    | TYPE_IDEAL_FLOAT
    | TYPE_RUNE
    | TYPE_NOTHING
    | TYPE_BOOLEAN
    | TYPE_TUPLE
    | TYPE_ENUM
    | TYPE_FUNC
    | TYPE_STRUCT
    | TYPE_ARRAY
    | TYPE_VARRAY
    | TYPE_POINTER
    | TYPE_CSTRING
    | TYPE_CLASS
    | TYPE_INTERFACE
    | TYPE
    | TYPE_GENERICS
    | TYPE_ANY
    | TYPE_INTERSECTION
    | TYPE_UNION
    | TYPE_QUEST
    | TYPE_INITIAL
}

public func TypeKindIndex(kind: TypeKind): Int64 {
    return match (kind) {
        case TypeKind.TYPE_INVALID => 0
        case TypeKind.TYPE_UNIT => 1
        case TypeKind.TYPE_INT8 => 2
        case TypeKind.TYPE_INT16 => 3
        case TypeKind.TYPE_INT32 => 4
        case TypeKind.TYPE_INT64 => 5
        case TypeKind.TYPE_INT_NATIVE => 6
        case TypeKind.TYPE_IDEAL_INT => 7
        case TypeKind.TYPE_UINT8 => 8
        case TypeKind.TYPE_UINT16 => 9
        case TypeKind.TYPE_UINT32 => 10
        case TypeKind.TYPE_UINT64 => 11
        case TypeKind.TYPE_UINT_NATIVE => 12
        case TypeKind.TYPE_FLOAT16 => 13
        case TypeKind.TYPE_FLOAT32 => 14
        case TypeKind.TYPE_FLOAT64 => 15
        case TypeKind.TYPE_IDEAL_FLOAT => 16
        case TypeKind.TYPE_RUNE => 17
        case TypeKind.TYPE_NOTHING => 18
        case TypeKind.TYPE_BOOLEAN => 19
        case TypeKind.TYPE_TUPLE => 20
        case TypeKind.TYPE_ENUM => 21
        case TypeKind.TYPE_FUNC => 22
        case TypeKind.TYPE_STRUCT => 23
        case TypeKind.TYPE_ARRAY => 24
        case TypeKind.TYPE_VARRAY => 25
        case TypeKind.TYPE_POINTER => 26
        case TypeKind.TYPE_CSTRING => 27
        case TypeKind.TYPE_CLASS => 28
        case TypeKind.TYPE_INTERFACE => 29
        case TypeKind.TYPE => 30
        case TypeKind.TYPE_GENERICS => 31
        case TypeKind.TYPE_ANY => 32
        case TypeKind.TYPE_INTERSECTION => 33
        case TypeKind.TYPE_UNION => 34
        case TypeKind.TYPE_QUEST => 35
        case TypeKind.TYPE_INITIAL => 36
    }
}

extend TypeKind <: Equatable<TypeKind> {
    public operator func ==(right: TypeKind): Bool {
        return TypeKindIndex(this) == TypeKindIndex(right)
    }

    public operator func !=(right: TypeKind): Bool {
        return !(this == right)
    }
}

public func TypeKindName(kind: TypeKind): String {
    return match (kind) {
        case TypeKind.TYPE_INVALID => "Invalid"
        case TypeKind.TYPE_UNIT => "Unit"
        case TypeKind.TYPE_INT8 => "Int8"
        case TypeKind.TYPE_INT16 => "Int16"
        case TypeKind.TYPE_INT32 => "Int32"
        case TypeKind.TYPE_INT64 => "Int64"
        case TypeKind.TYPE_INT_NATIVE => "IntNative"
        case TypeKind.TYPE_IDEAL_INT => "Int"
        case TypeKind.TYPE_UINT8 => "UInt8"
        case TypeKind.TYPE_UINT16 => "UInt16"
        case TypeKind.TYPE_UINT32 => "UInt32"
        case TypeKind.TYPE_UINT64 => "UInt64"
        case TypeKind.TYPE_UINT_NATIVE => "UIntNative"
        case TypeKind.TYPE_FLOAT16 => "Float16"
        case TypeKind.TYPE_FLOAT32 => "Float32"
        case TypeKind.TYPE_FLOAT64 => "Float64"
        case TypeKind.TYPE_IDEAL_FLOAT => "Float"
        case TypeKind.TYPE_RUNE => "Rune"
        case TypeKind.TYPE_NOTHING => "Nothing"
        case TypeKind.TYPE_BOOLEAN => "Bool"
        case TypeKind.TYPE_TUPLE => "Tuple"
        case TypeKind.TYPE_ENUM => "Enum"
        case TypeKind.TYPE_FUNC => "Function"
        case TypeKind.TYPE_STRUCT => "Struct"
        case TypeKind.TYPE_ARRAY => "RawArray"
        case TypeKind.TYPE_VARRAY => "VArray"
        case TypeKind.TYPE_POINTER => "CPointer"
        case TypeKind.TYPE_CSTRING => "CString"
        case TypeKind.TYPE_CLASS => "Class"
        case TypeKind.TYPE_INTERFACE => "Interface"
        case TypeKind.TYPE => "TypeAlias"
        case TypeKind.TYPE_GENERICS => "Generic"
        case _ => "UnknownType"
    }
}

public func TypeKindFromName(name: String): TypeKind {
    return match (name) {
        case "Unit" => TypeKind.TYPE_UNIT
        case "Int8" => TypeKind.TYPE_INT8
        case "Int16" => TypeKind.TYPE_INT16
        case "Int32" => TypeKind.TYPE_INT32
        case "Int64" => TypeKind.TYPE_INT64
        case "IntNative" => TypeKind.TYPE_INT_NATIVE
        case "Int" => TypeKind.TYPE_IDEAL_INT
        case "UInt8" => TypeKind.TYPE_UINT8
        case "UInt16" => TypeKind.TYPE_UINT16
        case "UInt32" => TypeKind.TYPE_UINT32
        case "UInt64" => TypeKind.TYPE_UINT64
        case "UIntNative" => TypeKind.TYPE_UINT_NATIVE
        case "Float16" => TypeKind.TYPE_FLOAT16
        case "Float32" => TypeKind.TYPE_FLOAT32
        case "Float64" => TypeKind.TYPE_FLOAT64
        case "Float" => TypeKind.TYPE_IDEAL_FLOAT
        case "Rune" => TypeKind.TYPE_RUNE
        case "Nothing" => TypeKind.TYPE_NOTHING
        case "Bool" => TypeKind.TYPE_BOOLEAN
        case "Tuple" => TypeKind.TYPE_TUPLE
        case "Enum" => TypeKind.TYPE_ENUM
        case "Function" => TypeKind.TYPE_FUNC
        case "Struct" => TypeKind.TYPE_STRUCT
        case "RawArray" => TypeKind.TYPE_ARRAY
        case "VArray" => TypeKind.TYPE_VARRAY
        case "CPointer" => TypeKind.TYPE_POINTER
        case "CString" => TypeKind.TYPE_CSTRING
        case "Class" => TypeKind.TYPE_CLASS
        case "Interface" => TypeKind.TYPE_INTERFACE
        case "TypeAlias" => TypeKind.TYPE
        case "Generic" => TypeKind.TYPE_GENERICS
        case "Any" => TypeKind.TYPE_ANY
        case "Intersection" => TypeKind.TYPE_INTERSECTION
        case "Union" => TypeKind.TYPE_UNION
        case "Quest" => TypeKind.TYPE_QUEST
        case "Initial" => TypeKind.TYPE_INITIAL
        case _ => TypeKind.TYPE_INVALID
    }
}

public func TypeKindInRange(kind: TypeKind, low: TypeKind, high: TypeKind): Bool {
    let idx = TypeKindIndex(kind)
    return idx >= TypeKindIndex(low) && idx <= TypeKindIndex(high)
}
