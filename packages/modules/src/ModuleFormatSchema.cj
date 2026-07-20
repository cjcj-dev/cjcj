package cjcj::modules

import cjcj::flatbuffers.ReadScalar

// ModuleFormat FlatBuffer bindings root and file identifier.
// ModuleFormat.fbs:14 (file_identifier "CJOF"); ModuleFormat_generated.h:6717-6720
// (PackageIdentifier/PackageBufferHasIdentifier) and 6623 (root_type Package).
const MF_FILE_IDENTIFIER: String = "CJOF"
const MF_ROOT_TABLE: String = "Package"

// ModuleFormat.fbs:16-19: table indexes are uint32; 0 is the invalid/null index
// and valid indexes start at 1. Mirrors INVALID_FORMAT_INDEX in
// ASTSerializationTypeDef.cj.
const MF_INVALID_INDEX: UInt32 = 0u32
const MF_FIRST_INDEX: UInt32 = 1u32

// Reads the root Package table offset from the buffer front (uoffset_t).
// ModuleFormat_generated.h:6701-6704 (GetPackage).
public func GetPackage(data: Array<UInt8>): PackageFormat_Package {
    return PackageFormat_Package(data, Int64(ReadScalar(data, 0, 0u32)))
}

// DeclKind enum ordinals. ModuleFormat.fbs:20-35; ModuleFormat_generated.h:220-251.
const MF_DECL_KIND_INVALID_DECL: UInt16 = 0u16
public const MF_DECL_KIND_CLASS_DECL: UInt16 = 1u16
public const MF_DECL_KIND_INTERFACE_DECL: UInt16 = 2u16
public const MF_DECL_KIND_FUNC_DECL: UInt16 = 3u16
public const MF_DECL_KIND_PROP_DECL: UInt16 = 4u16
public const MF_DECL_KIND_VAR_DECL: UInt16 = 5u16
public const MF_DECL_KIND_VAR_WITH_PATTERN_DECL: UInt16 = 6u16
public const MF_DECL_KIND_FUNC_PARAM: UInt16 = 7u16
public const MF_DECL_KIND_STRUCT_DECL: UInt16 = 8u16
public const MF_DECL_KIND_ENUM_DECL: UInt16 = 9u16
public const MF_DECL_KIND_EXTEND_DECL: UInt16 = 10u16
public const MF_DECL_KIND_TYPE_ALIAS_DECL: UInt16 = 11u16
const MF_DECL_KIND_GENERIC_PARAM_DECL: UInt16 = 12u16
const MF_DECL_KIND_BUILT_IN_DECL: UInt16 = 13u16

// ConstValue union type ordinals. ModuleFormat.fbs:96-111; ModuleFormat_generated.h:286-303.
const MF_CONST_VALUE_NONE: UInt8 = 0u8
const MF_CONST_VALUE_INT8_VALUE: UInt8 = 1u8
const MF_CONST_VALUE_UINT8_VALUE: UInt8 = 2u8
const MF_CONST_VALUE_INT16_VALUE: UInt8 = 3u8
const MF_CONST_VALUE_UINT16_VALUE: UInt8 = 4u8
const MF_CONST_VALUE_INT32_VALUE: UInt8 = 5u8
const MF_CONST_VALUE_UINT32_VALUE: UInt8 = 6u8
const MF_CONST_VALUE_INT64_VALUE: UInt8 = 7u8
const MF_CONST_VALUE_UINT64_VALUE: UInt8 = 8u8
const MF_CONST_VALUE_FLOAT32_VALUE: UInt8 = 9u8
const MF_CONST_VALUE_FLOAT64_VALUE: UInt8 = 10u8
const MF_CONST_VALUE_ARRAY_VALUE: UInt8 = 11u8
const MF_CONST_VALUE_STRING_VALUE: UInt8 = 12u8
const MF_CONST_VALUE_COMPOSITE_VALUE: UInt8 = 13u8

// OverflowPolicy enum ordinals. ModuleFormat.fbs:159-165; ModuleFormat_generated.h:411-419.
const MF_OVERFLOW_POLICY_NA: UInt8 = 0u8
const MF_OVERFLOW_POLICY_CHECKED: UInt8 = 1u8
const MF_OVERFLOW_POLICY_WRAPPING: UInt8 = 2u8
const MF_OVERFLOW_POLICY_THROWING: UInt8 = 3u8
const MF_OVERFLOW_POLICY_SATURATING: UInt8 = 4u8

