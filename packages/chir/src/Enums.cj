package cangjie_compiler::chir

public enum TypeKind {
    | TYPE_INVALID
    | TYPE_INT8 | TYPE_INT16 | TYPE_INT32 | TYPE_INT64 | TYPE_INT_NATIVE
    | TYPE_UINT8 | TYPE_UINT16 | TYPE_UINT32 | TYPE_UINT64 | TYPE_UINT_NATIVE
    | TYPE_FLOAT16 | TYPE_FLOAT32 | TYPE_FLOAT64
    | TYPE_RUNE | TYPE_BOOLEAN | TYPE_UNIT | TYPE_NOTHING | TYPE_VOID
    | TYPE_TUPLE | TYPE_STRUCT | TYPE_ENUM | TYPE_FUNC | TYPE_CLASS
    | TYPE_RAWARRAY | TYPE_VARRAY | TYPE_CPOINTER | TYPE_CSTRING
    | TYPE_GENERIC | TYPE_REFTYPE | TYPE_BOXTYPE | TYPE_THIS
}

public func TypeKindIndex(kind: TypeKind): Int64 {
    return match (kind) {
        case TypeKind.TYPE_INVALID => 0
        case TypeKind.TYPE_INT8 => 1
        case TypeKind.TYPE_INT16 => 2
        case TypeKind.TYPE_INT32 => 3
        case TypeKind.TYPE_INT64 => 4
        case TypeKind.TYPE_INT_NATIVE => 5
        case TypeKind.TYPE_UINT8 => 6
        case TypeKind.TYPE_UINT16 => 7
        case TypeKind.TYPE_UINT32 => 8
        case TypeKind.TYPE_UINT64 => 9
        case TypeKind.TYPE_UINT_NATIVE => 10
        case TypeKind.TYPE_FLOAT16 => 11
        case TypeKind.TYPE_FLOAT32 => 12
        case TypeKind.TYPE_FLOAT64 => 13
        case TypeKind.TYPE_RUNE => 14
        case TypeKind.TYPE_BOOLEAN => 15
        case TypeKind.TYPE_UNIT => 16
        case TypeKind.TYPE_NOTHING => 17
        case TypeKind.TYPE_VOID => 18
        case TypeKind.TYPE_TUPLE => 19
        case TypeKind.TYPE_STRUCT => 20
        case TypeKind.TYPE_ENUM => 21
        case TypeKind.TYPE_FUNC => 22
        case TypeKind.TYPE_CLASS => 23
        case TypeKind.TYPE_RAWARRAY => 24
        case TypeKind.TYPE_VARRAY => 25
        case TypeKind.TYPE_CPOINTER => 26
        case TypeKind.TYPE_CSTRING => 27
        case TypeKind.TYPE_GENERIC => 28
        case TypeKind.TYPE_REFTYPE => 29
        case TypeKind.TYPE_BOXTYPE => 30
        case TypeKind.TYPE_THIS => 31
    }
}

