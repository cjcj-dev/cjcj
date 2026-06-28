package cangjie_compiler::modules

import std.collection.*
import cangjie_compiler::ast.BuiltInType
import cangjie_compiler::ast.CallKind
import cangjie_compiler::ast.ForInKind
import cangjie_compiler::ast.LitConstKind
import cangjie_compiler::ast.StringKind
import cangjie_compiler::ast.TypeKind
import cangjie_compiler::lex.TokenKind
import cangjie_compiler::utils.OverflowStrategy

public let ACCESS_LEVEL_MAP: ArrayList<(AccessLevel, UInt8)> = { =>
    let values = ArrayList<(AccessLevel, UInt8)>()
    values.add((AccessLevel.PUBLIC, 0u8))
    values.add((AccessLevel.PROTECTED, 1u8))
    values.add((AccessLevel.INTERNAL, 2u8))
    values
}()

public let ACCESS_LEVEL_RMAP: HashMap<UInt8, AccessLevel> = { =>
    let values = HashMap<UInt8, AccessLevel>()
    values[0u8] = AccessLevel.PUBLIC
    values[1u8] = AccessLevel.PROTECTED
    values[2u8] = AccessLevel.INTERNAL
    values
}()

public let ACCESS_MODIFIER_MAP: ArrayList<(TokenKind, UInt8)> = { =>
    let values = ArrayList<(TokenKind, UInt8)>()
    values.add((TokenKind.PUBLIC, 3u8))
    values.add((TokenKind.PROTECTED, 2u8))
    values.add((TokenKind.INTERNAL, 1u8))
    values.add((TokenKind.PRIVATE, 0u8))
    values
}()

public let ACCESS_MODIFIER_RMAP: HashMap<UInt8, (TokenKind, Attribute)> = { =>
    let values = HashMap<UInt8, (TokenKind, Attribute)>()
    values[3u8] = (TokenKind.PUBLIC, Attribute.PUBLIC)
    values[2u8] = (TokenKind.PROTECTED, Attribute.PROTECTED)
    values[1u8] = (TokenKind.INTERNAL, Attribute.INTERNAL)
    values[0u8] = (TokenKind.PRIVATE, Attribute.PRIVATE)
    values
}()

public let BUILTIN_TYPE_MAP: ArrayList<(BuiltInType, UInt8)> = { =>
    let values = ArrayList<(BuiltInType, UInt8)>()
    values.add((BuiltInType.ARRAY, 0u8))
    values.add((BuiltInType.VARRAY, 1u8))
    values.add((BuiltInType.POINTER, 2u8))
    values.add((BuiltInType.CSTRING, 3u8))
    values.add((BuiltInType.CFUNC, 4u8))
    values
}()

public let BUILTIN_TYPE_RMAP: HashMap<UInt8, BuiltInType> = { =>
    let values = HashMap<UInt8, BuiltInType>()
    values[0u8] = BuiltInType.ARRAY
    values[1u8] = BuiltInType.VARRAY
    values[2u8] = BuiltInType.POINTER
    values[3u8] = BuiltInType.CSTRING
    values[4u8] = BuiltInType.CFUNC
    values
}()

public let STRATEGY_MAP: ArrayList<(OverflowStrategy, UInt8)> = { =>
    let values = ArrayList<(OverflowStrategy, UInt8)>()
    values.add((OverflowStrategy.NA, 0u8))
    values.add((OverflowStrategy.CHECKED, 1u8))
    values.add((OverflowStrategy.WRAPPING, 2u8))
    values.add((OverflowStrategy.THROWING, 3u8))
    values.add((OverflowStrategy.SATURATING, 4u8))
    values
}()

public let STRATEGY_RMAP: HashMap<UInt8, OverflowStrategy> = { =>
    let values = HashMap<UInt8, OverflowStrategy>()
    values[0u8] = OverflowStrategy.NA
    values[1u8] = OverflowStrategy.CHECKED
    values[2u8] = OverflowStrategy.WRAPPING
    values[3u8] = OverflowStrategy.THROWING
    values[4u8] = OverflowStrategy.SATURATING
    values
}()