// OperatorKind enum ordinals. ModuleFormat.fbs:166-215; ModuleFormat_generated.h:450-503.
const MF_OPERATOR_KIND_NA: UInt8 = 0u8
const MF_OPERATOR_KIND_INDEX: UInt8 = 1u8
const MF_OPERATOR_KIND_CALL: UInt8 = 2u8
const MF_OPERATOR_KIND_NOT: UInt8 = 3u8
const MF_OPERATOR_KIND_POWER: UInt8 = 4u8
const MF_OPERATOR_KIND_MULTIPLY: UInt8 = 5u8
const MF_OPERATOR_KIND_DIVIDE: UInt8 = 6u8
const MF_OPERATOR_KIND_REMAINDER: UInt8 = 7u8
const MF_OPERATOR_KIND_ADD: UInt8 = 8u8
const MF_OPERATOR_KIND_SUBTRACT: UInt8 = 9u8
const MF_OPERATOR_KIND_BIT_LEFT_SHIFT: UInt8 = 10u8
const MF_OPERATOR_KIND_BIT_RIGHT_SHIFT: UInt8 = 11u8
const MF_OPERATOR_KIND_LT: UInt8 = 12u8
const MF_OPERATOR_KIND_LE: UInt8 = 13u8
const MF_OPERATOR_KIND_GT: UInt8 = 14u8
const MF_OPERATOR_KIND_GE: UInt8 = 15u8
const MF_OPERATOR_KIND_EQUAL: UInt8 = 16u8
const MF_OPERATOR_KIND_NOT_EQUAL: UInt8 = 17u8
const MF_OPERATOR_KIND_BIT_AND: UInt8 = 18u8
const MF_OPERATOR_KIND_BIT_XOR: UInt8 = 19u8
const MF_OPERATOR_KIND_BIT_OR: UInt8 = 20u8
const MF_OPERATOR_KIND_POST_INC: UInt8 = 21u8
const MF_OPERATOR_KIND_POST_DEC: UInt8 = 22u8
const MF_OPERATOR_KIND_IS: UInt8 = 23u8
const MF_OPERATOR_KIND_AS: UInt8 = 24u8
const MF_OPERATOR_KIND_LOGIC_AND: UInt8 = 25u8
const MF_OPERATOR_KIND_LOGIC_OR: UInt8 = 26u8
const MF_OPERATOR_KIND_COALESCING: UInt8 = 27u8
const MF_OPERATOR_KIND_PIPELINE: UInt8 = 28u8
const MF_OPERATOR_KIND_COMPOSITION: UInt8 = 29u8
const MF_OPERATOR_KIND_ASSIGN: UInt8 = 30u8
const MF_OPERATOR_KIND_POWER_ASSIGN: UInt8 = 31u8
const MF_OPERATOR_KIND_MULTIPLY_ASSIGN: UInt8 = 32u8
const MF_OPERATOR_KIND_DIVIDE_ASSIGN: UInt8 = 33u8
const MF_OPERATOR_KIND_REMAINDER_ASSIGN: UInt8 = 34u8
const MF_OPERATOR_KIND_ADD_ASSIGN: UInt8 = 35u8
const MF_OPERATOR_KIND_SUBTRACT_ASSIGN: UInt8 = 36u8
const MF_OPERATOR_KIND_LEFT_SHIFT_ASSIGN: UInt8 = 37u8
const MF_OPERATOR_KIND_RIGHT_SHIFT_ASSIGN: UInt8 = 38u8
const MF_OPERATOR_KIND_BIT_AND_ASSIGN: UInt8 = 39u8
const MF_OPERATOR_KIND_BIT_XOR_ASSIGN: UInt8 = 40u8
const MF_OPERATOR_KIND_BIT_OR_ASSIGN: UInt8 = 41u8
const MF_OPERATOR_KIND_LOGIC_AND_ASSIGN: UInt8 = 42u8
const MF_OPERATOR_KIND_LOGIC_OR_ASSIGN: UInt8 = 43u8

// DeclInfo union type ordinals. ModuleFormat.fbs:288-301; ModuleFormat_generated.h:645-661.
const MF_DECL_INFO_NONE: UInt8 = 0u8
const MF_DECL_INFO_CLASS_INFO: UInt8 = 1u8
const MF_DECL_INFO_INTERFACE_INFO: UInt8 = 2u8
const MF_DECL_INFO_STRUCT_INFO: UInt8 = 3u8
const MF_DECL_INFO_ENUM_INFO: UInt8 = 4u8
const MF_DECL_INFO_EXTEND_INFO: UInt8 = 5u8
const MF_DECL_INFO_PROP_INFO: UInt8 = 6u8
const MF_DECL_INFO_VAR_INFO: UInt8 = 7u8
const MF_DECL_INFO_VAR_WITH_PATTERN_INFO: UInt8 = 8u8
const MF_DECL_INFO_PARAM_INFO: UInt8 = 9u8
const MF_DECL_INFO_FUNC_INFO: UInt8 = 10u8
const MF_DECL_INFO_BUILT_IN_INFO: UInt8 = 11u8
const MF_DECL_INFO_ALIAS_INFO: UInt8 = 12u8

// BuiltInType enum ordinals. ModuleFormat.fbs:277-283; ModuleFormat_generated.h:606-618.
const MF_BUILT_IN_TYPE_ARRAY: UInt8 = 0u8
const MF_BUILT_IN_TYPE_V_ARRAY: UInt8 = 1u8
const MF_BUILT_IN_TYPE_C_POINTER: UInt8 = 2u8
const MF_BUILT_IN_TYPE_C_STRING: UInt8 = 3u8
const MF_BUILT_IN_TYPE_C_FUNC: UInt8 = 4u8

// AnnoKind enum ordinals. ModuleFormat.fbs:376-388; ModuleFormat_generated.h:763-781.
const MF_ANNO_KIND_DEPRECATED: UInt16 = 0u16
const MF_ANNO_KIND_TEST_REGISTRATION: UInt16 = 1u16
const MF_ANNO_KIND_FROZEN: UInt16 = 2u16
const MF_ANNO_KIND_CUSTOM: UInt16 = 3u16
const MF_ANNO_KIND_JAVA_MIRROR: UInt16 = 4u16
const MF_ANNO_KIND_JAVA_IMPL: UInt16 = 5u16
const MF_ANNO_KIND_OBJC_MIRROR: UInt16 = 6u16
const MF_ANNO_KIND_OBJC_IMPL: UInt16 = 7u16
const MF_ANNO_KIND_FOREIGN_NAME: UInt16 = 8u16
const MF_ANNO_KIND_JAVA_HAS_DEFAULT: UInt16 = 9u16
const MF_ANNO_KIND_ANNOTATION: UInt16 = 10u16

