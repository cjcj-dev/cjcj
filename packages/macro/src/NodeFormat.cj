package cjcj::macro_pkg

import std.collection.*
import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset}

// Generated from schema/NodeFormat.fbs and NodeFormat_generated.h for Macro/NodeSerialization.cpp.

public const AnyExpr_NONE: UInt8 = 0u8
public const AnyExpr_BINARY_EXPR: UInt8 = 1u8
public const AnyExpr_UNARY_EXPR: UInt8 = 2u8
public const AnyExpr_PAREN_EXPR: UInt8 = 3u8
public const AnyExpr_LIT_CONST_EXPR: UInt8 = 4u8
public const AnyExpr_CALL_EXPR: UInt8 = 5u8
public const AnyExpr_REF_EXPR: UInt8 = 6u8
public const AnyExpr_RETURN_EXPR: UInt8 = 7u8
public const AnyExpr_ASSIGN_EXPR: UInt8 = 8u8
public const AnyExpr_MEMBER_ACCESS: UInt8 = 9u8
public const AnyExpr_IF_EXPR: UInt8 = 10u8
public const AnyExpr_BLOCK: UInt8 = 11u8
public const AnyExpr_LAMBDA_EXPR: UInt8 = 12u8
public const AnyExpr_ARRAY_LIT: UInt8 = 13u8
public const AnyExpr_TUPLE_LIT: UInt8 = 14u8
public const AnyExpr_SUBSCRIPT_EXPR: UInt8 = 15u8
public const AnyExpr_RANGE_EXPR: UInt8 = 16u8
public const AnyExpr_FOR_IN_EXPR: UInt8 = 17u8
public const AnyExpr_IS_EXPR: UInt8 = 18u8
public const AnyExpr_AS_EXPR: UInt8 = 19u8
public const AnyExpr_TRAILING_CLOSURE_EXPR: UInt8 = 20u8
public const AnyExpr_TYPE_CONV_EXPR: UInt8 = 21u8
public const AnyExpr_THROW_EXPR: UInt8 = 22u8
public const AnyExpr_TRY_EXPR: UInt8 = 23u8
public const AnyExpr_PRIMITIVE_TYPE_EXPR: UInt8 = 24u8
public const AnyExpr_WHILE_EXPR: UInt8 = 25u8
public const AnyExpr_DO_WHILE_EXPR: UInt8 = 26u8
public const AnyExpr_JUMP_EXPR: UInt8 = 27u8
public const AnyExpr_INC_OR_DEC_EXPR: UInt8 = 28u8
public const AnyExpr_SPAWN_EXPR: UInt8 = 29u8
public const AnyExpr_SYNCHRONIZED_EXPR: UInt8 = 30u8
public const AnyExpr_LET_PATTERN_DESTRUCTOR: UInt8 = 31u8
public const AnyExpr_TOKEN_PART: UInt8 = 32u8
public const AnyExpr_QUOTE_EXPR: UInt8 = 33u8
public const AnyExpr_MATCH_EXPR: UInt8 = 34u8
public const AnyExpr_OPTIONAL_EXPR: UInt8 = 35u8
public const AnyExpr_OPTIONAL_CHAIN_EXPR: UInt8 = 36u8
public const AnyExpr_MACRO_EXPAND_EXPR: UInt8 = 37u8
public const AnyExpr_WILDCARD_EXPR: UInt8 = 38u8
public const AnyExpr_ARRAY_EXPR: UInt8 = 39u8
public const AnyExpr_PERFORM_EXPR: UInt8 = 40u8
public const AnyExpr_RESUME_EXPR: UInt8 = 41u8

public const AnyPattern_NONE: UInt8 = 0u8
public const AnyPattern_CONST_PATTERN: UInt8 = 1u8
public const AnyPattern_WILDCARD_PATTERN: UInt8 = 2u8
public const AnyPattern_VAR_PATTERN: UInt8 = 3u8
public const AnyPattern_EXCEPT_TYPE_PATTERN: UInt8 = 4u8
public const AnyPattern_TYPE_PATTERN: UInt8 = 5u8
public const AnyPattern_ENUM_PATTERN: UInt8 = 6u8
public const AnyPattern_VAR_OR_ENUM_PATTERN: UInt8 = 7u8
public const AnyPattern_TUPLE_PATTERN: UInt8 = 8u8
public const AnyPattern_COMMAND_TYPE_PATTERN: UInt8 = 9u8

public const MacroParam_NONE: UInt8 = 0u8
public const MacroParam_MACRO_EXPAND_PARAM: UInt8 = 1u8

public const AnyType_NONE: UInt8 = 0u8
public const AnyType_REF_TYPE: UInt8 = 1u8
public const AnyType_PRIMITIVE_TYPE: UInt8 = 2u8
public const AnyType_FUNC_TYPE: UInt8 = 3u8
public const AnyType_THIS_TYPE: UInt8 = 4u8
public const AnyType_PAREN_TYPE: UInt8 = 5u8
public const AnyType_QUALIFIED_TYPE: UInt8 = 6u8
public const AnyType_OPTION_TYPE: UInt8 = 7u8
public const AnyType_TUPLE_TYPE: UInt8 = 8u8
public const AnyType_VARRAY_TYPE: UInt8 = 9u8
public const AnyType_CONSTANT_TYPE: UInt8 = 10u8

public const AnyDecl_NONE: UInt8 = 0u8
public const AnyDecl_FUNC_DECL: UInt8 = 1u8
public const AnyDecl_MAIN_DECL: UInt8 = 2u8
public const AnyDecl_VAR_DECL: UInt8 = 3u8
public const AnyDecl_VAR_WITH_PATTERN_DECL: UInt8 = 4u8
public const AnyDecl_STRUCT_DECL: UInt8 = 5u8
public const AnyDecl_CLASS_DECL: UInt8 = 6u8
public const AnyDecl_INTERFACE_DECL: UInt8 = 7u8
public const AnyDecl_GENERIC_PARAM_DECL: UInt8 = 8u8
public const AnyDecl_PRIMARY_CTOR_DECL: UInt8 = 9u8
public const AnyDecl_PROP_DECL: UInt8 = 10u8
public const AnyDecl_ENUM_DECL: UInt8 = 11u8
public const AnyDecl_TYPE_ALIAS_DECL: UInt8 = 12u8
public const AnyDecl_EXTEND_DECL: UInt8 = 13u8
public const AnyDecl_MACRO_DECL: UInt8 = 14u8
public const AnyDecl_MACRO_EXPAND_DECL: UInt8 = 15u8
public const AnyDecl_FUNC_PARAM: UInt8 = 16u8
public const AnyDecl_MACRO_EXPAND_PARAM: UInt8 = 17u8