public let TYPE_KIND_MAP: ArrayList<(TypeKind, UInt16)> = { =>
    let values = ArrayList<(TypeKind, UInt16)>()
    values.add((TypeKind.TYPE_UNIT, 1u16))
    values.add((TypeKind.TYPE_INT8, 2u16))
    values.add((TypeKind.TYPE_INT16, 3u16))
    values.add((TypeKind.TYPE_INT32, 4u16))
    values.add((TypeKind.TYPE_INT64, 5u16))
    values.add((TypeKind.TYPE_INT_NATIVE, 6u16))
    values.add((TypeKind.TYPE_UINT8, 7u16))
    values.add((TypeKind.TYPE_UINT16, 8u16))
    values.add((TypeKind.TYPE_UINT32, 9u16))
    values.add((TypeKind.TYPE_UINT64, 10u16))
    values.add((TypeKind.TYPE_UINT_NATIVE, 11u16))
    values.add((TypeKind.TYPE_FLOAT16, 12u16))
    values.add((TypeKind.TYPE_FLOAT32, 13u16))
    values.add((TypeKind.TYPE_FLOAT64, 14u16))
    values.add((TypeKind.TYPE_RUNE, 15u16))
    values.add((TypeKind.TYPE_NOTHING, 16u16))
    values.add((TypeKind.TYPE_BOOLEAN, 17u16))
    values.add((TypeKind.TYPE_TUPLE, 18u16))
    values.add((TypeKind.TYPE_ENUM, 19u16))
    values.add((TypeKind.TYPE_FUNC, 20u16))
    values.add((TypeKind.TYPE_STRUCT, 21u16))
    values.add((TypeKind.TYPE_ARRAY, 22u16))
    values.add((TypeKind.TYPE_VARRAY, 23u16))
    values.add((TypeKind.TYPE_POINTER, 24u16))
    values.add((TypeKind.TYPE_CSTRING, 25u16))
    values.add((TypeKind.TYPE_CLASS, 26u16))
    values.add((TypeKind.TYPE_INTERFACE, 27u16))
    values.add((TypeKind.TYPE, 28u16))
    values.add((TypeKind.TYPE_GENERICS, 29u16))
    values
}()

public let TYPE_KIND_RMAP: HashMap<UInt16, TypeKind> = { =>
    let values = HashMap<UInt16, TypeKind>()
    values[1u16] = TypeKind.TYPE_UNIT
    values[2u16] = TypeKind.TYPE_INT8
    values[3u16] = TypeKind.TYPE_INT16
    values[4u16] = TypeKind.TYPE_INT32
    values[5u16] = TypeKind.TYPE_INT64
    values[6u16] = TypeKind.TYPE_INT_NATIVE
    values[7u16] = TypeKind.TYPE_UINT8
    values[8u16] = TypeKind.TYPE_UINT16
    values[9u16] = TypeKind.TYPE_UINT32
    values[10u16] = TypeKind.TYPE_UINT64
    values[11u16] = TypeKind.TYPE_UINT_NATIVE
    values[12u16] = TypeKind.TYPE_FLOAT16
    values[13u16] = TypeKind.TYPE_FLOAT32
    values[14u16] = TypeKind.TYPE_FLOAT64
    values[15u16] = TypeKind.TYPE_RUNE
    values[16u16] = TypeKind.TYPE_NOTHING
    values[17u16] = TypeKind.TYPE_BOOLEAN
    values[18u16] = TypeKind.TYPE_TUPLE
    values[19u16] = TypeKind.TYPE_ENUM
    values[20u16] = TypeKind.TYPE_FUNC
    values[21u16] = TypeKind.TYPE_STRUCT
    values[22u16] = TypeKind.TYPE_ARRAY
    values[23u16] = TypeKind.TYPE_VARRAY
    values[24u16] = TypeKind.TYPE_POINTER
    values[25u16] = TypeKind.TYPE_CSTRING
    values[26u16] = TypeKind.TYPE_CLASS
    values[27u16] = TypeKind.TYPE_INTERFACE
    values[28u16] = TypeKind.TYPE
    values[29u16] = TypeKind.TYPE_GENERICS
    values
}()

