package cjcj::chir

public enum OpCode {
    | GVAR | LVAR | GVAR_SET | LVAR_SET
    | ALLOCATE_CLASS | ALLOCATE_CLASS_EXC | ALLOCATE_STRUCT | ALLOCATE_STRUCT_EXC
    | ALLOCATE_RAW_ARRAY | ALLOCATE_RAW_ARRAY_EXC | ALLOCATE_RAW_ARRAY_LITERAL | ALLOCATE_RAW_ARRAY_LITERAL_EXC
    | RAW_ARRAY_LITERAL_INIT | RAW_ARRAY_INIT_BY_VALUE | ALLOCATE | ALLOCATE_EXC | FRAME
    | UINT8 | UINT16 | UINT32 | UINT64 | UINTNAT
    | INT8 | INT16 | INT32 | INT64 | INTNAT
    | FLOAT16 | FLOAT32 | FLOAT64 | RUNE | BOOL | UNIT | NULLPTR | STRING
    | TUPLE | ARRAY | VARRAY | VARRAY_BY_VALUE | VARRAY_GET | FUNC
    | RETURN | JUMP | BRANCH | EXIT | STORE | DROP | GETREF | STOREINREF
    | UN_NEG | UN_NEG_EXC | UN_NOT | UN_BITNOT | UN_INC | UN_DEC
    | BIN_ADD | BIN_SUB | BIN_MUL | BIN_DIV | BIN_MOD | BIN_EXP
    | BIN_ADD_EXC | BIN_SUB_EXC | BIN_MUL_EXC | BIN_DIV_EXC | BIN_MOD_EXC | BIN_EXP_EXC
    | BIN_LT | BIN_GT | BIN_LE | BIN_GE | BIN_NOTEQ | BIN_EQUAL
    | BIN_BITAND | BIN_BITOR | BIN_BITXOR
    | BIN_LSHIFT | BIN_RSHIFT | BIN_LSHIFT_EXC | BIN_RSHIFT_EXC
    | FIELD | FIELD_TPL | INVOKE | INVOKE_EXC | TYPECAST | TYPECAST_EXC | INSTANCEOF
    | APPLY | APPLY_EXC | CAPPLY | ASG | DEREF | RAISE | RAISE_EXC | GET_EXCEPTION | SYSCALL
    | INTRINSIC0 | INTRINSIC1 | INTRINSIC2 | INTRINSIC0_EXC | INTRINSIC1_EXC | INTRINSIC2_EXC
    | SWITCH | SPAWN | SPAWN_EXC | BOX | UNBOX | UNBOX_REF | NOT_SUPPORTED | ABORT | INVALID
}