// ExprKind enum ordinals. ModuleFormat.fbs:404-445; ModuleFormat_generated.h:820-901.
const MF_EXPR_KIND_INVALID_EXPR: UInt16 = 0u16
const MF_EXPR_KIND_WILDCARD_EXPR: UInt16 = 1u16
const MF_EXPR_KIND_PRIMITIVE_TYPE_EXPR: UInt16 = 2u16
const MF_EXPR_KIND_RETURN_EXPR: UInt16 = 3u16
public const MF_EXPR_KIND_JUMP_EXPR: UInt16 = 4u16
public const MF_EXPR_KIND_MEMBER_ACCESS: UInt16 = 5u16
public const MF_EXPR_KIND_REF_EXPR: UInt16 = 6u16
public const MF_EXPR_KIND_CALL_EXPR: UInt16 = 7u16
const MF_EXPR_KIND_UNARY_EXPR: UInt16 = 8u16
const MF_EXPR_KIND_INC_OR_DEC_EXPR: UInt16 = 9u16
public const MF_EXPR_KIND_LIT_CONST_EXPR: UInt16 = 10u16
const MF_EXPR_KIND_BINARY_EXPR: UInt16 = 11u16
const MF_EXPR_KIND_SUBSCRIPT_EXPR: UInt16 = 12u16
const MF_EXPR_KIND_ASSIGN_EXPR: UInt16 = 13u16
public const MF_EXPR_KIND_ARRAY_EXPR: UInt16 = 14u16
const MF_EXPR_KIND_POINTER_EXPR: UInt16 = 15u16
const MF_EXPR_KIND_TYPE_CONV_EXPR: UInt16 = 16u16
const MF_EXPR_KIND_THROW_EXPR: UInt16 = 17u16
const MF_EXPR_KIND_SPAWN_EXPR: UInt16 = 18u16
public const MF_EXPR_KIND_ARRAY_LIT: UInt16 = 19u16
const MF_EXPR_KIND_TUPLE_LIT: UInt16 = 20u16
public const MF_EXPR_KIND_MATCH_EXPR: UInt16 = 21u16
public const MF_EXPR_KIND_LET_PATTERN_DESTRUCTOR: UInt16 = 22u16
const MF_EXPR_KIND_IF_EXPR: UInt16 = 23u16
public const MF_EXPR_KIND_TRY_EXPR: UInt16 = 24u16
const MF_EXPR_KIND_WHILE_EXPR: UInt16 = 25u16
const MF_EXPR_KIND_DO_WHILE_EXPR: UInt16 = 26u16
public const MF_EXPR_KIND_LAMBDA_EXPR: UInt16 = 27u16
const MF_EXPR_KIND_BLOCK: UInt16 = 28u16
const MF_EXPR_KIND_MATCH_CASE: UInt16 = 29u16
const MF_EXPR_KIND_MATCH_CASE_OTHER: UInt16 = 30u16
const MF_EXPR_KIND_ADJOINT_EXPR: UInt16 = 31u16
const MF_EXPR_KIND_GRAD_EXPR: UInt16 = 32u16
const MF_EXPR_KIND_VAL_WITH_GRAD_EXPR: UInt16 = 33u16
const MF_EXPR_KIND_VJP_EXPR: UInt16 = 34u16
public const MF_EXPR_KIND_FOR_IN_EXPR: UInt16 = 35u16
const MF_EXPR_KIND_IF_AVAILABLE_EXPR: UInt16 = 36u16
const MF_EXPR_KIND_PERFORM_EXPR: UInt16 = 37u16
const MF_EXPR_KIND_RESUME_EXPR: UInt16 = 38u16

// CallKind enum ordinals. ModuleFormat.fbs:447-458; ModuleFormat_generated.h:961-975.
const MF_CALL_KIND_NA: UInt8 = 0u8
const MF_CALL_KIND_CALL_DECLARED_FUNCTION: UInt8 = 1u8
const MF_CALL_KIND_CALL_OBJECT_CREATION: UInt8 = 2u8
const MF_CALL_KIND_CALL_STRUCT_CREATION: UInt8 = 3u8
const MF_CALL_KIND_CALL_SUPER_FUNCTION: UInt8 = 4u8
const MF_CALL_KIND_CALL_VARIADIC_FUNCTION: UInt8 = 5u8
const MF_CALL_KIND_CALL_FUNCTION_PTR: UInt8 = 6u8
const MF_CALL_KIND_CALL_ANNOTATION: UInt8 = 7u8
const MF_CALL_KIND_CALL_BUILTIN_FUNCTION: UInt8 = 8u8
const MF_CALL_KIND_CALL_INTRINSIC_FUNCTION: UInt8 = 9u8

// LitConstKind enum ordinals. ModuleFormat.fbs:460-469; ModuleFormat_generated.h:1015-1027.
const MF_LIT_CONST_KIND_INTEGER: UInt8 = 0u8
const MF_LIT_CONST_KIND_RUNE_BYTE: UInt8 = 1u8
const MF_LIT_CONST_KIND_FLOAT: UInt8 = 2u8
const MF_LIT_CONST_KIND_RUNE: UInt8 = 3u8
const MF_LIT_CONST_KIND_STRING: UInt8 = 4u8
const MF_LIT_CONST_KIND_J_STRING: UInt8 = 5u8
const MF_LIT_CONST_KIND_BOOL: UInt8 = 6u8
const MF_LIT_CONST_KIND_UNIT: UInt8 = 7u8

// StringKind enum ordinals. ModuleFormat.fbs:470-475; ModuleFormat_generated.h:1063-1071.
const MF_STRING_KIND_NORMAL: UInt8 = 0u8
const MF_STRING_KIND_J_STRING: UInt8 = 1u8
const MF_STRING_KIND_MULTI_LINE: UInt8 = 2u8
const MF_STRING_KIND_MULTI_LINE_RAW: UInt8 = 3u8

// ForInKind enum ordinals. ModuleFormat.fbs:477-482; ModuleFormat_generated.h:1099-1107.
const MF_FOR_IN_KIND_NA: UInt8 = 0u8
const MF_FOR_IN_KIND_RANGE: UInt8 = 1u8
const MF_FOR_IN_KIND_STRING: UInt8 = 2u8
const MF_FOR_IN_KIND_ITERATOR: UInt8 = 3u8