public let OP_KIND_MAP: ArrayList<(TokenKind, UInt8)> = { =>
    let values = ArrayList<(TokenKind, UInt8)>()
    values.add((TokenKind.ILLEGAL, 0u8))
    values.add((TokenKind.LPAREN, 2u8))
    values.add((TokenKind.LSQUARE, 1u8))
    values.add((TokenKind.NOT, 3u8))
    values.add((TokenKind.SUB, 9u8))
    values.add((TokenKind.EXP, 4u8))
    values.add((TokenKind.MUL, 5u8))
    values.add((TokenKind.DIV, 6u8))
    values.add((TokenKind.MOD, 7u8))
    values.add((TokenKind.ADD, 8u8))
    values.add((TokenKind.LSHIFT, 10u8))
    values.add((TokenKind.RSHIFT, 11u8))
    values.add((TokenKind.LT, 12u8))
    values.add((TokenKind.LE, 13u8))
    values.add((TokenKind.GT, 14u8))
    values.add((TokenKind.GE, 15u8))
    values.add((TokenKind.EQUAL, 16u8))
    values.add((TokenKind.NOTEQ, 17u8))
    values.add((TokenKind.BITAND, 18u8))
    values.add((TokenKind.BITXOR, 19u8))
    values.add((TokenKind.BITOR, 20u8))
    values.add((TokenKind.INCR, 21u8))
    values.add((TokenKind.DECR, 22u8))
    values.add((TokenKind.IS, 23u8))
    values.add((TokenKind.AS, 24u8))
    values.add((TokenKind.AND, 25u8))
    values.add((TokenKind.OR, 26u8))
    values.add((TokenKind.COALESCING, 27u8))
    values.add((TokenKind.PIPELINE, 28u8))
    values.add((TokenKind.COMPOSITION, 29u8))
    values.add((TokenKind.ASSIGN, 30u8))
    values.add((TokenKind.EXP_ASSIGN, 31u8))
    values.add((TokenKind.MUL_ASSIGN, 32u8))
    values.add((TokenKind.DIV_ASSIGN, 33u8))
    values.add((TokenKind.MOD_ASSIGN, 34u8))
    values.add((TokenKind.ADD_ASSIGN, 35u8))
    values.add((TokenKind.SUB_ASSIGN, 36u8))
    values.add((TokenKind.LSHIFT_ASSIGN, 37u8))
    values.add((TokenKind.RSHIFT_ASSIGN, 38u8))
    values.add((TokenKind.BITAND_ASSIGN, 39u8))
    values.add((TokenKind.BITXOR_ASSIGN, 40u8))
    values.add((TokenKind.BITOR_ASSIGN, 41u8))
    values.add((TokenKind.AND_ASSIGN, 42u8))
    values.add((TokenKind.OR_ASSIGN, 43u8))
    values
}()

public let OP_KIND_RMAP: HashMap<UInt8, TokenKind> = { =>
    let values = HashMap<UInt8, TokenKind>()
    values[0u8] = TokenKind.ILLEGAL
    values[2u8] = TokenKind.LPAREN
    values[1u8] = TokenKind.LSQUARE
    values[3u8] = TokenKind.NOT
    values[9u8] = TokenKind.SUB
    values[4u8] = TokenKind.EXP
    values[5u8] = TokenKind.MUL
    values[6u8] = TokenKind.DIV
    values[7u8] = TokenKind.MOD
    values[8u8] = TokenKind.ADD
    values[10u8] = TokenKind.LSHIFT
    values[11u8] = TokenKind.RSHIFT
    values[12u8] = TokenKind.LT
    values[13u8] = TokenKind.LE
    values[14u8] = TokenKind.GT
    values[15u8] = TokenKind.GE
    values[16u8] = TokenKind.EQUAL
    values[17u8] = TokenKind.NOTEQ
    values[18u8] = TokenKind.BITAND
    values[19u8] = TokenKind.BITXOR
    values[20u8] = TokenKind.BITOR
    values[21u8] = TokenKind.INCR
    values[22u8] = TokenKind.DECR
    values[23u8] = TokenKind.IS
    values[24u8] = TokenKind.AS
    values[25u8] = TokenKind.AND
    values[26u8] = TokenKind.OR
    values[27u8] = TokenKind.COALESCING
    values[28u8] = TokenKind.PIPELINE
    values[29u8] = TokenKind.COMPOSITION
    values[30u8] = TokenKind.ASSIGN
    values[31u8] = TokenKind.EXP_ASSIGN
    values[32u8] = TokenKind.MUL_ASSIGN
    values[33u8] = TokenKind.DIV_ASSIGN
    values[34u8] = TokenKind.MOD_ASSIGN
    values[35u8] = TokenKind.ADD_ASSIGN
    values[36u8] = TokenKind.SUB_ASSIGN
    values[37u8] = TokenKind.LSHIFT_ASSIGN
    values[38u8] = TokenKind.RSHIFT_ASSIGN
    values[39u8] = TokenKind.BITAND_ASSIGN
    values[40u8] = TokenKind.BITXOR_ASSIGN
    values[41u8] = TokenKind.BITOR_ASSIGN
    values[42u8] = TokenKind.AND_ASSIGN
    values[43u8] = TokenKind.OR_ASSIGN
    values
}()