public const AnyNode_NONE: UInt8 = 0u8
public const AnyNode_EXPR: UInt8 = 1u8
public const AnyNode_DECL: UInt8 = 2u8
public const AnyNode_TYPE: UInt8 = 3u8
public const AnyNode_PATTERN: UInt8 = 4u8
public const AnyNode_FILE: UInt8 = 5u8
public const AnyNode_PACKAGE_SPEC: UInt8 = 6u8
public const AnyNode_IMPORT_SPEC: UInt8 = 7u8
public const AnyNode_ANNOTATION: UInt8 = 8u8
public const AnyNode_FEATURES_DIRECTIVE: UInt8 = 9u8

public const AccessibleKind_ACCESSIBLE_PUBLIC: UInt8 = 0u8
public const AccessibleKind_ACCESSIBLE_PROTECTED: UInt8 = 1u8
public const AccessibleKind_ACCESSIBLE_INTERNAL: UInt8 = 2u8

public const ImportKind_IMPORT_SINGLE: UInt8 = 0u8
public const ImportKind_IMPORT_ALIAS: UInt8 = 1u8
public const ImportKind_IMPORT_ALL: UInt8 = 2u8
public const ImportKind_IMPORT_MULTI: UInt8 = 3u8

public const ReExportKind_REEXPORT_PRIVATE: UInt8 = 0u8
public const ReExportKind_REEXPORT_INTERNAL: UInt8 = 1u8
public const ReExportKind_REEXPORT_PROTECTED: UInt8 = 2u8
public const ReExportKind_REEXPORT_PUBLIC: UInt8 = 3u8