// ExprInfo union type ordinals. ModuleFormat.fbs:484-504; ModuleFormat_generated.h:1135-1157.
const MF_EXPR_INFO_NONE: UInt8 = 0u8
const MF_EXPR_INFO_CALL_INFO: UInt8 = 1u8
const MF_EXPR_INFO_UNARY_INFO: UInt8 = 2u8
const MF_EXPR_INFO_BINARY_INFO: UInt8 = 3u8
const MF_EXPR_INFO_INC_OR_DEC_INFO: UInt8 = 4u8
const MF_EXPR_INFO_LIT_CONST_INFO: UInt8 = 5u8
const MF_EXPR_INFO_REFERENCE_INFO: UInt8 = 6u8
const MF_EXPR_INFO_LAMBDA_INFO: UInt8 = 7u8
const MF_EXPR_INFO_ASSIGN_INFO: UInt8 = 8u8
const MF_EXPR_INFO_ARRAY_INFO: UInt8 = 9u8
const MF_EXPR_INFO_JUMP_INFO: UInt8 = 10u8
const MF_EXPR_INFO_FUNC_ARG_INFO: UInt8 = 11u8
const MF_EXPR_INFO_SUBSCRIPT_INFO: UInt8 = 12u8
const MF_EXPR_INFO_MATCH_INFO: UInt8 = 13u8
const MF_EXPR_INFO_BLOCK_INFO: UInt8 = 14u8
const MF_EXPR_INFO_TRY_INFO: UInt8 = 15u8
const MF_EXPR_INFO_LET_PATTERN_DESTRUCTOR_INFO: UInt8 = 16u8
const MF_EXPR_INFO_FOR_IN_INFO: UInt8 = 17u8
const MF_EXPR_INFO_MATCH_CASE_INFO: UInt8 = 18u8
const MF_EXPR_INFO_SPAWN_INFO: UInt8 = 19u8

// PatternKind enum ordinals (int8). ModuleFormat.fbs:594-604; ModuleFormat_generated.h:1302-1314.
const MF_PATTERN_KIND_INVALID_PATTERN: Int8 = 0i8
const MF_PATTERN_KIND_CONST_PATTERN: Int8 = 1i8
const MF_PATTERN_KIND_WILDCARD_PATTERN: Int8 = 2i8
const MF_PATTERN_KIND_VAR_PATTERN: Int8 = 3i8
public const MF_PATTERN_KIND_TUPLE_PATTERN: Int8 = 4i8
public const MF_PATTERN_KIND_TYPE_PATTERN: Int8 = 5i8
public const MF_PATTERN_KIND_ENUM_PATTERN: Int8 = 6i8
public const MF_PATTERN_KIND_EXCEPT_TYPE_PATTERN: Int8 = 7i8
public const MF_PATTERN_KIND_COMMAND_TYPE_PATTERN: Int8 = 8i8

// TypeKind enum ordinals. ModuleFormat.fbs:619-651; ModuleFormat_generated.h:1353-1415.
const MF_TYPE_KIND_INVALID: UInt16 = 0u16
public const MF_TYPE_KIND_UNIT: UInt16 = 1u16
public const MF_TYPE_KIND_INT8: UInt16 = 2u16
public const MF_TYPE_KIND_INT16: UInt16 = 3u16
public const MF_TYPE_KIND_INT32: UInt16 = 4u16
public const MF_TYPE_KIND_INT64: UInt16 = 5u16
public const MF_TYPE_KIND_INT_NATIVE: UInt16 = 6u16
public const MF_TYPE_KIND_UINT8: UInt16 = 7u16
public const MF_TYPE_KIND_UINT16: UInt16 = 8u16
public const MF_TYPE_KIND_UINT32: UInt16 = 9u16
public const MF_TYPE_KIND_UINT64: UInt16 = 10u16
public const MF_TYPE_KIND_UINT_NATIVE: UInt16 = 11u16
public const MF_TYPE_KIND_FLOAT16: UInt16 = 12u16
public const MF_TYPE_KIND_FLOAT32: UInt16 = 13u16
public const MF_TYPE_KIND_FLOAT64: UInt16 = 14u16
public const MF_TYPE_KIND_RUNE: UInt16 = 15u16
public const MF_TYPE_KIND_NOTHING: UInt16 = 16u16
public const MF_TYPE_KIND_BOOL: UInt16 = 17u16
public const MF_TYPE_KIND_TUPLE: UInt16 = 18u16
public const MF_TYPE_KIND_ENUM: UInt16 = 19u16
public const MF_TYPE_KIND_FUNC: UInt16 = 20u16
public const MF_TYPE_KIND_STRUCT: UInt16 = 21u16
public const MF_TYPE_KIND_ARRAY: UInt16 = 22u16
public const MF_TYPE_KIND_V_ARRAY: UInt16 = 23u16
public const MF_TYPE_KIND_C_POINTER: UInt16 = 24u16
public const MF_TYPE_KIND_C_STRING: UInt16 = 25u16
public const MF_TYPE_KIND_CLASS: UInt16 = 26u16
public const MF_TYPE_KIND_INTERFACE: UInt16 = 27u16
public const MF_TYPE_KIND_TYPE: UInt16 = 28u16
public const MF_TYPE_KIND_GENERIC: UInt16 = 29u16

// SemaTyInfo union type ordinals. ModuleFormat.fbs:653-658; ModuleFormat_generated.h:1467-1477.
public const MF_SEMA_TY_INFO_NONE: UInt8 = 0u8
public const MF_SEMA_TY_INFO_FUNC_TY_INFO: UInt8 = 1u8
public const MF_SEMA_TY_INFO_COMPOSITE_TY_INFO: UInt8 = 2u8
public const MF_SEMA_TY_INFO_GENERIC_TY_INFO: UInt8 = 3u8
public const MF_SEMA_TY_INFO_ARRAY_TY_INFO: UInt8 = 4u8

