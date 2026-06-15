package cangjie_compiler::ast

public enum ASTKind {
    | ANNOTATION
    | MODIFIER
    | DECL
    | MAIN_DECL
    | FUNC_DECL
    | MACRO_DECL
    | CLASS_LIKE_DECL
    | CLASS_DECL
    | INTERFACE_DECL
    | EXTEND_DECL
    | ENUM_DECL
    | STRUCT_DECL
    | TYPE_ALIAS_DECL
    | PRIMARY_CTOR_DECL
    | BUILTIN_DECL
    | VAR_DECL
    | PROP_DECL
    | MACRO_EXPAND_PARAM
    | FUNC_PARAM
    | VAR_WITH_PATTERN_DECL
    | GENERIC_PARAM_DECL
    | PACKAGE_DECL
    | MACRO_EXPAND_DECL
    | INVALID_DECL
    | PATTERN
    | VAR_PATTERN
    | CONST_PATTERN
    | TUPLE_PATTERN
    | ENUM_PATTERN
    | VAR_OR_ENUM_PATTERN
    | TYPE_PATTERN
    | EXCEPT_TYPE_PATTERN
    | COMMAND_TYPE_PATTERN
    | WILDCARD_PATTERN
    | INVALID_PATTERN
    | TYPE
    | REF_TYPE
    | QUALIFIED_TYPE
    | OPTION_TYPE
    | CONSTANT_TYPE
    | VARRAY_TYPE
    | PRIMITIVE_TYPE
    | PAREN_TYPE
    | FUNC_TYPE
    | TUPLE_TYPE
    | THIS_TYPE
    | INVALID_TYPE
    | EXPR
    | WILDCARD_EXPR
    | CALL_EXPR
    | PAREN_EXPR
    | MEMBER_ACCESS
    | REF_EXPR
    | OPTIONAL_EXPR
    | OPTIONAL_CHAIN_EXPR
    | PRIMITIVE_TYPE_EXPR
    | RETURN_EXPR
    | LIT_CONST_EXPR
    | INTERPOLATION_EXPR
    | STR_INTERPOLATION_EXPR
    | ASSIGN_EXPR
    | UNARY_EXPR
    | BINARY_EXPR
    | INC_OR_DEC_EXPR
    | SUBSCRIPT_EXPR
    | IS_EXPR
    | AS_EXPR
    | RANGE_EXPR
    | ARRAY_LIT
    | ARRAY_EXPR
    | POINTER_EXPR
    | TUPLE_LIT
    | MATCH_EXPR
    | BLOCK
    | IF_EXPR
    | LET_PATTERN_DESTRUCTOR
    | TOKEN_PART
    | QUOTE_EXPR
    | TRY_EXPR
    | WHILE_EXPR
    | JUMP_EXPR
    | LAMBDA_EXPR
    | TRAIL_CLOSURE_EXPR
    | FOR_IN_EXPR
    | DO_WHILE_EXPR
    | TYPE_CONV_EXPR
    | THROW_EXPR
    | PERFORM_EXPR
    | RESUME_EXPR
    | SPAWN_EXPR
    | SYNCHRONIZED_EXPR
    | MACRO_EXPAND_EXPR
    | IF_AVAILABLE_EXPR
    | INVALID_EXPR
    | GENERIC
    | GENERIC_CONSTRAINT
    | MATCH_CASE
    | MATCH_CASE_OTHER
    | FUNC_ARG
    | FUNC_PARAM_LIST
    | FUNC_BODY
    | STRUCT_BODY
    | CLASS_BODY
    | INTERFACE_BODY
    | DUMMY_BODY
    | IMPORT_CONTENT
    | IMPORT_SPEC
    | PACKAGE_SPEC
    | PACKAGE
    | FEATURE_ID
    | FEATURES_SET
    | FEATURES_DIRECTIVE
    | FILE
    | NODE
}