public let CALL_KIND_MAP: ArrayList<(CallKind, UInt8)> = { =>
    let values = ArrayList<(CallKind, UInt8)>()
    values.add((CallKind.CALL_INVALID, 0u8))
    values.add((CallKind.CALL_DECLARED_FUNCTION, 1u8))
    values.add((CallKind.CALL_OBJECT_CREATION, 2u8))
    values.add((CallKind.CALL_FUNCTION_PTR, 3u8))
    values.add((CallKind.CALL_STRUCT_CREATION, 4u8))
    values.add((CallKind.CALL_SUPER_FUNCTION, 5u8))
    values.add((CallKind.CALL_VARIADIC_FUNCTION, 6u8))
    values.add((CallKind.CALL_ANNOTATION, 7u8))
    values.add((CallKind.CALL_BUILTIN_FUNCTION, 8u8))
    values.add((CallKind.CALL_INTRINSIC_FUNCTION, 9u8))
    values
}()

public let CALL_KIND_RMAP: HashMap<UInt8, CallKind> = { =>
    let values = HashMap<UInt8, CallKind>()
    values[0u8] = CallKind.CALL_INVALID
    values[1u8] = CallKind.CALL_DECLARED_FUNCTION
    values[2u8] = CallKind.CALL_OBJECT_CREATION
    values[3u8] = CallKind.CALL_FUNCTION_PTR
    values[4u8] = CallKind.CALL_STRUCT_CREATION
    values[5u8] = CallKind.CALL_SUPER_FUNCTION
    values[6u8] = CallKind.CALL_VARIADIC_FUNCTION
    values[7u8] = CallKind.CALL_ANNOTATION
    values[8u8] = CallKind.CALL_BUILTIN_FUNCTION
    values[9u8] = CallKind.CALL_INTRINSIC_FUNCTION
    values
}()

public let LIT_CONST_KIND_MAP: ArrayList<(LitConstKind, UInt8)> = { =>
    let values = ArrayList<(LitConstKind, UInt8)>()
    values.add((LitConstKind.INTEGER, 0u8))
    values.add((LitConstKind.RUNE_BYTE, 1u8))
    values.add((LitConstKind.FLOAT, 2u8))
    values.add((LitConstKind.RUNE, 3u8))
    values.add((LitConstKind.STRING, 4u8))
    values.add((LitConstKind.JSTRING, 5u8))
    values.add((LitConstKind.BOOL, 6u8))
    values.add((LitConstKind.UNIT, 7u8))
    values
}()

public let LIT_CONST_KIND_RMAP: HashMap<UInt8, LitConstKind> = { =>
    let values = HashMap<UInt8, LitConstKind>()
    values[0u8] = LitConstKind.INTEGER
    values[1u8] = LitConstKind.RUNE_BYTE
    values[2u8] = LitConstKind.FLOAT
    values[3u8] = LitConstKind.RUNE
    values[4u8] = LitConstKind.STRING
    values[5u8] = LitConstKind.JSTRING
    values[6u8] = LitConstKind.BOOL
    values[7u8] = LitConstKind.UNIT
    values
}()

public let STRING_KIND_MAP: ArrayList<(StringKind, UInt8)> = { =>
    let values = ArrayList<(StringKind, UInt8)>()
    values.add((StringKind.NORMAL, 0u8))
    values.add((StringKind.JSTRING, 1u8))
    values.add((StringKind.MULTILINE, 2u8))
    values.add((StringKind.MULTILINE_RAW, 3u8))
    values
}()

public let STRING_KIND_RMAP: HashMap<UInt8, StringKind> = { =>
    let values = HashMap<UInt8, StringKind>()
    values[0u8] = StringKind.NORMAL
    values[1u8] = StringKind.JSTRING
    values[2u8] = StringKind.MULTILINE
    values[3u8] = StringKind.MULTILINE_RAW
    values
}()

public let FOR_IN_KIND_MAP: ArrayList<(ForInKind, UInt8)> = { =>
    let values = ArrayList<(ForInKind, UInt8)>()
    values.add((ForInKind.FORIN_INVALID, 0u8))
    values.add((ForInKind.FORIN_RANGE, 1u8))
    values.add((ForInKind.FORIN_STRING, 2u8))
    values.add((ForInKind.FORIN_ITER, 3u8))
    values
}()

public let FOR_IN_KIND_RMAP: HashMap<UInt8, ForInKind> = { =>
    let values = HashMap<UInt8, ForInKind>()
    values[0u8] = ForInKind.FORIN_INVALID
    values[1u8] = ForInKind.FORIN_RANGE
    values[2u8] = ForInKind.FORIN_STRING
    values[3u8] = ForInKind.FORIN_ITER
    values
}()