// AccessModifier enum ordinals. ModuleFormat.fbs:686-691; ModuleFormat_generated.h:1529-1537.
const MF_ACCESS_MODIFIER_PRIVATE: UInt8 = 0u8
const MF_ACCESS_MODIFIER_INTERNAL: UInt8 = 1u8
const MF_ACCESS_MODIFIER_PROTECTED: UInt8 = 2u8
const MF_ACCESS_MODIFIER_PUBLIC: UInt8 = 3u8

// PackageKind enum ordinals. ModuleFormat.fbs:715-720; ModuleFormat_generated.h:1565-1573.
const MF_PACKAGE_KIND_NORMAL: UInt8 = 0u8
const MF_PACKAGE_KIND_MACRO: UInt8 = 1u8
const MF_PACKAGE_KIND_FOREIGN: UInt8 = 2u8
const MF_PACKAGE_KIND_MOCK: UInt8 = 3u8

// AccessLevel enum ordinals. ModuleFormat.fbs:722-726; ModuleFormat_generated.h:1601-1607.
const MF_ACCESS_LEVEL_PUBLIC: UInt8 = 0u8
const MF_ACCESS_LEVEL_PROTECTED: UInt8 = 1u8
const MF_ACCESS_LEVEL_INTERNAL: UInt8 = 2u8

// OptimizationLevel enum ordinals. ModuleFormat.fbs:737-739; ModuleFormat_generated.h:1634-1642.
const MF_OPTIMIZATION_LEVEL_O0: UInt8 = 0u8
const MF_OPTIMIZATION_LEVEL_O1: UInt8 = 1u8
const MF_OPTIMIZATION_LEVEL_O2: UInt8 = 2u8
const MF_OPTIMIZATION_LEVEL_O3: UInt8 = 3u8
const MF_OPTIMIZATION_LEVEL_OS: UInt8 = 4u8
const MF_OPTIMIZATION_LEVEL_OZ: UInt8 = 5u8

// Table vtable field offsets. Each block cites ModuleFormat_generated.h's
// VT_ enum for the corresponding table. Offsets follow FlatBuffers' 4+2*slot
// layout, with union members occupying two slots (_TYPE then value).
// FullId. ModuleFormat_generated.h:1986-1988.
const MF_FULL_ID_VT_PKGID: UInt16 = 4u16
const MF_FULL_ID_VT_DECL: UInt16 = 6u16
const MF_FULL_ID_VT_INDEX: UInt16 = 8u16

// Constraint. ModuleFormat_generated.h:2061-2065.
const MF_CONSTRAINT_VT_BEGIN: UInt16 = 4u16
const MF_CONSTRAINT_VT_END: UInt16 = 6u16
const MF_CONSTRAINT_VT_TYPE: UInt16 = 8u16
const MF_CONSTRAINT_VT_UPPERS: UInt16 = 10u16
const MF_CONSTRAINT_VT_ISIMPLICITLYINTRODUCED: UInt16 = 12u16

// Generic. ModuleFormat_generated.h:2160-2161.
const MF_GENERIC_VT_TYPEPARAMETERS: UInt16 = 4u16
const MF_GENERIC_VT_CONSTRAINTS: UInt16 = 6u16

// FuncParamList. ModuleFormat_generated.h:2226-2227.
const MF_FUNC_PARAM_LIST_VT_PARAMS: UInt16 = 4u16
const MF_FUNC_PARAM_LIST_VT_DESUGARS: UInt16 = 6u16

// FuncBody. ModuleFormat_generated.h:2291-2295.
const MF_FUNC_BODY_VT_PARAMLISTS: UInt16 = 4u16
const MF_FUNC_BODY_VT_RETTYPE: UInt16 = 6u16
const MF_FUNC_BODY_VT_BODY: UInt16 = 8u16
const MF_FUNC_BODY_VT_ALWAYS: UInt16 = 10u16
const MF_FUNC_BODY_VT_CAPTUREKIND: UInt16 = 12u16

// ArrayValue. ModuleFormat_generated.h:2391-2392.
const MF_ARRAY_VALUE_VT_VAL_TYPE: UInt16 = 4u16
const MF_ARRAY_VALUE_VT_VAL: UInt16 = 6u16

// MemberValue. ModuleFormat_generated.h:2457-2460.
const MF_MEMBER_VALUE_VT_FIELD: UInt16 = 4u16
const MF_MEMBER_VALUE_VT_TYPE: UInt16 = 6u16
const MF_MEMBER_VALUE_VT_VALUE_TYPE: UInt16 = 8u16
const MF_MEMBER_VALUE_VT_VALUE: UInt16 = 10u16

// CompositeValue. ModuleFormat_generated.h:2637-2638.
const MF_COMPOSITE_VALUE_VT_TYPE: UInt16 = 4u16
const MF_COMPOSITE_VALUE_VT_FIELDS: UInt16 = 6u16

// AutoDiffInfo. ModuleFormat_generated.h:2701-2706.
const MF_AUTO_DIFF_INFO_VT_ISDIFF: UInt16 = 4u16
const MF_AUTO_DIFF_INFO_VT_ISADJ: UInt16 = 6u16
const MF_AUTO_DIFF_INFO_VT_PRIMAL: UInt16 = 8u16
const MF_AUTO_DIFF_INFO_VT_EXCEPTS: UInt16 = 10u16
const MF_AUTO_DIFF_INFO_VT_INCLUDES: UInt16 = 12u16
const MF_AUTO_DIFF_INFO_VT_STAGE: UInt16 = 14u16

// ClassInfo. ModuleFormat_generated.h:2818-2824.
const MF_CLASS_INFO_VT_INHERITEDTYPES: UInt16 = 4u16
const MF_CLASS_INFO_VT_BODY: UInt16 = 6u16
const MF_CLASS_INFO_VT_ADINFO: UInt16 = 8u16
const MF_CLASS_INFO_VT_ISANNO: UInt16 = 10u16
const MF_CLASS_INFO_VT_ANNOTARGETS: UInt16 = 12u16
const MF_CLASS_INFO_VT_RUNTIMEVISIBLE: UInt16 = 14u16
const MF_CLASS_INFO_VT_ANNOTARGETS2: UInt16 = 16u16