public func ASTKindIndex(kind: ASTKind): Int64 {
    return match (kind) {
        case ASTKind.ANNOTATION => 0
        case ASTKind.MODIFIER => 1
        case ASTKind.DECL => 2
        case ASTKind.MAIN_DECL => 3
        case ASTKind.FUNC_DECL => 4
        case ASTKind.MACRO_DECL => 5
        case ASTKind.CLASS_LIKE_DECL => 6
        case ASTKind.CLASS_DECL => 7
        case ASTKind.INTERFACE_DECL => 8
        case ASTKind.EXTEND_DECL => 9
        case ASTKind.ENUM_DECL => 10
        case ASTKind.STRUCT_DECL => 11
        case ASTKind.TYPE_ALIAS_DECL => 12
        case ASTKind.PRIMARY_CTOR_DECL => 13
        case ASTKind.BUILTIN_DECL => 14
        case ASTKind.VAR_DECL => 15
        case ASTKind.PROP_DECL => 16
        case ASTKind.MACRO_EXPAND_PARAM => 17
        case ASTKind.FUNC_PARAM => 18
        case ASTKind.VAR_WITH_PATTERN_DECL => 19
        case ASTKind.GENERIC_PARAM_DECL => 20
        case ASTKind.PACKAGE_DECL => 21
        case ASTKind.MACRO_EXPAND_DECL => 22
        case ASTKind.INVALID_DECL => 23
        case ASTKind.PATTERN => 24
        case ASTKind.VAR_PATTERN => 25
        case ASTKind.CONST_PATTERN => 26
        case ASTKind.TUPLE_PATTERN => 27
        case ASTKind.ENUM_PATTERN => 28
        case ASTKind.VAR_OR_ENUM_PATTERN => 29
        case ASTKind.TYPE_PATTERN => 30
        case ASTKind.EXCEPT_TYPE_PATTERN => 31
        case ASTKind.COMMAND_TYPE_PATTERN => 32
        case ASTKind.WILDCARD_PATTERN => 33
        case ASTKind.INVALID_PATTERN => 34
        case ASTKind.TYPE => 35
        case ASTKind.REF_TYPE => 36
        case ASTKind.QUALIFIED_TYPE => 37
        case ASTKind.OPTION_TYPE => 38
        case ASTKind.CONSTANT_TYPE => 39
        case ASTKind.VARRAY_TYPE => 40
        case ASTKind.PRIMITIVE_TYPE => 41
        case ASTKind.PAREN_TYPE => 42
        case ASTKind.FUNC_TYPE => 43
        case ASTKind.TUPLE_TYPE => 44
        case ASTKind.THIS_TYPE => 45
        case ASTKind.INVALID_TYPE => 46
        case ASTKind.EXPR => 47
        case ASTKind.WILDCARD_EXPR => 48
        case ASTKind.CALL_EXPR => 49
        case ASTKind.PAREN_EXPR => 50
        case ASTKind.MEMBER_ACCESS => 51
        case ASTKind.REF_EXPR => 52
        case ASTKind.OPTIONAL_EXPR => 53
        case ASTKind.OPTIONAL_CHAIN_EXPR => 54
        case ASTKind.PRIMITIVE_TYPE_EXPR => 55
        case ASTKind.RETURN_EXPR => 56
        case ASTKind.LIT_CONST_EXPR => 57
        case ASTKind.INTERPOLATION_EXPR => 58
        case ASTKind.STR_INTERPOLATION_EXPR => 59
        case ASTKind.ASSIGN_EXPR => 60
        case ASTKind.UNARY_EXPR => 61
        case ASTKind.BINARY_EXPR => 62
        case ASTKind.INC_OR_DEC_EXPR => 63
        case ASTKind.SUBSCRIPT_EXPR => 64
        case ASTKind.IS_EXPR => 65
        case ASTKind.AS_EXPR => 66
        case ASTKind.RANGE_EXPR => 67
        case ASTKind.ARRAY_LIT => 68
        case ASTKind.ARRAY_EXPR => 69
        case ASTKind.POINTER_EXPR => 70
        case ASTKind.TUPLE_LIT => 71
        case ASTKind.MATCH_EXPR => 72
        case ASTKind.BLOCK => 73
        case ASTKind.IF_EXPR => 74
        case ASTKind.LET_PATTERN_DESTRUCTOR => 75
        case ASTKind.TOKEN_PART => 76
        case ASTKind.QUOTE_EXPR => 77
        case ASTKind.TRY_EXPR => 78
        case ASTKind.WHILE_EXPR => 79
        case ASTKind.JUMP_EXPR => 80
        case ASTKind.LAMBDA_EXPR => 81
        case ASTKind.TRAIL_CLOSURE_EXPR => 82
        case ASTKind.FOR_IN_EXPR => 83
        case ASTKind.DO_WHILE_EXPR => 84
        case ASTKind.TYPE_CONV_EXPR => 85
        case ASTKind.THROW_EXPR => 86
        case ASTKind.PERFORM_EXPR => 87
        case ASTKind.RESUME_EXPR => 88
        case ASTKind.SPAWN_EXPR => 89
        case ASTKind.SYNCHRONIZED_EXPR => 90
        case ASTKind.MACRO_EXPAND_EXPR => 91
        case ASTKind.IF_AVAILABLE_EXPR => 92
        case ASTKind.INVALID_EXPR => 93
        case ASTKind.GENERIC => 94
        case ASTKind.GENERIC_CONSTRAINT => 95
        case ASTKind.MATCH_CASE => 96
        case ASTKind.MATCH_CASE_OTHER => 97
        case ASTKind.FUNC_ARG => 98
        case ASTKind.FUNC_PARAM_LIST => 99
        case ASTKind.FUNC_BODY => 100
        case ASTKind.STRUCT_BODY => 101
        case ASTKind.CLASS_BODY => 102
        case ASTKind.INTERFACE_BODY => 103
        case ASTKind.DUMMY_BODY => 104
        case ASTKind.IMPORT_CONTENT => 105
        case ASTKind.IMPORT_SPEC => 106
        case ASTKind.PACKAGE_SPEC => 107
        case ASTKind.PACKAGE => 108
        case ASTKind.FEATURE_ID => 109
        case ASTKind.FEATURES_SET => 110
        case ASTKind.FEATURES_DIRECTIVE => 111
        case ASTKind.FILE => 112
        case ASTKind.NODE => 113
    }
}