public func OpCodeIndex(opCode: OpCode): Int64 {
    return match (opCode) {
        case OpCode.GVAR => 0
        case OpCode.LVAR => 1
        case OpCode.GVAR_SET => 2
        case OpCode.LVAR_SET => 3
        case OpCode.ALLOCATE_CLASS => 4
        case OpCode.ALLOCATE_CLASS_EXC => 5
        case OpCode.ALLOCATE_STRUCT => 6
        case OpCode.ALLOCATE_STRUCT_EXC => 7
        case OpCode.ALLOCATE_RAW_ARRAY => 8
        case OpCode.ALLOCATE_RAW_ARRAY_EXC => 9
        case OpCode.ALLOCATE_RAW_ARRAY_LITERAL => 10
        case OpCode.ALLOCATE_RAW_ARRAY_LITERAL_EXC => 11
        case OpCode.RAW_ARRAY_LITERAL_INIT => 12
        case OpCode.RAW_ARRAY_INIT_BY_VALUE => 13
        case OpCode.ALLOCATE => 14
        case OpCode.ALLOCATE_EXC => 15
        case OpCode.FRAME => 16
        case OpCode.UINT8 => 17
        case OpCode.UINT16 => 18
        case OpCode.UINT32 => 19
        case OpCode.UINT64 => 20
        case OpCode.UINTNAT => 21
        case OpCode.INT8 => 22
        case OpCode.INT16 => 23
        case OpCode.INT32 => 24
        case OpCode.INT64 => 25
        case OpCode.INTNAT => 26
        case OpCode.FLOAT16 => 27
        case OpCode.FLOAT32 => 28
        case OpCode.FLOAT64 => 29
        case OpCode.RUNE => 30
        case OpCode.BOOL => 31
        case OpCode.UNIT => 32
        case OpCode.NULLPTR => 33
        case OpCode.STRING => 34
        case OpCode.TUPLE => 35
        case OpCode.ARRAY => 36
        case OpCode.VARRAY => 37
        case OpCode.VARRAY_BY_VALUE => 38
        case OpCode.VARRAY_GET => 39
        case OpCode.FUNC => 40
        case OpCode.RETURN => 41
        case OpCode.JUMP => 42
        case OpCode.BRANCH => 43
        case OpCode.EXIT => 44
        case OpCode.STORE => 45
        case OpCode.DROP => 46
        case OpCode.GETREF => 47
        case OpCode.STOREINREF => 48
        case OpCode.UN_NEG => 49
        case OpCode.UN_NEG_EXC => 50
        case OpCode.UN_NOT => 51
        case OpCode.UN_BITNOT => 52
        case OpCode.UN_INC => 53
        case OpCode.UN_DEC => 54
        case OpCode.BIN_ADD => 55
        case OpCode.BIN_SUB => 56
        case OpCode.BIN_MUL => 57
        case OpCode.BIN_DIV => 58
        case OpCode.BIN_MOD => 59
        case OpCode.BIN_EXP => 60
        case OpCode.BIN_ADD_EXC => 61
        case OpCode.BIN_SUB_EXC => 62
        case OpCode.BIN_MUL_EXC => 63
        case OpCode.BIN_DIV_EXC => 64
        case OpCode.BIN_MOD_EXC => 65
        case OpCode.BIN_EXP_EXC => 66
        case OpCode.BIN_LT => 67
        case OpCode.BIN_GT => 68
        case OpCode.BIN_LE => 69
        case OpCode.BIN_GE => 70
        case OpCode.BIN_NOTEQ => 71
        case OpCode.BIN_EQUAL => 72
        case OpCode.BIN_BITAND => 73
        case OpCode.BIN_BITOR => 74
        case OpCode.BIN_BITXOR => 75
        case OpCode.BIN_LSHIFT => 76
        case OpCode.BIN_RSHIFT => 77
        case OpCode.BIN_LSHIFT_EXC => 78
        case OpCode.BIN_RSHIFT_EXC => 79
        case OpCode.FIELD => 80
        case OpCode.FIELD_TPL => 81
        case OpCode.INVOKE => 82
        case OpCode.INVOKE_EXC => 83
        case OpCode.TYPECAST => 84
        case OpCode.TYPECAST_EXC => 85
        case OpCode.INSTANCEOF => 86
        case OpCode.APPLY => 87
        case OpCode.APPLY_EXC => 88
        case OpCode.CAPPLY => 89
        case OpCode.ASG => 90
        case OpCode.DEREF => 91
        case OpCode.RAISE => 92
        case OpCode.RAISE_EXC => 93
        case OpCode.GET_EXCEPTION => 94
        case OpCode.SYSCALL => 95
        case OpCode.INTRINSIC0 => 96
        case OpCode.INTRINSIC1 => 97
        case OpCode.INTRINSIC2 => 98
        case OpCode.INTRINSIC0_EXC => 99
        case OpCode.INTRINSIC1_EXC => 100
        case OpCode.INTRINSIC2_EXC => 101
        case OpCode.SWITCH => 102
        case OpCode.SPAWN => 103
        case OpCode.SPAWN_EXC => 104
        case OpCode.BOX => 105
        case OpCode.UNBOX => 106
        case OpCode.UNBOX_REF => 107
        case OpCode.NOT_SUPPORTED => 108
        case OpCode.ABORT => 109
        case OpCode.INVALID => 110
    }
}