// InterfaceInfo. ModuleFormat_generated.h:2944-2945.
const MF_INTERFACE_INFO_VT_INHERITEDTYPES: UInt16 = 4u16
const MF_INTERFACE_INFO_VT_BODY: UInt16 = 6u16

// StructInfo. ModuleFormat_generated.h:3009-3011.
const MF_STRUCT_INFO_VT_INHERITEDTYPES: UInt16 = 4u16
const MF_STRUCT_INFO_VT_BODY: UInt16 = 6u16
const MF_STRUCT_INFO_VT_ADINFO: UInt16 = 8u16

// EnumInfo. ModuleFormat_generated.h:3087-3092.
const MF_ENUM_INFO_VT_INHERITEDTYPES: UInt16 = 4u16
const MF_ENUM_INFO_VT_BODY: UInt16 = 6u16
const MF_ENUM_INFO_VT_ADINFO: UInt16 = 8u16
const MF_ENUM_INFO_VT_HASARGUMENTS: UInt16 = 10u16
const MF_ENUM_INFO_VT_NONEXHAUSTIVE: UInt16 = 12u16
const MF_ENUM_INFO_VT_ELLIPSISPOS: UInt16 = 14u16

// ExtendInfo. ModuleFormat_generated.h:3201-3202.
const MF_EXTEND_INFO_VT_INHERITEDTYPES: UInt16 = 4u16
const MF_EXTEND_INFO_VT_BODY: UInt16 = 6u16

// VarInfo. ModuleFormat_generated.h:3266-3271.
const MF_VAR_INFO_VT_ISVAR: UInt16 = 4u16
const MF_VAR_INFO_VT_ISCONST: UInt16 = 6u16
const MF_VAR_INFO_VT_ISMEMBERPARAM: UInt16 = 8u16
const MF_VAR_INFO_VT_INITIALIZER: UInt16 = 10u16
const MF_VAR_INFO_VT_VALUE_TYPE: UInt16 = 12u16
const MF_VAR_INFO_VT_VALUE: UInt16 = 14u16

// VarWithPatternInfo. ModuleFormat_generated.h:3450-3453.
const MF_VAR_WITH_PATTERN_INFO_VT_ISVAR: UInt16 = 4u16
const MF_VAR_WITH_PATTERN_INFO_VT_ISCONST: UInt16 = 6u16
const MF_VAR_WITH_PATTERN_INFO_VT_IRREFUTABLEPATTERN: UInt16 = 8u16
const MF_VAR_WITH_PATTERN_INFO_VT_INITIALIZER: UInt16 = 10u16

// FuncInfo. ModuleFormat_generated.h:3522-3528.
const MF_FUNC_INFO_VT_FUNCBODY: UInt16 = 4u16
const MF_FUNC_INFO_VT_OVERFLOWPOLICY: UInt16 = 6u16
const MF_FUNC_INFO_VT_OP: UInt16 = 8u16
const MF_FUNC_INFO_VT_ADINFO: UInt16 = 10u16
const MF_FUNC_INFO_VT_ISCONST: UInt16 = 12u16
const MF_FUNC_INFO_VT_ISINLINE: UInt16 = 14u16
const MF_FUNC_INFO_VT_ISFASTNATIVE: UInt16 = 16u16

// ParamInfo. ModuleFormat_generated.h:3625-3627.
const MF_PARAM_INFO_VT_ISNAMEDPARAM: UInt16 = 4u16
const MF_PARAM_INFO_VT_ISMEMBERPARAM: UInt16 = 6u16
const MF_PARAM_INFO_VT_DEFAULTVAL: UInt16 = 8u16

// PropInfo. ModuleFormat_generated.h:3686-3689.
const MF_PROP_INFO_VT_ISCONST: UInt16 = 4u16
const MF_PROP_INFO_VT_ISMUTABLE: UInt16 = 6u16
const MF_PROP_INFO_VT_SETTERS: UInt16 = 8u16
const MF_PROP_INFO_VT_GETTERS: UInt16 = 10u16

// BuiltInInfo. ModuleFormat_generated.h:3775.
const MF_BUILT_IN_INFO_VT_BUILTINTYPE: UInt16 = 4u16

// AliasInfo. ModuleFormat_generated.h:3816.
const MF_ALIAS_INFO_VT_ALIASEDTY: UInt16 = 4u16

// Decl. ModuleFormat_generated.h:3857-3875.
const MF_DECL_VT_KIND: UInt16 = 4u16
const MF_DECL_VT_ISTOPLEVEL: UInt16 = 6u16
const MF_DECL_VT_FULLPKGNAME: UInt16 = 8u16
const MF_DECL_VT_GENERICDECL: UInt16 = 10u16
const MF_DECL_VT_GENERIC: UInt16 = 12u16
const MF_DECL_VT_BEGIN: UInt16 = 14u16
const MF_DECL_VT_END: UInt16 = 16u16
const MF_DECL_VT_IDENTIFIER: UInt16 = 18u16
const MF_DECL_VT_IDENTIFIERPOS: UInt16 = 20u16
const MF_DECL_VT_ATTRIBUTES: UInt16 = 22u16
const MF_DECL_VT_ANNOTATIONS: UInt16 = 24u16
const MF_DECL_VT_TYPE: UInt16 = 26u16
const MF_DECL_VT_MANGLEDNAME: UInt16 = 28u16
const MF_DECL_VT_EXPORTID: UInt16 = 30u16
const MF_DECL_VT_MANGLEDBEFORESEMA: UInt16 = 32u16
const MF_DECL_VT_HASH: UInt16 = 34u16
const MF_DECL_VT_INFO_TYPE: UInt16 = 36u16
const MF_DECL_VT_INFO: UInt16 = 38u16
const MF_DECL_VT_DEPENDENCIES: UInt16 = 40u16