extend ASTKind <: Equatable<ASTKind> {
    public operator func ==(right: ASTKind): Bool {
        return ASTKindIndex(this) == ASTKindIndex(right)
    }

    public operator func !=(right: ASTKind): Bool {
        return !(this == right)
    }
}

public func ASTKindName(kind: ASTKind): String {
    return match (kind) {
        case ASTKind.ANNOTATION => "annotation"
        case ASTKind.MODIFIER => "modifier"
        case ASTKind.DECL => "*decl"
        case ASTKind.MAIN_DECL => "main_decl"
        case ASTKind.FUNC_DECL => "func_decl"
        case ASTKind.MACRO_DECL => "macro_decl"
        case ASTKind.CLASS_LIKE_DECL => "class_like_decl"
        case ASTKind.CLASS_DECL => "class_decl"
        case ASTKind.INTERFACE_DECL => "interface_decl"
        case ASTKind.EXTEND_DECL => "extend_decl"
        case ASTKind.ENUM_DECL => "enum_decl"
        case ASTKind.STRUCT_DECL => "struct_decl"
        case ASTKind.TYPE_ALIAS_DECL => "type_alias_decl"
        case ASTKind.PRIMARY_CTOR_DECL => "primary_ctor_decl"
        case ASTKind.BUILTIN_DECL => "builtin_decl"
        case ASTKind.VAR_DECL => "var_decl"
        case ASTKind.PROP_DECL => "prop_decl"
        case ASTKind.MACRO_EXPAND_PARAM => "macro_expand_param"
        case ASTKind.FUNC_PARAM => "func_param"
        case ASTKind.VAR_WITH_PATTERN_DECL => "var_with_pattern_decl"
        case ASTKind.GENERIC_PARAM_DECL => "generic_param_decl"
        case ASTKind.PACKAGE_DECL => "package_decl"
        case ASTKind.MACRO_EXPAND_DECL => "macro_expand_decl"
        case ASTKind.INVALID_DECL => "invalid_decl"
        case ASTKind.PATTERN => "*pattern"
        case ASTKind.VAR_PATTERN => "var_pattern"
        case ASTKind.CONST_PATTERN => "const_pattern"
        case ASTKind.TUPLE_PATTERN => "tuple_pattern"
        case ASTKind.ENUM_PATTERN => "enum_pattern"
        case ASTKind.VAR_OR_ENUM_PATTERN => "var_or_enum_pattern"
        case ASTKind.TYPE_PATTERN => "type_pattern"
        case ASTKind.EXCEPT_TYPE_PATTERN => "except_type_pattern"
        case ASTKind.COMMAND_TYPE_PATTERN => "effect_type_pattern"
        case ASTKind.WILDCARD_PATTERN => "wildcard_pattern"
        case ASTKind.INVALID_PATTERN => "invalid_pattern"
        case ASTKind.TYPE => "*type"
        case ASTKind.REF_TYPE => "ref_type"
        case ASTKind.QUALIFIED_TYPE => "qualified_type"
        case ASTKind.OPTION_TYPE => "option_type"
        case ASTKind.CONSTANT_TYPE => "constant_type"
        case ASTKind.VARRAY_TYPE => "varray_type"
        case ASTKind.PRIMITIVE_TYPE => "primitive_type"
        case ASTKind.PAREN_TYPE => "paren_type"
        case ASTKind.FUNC_TYPE => "func_type"
        case ASTKind.TUPLE_TYPE => "tuple_type"
        case ASTKind.THIS_TYPE => "this_type"
        case ASTKind.INVALID_TYPE => "invalid_type"
        case ASTKind.EXPR => "*expr"
        case ASTKind.WILDCARD_EXPR => "wildcard_expr"
        case ASTKind.CALL_EXPR => "call_expr"
        case ASTKind.PAREN_EXPR => "paren_expr"
        case ASTKind.MEMBER_ACCESS => "member_access_expr"
        case ASTKind.REF_EXPR => "ref_expr"
        case ASTKind.OPTIONAL_EXPR => "optional_expr"
        case ASTKind.OPTIONAL_CHAIN_EXPR => "optional_chain_expr"
        case ASTKind.PRIMITIVE_TYPE_EXPR => "primitive_type_expr"
        case ASTKind.RETURN_EXPR => "return_expr"
        case ASTKind.LIT_CONST_EXPR => "lit_const_expr"
        case ASTKind.INTERPOLATION_EXPR => "interpolation_expr"
        case ASTKind.STR_INTERPOLATION_EXPR => "str_interpolation_expr"
        case ASTKind.ASSIGN_EXPR => "assign_expr"
        case ASTKind.UNARY_EXPR => "unary_expr"
        case ASTKind.BINARY_EXPR => "binary_expr"
        case ASTKind.INC_OR_DEC_EXPR => "inc_or_dec_expr"
        case ASTKind.SUBSCRIPT_EXPR => "subscript_expr"
        case ASTKind.IS_EXPR => "is_expr"
        case ASTKind.AS_EXPR => "as_expr"
        case ASTKind.RANGE_EXPR => "range_expr"
        case ASTKind.ARRAY_LIT => "array_lit_expr"
        case ASTKind.ARRAY_EXPR => "array_expr"
        case ASTKind.POINTER_EXPR => "pointer_expr"
        case ASTKind.TUPLE_LIT => "tuple_lit_expr"
        case ASTKind.MATCH_EXPR => "match_expr"
        case ASTKind.BLOCK => "block"
        case ASTKind.IF_EXPR => "if_expr"
        case ASTKind.LET_PATTERN_DESTRUCTOR => "let_pattern_destructor"
        case ASTKind.TOKEN_PART => "token_part"
        case ASTKind.QUOTE_EXPR => "quote_expr"
        case ASTKind.TRY_EXPR => "try_expr"
        case ASTKind.WHILE_EXPR => "while_expr"
        case ASTKind.JUMP_EXPR => "jump_expr"
        case ASTKind.LAMBDA_EXPR => "lambda_expr"
        case ASTKind.TRAIL_CLOSURE_EXPR => "trailing_closure_expr"
        case ASTKind.FOR_IN_EXPR => "for_in_expr"
        case ASTKind.DO_WHILE_EXPR => "do_while_expr"
        case ASTKind.TYPE_CONV_EXPR => "type_conv_expr"
        case ASTKind.THROW_EXPR => "throw_expr"
        case ASTKind.PERFORM_EXPR => "perform_expr"
        case ASTKind.RESUME_EXPR => "resume_expr"
        case ASTKind.SPAWN_EXPR => "spawn_expr"
        case ASTKind.SYNCHRONIZED_EXPR => "synchronized_expr"
        case ASTKind.MACRO_EXPAND_EXPR => "macro_expand_expr"
        case ASTKind.IF_AVAILABLE_EXPR => "if_available_expr"
        case ASTKind.INVALID_EXPR => "invalid_expr"
        case ASTKind.GENERIC => "generic"
        case ASTKind.GENERIC_CONSTRAINT => "generic_constraint"
        case ASTKind.MATCH_CASE => "match_case"
        case ASTKind.MATCH_CASE_OTHER => "match_case_other"
        case ASTKind.FUNC_ARG => "func_arg"
        case ASTKind.FUNC_PARAM_LIST => "func_param_list"
        case ASTKind.FUNC_BODY => "func_body"
        case ASTKind.STRUCT_BODY => "struct_body"
        case ASTKind.CLASS_BODY => "class_body"
        case ASTKind.INTERFACE_BODY => "interface_body"
        case ASTKind.DUMMY_BODY => "dummy_body"
        case ASTKind.IMPORT_CONTENT => "import_content"
        case ASTKind.IMPORT_SPEC => "import_spec"
        case ASTKind.PACKAGE_SPEC => "package_spec"
        case ASTKind.PACKAGE => "package"
        case ASTKind.FEATURE_ID => "feature_id"
        case ASTKind.FEATURES_SET => "features_set"
        case ASTKind.FEATURES_DIRECTIVE => "features_directive"
        case ASTKind.FILE => "file"
        case ASTKind.NODE => "node"
    }
}