public func OpCodeFromIndex(index: Int64): OpCode {
    return match (index) {
        case 0 => OpCode.GVAR
        case 1 => OpCode.LVAR
        case 2 => OpCode.GVAR_SET
        case 3 => OpCode.LVAR_SET
        case 4 => OpCode.ALLOCATE_CLASS
        case 5 => OpCode.ALLOCATE_CLASS_EXC
        case 6 => OpCode.ALLOCATE_STRUCT
        case 7 => OpCode.ALLOCATE_STRUCT_EXC
        case 8 => OpCode.ALLOCATE_RAW_ARRAY
        case 9 => OpCode.ALLOCATE_RAW_ARRAY_EXC
        case 10 => OpCode.ALLOCATE_RAW_ARRAY_LITERAL
        case 11 => OpCode.ALLOCATE_RAW_ARRAY_LITERAL_EXC
        case 12 => OpCode.RAW_ARRAY_LITERAL_INIT
        case 13 => OpCode.RAW_ARRAY_INIT_BY_VALUE
        case 14 => OpCode.ALLOCATE
        case 15 => OpCode.ALLOCATE_EXC
        case 16 => OpCode.FRAME
        case 17 => OpCode.UINT8
        case 18 => OpCode.UINT16
        case 19 => OpCode.UINT32
        case 20 => OpCode.UINT64
        case 21 => OpCode.UINTNAT
        case 22 => OpCode.INT8
        case 23 => OpCode.INT16
        case 24 => OpCode.INT32
        case 25 => OpCode.INT64
        case 26 => OpCode.INTNAT
        case 27 => OpCode.FLOAT16
        case 28 => OpCode.FLOAT32
        case 29 => OpCode.FLOAT64
        case 30 => OpCode.RUNE
        case 31 => OpCode.BOOL
        case 32 => OpCode.UNIT
        case 33 => OpCode.NULLPTR
        case 34 => OpCode.STRING
        case 35 => OpCode.TUPLE
        case 36 => OpCode.ARRAY
        case 37 => OpCode.VARRAY
        case 38 => OpCode.VARRAY_BY_VALUE
        case 39 => OpCode.VARRAY_GET
        case 40 => OpCode.FUNC
        case 41 => OpCode.RETURN
        case 42 => OpCode.JUMP
        case 43 => OpCode.BRANCH
        case 44 => OpCode.EXIT
        case 45 => OpCode.STORE
        case 46 => OpCode.DROP
        case 47 => OpCode.GETREF
        case 48 => OpCode.STOREINREF
        case 49 => OpCode.UN_NEG
        case 50 => OpCode.UN_NEG_EXC
        case 51 => OpCode.UN_NOT
        case 52 => OpCode.UN_BITNOT
        case 53 => OpCode.UN_INC
        case 54 => OpCode.UN_DEC
        case 55 => OpCode.BIN_ADD
        case 56 => OpCode.BIN_SUB
        case 57 => OpCode.BIN_MUL
        case 58 => OpCode.BIN_DIV
        case 59 => OpCode.BIN_MOD
        case 60 => OpCode.BIN_EXP
        case 61 => OpCode.BIN_ADD_EXC
        case 62 => OpCode.BIN_SUB_EXC
        case 63 => OpCode.BIN_MUL_EXC
        case 64 => OpCode.BIN_DIV_EXC
        case 65 => OpCode.BIN_MOD_EXC
        case 66 => OpCode.BIN_EXP_EXC
        case 67 => OpCode.BIN_LT
        case 68 => OpCode.BIN_GT
        case 69 => OpCode.BIN_LE
        case 70 => OpCode.BIN_GE
        case 71 => OpCode.BIN_NOTEQ
        case 72 => OpCode.BIN_EQUAL
        case 73 => OpCode.BIN_BITAND
        case 74 => OpCode.BIN_BITOR
        case 75 => OpCode.BIN_BITXOR
        case 76 => OpCode.BIN_LSHIFT
        case 77 => OpCode.BIN_RSHIFT
        case 78 => OpCode.BIN_LSHIFT_EXC
        case 79 => OpCode.BIN_RSHIFT_EXC
        case 80 => OpCode.FIELD
        case 81 => OpCode.FIELD_TPL
        case 82 => OpCode.INVOKE
        case 83 => OpCode.INVOKE_EXC
        case 84 => OpCode.TYPECAST
        case 85 => OpCode.TYPECAST_EXC
        case 86 => OpCode.INSTANCEOF
        case 87 => OpCode.APPLY
        case 88 => OpCode.APPLY_EXC
        case 89 => OpCode.CAPPLY
        case 90 => OpCode.ASG
        case 91 => OpCode.DEREF
        case 92 => OpCode.RAISE
        case 93 => OpCode.RAISE_EXC
        case 94 => OpCode.GET_EXCEPTION
        case 95 => OpCode.SYSCALL
        case 96 => OpCode.INTRINSIC0
        case 97 => OpCode.INTRINSIC1
        case 98 => OpCode.INTRINSIC2
        case 99 => OpCode.INTRINSIC0_EXC
        case 100 => OpCode.INTRINSIC1_EXC
        case 101 => OpCode.INTRINSIC2_EXC
        case 102 => OpCode.SWITCH
        case 103 => OpCode.SPAWN
        case 104 => OpCode.SPAWN_EXC
        case 105 => OpCode.BOX
        case 106 => OpCode.UNBOX
        case 107 => OpCode.UNBOX_REF
        case 108 => OpCode.NOT_SUPPORTED
        case 109 => OpCode.ABORT
        case _ => OpCode.INVALID
    }
}