public func CreateMatchCase(fb: FlatBufferBuilder, base: FlatBufferOffset, patterns: FlatBufferOffset, patternguard: FlatBufferOffset, if_pos: ArrayList<UInt8>, arrow_pos: ArrayList<UInt8>, expr_or_decls: FlatBufferOffset, bit_or_pos_vec: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(7)
    fb.AddOffset(6, bit_or_pos_vec)
    fb.AddOffset(5, expr_or_decls)
    fb.AddStruct(4, arrow_pos, 4)
    fb.AddStruct(3, if_pos, 4)
    fb.AddOffset(2, patternguard)
    fb.AddOffset(1, patterns)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateMatchCaseOther(fb: FlatBufferBuilder, base: FlatBufferOffset, match_expr: FlatBufferOffset, arrow_pos: ArrayList<UInt8>, expr_or_decls: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddOffset(3, expr_or_decls)
    fb.AddStruct(2, arrow_pos, 4)
    fb.AddOffset(1, match_expr)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreatePattern(fb: FlatBufferBuilder, base: FlatBufferOffset, pattern_type: UInt8, pattern: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddOffset(2, pattern)
    fb.AddOffset(0, base)
    fb.AddU8(1, pattern_type)
    return fb.EndTable()
}

public func CreateConstPattern(fb: FlatBufferBuilder, base: FlatBufferOffset, literal: FlatBufferOffset, operator_call_expr: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddOffset(2, operator_call_expr)
    fb.AddOffset(1, literal)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateWildcardPattern(fb: FlatBufferBuilder, base: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(1)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateVarPattern(fb: FlatBufferBuilder, base: FlatBufferOffset, var_decl: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(2)
    fb.AddOffset(1, var_decl)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateExceptTypePattern(fb: FlatBufferBuilder, base: FlatBufferOffset, pattern: FlatBufferOffset, pattern_pos: ArrayList<UInt8>, colon_pos: ArrayList<UInt8>, types: FlatBufferOffset, bit_or_pos_vec: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddOffset(5, bit_or_pos_vec)
    fb.AddOffset(4, types)
    fb.AddStruct(3, colon_pos, 4)
    fb.AddStruct(2, pattern_pos, 4)
    fb.AddOffset(1, pattern)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateCommandTypePattern(fb: FlatBufferBuilder, base: FlatBufferOffset, pattern: FlatBufferOffset, pattern_pos: ArrayList<UInt8>, colon_pos: ArrayList<UInt8>, types: FlatBufferOffset, bit_or_pos_vec: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddOffset(5, bit_or_pos_vec)
    fb.AddOffset(4, types)
    fb.AddStruct(3, colon_pos, 4)
    fb.AddStruct(2, pattern_pos, 4)
    fb.AddOffset(1, pattern)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateTypePattern(fb: FlatBufferBuilder, base: FlatBufferOffset, pattern: FlatBufferOffset, colon_pos: ArrayList<UInt8>, typeValue: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddOffset(3, typeValue)
    fb.AddStruct(2, colon_pos, 4)
    fb.AddOffset(1, pattern)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateEnumPattern(fb: FlatBufferBuilder, base: FlatBufferOffset, ref: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, patterns: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>, comma_pos_vec: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddOffset(5, comma_pos_vec)
    fb.AddStruct(4, right_paren_pos, 4)
    fb.AddOffset(3, patterns)
    fb.AddStruct(2, left_paren_pos, 4)
    fb.AddOffset(1, ref)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateVarOrEnumPattern(fb: FlatBufferBuilder, base: FlatBufferOffset, identifier: FlatBufferOffset, pattern: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddOffset(2, pattern)
    fb.AddOffset(1, identifier)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateTuplePattern(fb: FlatBufferBuilder, base: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, patterns: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>, comma_pos_vec: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddOffset(4, comma_pos_vec)
    fb.AddStruct(3, right_paren_pos, 4)
    fb.AddOffset(2, patterns)
    fb.AddStruct(1, left_paren_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateBinaryExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, left_expr: FlatBufferOffset, right_expr: FlatBufferOffset, operator_kind: UInt16, operator_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddStruct(4, operator_pos, 4)
    fb.AddOffset(2, right_expr)
    fb.AddOffset(1, left_expr)
    fb.AddOffset(0, base)
    fb.AddU16(3, operator_kind)
    return fb.EndTable()
}

public func CreateIsExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, expr: FlatBufferOffset, is_type: FlatBufferOffset, is_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddStruct(3, is_pos, 4)
    fb.AddOffset(2, is_type)
    fb.AddOffset(1, expr)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateAsExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, expr: FlatBufferOffset, as_type: FlatBufferOffset, as_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddStruct(3, as_pos, 4)
    fb.AddOffset(2, as_type)
    fb.AddOffset(1, expr)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateUnaryExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, expr: FlatBufferOffset, operator_kind: UInt16, operator_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddStruct(3, operator_pos, 4)
    fb.AddOffset(1, expr)
    fb.AddOffset(0, base)
    fb.AddU16(2, operator_kind)
    return fb.EndTable()
}

public func CreateWildcardExpr(fb: FlatBufferBuilder, base: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(1)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateArrayExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, typeValue: FlatBufferOffset, leftParenPos: ArrayList<UInt8>, args: FlatBufferOffset, rightParenPos: ArrayList<UInt8>, isValueArray: Bool): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddStruct(4, rightParenPos, 4)
    fb.AddOffset(3, args)
    fb.AddStruct(2, leftParenPos, 4)
    fb.AddOffset(1, typeValue)
    fb.AddOffset(0, base)
    fb.AddU8(5, isValueArray)
    return fb.EndTable()
}

public func CreateParenExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, expr: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddStruct(3, right_paren_pos, 4)
    fb.AddOffset(2, expr)
    fb.AddStruct(1, left_paren_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateLitConstExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, literal: FlatBufferOffset, literal_const_kind: UInt16, delimiter_num: UInt16, string_kind: UInt16, is_single_quote: Bool): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddOffset(1, literal)
    fb.AddOffset(0, base)
    fb.AddU16(4, string_kind)
    fb.AddU16(3, delimiter_num)
    fb.AddU16(2, literal_const_kind)
    fb.AddU8(5, is_single_quote)
    return fb.EndTable()
}

public func CreateFuncArg(fb: FlatBufferBuilder, base: FlatBufferOffset, name: FlatBufferOffset, name_pos: ArrayList<UInt8>, colon_pos: ArrayList<UInt8>, expr: FlatBufferOffset, comma_pos: ArrayList<UInt8>, withInout: Bool): FlatBufferOffset {
    fb.StartTable(7)
    fb.AddStruct(5, comma_pos, 4)
    fb.AddOffset(4, expr)
    fb.AddStruct(3, colon_pos, 4)
    fb.AddStruct(2, name_pos, 4)
    fb.AddOffset(1, name)
    fb.AddOffset(0, base)
    fb.AddU8(6, withInout)
    return fb.EndTable()
}

public func CreateCallExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, base_func: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, args: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddStruct(4, right_paren_pos, 4)
    fb.AddOffset(3, args)
    fb.AddStruct(2, left_paren_pos, 4)
    fb.AddOffset(1, base_func)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateRefExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, ref: FlatBufferOffset, left_angle_pos: ArrayList<UInt8>, type_arguments: FlatBufferOffset, right_angle_pos: ArrayList<UInt8>, is_this: Bool, is_super: Bool, is_quote_dollar: Bool): FlatBufferOffset {
    fb.StartTable(8)
    fb.AddStruct(4, right_angle_pos, 4)
    fb.AddOffset(3, type_arguments)
    fb.AddStruct(2, left_angle_pos, 4)
    fb.AddOffset(1, ref)
    fb.AddOffset(0, base)
    fb.AddU8(7, is_quote_dollar)
    fb.AddU8(6, is_super)
    fb.AddU8(5, is_this)
    return fb.EndTable()
}

public func CreateReturnExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, return_pos: ArrayList<UInt8>, expr: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddOffset(2, expr)
    fb.AddStruct(1, return_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateAssignExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, left_value: FlatBufferOffset, assign_op: UInt16, assign_pos: ArrayList<UInt8>, right_expr: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddOffset(4, right_expr)
    fb.AddStruct(3, assign_pos, 4)
    fb.AddOffset(1, left_value)
    fb.AddOffset(0, base)
    fb.AddU16(2, assign_op)
    return fb.EndTable()
}

public func CreateMemberAccess(fb: FlatBufferBuilder, base: FlatBufferOffset, base_expr: FlatBufferOffset, dot_pos: ArrayList<UInt8>, field: FlatBufferOffset, field_pos: ArrayList<UInt8>, left_angle_pos: ArrayList<UInt8>, type_arguments: FlatBufferOffset, right_angle_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(8)
    fb.AddStruct(7, right_angle_pos, 4)
    fb.AddOffset(6, type_arguments)
    fb.AddStruct(5, left_angle_pos, 4)
    fb.AddStruct(4, field_pos, 4)
    fb.AddOffset(3, field)
    fb.AddStruct(2, dot_pos, 4)
    fb.AddOffset(1, base_expr)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateIfExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, if_pos: ArrayList<UInt8>, cond_expr: FlatBufferOffset, body: FlatBufferOffset, has_else: Bool, else_pos: ArrayList<UInt8>, else_body: FlatBufferOffset, isElseIf: Bool, left_paren_pos: ArrayList<UInt8>, right_paren_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(10)
    fb.AddStruct(9, right_paren_pos, 4)
    fb.AddStruct(8, left_paren_pos, 4)
    fb.AddOffset(6, else_body)
    fb.AddStruct(5, else_pos, 4)
    fb.AddOffset(3, body)
    fb.AddOffset(2, cond_expr)
    fb.AddStruct(1, if_pos, 4)
    fb.AddOffset(0, base)
    fb.AddU8(7, isElseIf)
    fb.AddU8(4, has_else)
    return fb.EndTable()
}

public func CreateLetPatternDestructor(fb: FlatBufferBuilder, base: FlatBufferOffset, patterns: FlatBufferOffset, bit_or_pos_vec: FlatBufferOffset, backarrow_pos: ArrayList<UInt8>, initializer: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddOffset(4, initializer)
    fb.AddStruct(3, backarrow_pos, 4)
    fb.AddOffset(2, bit_or_pos_vec)
    fb.AddOffset(1, patterns)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateLambdaExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, body: FlatBufferOffset, mockSupported: Bool): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddOffset(1, body)
    fb.AddOffset(0, base)
    fb.AddU8(2, mockSupported)
    return fb.EndTable()
}

public func CreateArrayLit(fb: FlatBufferBuilder, base: FlatBufferOffset, left_curl_pos: ArrayList<UInt8>, children: FlatBufferOffset, comma_pos_vec: FlatBufferOffset, right_curl_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddStruct(4, right_curl_pos, 4)
    fb.AddOffset(3, comma_pos_vec)
    fb.AddOffset(2, children)
    fb.AddStruct(1, left_curl_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateTupleLit(fb: FlatBufferBuilder, base: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, children: FlatBufferOffset, comma_pos_vec: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddStruct(4, right_paren_pos, 4)
    fb.AddOffset(3, comma_pos_vec)
    fb.AddOffset(2, children)
    fb.AddStruct(1, left_paren_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateSubscriptExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, base_expr: FlatBufferOffset, left_square_pos: ArrayList<UInt8>, index_exprs: FlatBufferOffset, right_square_pos: ArrayList<UInt8>, is_tuple_access: Bool): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddStruct(4, right_square_pos, 4)
    fb.AddOffset(3, index_exprs)
    fb.AddStruct(2, left_square_pos, 4)
    fb.AddOffset(1, base_expr)
    fb.AddOffset(0, base)
    fb.AddU8(5, is_tuple_access)
    return fb.EndTable()
}

public func CreateMatchExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, match_mode: Bool, left_paren_pos: ArrayList<UInt8>, selector: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>, left_curl_pos: ArrayList<UInt8>, match_cases: FlatBufferOffset, match_case_others: FlatBufferOffset, right_curl_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(9)
    fb.AddStruct(8, right_curl_pos, 4)
    fb.AddOffset(7, match_case_others)
    fb.AddOffset(6, match_cases)
    fb.AddStruct(5, left_curl_pos, 4)
    fb.AddStruct(4, right_paren_pos, 4)
    fb.AddOffset(3, selector)
    fb.AddStruct(2, left_paren_pos, 4)
    fb.AddOffset(0, base)
    fb.AddU8(1, match_mode)
    return fb.EndTable()
}

public func CreateRangeExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, start_expr: FlatBufferOffset, range_pos: ArrayList<UInt8>, stop_expr: FlatBufferOffset, colon_pos: ArrayList<UInt8>, step_expr: FlatBufferOffset, is_closed: Bool): FlatBufferOffset {
    fb.StartTable(7)
    fb.AddOffset(5, step_expr)
    fb.AddStruct(4, colon_pos, 4)
    fb.AddOffset(3, stop_expr)
    fb.AddStruct(2, range_pos, 4)
    fb.AddOffset(1, start_expr)
    fb.AddOffset(0, base)
    fb.AddU8(6, is_closed)
    return fb.EndTable()
}

public func CreateForInExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, pattern: FlatBufferOffset, in_pos: ArrayList<UInt8>, in_expr: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>, if_pos: ArrayList<UInt8>, pattern_guard: FlatBufferOffset, body: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(9)
    fb.AddOffset(8, body)
    fb.AddOffset(7, pattern_guard)
    fb.AddStruct(6, if_pos, 4)
    fb.AddStruct(5, right_paren_pos, 4)
    fb.AddOffset(4, in_expr)
    fb.AddStruct(3, in_pos, 4)
    fb.AddOffset(2, pattern)
    fb.AddStruct(1, left_paren_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateWhileExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, while_pos: ArrayList<UInt8>, left_paren_pos: ArrayList<UInt8>, cond_expr: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>, body: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddOffset(5, body)
    fb.AddStruct(4, right_paren_pos, 4)
    fb.AddOffset(3, cond_expr)
    fb.AddStruct(2, left_paren_pos, 4)
    fb.AddStruct(1, while_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateSpawnExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, spawn_pos: ArrayList<UInt8>, task_expr: FlatBufferOffset, has_arg: Bool, spawn_arg_expr: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, right_paren_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(7)
    fb.AddStruct(6, right_paren_pos, 4)
    fb.AddStruct(5, left_paren_pos, 4)
    fb.AddOffset(4, spawn_arg_expr)
    fb.AddOffset(2, task_expr)
    fb.AddStruct(1, spawn_pos, 4)
    fb.AddOffset(0, base)
    fb.AddU8(3, has_arg)
    return fb.EndTable()
}

public func CreateSynchronizedExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, sync_pos: ArrayList<UInt8>, left_paren_pos: ArrayList<UInt8>, mutex_expr: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>, body: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddOffset(5, body)
    fb.AddStruct(4, right_paren_pos, 4)
    fb.AddOffset(3, mutex_expr)
    fb.AddStruct(2, left_paren_pos, 4)
    fb.AddStruct(1, sync_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateTrailingClosureExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, left_lambda: ArrayList<UInt8>, expr: FlatBufferOffset, lambda: FlatBufferOffset, right_lambda: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddStruct(4, right_lambda, 4)
    fb.AddOffset(3, lambda)
    fb.AddOffset(2, expr)
    fb.AddStruct(1, left_lambda, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateTypeConvExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, typeValue: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, expr: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddStruct(4, right_paren_pos, 4)
    fb.AddOffset(3, expr)
    fb.AddStruct(2, left_paren_pos, 4)
    fb.AddOffset(1, typeValue)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateThrowExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, expr: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(2)
    fb.AddOffset(1, expr)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreatePerformExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, expr: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(2)
    fb.AddOffset(1, expr)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateResumeExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, with_pos: ArrayList<UInt8>, with_expr: FlatBufferOffset, throwing_pos: ArrayList<UInt8>, throwing_expr: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddOffset(4, throwing_expr)
    fb.AddStruct(3, throwing_pos, 4)
    fb.AddOffset(2, with_expr)
    fb.AddStruct(1, with_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateHandler(fb: FlatBufferBuilder, handler_pos: ArrayList<UInt8>, command_pattern: FlatBufferOffset, handle_block: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddOffset(2, handle_block)
    fb.AddOffset(1, command_pattern)
    fb.AddStruct(0, handler_pos, 4)
    return fb.EndTable()
}

public func CreateTryExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, resource_spec: FlatBufferOffset, is_resource_spec: Bool, try_block: FlatBufferOffset, catch_blocks: FlatBufferOffset, catch_patterns: FlatBufferOffset, finally_pos: ArrayList<UInt8>, finally_block: FlatBufferOffset, resource_spec_lparen_pos: ArrayList<UInt8>, resource_spec_rparen_pos: ArrayList<UInt8>, resource_spec_comma_pos_vec: FlatBufferOffset, catch_pos_vec: FlatBufferOffset, catch_left_paren_pos_vec: FlatBufferOffset, catch_right_paren_pos_vec: FlatBufferOffset, handlers: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(15)
    fb.AddOffset(14, handlers)
    fb.AddOffset(13, catch_right_paren_pos_vec)
    fb.AddOffset(12, catch_left_paren_pos_vec)
    fb.AddOffset(11, catch_pos_vec)
    fb.AddOffset(10, resource_spec_comma_pos_vec)
    fb.AddStruct(9, resource_spec_rparen_pos, 4)
    fb.AddStruct(8, resource_spec_lparen_pos, 4)
    fb.AddOffset(7, finally_block)
    fb.AddStruct(6, finally_pos, 4)
    fb.AddOffset(5, catch_patterns)
    fb.AddOffset(4, catch_blocks)
    fb.AddOffset(3, try_block)
    fb.AddOffset(1, resource_spec)
    fb.AddOffset(0, base)
    fb.AddU8(2, is_resource_spec)
    return fb.EndTable()
}

public func CreateDoWhileExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, do_pos: ArrayList<UInt8>, body: FlatBufferOffset, while_pos: ArrayList<UInt8>, left_paren_pos: ArrayList<UInt8>, cond_expr: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(7)
    fb.AddStruct(6, right_paren_pos, 4)
    fb.AddOffset(5, cond_expr)
    fb.AddStruct(4, left_paren_pos, 4)
    fb.AddStruct(3, while_pos, 4)
    fb.AddOffset(2, body)
    fb.AddStruct(1, do_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateIncOrDecExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, operator_kind: UInt16, operator_pos: ArrayList<UInt8>, expr: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddOffset(3, expr)
    fb.AddStruct(2, operator_pos, 4)
    fb.AddOffset(0, base)
    fb.AddU16(1, operator_kind)
    return fb.EndTable()
}

public func CreateOptionalExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, baseExpr: FlatBufferOffset, quest_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddStruct(2, quest_pos, 4)
    fb.AddOffset(1, baseExpr)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateOptionalChainExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, expr: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(2)
    fb.AddOffset(1, expr)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateToken(fb: FlatBufferBuilder, kind: UInt16, value: FlatBufferOffset, pos: ArrayList<UInt8>, delimiter_num: UInt32, is_single_quote: Bool, has_escape: Bool): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddU32(3, delimiter_num)
    fb.AddStruct(2, pos, 4)
    fb.AddOffset(1, value)
    fb.AddU16(0, kind)
    fb.AddU8(5, has_escape)
    fb.AddU8(4, is_single_quote)
    return fb.EndTable()
}

public func CreateTokenPart(fb: FlatBufferBuilder, tokens: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(1)
    fb.AddOffset(0, tokens)
    return fb.EndTable()
}

public func CreateQuoteExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, exprs: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddStruct(3, right_paren_pos, 4)
    fb.AddOffset(2, exprs)
    fb.AddStruct(1, left_paren_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateReference(fb: FlatBufferBuilder, identifier: FlatBufferOffset, identifier_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(2)
    fb.AddStruct(1, identifier_pos, 4)
    fb.AddOffset(0, identifier)
    return fb.EndTable()
}

public func CreateFuncParamList(fb: FlatBufferBuilder, base: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, params: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddStruct(3, right_paren_pos, 4)
    fb.AddOffset(2, params)
    fb.AddStruct(1, left_paren_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateFuncParam(fb: FlatBufferBuilder, nodeBase: FlatBufferOffset, base: FlatBufferOffset, colon_pos: ArrayList<UInt8>, assignment: FlatBufferOffset, comma_pos: ArrayList<UInt8>, is_named_param: Bool, is_member_param: Bool, not_mark_pos: ArrayList<UInt8>, has_let_or_var: Bool, macroParam_type: UInt8, macroParam: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(11)
    fb.AddOffset(10, macroParam)
    fb.AddStruct(7, not_mark_pos, 4)
    fb.AddStruct(4, comma_pos, 4)
    fb.AddOffset(3, assignment)
    fb.AddStruct(2, colon_pos, 4)
    fb.AddOffset(1, base)
    fb.AddOffset(0, nodeBase)
    fb.AddU8(9, macroParam_type)
    fb.AddU8(8, has_let_or_var)
    fb.AddU8(6, is_member_param)
    fb.AddU8(5, is_named_param)
    return fb.EndTable()
}

public func CreateFuncBody(fb: FlatBufferBuilder, base: FlatBufferOffset, param_list: FlatBufferOffset, arrow_pos: ArrayList<UInt8>, colon_pos: ArrayList<UInt8>, ret_type: FlatBufferOffset, has_body: Bool, body: FlatBufferOffset, generic: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(8)
    fb.AddOffset(7, generic)
    fb.AddOffset(6, body)
    fb.AddOffset(4, ret_type)
    fb.AddStruct(3, colon_pos, 4)
    fb.AddStruct(2, arrow_pos, 4)
    fb.AddOffset(1, param_list)
    fb.AddOffset(0, base)
    fb.AddU8(5, has_body)
    return fb.EndTable()
}

public func CreateJumpExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, is_break: Bool): FlatBufferOffset {
    fb.StartTable(2)
    fb.AddOffset(0, base)
    fb.AddU8(1, is_break)
    return fb.EndTable()
}

public func CreateExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, expr_type: UInt8, expr: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddOffset(2, expr)
    fb.AddOffset(0, base)
    fb.AddU8(1, expr_type)
    return fb.EndTable()
}

public func CreatePrimitiveTypeExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, kind: UInt16): FlatBufferOffset {
    fb.StartTable(2)
    fb.AddOffset(0, base)
    fb.AddU16(1, kind)
    return fb.EndTable()
}

public func CreateTypeBase(fb: FlatBufferBuilder, base: FlatBufferOffset, comma_pos: ArrayList<UInt8>, type_parameter_name: FlatBufferOffset, colon_pos: ArrayList<UInt8>, type_pos: ArrayList<UInt8>, bit_and_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddStruct(5, bit_and_pos, 4)
    fb.AddStruct(4, type_pos, 4)
    fb.AddStruct(3, colon_pos, 4)
    fb.AddOffset(2, type_parameter_name)
    fb.AddStruct(1, comma_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateRefType(fb: FlatBufferBuilder, base: FlatBufferOffset, ref: FlatBufferOffset, left_angle_pos: ArrayList<UInt8>, type_arguments: FlatBufferOffset, right_angle_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddStruct(4, right_angle_pos, 4)
    fb.AddOffset(3, type_arguments)
    fb.AddStruct(2, left_angle_pos, 4)
    fb.AddOffset(1, ref)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreatePrimitiveType(fb: FlatBufferBuilder, base: FlatBufferOffset, type_str: FlatBufferOffset, kind: UInt16): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddOffset(1, type_str)
    fb.AddOffset(0, base)
    fb.AddU16(2, kind)
    return fb.EndTable()
}

public func CreateFuncType(fb: FlatBufferBuilder, base: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, param_types: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>, arrow_pos: ArrayList<UInt8>, ret_type: FlatBufferOffset, isC: Bool): FlatBufferOffset {
    fb.StartTable(7)
    fb.AddOffset(5, ret_type)
    fb.AddStruct(4, arrow_pos, 4)
    fb.AddStruct(3, right_paren_pos, 4)
    fb.AddOffset(2, param_types)
    fb.AddStruct(1, left_paren_pos, 4)
    fb.AddOffset(0, base)
    fb.AddU8(6, isC)
    return fb.EndTable()
}

public func CreateThisType(fb: FlatBufferBuilder, base: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(1)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateParenType(fb: FlatBufferBuilder, base: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, typeValue: FlatBufferOffset, right_paren_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddStruct(3, right_paren_pos, 4)
    fb.AddOffset(2, typeValue)
    fb.AddStruct(1, left_paren_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateQualifiedType(fb: FlatBufferBuilder, base: FlatBufferOffset, base_type: FlatBufferOffset, dot_pos: ArrayList<UInt8>, field: FlatBufferOffset, field_pos: ArrayList<UInt8>, left_angle_pos: ArrayList<UInt8>, type_arguments: FlatBufferOffset, right_angle_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(8)
    fb.AddStruct(7, right_angle_pos, 4)
    fb.AddOffset(6, type_arguments)
    fb.AddStruct(5, left_angle_pos, 4)
    fb.AddStruct(4, field_pos, 4)
    fb.AddOffset(3, field)
    fb.AddStruct(2, dot_pos, 4)
    fb.AddOffset(1, base_type)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateOptionType(fb: FlatBufferBuilder, base: FlatBufferOffset, component_type: FlatBufferOffset, quest_num: Int64, quest_vector: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddOffset(3, quest_vector)
    fb.AddI32(2, quest_num)
    fb.AddOffset(1, component_type)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateTupleType(fb: FlatBufferBuilder, base: FlatBufferOffset, field_types: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, right_paren_pos: ArrayList<UInt8>, comma_pos_vector: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddOffset(4, comma_pos_vector)
    fb.AddStruct(3, right_paren_pos, 4)
    fb.AddStruct(2, left_paren_pos, 4)
    fb.AddOffset(1, field_types)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateVArrayType(fb: FlatBufferBuilder, base: FlatBufferOffset, varrayPos: ArrayList<UInt8>, leftAnglePos: ArrayList<UInt8>, typeArgument: FlatBufferOffset, constantType: FlatBufferOffset, rightAnglePos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddStruct(5, rightAnglePos, 4)
    fb.AddOffset(4, constantType)
    fb.AddOffset(3, typeArgument)
    fb.AddStruct(2, leftAnglePos, 4)
    fb.AddStruct(1, varrayPos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateConstantType(fb: FlatBufferBuilder, base: FlatBufferOffset, constantExpr: FlatBufferOffset, dollarPos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddStruct(2, dollarPos, 4)
    fb.AddOffset(1, constantExpr)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateType(fb: FlatBufferBuilder, base: FlatBufferOffset, type_type: UInt8, typeValue: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddOffset(2, typeValue)
    fb.AddOffset(0, base)
    fb.AddU8(1, type_type)
    return fb.EndTable()
}

public func CreateVarDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, typeValue: FlatBufferOffset, colon_pos: ArrayList<UInt8>, initializer: FlatBufferOffset, assign_pos: ArrayList<UInt8>, is_var: Bool, isEnumConstruct: Bool, emptyKeyword: Bool): FlatBufferOffset {
    fb.StartTable(8)
    fb.AddStruct(4, assign_pos, 4)
    fb.AddOffset(3, initializer)
    fb.AddStruct(2, colon_pos, 4)
    fb.AddOffset(1, typeValue)
    fb.AddOffset(0, base)
    fb.AddU8(7, emptyKeyword)
    fb.AddU8(6, isEnumConstruct)
    fb.AddU8(5, is_var)
    return fb.EndTable()
}

public func CreateVarWithPatternDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, typeValue: FlatBufferOffset, colon_pos: ArrayList<UInt8>, initializer: FlatBufferOffset, pattern: FlatBufferOffset, assign_pos: ArrayList<UInt8>, is_var: Bool): FlatBufferOffset {
    fb.StartTable(7)
    fb.AddStruct(5, assign_pos, 4)
    fb.AddOffset(4, pattern)
    fb.AddOffset(3, initializer)
    fb.AddStruct(2, colon_pos, 4)
    fb.AddOffset(1, typeValue)
    fb.AddOffset(0, base)
    fb.AddU8(6, is_var)
    return fb.EndTable()
}

public func CreateFuncDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, left_paren_pos: ArrayList<UInt8>, right_paren_pos: ArrayList<UInt8>, func_body: FlatBufferOffset, is_setter: Bool, is_getter: Bool, op_kind: Int64, isEnumConstruct: Bool): FlatBufferOffset {
    fb.StartTable(8)
    fb.AddI32(6, op_kind)
    fb.AddOffset(3, func_body)
    fb.AddStruct(2, right_paren_pos, 4)
    fb.AddStruct(1, left_paren_pos, 4)
    fb.AddOffset(0, base)
    fb.AddU8(7, isEnumConstruct)
    fb.AddU8(5, is_getter)
    fb.AddU8(4, is_setter)
    return fb.EndTable()
}

public func CreateMainDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, func_body: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(2)
    fb.AddOffset(1, func_body)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateMacroDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, leftParenPos: ArrayList<UInt8>, rightParenPos: ArrayList<UInt8>, func_body: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddOffset(3, func_body)
    fb.AddStruct(2, rightParenPos, 4)
    fb.AddStruct(1, leftParenPos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateStructBody(fb: FlatBufferBuilder, base: FlatBufferOffset, left_curl_pos: ArrayList<UInt8>, decls: FlatBufferOffset, right_curl_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddStruct(3, right_curl_pos, 4)
    fb.AddOffset(2, decls)
    fb.AddStruct(1, left_curl_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateStructDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, body: FlatBufferOffset, upper_bound_pos: ArrayList<UInt8>, super_types: FlatBufferOffset, generic: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddOffset(4, generic)
    fb.AddOffset(3, super_types)
    fb.AddStruct(2, upper_bound_pos, 4)
    fb.AddOffset(1, body)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateClassBody(fb: FlatBufferBuilder, base: FlatBufferOffset, left_curl_pos: ArrayList<UInt8>, decls: FlatBufferOffset, right_curl_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddStruct(3, right_curl_pos, 4)
    fb.AddOffset(2, decls)
    fb.AddStruct(1, left_curl_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateClassDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, upper_bound_pos: ArrayList<UInt8>, super_types: FlatBufferOffset, body: FlatBufferOffset, sub_decls: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddOffset(4, sub_decls)
    fb.AddOffset(3, body)
    fb.AddOffset(2, super_types)
    fb.AddStruct(1, upper_bound_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateInterfaceBody(fb: FlatBufferBuilder, base: FlatBufferOffset, left_curl_pos: ArrayList<UInt8>, decls: FlatBufferOffset, right_curl_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddStruct(3, right_curl_pos, 4)
    fb.AddOffset(2, decls)
    fb.AddStruct(1, left_curl_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateInterfaceDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, upper_bound_pos: ArrayList<UInt8>, super_types: FlatBufferOffset, body: FlatBufferOffset, sub_decls: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddOffset(4, sub_decls)
    fb.AddOffset(3, body)
    fb.AddOffset(2, super_types)
    fb.AddStruct(1, upper_bound_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateEnumDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, has_arguments: Bool, left_curl_pos: ArrayList<UInt8>, constructors: FlatBufferOffset, bit_or_pos_vec: FlatBufferOffset, members: FlatBufferOffset, right_curl_pos: ArrayList<UInt8>, upper_bound_pos: ArrayList<UInt8>, super_interface_types: FlatBufferOffset, hasEllipsis: Bool, ellipsis_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(11)
    fb.AddStruct(10, ellipsis_pos, 4)
    fb.AddOffset(8, super_interface_types)
    fb.AddStruct(7, upper_bound_pos, 4)
    fb.AddStruct(6, right_curl_pos, 4)
    fb.AddOffset(5, members)
    fb.AddOffset(4, bit_or_pos_vec)
    fb.AddOffset(3, constructors)
    fb.AddStruct(2, left_curl_pos, 4)
    fb.AddOffset(0, base)
    fb.AddU8(9, hasEllipsis)
    fb.AddU8(1, has_arguments)
    return fb.EndTable()
}

public func CreateGenericParamDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, comma_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(2)
    fb.AddStruct(1, comma_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreatePrimaryCtorDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, func_body: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(2)
    fb.AddOffset(1, func_body)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreatePropDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, colon_pos: ArrayList<UInt8>, left_curl_pos: ArrayList<UInt8>, getters: FlatBufferOffset, setters: FlatBufferOffset, right_curl_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddStruct(5, right_curl_pos, 4)
    fb.AddOffset(4, setters)
    fb.AddOffset(3, getters)
    fb.AddStruct(2, left_curl_pos, 4)
    fb.AddStruct(1, colon_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateGenericConstraint(fb: FlatBufferBuilder, base: FlatBufferOffset, where_pos: ArrayList<UInt8>, typeValue: FlatBufferOffset, operator_pos: ArrayList<UInt8>, upper_bound: FlatBufferOffset, bit_and_pos_vec: FlatBufferOffset, comma_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(7)
    fb.AddStruct(6, comma_pos, 4)
    fb.AddOffset(5, bit_and_pos_vec)
    fb.AddOffset(4, upper_bound)
    fb.AddStruct(3, operator_pos, 4)
    fb.AddOffset(2, typeValue)
    fb.AddStruct(1, where_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateGeneric(fb: FlatBufferBuilder, left_angle_pos: ArrayList<UInt8>, type_parameters: FlatBufferOffset, right_angle_pos: ArrayList<UInt8>, generic_constraints: FlatBufferOffset, content: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddOffset(4, content)
    fb.AddOffset(3, generic_constraints)
    fb.AddStruct(2, right_angle_pos, 4)
    fb.AddOffset(1, type_parameters)
    fb.AddStruct(0, left_angle_pos, 4)
    return fb.EndTable()
}

public func CreateAnnotation(fb: FlatBufferBuilder, base: FlatBufferOffset, kind: UInt16, identPos: ArrayList<UInt8>, identifier: FlatBufferOffset, args: FlatBufferOffset, overflow_strategy: FlatBufferOffset, attrs: FlatBufferOffset, condExpr: FlatBufferOffset, left_square_pos: ArrayList<UInt8>, right_square_pos: ArrayList<UInt8>, is_compile_time_visible: Bool): FlatBufferOffset {
    fb.StartTable(11)
    fb.AddStruct(9, right_square_pos, 4)
    fb.AddStruct(8, left_square_pos, 4)
    fb.AddOffset(7, condExpr)
    fb.AddOffset(6, attrs)
    fb.AddOffset(5, overflow_strategy)
    fb.AddOffset(4, args)
    fb.AddOffset(3, identifier)
    fb.AddStruct(2, identPos, 4)
    fb.AddOffset(0, base)
    fb.AddU16(1, kind)
    fb.AddU8(10, is_compile_time_visible)
    return fb.EndTable()
}

public func CreateModifier(fb: FlatBufferBuilder, base: FlatBufferOffset, kind: UInt16, is_explicit: Bool): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddOffset(0, base)
    fb.AddU16(1, kind)
    fb.AddU8(2, is_explicit)
    return fb.EndTable()
}

public func CreateDeclBase(fb: FlatBufferBuilder, base: FlatBufferOffset, identifier: FlatBufferOffset, identifier_pos: ArrayList<UInt8>, keyword_pos: ArrayList<UInt8>, annotations: FlatBufferOffset, modifiers: FlatBufferOffset, generic: FlatBufferOffset, isConst: Bool): FlatBufferOffset {
    fb.StartTable(8)
    fb.AddOffset(6, generic)
    fb.AddOffset(5, modifiers)
    fb.AddOffset(4, annotations)
    fb.AddStruct(3, keyword_pos, 4)
    fb.AddStruct(2, identifier_pos, 4)
    fb.AddOffset(1, identifier)
    fb.AddOffset(0, base)
    fb.AddU8(7, isConst)
    return fb.EndTable()
}

public func CreateTypeAliasDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, assign_pos: ArrayList<UInt8>, typeValue: FlatBufferOffset, generic: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddOffset(3, generic)
    fb.AddOffset(2, typeValue)
    fb.AddStruct(1, assign_pos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateExtendDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, extended_type: FlatBufferOffset, upper_bound_pos: ArrayList<UInt8>, interfaces: FlatBufferOffset, where_pos: ArrayList<UInt8>, left_curl_pos: ArrayList<UInt8>, members: FlatBufferOffset, right_curl_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(8)
    fb.AddStruct(7, right_curl_pos, 4)
    fb.AddOffset(6, members)
    fb.AddStruct(5, left_curl_pos, 4)
    fb.AddStruct(4, where_pos, 4)
    fb.AddOffset(3, interfaces)
    fb.AddStruct(2, upper_bound_pos, 4)
    fb.AddOffset(1, extended_type)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, decl_type: UInt8, decl: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddOffset(2, decl)
    fb.AddOffset(0, base)
    fb.AddU8(1, decl_type)
    return fb.EndTable()
}

public func CreateBlock(fb: FlatBufferBuilder, base: FlatBufferOffset, left_curl_pos: ArrayList<UInt8>, body: FlatBufferOffset, right_curl_pos: ArrayList<UInt8>, is_unsafe: Bool, unsafe_pos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddStruct(5, unsafe_pos, 4)
    fb.AddStruct(3, right_curl_pos, 4)
    fb.AddOffset(2, body)
    fb.AddStruct(1, left_curl_pos, 4)
    fb.AddOffset(0, base)
    fb.AddU8(4, is_unsafe)
    return fb.EndTable()
}

public func CreateMacroInvocation(fb: FlatBufferBuilder, fullName: FlatBufferOffset, identifier: FlatBufferOffset, identifierPos: ArrayList<UInt8>, leftSquarePos: ArrayList<UInt8>, rightSquarePos: ArrayList<UInt8>, leftParenPos: ArrayList<UInt8>, rightParenPos: ArrayList<UInt8>, atPos: ArrayList<UInt8>, attrs: FlatBufferOffset, args: FlatBufferOffset, decl: FlatBufferOffset, hasParenthesis: Bool, is_compile_time_visible: Bool): FlatBufferOffset {
    fb.StartTable(13)
    fb.AddOffset(10, decl)
    fb.AddOffset(9, args)
    fb.AddOffset(8, attrs)
    fb.AddStruct(7, atPos, 4)
    fb.AddStruct(6, rightParenPos, 4)
    fb.AddStruct(5, leftParenPos, 4)
    fb.AddStruct(4, rightSquarePos, 4)
    fb.AddStruct(3, leftSquarePos, 4)
    fb.AddStruct(2, identifierPos, 4)
    fb.AddOffset(1, identifier)
    fb.AddOffset(0, fullName)
    fb.AddU8(12, is_compile_time_visible)
    fb.AddU8(11, hasParenthesis)
    return fb.EndTable()
}

public func CreateMacroExpandExpr(fb: FlatBufferBuilder, base: FlatBufferOffset, invocation: FlatBufferOffset, identifier: FlatBufferOffset, identifierPos: ArrayList<UInt8>, annotations: FlatBufferOffset, modifiers: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(6)
    fb.AddOffset(5, modifiers)
    fb.AddOffset(4, annotations)
    fb.AddStruct(3, identifierPos, 4)
    fb.AddOffset(2, identifier)
    fb.AddOffset(1, invocation)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateMacroExpandDecl(fb: FlatBufferBuilder, base: FlatBufferOffset, invocation: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(2)
    fb.AddOffset(1, invocation)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateMacroExpandParam(fb: FlatBufferBuilder, base: FlatBufferOffset, invocation: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(2)
    fb.AddOffset(1, invocation)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateFile(fb: FlatBufferBuilder, base: FlatBufferOffset, fileName: FlatBufferOffset, filePath: FlatBufferOffset, packageValue: FlatBufferOffset, imports: FlatBufferOffset, decls: FlatBufferOffset, feature: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(7)
    fb.AddOffset(6, feature)
    fb.AddOffset(5, decls)
    fb.AddOffset(4, imports)
    fb.AddOffset(3, packageValue)
    fb.AddOffset(2, filePath)
    fb.AddOffset(1, fileName)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateFeatureId(fb: FlatBufferBuilder, base: FlatBufferOffset, identifiers: FlatBufferOffset, identPoses: FlatBufferOffset, dotPoses: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddOffset(3, dotPoses)
    fb.AddOffset(2, identPoses)
    fb.AddOffset(1, identifiers)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateFeaturesSet(fb: FlatBufferBuilder, base: FlatBufferOffset, lCurlPos: ArrayList<UInt8>, content: FlatBufferOffset, commaPoses: FlatBufferOffset, rCurlPos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(5)
    fb.AddStruct(4, rCurlPos, 4)
    fb.AddOffset(3, commaPoses)
    fb.AddOffset(2, content)
    fb.AddStruct(1, lCurlPos, 4)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreateFeaturesDirective(fb: FlatBufferBuilder, base: FlatBufferOffset, annotations: FlatBufferOffset, featuresSet: FlatBufferOffset, featuresPos: ArrayList<UInt8>): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddStruct(3, featuresPos, 4)
    fb.AddOffset(2, featuresSet)
    fb.AddOffset(1, annotations)
    fb.AddOffset(0, base)
    return fb.EndTable()
}

public func CreatePackageSpec(fb: FlatBufferBuilder, base: FlatBufferOffset, macroPos: ArrayList<UInt8>, packagePos: ArrayList<UInt8>, prefixPaths: FlatBufferOffset, prefixPoses: FlatBufferOffset, prefixDotPoses: FlatBufferOffset, packageName: FlatBufferOffset, packageNamePos: ArrayList<UInt8>, accessible: UInt8, hasMacro: Bool, hasDoubleColon: Bool): FlatBufferOffset {
    fb.StartTable(11)
    fb.AddStruct(7, packageNamePos, 4)
    fb.AddOffset(6, packageName)
    fb.AddOffset(5, prefixDotPoses)
    fb.AddOffset(4, prefixPoses)
    fb.AddOffset(3, prefixPaths)
    fb.AddStruct(2, packagePos, 4)
    fb.AddStruct(1, macroPos, 4)
    fb.AddOffset(0, base)
    fb.AddU8(10, hasDoubleColon)
    fb.AddU8(9, hasMacro)
    fb.AddU8(8, accessible)
    return fb.EndTable()
}

public func CreateImportContent(fb: FlatBufferBuilder, base: FlatBufferOffset, kind: UInt8, prefixPaths: FlatBufferOffset, prefixPoses: FlatBufferOffset, prefixDotPoses: FlatBufferOffset, identifier: FlatBufferOffset, identifierPos: ArrayList<UInt8>, asPos: ArrayList<UInt8>, asIdentifier: FlatBufferOffset, asIdentifierPos: ArrayList<UInt8>, leftCurlPos: ArrayList<UInt8>, items: FlatBufferOffset, commaPoses: FlatBufferOffset, rightCurlPos: ArrayList<UInt8>, hasDoubleColon: Bool): FlatBufferOffset {
    fb.StartTable(15)
    fb.AddStruct(13, rightCurlPos, 4)
    fb.AddOffset(12, commaPoses)
    fb.AddOffset(11, items)
    fb.AddStruct(10, leftCurlPos, 4)
    fb.AddStruct(9, asIdentifierPos, 4)
    fb.AddOffset(8, asIdentifier)
    fb.AddStruct(7, asPos, 4)
    fb.AddStruct(6, identifierPos, 4)
    fb.AddOffset(5, identifier)
    fb.AddOffset(4, prefixDotPoses)
    fb.AddOffset(3, prefixPoses)
    fb.AddOffset(2, prefixPaths)
    fb.AddOffset(0, base)
    fb.AddU8(14, hasDoubleColon)
    fb.AddU8(1, kind)
    return fb.EndTable()
}

public func CreateImportSpec(fb: FlatBufferBuilder, base: FlatBufferOffset, reExport: UInt8, importPos: ArrayList<UInt8>, content: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(4)
    fb.AddOffset(3, content)
    fb.AddStruct(2, importPos, 4)
    fb.AddOffset(0, base)
    fb.AddU8(1, reExport)
    return fb.EndTable()
}

public func CreateNodeBase(fb: FlatBufferBuilder, begin: ArrayList<UInt8>, end: ArrayList<UInt8>, ast_kind: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddOffset(2, ast_kind)
    fb.AddStruct(1, end, 4)
    fb.AddStruct(0, begin, 4)
    return fb.EndTable()
}

public func CreateNode(fb: FlatBufferBuilder, base: FlatBufferOffset, root_type: UInt8, root: FlatBufferOffset): FlatBufferOffset {
    fb.StartTable(3)
    fb.AddOffset(2, root)
    fb.AddOffset(0, base)
    fb.AddU8(1, root_type)
    return fb.EndTable()
}