// Anno. ModuleFormat_generated.h:4228-4231.
const MF_ANNO_VT_KIND: UInt16 = 4u16
const MF_ANNO_VT_IDENTIFIER: UInt16 = 6u16
const MF_ANNO_VT_ARGS: UInt16 = 8u16
const MF_ANNO_VT_TARGET: UInt16 = 10u16

// AnnoArg. ModuleFormat_generated.h:4319-4320.
const MF_ANNO_ARG_VT_NAME: UInt16 = 4u16
const MF_ANNO_ARG_VT_EXPR: UInt16 = 6u16

// CallInfo. ModuleFormat_generated.h:4382-4383.
const MF_CALL_INFO_VT_HASSIDEEFFECT: UInt16 = 4u16
const MF_CALL_INFO_VT_CALLKIND: UInt16 = 6u16

// UnaryInfo. ModuleFormat_generated.h:4433.
const MF_UNARY_INFO_VT_OP: UInt16 = 4u16

// BinaryInfo. ModuleFormat_generated.h:4474.
const MF_BINARY_INFO_VT_OP: UInt16 = 4u16

// IncOrDecInfo. ModuleFormat_generated.h:4515.
const MF_INC_OR_DEC_INFO_VT_OP: UInt16 = 4u16

// LitConstInfo. ModuleFormat_generated.h:4556-4558.
const MF_LIT_CONST_INFO_VT_STRVALUE: UInt16 = 4u16
const MF_LIT_CONST_INFO_VT_CONSTKIND: UInt16 = 6u16
const MF_LIT_CONST_INFO_VT_STRKIND: UInt16 = 8u16

// ReferenceInfo. ModuleFormat_generated.h:4631-4634.
const MF_REFERENCE_INFO_VT_REFERENCE: UInt16 = 4u16
const MF_REFERENCE_INFO_VT_TARGET: UInt16 = 6u16
const MF_REFERENCE_INFO_VT_INSTTYS: UInt16 = 8u16
const MF_REFERENCE_INFO_VT_MATCHEDPARENTTY: UInt16 = 10u16

// LambdaInfo. ModuleFormat_generated.h:4721-4722.
const MF_LAMBDA_INFO_VT_FUNCBODY: UInt16 = 4u16
const MF_LAMBDA_INFO_VT_SUPPORTMOCK: UInt16 = 6u16

// AssignInfo. ModuleFormat_generated.h:4774-4775.
const MF_ASSIGN_INFO_VT_ISCOMPOUND: UInt16 = 4u16
const MF_ASSIGN_INFO_VT_OP: UInt16 = 6u16

// ArrayInfo. ModuleFormat_generated.h:4825-4826.
const MF_ARRAY_INFO_VT_INITFUNC: UInt16 = 4u16
const MF_ARRAY_INFO_VT_ISVALUEARRAY: UInt16 = 6u16

// JumpInfo. ModuleFormat_generated.h:4877.
const MF_JUMP_INFO_VT_ISBREAK: UInt16 = 4u16

// FuncArgInfo. ModuleFormat_generated.h:4918-4919.
const MF_FUNC_ARG_INFO_VT_WITHINOUT: UInt16 = 4u16
const MF_FUNC_ARG_INFO_VT_ISDEFAULTVAL: UInt16 = 6u16

// SubscriptInfo. ModuleFormat_generated.h:4969.
const MF_SUBSCRIPT_INFO_VT_ISTUPLEACCESS: UInt16 = 4u16

// MatchInfo. ModuleFormat_generated.h:5010.
const MF_MATCH_INFO_VT_MATCHMODE: UInt16 = 4u16

// BlockInfo. ModuleFormat_generated.h:5051.
const MF_BLOCK_INFO_VT_ISEXPR: UInt16 = 4u16

// TryInfo. ModuleFormat_generated.h:5102-5103.
const MF_TRY_INFO_VT_RESOURCES: UInt16 = 4u16
const MF_TRY_INFO_VT_PATTERNS: UInt16 = 6u16

// LetPatternDestructorInfo. ModuleFormat_generated.h:5169.
const MF_LET_PATTERN_DESTRUCTOR_INFO_VT_PATTERNS: UInt16 = 4u16

// ForInInfo. ModuleFormat_generated.h:5221-5222.
const MF_FOR_IN_INFO_VT_PATTERN: UInt16 = 4u16
const MF_FOR_IN_INFO_VT_FORINKIND: UInt16 = 6u16

// MatchCaseInfo. ModuleFormat_generated.h:5273.
const MF_MATCH_CASE_INFO_VT_PATTERNS: UInt16 = 4u16

// SpawnInfo. ModuleFormat_generated.h:5325.
const MF_SPAWN_INFO_VT_FUTURE: UInt16 = 4u16

// Expr. ModuleFormat_generated.h:5367-5375.
const MF_EXPR_VT_KIND: UInt16 = 4u16
const MF_EXPR_VT_BEGIN: UInt16 = 6u16
const MF_EXPR_VT_END: UInt16 = 8u16
const MF_EXPR_VT_MAPEXPR: UInt16 = 10u16
const MF_EXPR_VT_OPERANDS: UInt16 = 12u16
const MF_EXPR_VT_TYPE: UInt16 = 14u16
const MF_EXPR_VT_OVERFLOWPOLICY: UInt16 = 16u16
const MF_EXPR_VT_INFO_TYPE: UInt16 = 18u16
const MF_EXPR_VT_INFO: UInt16 = 20u16