extend OpCode <: Equatable<OpCode> {
    public operator func ==(right: OpCode): Bool {
        return OpCodeIndex(this) == OpCodeIndex(right)
    }

    public operator func !=(right: OpCode): Bool {
        return !(this == right)
    }
}

public func GetOpCodeLabel(opCode: OpCode): String {
    return match (opCode) {
        case OpCode.GVAR => "GVAR"
        case OpCode.LVAR => "LVAR"
        case OpCode.GVAR_SET => "GVAR_SET"
        case OpCode.LVAR_SET => "LVAR_SET"
        case OpCode.ALLOCATE_CLASS => "ALLOCATE_CLASS"
        case OpCode.ALLOCATE_CLASS_EXC => "ALLOCATE_CLASS_EXC"
        case OpCode.ALLOCATE_STRUCT => "ALLOCATE_STRUCT"
        case OpCode.ALLOCATE_STRUCT_EXC => "ALLOCATE_STRUCT_EXC"
        case OpCode.ALLOCATE_RAW_ARRAY => "ALLOCATE_RAW_ARRAY"
        case OpCode.ALLOCATE_RAW_ARRAY_EXC => "ALLOCATE_RAW_ARRAY_EXC"
        case OpCode.ALLOCATE_RAW_ARRAY_LITERAL => "ALLOCATE_RAW_ARRAY_LITERAL"
        case OpCode.ALLOCATE_RAW_ARRAY_LITERAL_EXC => "ALLOCATE_RAW_ARRAY_LITERAL_EXC"
        case OpCode.RAW_ARRAY_LITERAL_INIT => "RAW_ARRAY_LITERAL_INIT"
        case OpCode.RAW_ARRAY_INIT_BY_VALUE => "RAW_ARRAY_INIT_BY_VALUE"
        case OpCode.ALLOCATE => "ALLOCATE"
        case OpCode.ALLOCATE_EXC => "ALLOCATE_EXC"
        case OpCode.FRAME => "FRAME"
        case OpCode.UINT8 => "UINT8"
        case OpCode.UINT16 => "UINT16"
        case OpCode.UINT32 => "UINT32"
        case OpCode.UINT64 => "UINT64"
        case OpCode.UINTNAT => "UINTNAT"
        case OpCode.INT8 => "INT8"
        case OpCode.INT16 => "INT16"
        case OpCode.INT32 => "INT32"
        case OpCode.INT64 => "INT64"
        case OpCode.INTNAT => "INTNAT"
        case OpCode.FLOAT16 => "FLOAT16"
        case OpCode.FLOAT32 => "FLOAT32"
        case OpCode.FLOAT64 => "FLOAT64"
        case OpCode.RUNE => "RUNE"
        case OpCode.BOOL => "BOOL"
        case OpCode.UNIT => "UNIT"
        case OpCode.NULLPTR => "NULLPTR"
        case OpCode.STRING => "STRING"
        case OpCode.TUPLE => "TUPLE"
        case OpCode.ARRAY => "ARRAY"
        case OpCode.VARRAY => "VARRAY"
        case OpCode.VARRAY_BY_VALUE => "VARRAY_BY_VALUE"
        case OpCode.VARRAY_GET => "VARRAY_GET"
        case OpCode.FUNC => "FUNC"
        case OpCode.RETURN => "RETURN"
        case OpCode.JUMP => "JUMP"
        case OpCode.BRANCH => "BRANCH"
        case OpCode.EXIT => "EXIT"
        case OpCode.STORE => "STORE"
        case OpCode.DROP => "DROP"
        case OpCode.GETREF => "GETREF"
        case OpCode.STOREINREF => "STOREINREF"
        case OpCode.UN_NEG => "UN_NEG"
        case OpCode.UN_NEG_EXC => "UN_NEG_EXC"
        case OpCode.UN_NOT => "UN_NOT"
        case OpCode.UN_BITNOT => "UN_BITNOT"
        case OpCode.UN_INC => "UN_INC"
        case OpCode.UN_DEC => "UN_DEC"
        case OpCode.BIN_ADD => "BIN_ADD"
        case OpCode.BIN_SUB => "BIN_SUB"
        case OpCode.BIN_MUL => "BIN_MUL"
        case OpCode.BIN_DIV => "BIN_DIV"
        case OpCode.BIN_MOD => "BIN_MOD"
        case OpCode.BIN_EXP => "BIN_EXP"
        case OpCode.BIN_ADD_EXC => "BIN_ADD_EXC"
        case OpCode.BIN_SUB_EXC => "BIN_SUB_EXC"
        case OpCode.BIN_MUL_EXC => "BIN_MUL_EXC"
        case OpCode.BIN_DIV_EXC => "BIN_DIV_EXC"
        case OpCode.BIN_MOD_EXC => "BIN_MOD_EXC"
        case OpCode.BIN_EXP_EXC => "BIN_EXP_EXC"
        case OpCode.BIN_LT => "BIN_LT"
        case OpCode.BIN_GT => "BIN_GT"
        case OpCode.BIN_LE => "BIN_LE"
        case OpCode.BIN_GE => "BIN_GE"
        case OpCode.BIN_NOTEQ => "BIN_NOTEQ"
        case OpCode.BIN_EQUAL => "BIN_EQUAL"
        case OpCode.BIN_BITAND => "BIN_BITAND"
        case OpCode.BIN_BITOR => "BIN_BITOR"
        case OpCode.BIN_BITXOR => "BIN_BITXOR"
        case OpCode.BIN_LSHIFT => "BIN_LSHIFT"
        case OpCode.BIN_RSHIFT => "BIN_RSHIFT"
        case OpCode.BIN_LSHIFT_EXC => "BIN_LSHIFT_EXC"
        case OpCode.BIN_RSHIFT_EXC => "BIN_RSHIFT_EXC"
        case OpCode.FIELD => "FIELD"
        case OpCode.FIELD_TPL => "FIELD_TPL"
        case OpCode.INVOKE => "INVOKE"
        case OpCode.INVOKE_EXC => "INVOKE_EXC"
        case OpCode.TYPECAST => "TYPECAST"
        case OpCode.TYPECAST_EXC => "TYPECAST_EXC"
        case OpCode.INSTANCEOF => "INSTANCEOF"
        case OpCode.APPLY => "APPLY"
        case OpCode.APPLY_EXC => "APPLY_EXC"
        case OpCode.CAPPLY => "CAPPLY"
        case OpCode.ASG => "ASG"
        case OpCode.DEREF => "DEREF"
        case OpCode.RAISE => "RAISE"
        case OpCode.RAISE_EXC => "RAISE_EXC"
        case OpCode.GET_EXCEPTION => "GET_EXCEPTION"
        case OpCode.SYSCALL => "SYSCALL"
        case OpCode.INTRINSIC0 => "INTRINSIC0"
        case OpCode.INTRINSIC1 => "INTRINSIC1"
        case OpCode.INTRINSIC2 => "INTRINSIC2"
        case OpCode.INTRINSIC0_EXC => "INTRINSIC0_EXC"
        case OpCode.INTRINSIC1_EXC => "INTRINSIC1_EXC"
        case OpCode.INTRINSIC2_EXC => "INTRINSIC2_EXC"
        case OpCode.SWITCH => "SWITCH"
        case OpCode.SPAWN => "SPAWN"
        case OpCode.SPAWN_EXC => "SPAWN_EXC"
        case OpCode.BOX => "BOX"
        case OpCode.UNBOX => "UNBOX"
        case OpCode.UNBOX_REF => "UNBOX_REF"
        case OpCode.NOT_SUPPORTED => "NOT_SUPPORTED"
        case OpCode.ABORT => "ABORT"
        case OpCode.INVALID => "INVALID"
    }
}