public func TypeKindName(kind: TypeKind): String {
    return match (kind) {
        case TypeKind.TYPE_INVALID => "Invalid"
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
        case TypeKind.TYPE_VOID => "Void"
        case TypeKind.TYPE_TUPLE => "Tuple"
        case TypeKind.TYPE_STRUCT => "Struct"
        case TypeKind.TYPE_ENUM => "Enum"
        case TypeKind.TYPE_FUNC => "Func"
        case TypeKind.TYPE_CLASS => "Class"
        case TypeKind.TYPE_RAWARRAY => "RawArray"
        case TypeKind.TYPE_VARRAY => "VArray"
        case TypeKind.TYPE_CPOINTER => "CPointer"
        case TypeKind.TYPE_CSTRING => "CString"
        case TypeKind.TYPE_GENERIC => "Generic"
        case TypeKind.TYPE_REFTYPE => "Ref"
        case TypeKind.TYPE_BOXTYPE => "Box"
        case TypeKind.TYPE_THIS => "This"
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

extend TypeKind <: Hashable {
    public func hashCode(): Int64 {
        return TypeKindIndex(this)
    }
}

public enum Attribute {
    | STATIC | PUBLIC | PRIVATE | PROTECTED
    | ABSTRACT | VIRTUAL | OVERRIDE | REDEF | SEALED | FOREIGN
    | MUT | FINAL | OPERATOR | READONLY | CONST | IMPORTED | GENERIC_INSTANTIATED
    | NO_DEBUG_INFO | GENERIC | INTERNAL | COMPILER_ADD | NO_REFLECT_INFO | NO_INLINE
    | NON_RECOMPILE | UNREACHABLE | NO_SIDE_EFFECT | COMMON | SPECIFIC | SKIP_ANALYSIS
    | DESERIALIZED | INITIALIZER | UNSAFE | JAVA_MIRROR | JAVA_IMPL | OBJ_C_MIRROR
    | HAS_INITED_FIELD | JAVA_HAS_DEFAULT | PREVIOUSLY_DESERIALIZED
    | FAST_NATIVE
    // FEATURE_DEBT(CJCJ_RUNTIME_SPEC §3.2/§7): selfhost-only extension domain;
    // upstream CHIR AttributeInfo.h still ends its C++ attribute domain at 38.
    | NO_HEAP_ALLOC | NO_WRITE_BARRIER_REC | NO_STACK_GROW
}

public func AttributeIndex(attr: Attribute): Int64 {
    return match (attr) {
        case Attribute.STATIC => 0
        case Attribute.PUBLIC => 1
        case Attribute.PRIVATE => 2
        case Attribute.PROTECTED => 3
        case Attribute.ABSTRACT => 4
        case Attribute.VIRTUAL => 5
        case Attribute.OVERRIDE => 6
        case Attribute.REDEF => 7
        case Attribute.SEALED => 8
        case Attribute.FOREIGN => 9
        case Attribute.MUT => 10
        case Attribute.FINAL => 11
        case Attribute.OPERATOR => 12
        case Attribute.READONLY => 13
        case Attribute.CONST => 14
        case Attribute.IMPORTED => 15
        case Attribute.GENERIC_INSTANTIATED => 16
        case Attribute.NO_DEBUG_INFO => 17
        case Attribute.GENERIC => 18
        case Attribute.INTERNAL => 19
        case Attribute.COMPILER_ADD => 20
        case Attribute.NO_REFLECT_INFO => 21
        case Attribute.NO_INLINE => 22
        case Attribute.NON_RECOMPILE => 23
        case Attribute.UNREACHABLE => 24
        case Attribute.NO_SIDE_EFFECT => 25
        case Attribute.COMMON => 26
        case Attribute.SPECIFIC => 27
        case Attribute.SKIP_ANALYSIS => 28
        case Attribute.DESERIALIZED => 29
        case Attribute.INITIALIZER => 30
        case Attribute.UNSAFE => 31
        case Attribute.JAVA_MIRROR => 32
        case Attribute.JAVA_IMPL => 33
        case Attribute.OBJ_C_MIRROR => 34
        case Attribute.HAS_INITED_FIELD => 35
        case Attribute.JAVA_HAS_DEFAULT => 36
        case Attribute.PREVIOUSLY_DESERIALIZED => 37
        case Attribute.FAST_NATIVE => 71
<<<<<<< HEAD
        case Attribute.THIN => 75
        case Attribute.NO_HEAP_ALLOC => 76
        case Attribute.NO_WRITE_BARRIER_REC => 77
        case Attribute.NO_STACK_GROW => 78
=======
>>>>>>> 57616346 (fix(chir): remove dead thin attribute value)
    }
}

public func AttributeName(attr: Attribute): String {
    return match (attr) {
        case Attribute.ABSTRACT => "abstract"
        case Attribute.COMMON => "common"
        case Attribute.COMPILER_ADD => "compilerAdd"
        case Attribute.CONST => "compileTimeVal"
        case Attribute.DESERIALIZED => "deserialized"
        case Attribute.FAST_NATIVE => "fastNative"
        case Attribute.FINAL => "final"
        case Attribute.FOREIGN => "foreign"
        case Attribute.GENERIC => "generic"
        case Attribute.GENERIC_INSTANTIATED => "generic_instantiated"
        case Attribute.HAS_INITED_FIELD => "hasInitedField"
        case Attribute.IMPORTED => "imported"
        case Attribute.INITIALIZER => "initializer"
        case Attribute.INTERNAL => "internal"
        case Attribute.JAVA_HAS_DEFAULT => "javaHasDefault"
        case Attribute.JAVA_IMPL => "javaImpl"
        case Attribute.JAVA_MIRROR => "javaMirror"
        case Attribute.MUT => "mut"
        case Attribute.NO_DEBUG_INFO => "noDebugInfo"
        case Attribute.NO_INLINE => "noInline"
        case Attribute.NO_REFLECT_INFO => "noReflectInfo"
        case Attribute.NO_SIDE_EFFECT => "noSideEffect"
        case Attribute.NON_RECOMPILE => "nonRecompile"
        case Attribute.OBJ_C_MIRROR => "objCMirror"
        case Attribute.OPERATOR => "operator"
        case Attribute.PREVIOUSLY_DESERIALIZED => "previouslyDeserialized"
        case Attribute.PRIVATE => "private"
        case Attribute.PROTECTED => "protected"
        case Attribute.PUBLIC => "public"
        case Attribute.READONLY => "readOnly"
        case Attribute.REDEF => "redef"
        case Attribute.SEALED => "sealed"
        case Attribute.SKIP_ANALYSIS => "skip_analysis"
        case Attribute.SPECIFIC => "specific"
        case Attribute.STATIC => "static"
<<<<<<< HEAD
        case Attribute.THIN => "thin"
        case Attribute.NO_HEAP_ALLOC => "noHeapAlloc"
        case Attribute.NO_WRITE_BARRIER_REC => "noWriteBarrierRec"
        case Attribute.NO_STACK_GROW => "noStackGrow"
=======
>>>>>>> 57616346 (fix(chir): remove dead thin attribute value)
        case Attribute.UNREACHABLE => "unreachable"
        case Attribute.UNSAFE => "unsafe"
        case Attribute.OVERRIDE => "override"
        case Attribute.VIRTUAL => "virtual"
    }
}

extend Attribute <: Equatable<Attribute> {
    public operator func ==(right: Attribute): Bool {
        return AttributeIndex(this) == AttributeIndex(right)
    }

    public operator func !=(right: Attribute): Bool {
        return !(this == right)
    }
}

extend Attribute <: Hashable {
    public func hashCode(): Int64 {
        return AttributeIndex(this)
    }
}

public enum Linkage {
    | WEAK_ODR
    | EXTERNAL
    | INTERNAL
    | LINKONCE_ODR
    | EXTERNAL_WEAK
}

public func LinkageToInt(value: Linkage): Int64 {
    return match (value) {
        case Linkage.WEAK_ODR => 0
        case Linkage.EXTERNAL => 1
        case Linkage.INTERNAL => 2
        case Linkage.LINKONCE_ODR => 3
        case Linkage.EXTERNAL_WEAK => 4
    }
}

extend Linkage <: Equatable<Linkage> {
    public operator func ==(right: Linkage): Bool {
        return LinkageToInt(this) == LinkageToInt(right)
    }

    public operator func !=(right: Linkage): Bool {
        return !(this == right)
    }
}

public enum AccessLevel {
    | INVALID | INTERNAL | PROTECTED | PUBLIC
}

public func AccessLevelIndex(level: AccessLevel): Int64 {
    return match (level) {
        case AccessLevel.INVALID => 0
        case AccessLevel.INTERNAL => 1
        case AccessLevel.PROTECTED => 2
        case AccessLevel.PUBLIC => 3
    }
}

extend AccessLevel <: Equatable<AccessLevel> {
    public operator func ==(right: AccessLevel): Bool {
        return AccessLevelIndex(this) == AccessLevelIndex(right)
    }

    public operator func !=(right: AccessLevel): Bool {
        return !(this == right)
    }
}

public enum CustomDefKind {
    | TYPE_STRUCT | TYPE_ENUM | TYPE_CLASS | TYPE_EXTEND
}

public func CustomDefKindIndex(kind: CustomDefKind): Int64 {
    return match (kind) {
        case CustomDefKind.TYPE_STRUCT => 0
        case CustomDefKind.TYPE_ENUM => 1
        case CustomDefKind.TYPE_CLASS => 2
        case CustomDefKind.TYPE_EXTEND => 3
    }
}

extend CustomDefKind <: Equatable<CustomDefKind> {
    public operator func ==(right: CustomDefKind): Bool {
        return CustomDefKindIndex(this) == CustomDefKindIndex(right)
    }

    public operator func !=(right: CustomDefKind): Bool {
        return !(this == right)
    }
}

public enum ValueKind {
    | KIND_LITERAL | KIND_GLOBALVAR | KIND_PARAMETER | KIND_LOCALVAR
    | KIND_FUNC | KIND_BLOCK | KIND_BLOCK_GROUP
}

public func ValueKindIndex(kind: ValueKind): Int64 {
    return match (kind) {
        case ValueKind.KIND_LITERAL => 0
        case ValueKind.KIND_GLOBALVAR => 1
        case ValueKind.KIND_PARAMETER => 2
        case ValueKind.KIND_LOCALVAR => 3
        case ValueKind.KIND_FUNC => 4
        case ValueKind.KIND_BLOCK => 5
        case ValueKind.KIND_BLOCK_GROUP => 6
    }
}

extend ValueKind <: Equatable<ValueKind> {
    public operator func ==(right: ValueKind): Bool {
        return ValueKindIndex(this) == ValueKindIndex(right)
    }

    public operator func !=(right: ValueKind): Bool {
        return !(this == right)
    }
}

public enum FuncKind {
    | DEFAULT | GETTER | SETTER | LAMBDA | CLASS_CONSTRUCTOR | PRIMAL_CLASS_CONSTRUCTOR
    | STRUCT_CONSTRUCTOR | PRIMAL_STRUCT_CONSTRUCTOR | GLOBALVAR_INIT | FINALIZER
    | MAIN_ENTRY | ANNOFACTORY_FUNC | MACRO_FUNC | DEFAULT_PARAMETER_FUNC | INSTANCEVAR_INIT
}

public func FuncKindIndex(kind: FuncKind): Int64 {
    return match (kind) {
        case FuncKind.DEFAULT => 0
        case FuncKind.GETTER => 1
        case FuncKind.SETTER => 2
        case FuncKind.LAMBDA => 3
        case FuncKind.CLASS_CONSTRUCTOR => 4
        case FuncKind.PRIMAL_CLASS_CONSTRUCTOR => 5
        case FuncKind.STRUCT_CONSTRUCTOR => 6
        case FuncKind.PRIMAL_STRUCT_CONSTRUCTOR => 7
        case FuncKind.GLOBALVAR_INIT => 8
        case FuncKind.FINALIZER => 9
        case FuncKind.MAIN_ENTRY => 10
        case FuncKind.ANNOFACTORY_FUNC => 11
        case FuncKind.MACRO_FUNC => 12
        case FuncKind.DEFAULT_PARAMETER_FUNC => 13
        case FuncKind.INSTANCEVAR_INIT => 14
    }
}

public func FuncKindName(kind: FuncKind): String {
    return match (kind) {
        case FuncKind.DEFAULT => "default"
        case FuncKind.GETTER => "getter"
        case FuncKind.SETTER => "setter"
        case FuncKind.LAMBDA => "lambda"
        case FuncKind.CLASS_CONSTRUCTOR => "classConstructor"
        case FuncKind.PRIMAL_CLASS_CONSTRUCTOR => "classPrimalConstructor"
        case FuncKind.STRUCT_CONSTRUCTOR => "structConstructor"
        case FuncKind.PRIMAL_STRUCT_CONSTRUCTOR => "structPrimalConstructor"
        case FuncKind.GLOBALVAR_INIT => "globalVarInit"
        case FuncKind.FINALIZER => "finalizer"
        case FuncKind.MAIN_ENTRY => "mainEntry"
        case FuncKind.ANNOFACTORY_FUNC => "annoFactory"
        case FuncKind.MACRO_FUNC => "macro"
        case FuncKind.DEFAULT_PARAMETER_FUNC => "defaultParameter"
        case FuncKind.INSTANCEVAR_INIT => "memberVariablesInit"
    }
}

extend FuncKind <: Equatable<FuncKind> {
    public operator func ==(right: FuncKind): Bool {
        return FuncKindIndex(this) == FuncKindIndex(right)
    }

    public operator func !=(right: FuncKind): Bool {
        return !(this == right)
    }
}

public enum ExprMajorKind {
    | TERMINATOR | UNARY_EXPR | BINARY_EXPR | MEMORY_EXPR | STRUCTURED_CTRL_FLOW_EXPR | OTHERS
}

public func ExprMajorKindIndex(kind: ExprMajorKind): Int64 {
    return match (kind) {
        case ExprMajorKind.TERMINATOR => 0
        case ExprMajorKind.UNARY_EXPR => 1
        case ExprMajorKind.BINARY_EXPR => 2
        case ExprMajorKind.MEMORY_EXPR => 3
        case ExprMajorKind.STRUCTURED_CTRL_FLOW_EXPR => 4
        case ExprMajorKind.OTHERS => 5
    }
}

extend ExprMajorKind <: Equatable<ExprMajorKind> {
    public operator func ==(right: ExprMajorKind): Bool {
        return ExprMajorKindIndex(this) == ExprMajorKindIndex(right)
    }

    public operator func !=(right: ExprMajorKind): Bool {
        return !(this == right)
    }
}

public enum ExprKind {
    | INVALID
    | GOTO | BRANCH | MULTIBRANCH | EXIT | APPLY_WITH_EXCEPTION | INVOKE_WITH_EXCEPTION
    | INVOKESTATIC_WITH_EXCEPTION | RAISE_EXCEPTION | INT_OP_WITH_EXCEPTION | SPAWN_WITH_EXCEPTION
    | TYPECAST_WITH_EXCEPTION | INTRINSIC_WITH_EXCEPTION | ALLOCATE_WITH_EXCEPTION
    | RAW_ARRAY_ALLOCATE_WITH_EXCEPTION
    | NEG | NOT | BITNOT
    | ADD | SUB | MUL | DIV | MOD | EXP | LSHIFT | RSHIFT | BITAND | BITOR | BITXOR
    | LT | GT | LE | GE | EQUAL | NOTEQUAL | AND | OR
    | ALLOCATE | LOAD | STORE | GET_ELEMENT_REF | GET_ELEMENT_BY_NAME
    | STORE_ELEMENT_REF | STORE_ELEMENT_BY_NAME
    | FORIN_RANGE | FORIN_ITER | FORIN_CLOSED_RANGE | LAMBDA
    | CONSTANT | DEBUGEXPR | TUPLE | FIELD | FIELD_BY_NAME | APPLY | INVOKE | INVOKESTATIC
    | INSTANCEOF | TYPECAST | GET_EXCEPTION | RAW_ARRAY_ALLOCATE | RAW_ARRAY_LITERAL_INIT
    | RAW_ARRAY_INIT_BY_VALUE | VARRAY | VARRAY_BUILDER | INTRINSIC | SPAWN
    | GET_INSTANTIATE_VALUE | BOX | UNBOX | TRANSFORM_TO_GENERIC | TRANSFORM_TO_CONCRETE
    | UNBOX_TO_REF | GET_RTTI | GET_RTTI_STATIC
}

public func ExprKindIndex(kind: ExprKind): Int64 {
    return match (kind) {
        case ExprKind.INVALID => 0
        case ExprKind.GOTO => 1
        case ExprKind.BRANCH => 2
        case ExprKind.MULTIBRANCH => 3
        case ExprKind.EXIT => 4
        case ExprKind.APPLY_WITH_EXCEPTION => 5
        case ExprKind.INVOKE_WITH_EXCEPTION => 6
        case ExprKind.INVOKESTATIC_WITH_EXCEPTION => 7
        case ExprKind.RAISE_EXCEPTION => 8
        case ExprKind.INT_OP_WITH_EXCEPTION => 9
        case ExprKind.SPAWN_WITH_EXCEPTION => 10
        case ExprKind.TYPECAST_WITH_EXCEPTION => 11
        case ExprKind.INTRINSIC_WITH_EXCEPTION => 12
        case ExprKind.ALLOCATE_WITH_EXCEPTION => 13
        case ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION => 14
        case ExprKind.NEG => 15
        case ExprKind.NOT => 16
        case ExprKind.BITNOT => 17
        case ExprKind.ADD => 18
        case ExprKind.SUB => 19
        case ExprKind.MUL => 20
        case ExprKind.DIV => 21
        case ExprKind.MOD => 22
        case ExprKind.EXP => 23
        case ExprKind.LSHIFT => 24
        case ExprKind.RSHIFT => 25
        case ExprKind.BITAND => 26
        case ExprKind.BITOR => 27
        case ExprKind.BITXOR => 28
        case ExprKind.LT => 29
        case ExprKind.GT => 30
        case ExprKind.LE => 31
        case ExprKind.GE => 32
        case ExprKind.EQUAL => 33
        case ExprKind.NOTEQUAL => 34
        case ExprKind.AND => 35
        case ExprKind.OR => 36
        case ExprKind.ALLOCATE => 37
        case ExprKind.LOAD => 38
        case ExprKind.STORE => 39
        case ExprKind.GET_ELEMENT_REF => 40
        case ExprKind.GET_ELEMENT_BY_NAME => 41
        case ExprKind.STORE_ELEMENT_REF => 42
        case ExprKind.STORE_ELEMENT_BY_NAME => 43
        case ExprKind.FORIN_RANGE => 44
        case ExprKind.FORIN_ITER => 45
        case ExprKind.FORIN_CLOSED_RANGE => 46
        case ExprKind.LAMBDA => 47
        case ExprKind.CONSTANT => 48
        case ExprKind.DEBUGEXPR => 49
        case ExprKind.TUPLE => 50
        case ExprKind.FIELD => 51
        case ExprKind.FIELD_BY_NAME => 52
        case ExprKind.APPLY => 53
        case ExprKind.INVOKE => 54
        case ExprKind.INVOKESTATIC => 55
        case ExprKind.INSTANCEOF => 56
        case ExprKind.TYPECAST => 57
        case ExprKind.GET_EXCEPTION => 58
        case ExprKind.RAW_ARRAY_ALLOCATE => 59
        case ExprKind.RAW_ARRAY_LITERAL_INIT => 60
        case ExprKind.RAW_ARRAY_INIT_BY_VALUE => 61
        case ExprKind.VARRAY => 62
        case ExprKind.VARRAY_BUILDER => 63
        case ExprKind.INTRINSIC => 64
        case ExprKind.SPAWN => 65
        case ExprKind.GET_INSTANTIATE_VALUE => 66
        case ExprKind.BOX => 67
        case ExprKind.UNBOX => 68
        case ExprKind.TRANSFORM_TO_GENERIC => 69
        case ExprKind.TRANSFORM_TO_CONCRETE => 70
        case ExprKind.UNBOX_TO_REF => 71
        case ExprKind.GET_RTTI => 72
        case ExprKind.GET_RTTI_STATIC => 73
    }
}

public func ExprKindName(kind: ExprKind): String {
    return match (kind) {
        case ExprKind.INVALID => "INVALID"
        case ExprKind.GOTO => "GoTo"
        case ExprKind.BRANCH => "Branch"
        case ExprKind.MULTIBRANCH => "MultiBranch"
        case ExprKind.EXIT => "Exit"
        case ExprKind.APPLY_WITH_EXCEPTION => "ApplyWithException"
        case ExprKind.INVOKE_WITH_EXCEPTION => "InvokeWithException"
        case ExprKind.INVOKESTATIC_WITH_EXCEPTION => "InvokeStaticWithException"
        case ExprKind.RAISE_EXCEPTION => "RaiseException"
        case ExprKind.INT_OP_WITH_EXCEPTION => "IntOpWithException"
        case ExprKind.SPAWN_WITH_EXCEPTION => "SpawnWithException"
        case ExprKind.TYPECAST_WITH_EXCEPTION => "TypeCastWithException"
        case ExprKind.INTRINSIC_WITH_EXCEPTION => "IntrinsicWithException"
        case ExprKind.ALLOCATE_WITH_EXCEPTION => "AllocateWithException"
        case ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION => "RawArrayAllocateWithException"
        case ExprKind.NEG => "Neg"
        case ExprKind.NOT => "Not"
        case ExprKind.BITNOT => "BitNot"
        case ExprKind.ADD => "Add"
        case ExprKind.SUB => "Sub"
        case ExprKind.MUL => "Mul"
        case ExprKind.DIV => "Div"
        case ExprKind.MOD => "Mod"
        case ExprKind.EXP => "Exp"
        case ExprKind.LSHIFT => "LShift"
        case ExprKind.RSHIFT => "RShift"
        case ExprKind.BITAND => "BitAnd"
        case ExprKind.BITOR => "BitOr"
        case ExprKind.BITXOR => "BitXor"
        case ExprKind.LT => "LT"
        case ExprKind.GT => "GT"
        case ExprKind.LE => "LE"
        case ExprKind.GE => "GE"
        case ExprKind.EQUAL => "Equal"
        case ExprKind.NOTEQUAL => "NotEqual"
        case ExprKind.AND => "And"
        case ExprKind.OR => "Or"
        case ExprKind.ALLOCATE => "Allocate"
        case ExprKind.LOAD => "Load"
        case ExprKind.STORE => "Store"
        case ExprKind.GET_ELEMENT_REF => "GetElementRef"
        case ExprKind.GET_ELEMENT_BY_NAME => "GetElementByName"
        case ExprKind.STORE_ELEMENT_REF => "StoreElementRef"
        case ExprKind.STORE_ELEMENT_BY_NAME => "StoreElementByName"
        case ExprKind.FORIN_RANGE => "ForInRange"
        case ExprKind.FORIN_ITER => "ForInIter"
        case ExprKind.FORIN_CLOSED_RANGE => "ForInClosedRange"
        case ExprKind.LAMBDA => "Lambda"
        case ExprKind.CONSTANT => "Constant"
        case ExprKind.DEBUGEXPR => "Debug"
        case ExprKind.TUPLE => "Tuple"
        case ExprKind.FIELD => "Field"
        case ExprKind.FIELD_BY_NAME => "FieldByName"
        case ExprKind.APPLY => "Apply"
        case ExprKind.INVOKE => "Invoke"
        case ExprKind.INVOKESTATIC => "InvokeStatic"
        case ExprKind.INSTANCEOF => "InstanceOf"
        case ExprKind.TYPECAST => "TypeCast"
        case ExprKind.GET_EXCEPTION => "GetException"
        case ExprKind.RAW_ARRAY_ALLOCATE => "RawArrayAllocate"
        case ExprKind.RAW_ARRAY_LITERAL_INIT => "RawArrayLiteralInit"
        case ExprKind.RAW_ARRAY_INIT_BY_VALUE => "RawArrayInitByValue"
        case ExprKind.VARRAY => "VArray"
        case ExprKind.VARRAY_BUILDER => "VArrayBuilder"
        case ExprKind.INTRINSIC => "Intrinsic"
        case ExprKind.SPAWN => "Spawn"
        case ExprKind.GET_INSTANTIATE_VALUE => "GetInstantiateValue"
        case ExprKind.BOX => "Box"
        case ExprKind.UNBOX => "UnBox"
        case ExprKind.TRANSFORM_TO_GENERIC => "TransformToGeneric"
        case ExprKind.TRANSFORM_TO_CONCRETE => "TransformToConcrete"
        case ExprKind.UNBOX_TO_REF => "UnBoxToRef"
        case ExprKind.GET_RTTI => "GetRTTI"
        case ExprKind.GET_RTTI_STATIC => "GetRTTIStatic"
    }
}

public func ExprKindMajor(kind: ExprKind): ExprMajorKind {
    let index = ExprKindIndex(kind)
    if (index >= ExprKindIndex(ExprKind.GOTO) && index <= ExprKindIndex(ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION)) {
        return ExprMajorKind.TERMINATOR
    }
    if (index >= ExprKindIndex(ExprKind.NEG) && index <= ExprKindIndex(ExprKind.BITNOT)) {
        return ExprMajorKind.UNARY_EXPR
    }
    if (index >= ExprKindIndex(ExprKind.ADD) && index <= ExprKindIndex(ExprKind.OR)) {
        return ExprMajorKind.BINARY_EXPR
    }
    if (index >= ExprKindIndex(ExprKind.ALLOCATE) && index <= ExprKindIndex(ExprKind.STORE_ELEMENT_BY_NAME)) {
        return ExprMajorKind.MEMORY_EXPR
    }
    if (index >= ExprKindIndex(ExprKind.FORIN_RANGE) && index <= ExprKindIndex(ExprKind.LAMBDA)) {
        return ExprMajorKind.STRUCTURED_CTRL_FLOW_EXPR
    }
    return ExprMajorKind.OTHERS
}

extend ExprKind <: Equatable<ExprKind> {
    public operator func ==(right: ExprKind): Bool {
        return ExprKindIndex(this) == ExprKindIndex(right)
    }

    public operator func !=(right: ExprKind): Bool {
        return !(this == right)
    }
}

public enum SourceExpr {
    | IF_EXPR | WHILE_EXPR | DO_WHILE_EXPR | MATCH_EXPR | IF_LET_OR_WHILE_LET
    | QUEST | BINARY | FOR_IN_EXPR | OTHER
}

public func SourceExprIndex(kind: SourceExpr): Int64 {
    return match (kind) {
        case SourceExpr.IF_EXPR => 0
        case SourceExpr.WHILE_EXPR => 1
        case SourceExpr.DO_WHILE_EXPR => 2
        case SourceExpr.MATCH_EXPR => 3
        case SourceExpr.IF_LET_OR_WHILE_LET => 4
        case SourceExpr.QUEST => 5
        case SourceExpr.BINARY => 6
        case SourceExpr.FOR_IN_EXPR => 7
        case SourceExpr.OTHER => 8
    }
}

public func SourceExprName(kind: SourceExpr): String {
    return match (kind) {
        case SourceExpr.IF_EXPR => "IF_EXPR"
        case SourceExpr.WHILE_EXPR => "WHILE_EXPR"
        case SourceExpr.DO_WHILE_EXPR => "DO_WHILE_EXPR"
        case SourceExpr.MATCH_EXPR => "MATCH_EXPR"
        case SourceExpr.IF_LET_OR_WHILE_LET => "IF_LET_OR_WHILE_LET"
        case SourceExpr.QUEST => "QUEST"
        case SourceExpr.BINARY => "BINARY"
        case SourceExpr.FOR_IN_EXPR => "FOR_IN_EXPR"
        case SourceExpr.OTHER => "OTHER"
    }
}

extend SourceExpr <: Equatable<SourceExpr> {
    public operator func ==(right: SourceExpr): Bool {
        return SourceExprIndex(this) == SourceExprIndex(right)
    }

    public operator func !=(right: SourceExpr): Bool {
        return !(this == right)
    }
}

public enum LiteralKind {
    | NULL | BOOL | INT | FLOAT | RUNE | STRING | UNIT
}

public func LiteralKindIndex(kind: LiteralKind): Int64 {
    return match (kind) {
        case LiteralKind.NULL => 0
        case LiteralKind.BOOL => 1
        case LiteralKind.INT => 2
        case LiteralKind.FLOAT => 3
        case LiteralKind.RUNE => 4
        case LiteralKind.STRING => 5
        case LiteralKind.UNIT => 6
    }
}

extend LiteralKind <: Equatable<LiteralKind> {
    public operator func ==(right: LiteralKind): Bool {
        return LiteralKindIndex(this) == LiteralKindIndex(right)
    }

    public operator func !=(right: LiteralKind): Bool {
        return !(this == right)
    }
}