// Pattern. ModuleFormat_generated.h:5649-5658.
const MF_PATTERN_VT_KIND: UInt16 = 4u16
const MF_PATTERN_VT_BEGIN: UInt16 = 6u16
const MF_PATTERN_VT_END: UInt16 = 8u16
const MF_PATTERN_VT_PATTERNS: UInt16 = 10u16
const MF_PATTERN_VT_TYPES: UInt16 = 12u16
const MF_PATTERN_VT_EXPRS: UInt16 = 14u16
const MF_PATTERN_VT_VALUES_TYPE: UInt16 = 16u16
const MF_PATTERN_VT_VALUES: UInt16 = 18u16
const MF_PATTERN_VT_MATCHBEFORERUNTIME: UInt16 = 20u16
const MF_PATTERN_VT_NEEDRUNTIMETYPECHECK: UInt16 = 22u16

// FuncTyInfo. ModuleFormat_generated.h:5818-5820.
const MF_FUNC_TY_INFO_VT_RETTYPE: UInt16 = 4u16
const MF_FUNC_TY_INFO_VT_ISC: UInt16 = 6u16
const MF_FUNC_TY_INFO_VT_HASVARIABLELENARG: UInt16 = 8u16

// CompositeTyInfo. ModuleFormat_generated.h:5879-5880.
const MF_COMPOSITE_TY_INFO_VT_DECLPTR: UInt16 = 4u16
const MF_COMPOSITE_TY_INFO_VT_ISTHISTY: UInt16 = 6u16

// GenericTyInfo. ModuleFormat_generated.h:5931-5932.
const MF_GENERIC_TY_INFO_VT_DECLPTR: UInt16 = 4u16
const MF_GENERIC_TY_INFO_VT_UPPERBOUNDS: UInt16 = 6u16

// ArrayTyInfo. ModuleFormat_generated.h:5995.
const MF_ARRAY_TY_INFO_VT_DIMSORSIZE: UInt16 = 4u16

// SemaTy. ModuleFormat_generated.h:6036-6039.
const MF_SEMA_TY_VT_KIND: UInt16 = 4u16
const MF_SEMA_TY_VT_TYPEARGS: UInt16 = 6u16
const MF_SEMA_TY_VT_INFO_TYPE: UInt16 = 8u16
const MF_SEMA_TY_VT_INFO: UInt16 = 10u16

// ImportSpec. ModuleFormat_generated.h:6153-6161.
const MF_IMPORT_SPEC_VT_BEGIN: UInt16 = 4u16
const MF_IMPORT_SPEC_VT_END: UInt16 = 6u16
const MF_IMPORT_SPEC_VT_PREFIXPATHS: UInt16 = 8u16
const MF_IMPORT_SPEC_VT_IDENTIFIER: UInt16 = 10u16
const MF_IMPORT_SPEC_VT_ASIDENTIFIER: UInt16 = 12u16
const MF_IMPORT_SPEC_VT_REEXPORT: UInt16 = 14u16
const MF_IMPORT_SPEC_VT_ISDECL: UInt16 = 16u16
const MF_IMPORT_SPEC_VT_HASDOUBLECOLON: UInt16 = 18u16
const MF_IMPORT_SPEC_VT_WITHIMPLICITEXPORT: UInt16 = 20u16

// Imports. ModuleFormat_generated.h:6305.
const MF_IMPORTS_VT_IMPORTSPECS: UInt16 = 4u16

// FeatureId. ModuleFormat_generated.h:6357.
const MF_FEATURE_ID_VT_IDENTIFIERS: UInt16 = 4u16

// FeaturesSet. ModuleFormat_generated.h:6409.
const MF_FEATURES_SET_VT_FEATURES: UInt16 = 4u16

// FeaturesDirective. ModuleFormat_generated.h:6461.
const MF_FEATURES_DIRECTIVE_VT_FEATURESSET: UInt16 = 4u16

// FileInfo. ModuleFormat_generated.h:6503-6506.
const MF_FILE_INFO_VT_FILEID: UInt16 = 4u16
const MF_FILE_INFO_VT_BEGIN: UInt16 = 6u16
const MF_FILE_INFO_VT_END: UInt16 = 8u16
const MF_FILE_INFO_VT_FEATURE: UInt16 = 10u16

// CompilationOptions. ModuleFormat_generated.h:6575-6576.
const MF_COMPILATION_OPTIONS_VT_OPTIMIZATION_LEVEL: UInt16 = 4u16
const MF_COMPILATION_OPTIONS_VT_DEBUG: UInt16 = 6u16

// Package. ModuleFormat_generated.h:6626-6642.
const MF_PACKAGE_VT_VERSION: UInt16 = 4u16
const MF_PACKAGE_VT_CJOVERSION: UInt16 = 6u16
const MF_PACKAGE_VT_FULLPKGNAME: UInt16 = 8u16
const MF_PACKAGE_VT_PKGDEPINFO: UInt16 = 10u16
const MF_PACKAGE_VT_IMPORTS: UInt16 = 12u16
const MF_PACKAGE_VT_ALLFILES: UInt16 = 14u16
const MF_PACKAGE_VT_ALLFILEIMPORTS: UInt16 = 16u16
const MF_PACKAGE_VT_ALLTYPES: UInt16 = 18u16
const MF_PACKAGE_VT_ALLDECLS: UInt16 = 20u16
const MF_PACKAGE_VT_ALLEXPRS: UInt16 = 22u16
const MF_PACKAGE_VT_ALLVALUES: UInt16 = 24u16
const MF_PACKAGE_VT_KIND: UInt16 = 26u16
const MF_PACKAGE_VT_ACCESS: UInt16 = 28u16
const MF_PACKAGE_VT_MODULENAME: UInt16 = 30u16
const MF_PACKAGE_VT_ALLFILEINFO: UInt16 = 32u16
const MF_PACKAGE_VT_ALLDEPENDENTSTDPKGS: UInt16 = 34u16
const MF_PACKAGE_VT_OPTIONS: UInt16 = 36u16