public func GetOpCodeArgSize(opCode: OpCode): Int64 {
    return match (opCode) {
        case OpCode.GVAR | OpCode.LVAR | OpCode.GVAR_SET | OpCode.LVAR_SET => 1
        case OpCode.ALLOCATE_CLASS => 2
        case OpCode.ALLOCATE_CLASS_EXC => 3
        case OpCode.ALLOCATE_STRUCT => 1
        case OpCode.ALLOCATE_STRUCT_EXC => 2
        case OpCode.ALLOCATE_RAW_ARRAY => 0
        case OpCode.ALLOCATE_RAW_ARRAY_EXC => 1
        case OpCode.ALLOCATE_RAW_ARRAY_LITERAL => 1
        case OpCode.ALLOCATE_RAW_ARRAY_LITERAL_EXC => 2
        case OpCode.RAW_ARRAY_LITERAL_INIT => 1
        case OpCode.RAW_ARRAY_INIT_BY_VALUE => 0
        case OpCode.ALLOCATE => 0
        case OpCode.ALLOCATE_EXC => 1
        case OpCode.FRAME => 1
        case OpCode.UINT8 | OpCode.UINT16 | OpCode.UINT32 => 1
        case OpCode.UINT64 | OpCode.UINTNAT => 2
        case OpCode.INT8 | OpCode.INT16 | OpCode.INT32 => 1
        case OpCode.INT64 | OpCode.INTNAT => 2
        case OpCode.FLOAT16 | OpCode.FLOAT32 => 1
        case OpCode.FLOAT64 => 2
        case OpCode.RUNE | OpCode.BOOL | OpCode.STRING | OpCode.TUPLE | OpCode.ARRAY | OpCode.VARRAY => 1
        case OpCode.UNIT | OpCode.NULLPTR | OpCode.VARRAY_BY_VALUE => 0
        case OpCode.VARRAY_GET => 1
        case OpCode.FUNC => 1
        case OpCode.RETURN => 0
        case OpCode.JUMP => 1
        case OpCode.BRANCH => 2
        case OpCode.EXIT | OpCode.STORE | OpCode.DROP => 0
        case OpCode.GETREF | OpCode.STOREINREF => 1
        case OpCode.UN_NEG | OpCode.UN_NOT | OpCode.UN_BITNOT | OpCode.UN_INC | OpCode.UN_DEC => 2
        case OpCode.UN_NEG_EXC => 3
        case OpCode.BIN_ADD | OpCode.BIN_SUB | OpCode.BIN_MUL | OpCode.BIN_DIV | OpCode.BIN_MOD |
            OpCode.BIN_EXP | OpCode.BIN_LT | OpCode.BIN_GT | OpCode.BIN_LE | OpCode.BIN_GE |
            OpCode.BIN_NOTEQ | OpCode.BIN_EQUAL | OpCode.BIN_BITAND | OpCode.BIN_BITOR | OpCode.BIN_BITXOR => 2
        case OpCode.BIN_ADD_EXC | OpCode.BIN_SUB_EXC | OpCode.BIN_MUL_EXC | OpCode.BIN_DIV_EXC |
            OpCode.BIN_MOD_EXC | OpCode.BIN_EXP_EXC => 3
        case OpCode.BIN_LSHIFT | OpCode.BIN_RSHIFT => 3
        case OpCode.BIN_LSHIFT_EXC | OpCode.BIN_RSHIFT_EXC => 4
        case OpCode.FIELD => 1
        case OpCode.FIELD_TPL => 1
        case OpCode.INVOKE => 2
        case OpCode.INVOKE_EXC => 3
        case OpCode.TYPECAST => 3
        case OpCode.TYPECAST_EXC => 4
        case OpCode.INSTANCEOF => 1
        case OpCode.APPLY | OpCode.CAPPLY => 1
        case OpCode.APPLY_EXC => 2
        case OpCode.ASG | OpCode.DEREF | OpCode.RAISE => 0
        case OpCode.RAISE_EXC => 1
        case OpCode.GET_EXCEPTION => 0
        case OpCode.SYSCALL => 2
        case OpCode.INTRINSIC0 => 1
        case OpCode.INTRINSIC1 => 2
        case OpCode.INTRINSIC2 => 3
        case OpCode.INTRINSIC0_EXC => 2
        case OpCode.INTRINSIC1_EXC => 3
        case OpCode.INTRINSIC2_EXC => 4
        case OpCode.SWITCH => 2
        case OpCode.SPAWN => 0
        case OpCode.SPAWN_EXC => 1
        case OpCode.BOX => 1
        case OpCode.UNBOX | OpCode.UNBOX_REF | OpCode.NOT_SUPPORTED | OpCode.ABORT | OpCode.INVALID => 0
    }
}

public func OpHasExceptionHandler(opCode: OpCode): Bool {
    return match (opCode) {
        case OpCode.ALLOCATE_CLASS_EXC | OpCode.ALLOCATE_STRUCT_EXC | OpCode.ALLOCATE_RAW_ARRAY_EXC |
            OpCode.ALLOCATE_RAW_ARRAY_LITERAL_EXC | OpCode.ALLOCATE_EXC | OpCode.UN_NEG_EXC |
            OpCode.BIN_ADD_EXC | OpCode.BIN_SUB_EXC | OpCode.BIN_MUL_EXC | OpCode.BIN_DIV_EXC |
            OpCode.BIN_MOD_EXC | OpCode.BIN_EXP_EXC | OpCode.BIN_LSHIFT_EXC | OpCode.BIN_RSHIFT_EXC |
            OpCode.INVOKE_EXC | OpCode.TYPECAST_EXC | OpCode.APPLY_EXC | OpCode.RAISE_EXC |
            OpCode.GET_EXCEPTION | OpCode.INTRINSIC0_EXC | OpCode.INTRINSIC1_EXC | OpCode.INTRINSIC2_EXC |
            OpCode.SPAWN_EXC => true
        case _ => false
    }
}
