package cangjie_compiler::basic

public let DEFAULT_DIAG_NUM: Int64 = 8

public enum WarnGroup {
    | UNUSED
    | UNUSED_MAIN
    | DRIVER_ARG
    | DEPRECATED
    | UNSUPPORT_COMPILE_SOURCE
    | PACKAGE_IMPORT
    | PARSER
    | SEMANTICS
    | INTERPRETER
    | APILEVEL_CHECK
    | UNGROUPED
    | NONE
}

public enum DiagFormat {
    | JSON
    | NO_COLOR
    | DEFAULT
}

public enum DiagSeverity {
    | DS_ERROR
    | DS_WARNING
    | DS_NOTE
    | DS_HINT
}

public enum DiagCategory {
    | LEX
    | PARSE
    | PARSE_QUERY
    | CONDITIONAL_COMPILATION
    | IMPORT_PACKAGE
    | MODULE
    | MACRO_EXPAND
    | SEMA
    | CHIR
    | OTHER
}

public enum DiagKind {
    | chir_diag_begin
    | chir_var_might_circular_dependency
    | chir_file_might_circular_dependency
    | chir_used_before_initialization
    | chir_sancov_illegal_usage_of_pc_table
    | chir_sancov_illegal_usage_of_level
    | interp_cannot_interp_node
    | interp_malloc_failed
    | interp_unsupported
    | interp_unsupported_type
    | interp_cannot_convert_array2ffi
    | interp_cannot_load_incremental_bchir
    | const_eval_exception
    | const_eval_load_dep
    | const_eval_unsupported
    | chir_diag_end
    | macro_expand_diag_begin
    | macro_undeclared_identifier
    | macro_expect_attributed_macro
    | macro_evaluate_failed
    | macro_expect_macro_definition
    | macro_undefined_pkg_name
    | macro_expect_plain_macro
    | macro_expand_invalid_attr_tokens
    | macro_expand_invalid_input_tokens
    | macro_expand_invalid_escape
    | macro_unexpect_def_and_call_in_same_pkg
    | macro_init_interpter_faild
    | macro_expand_invalid_node_replace
    | macro_ambiguous_match
    | macro_using_error
    | macro_expand_failed
    | not_find_macro_library
    | can_not_open_macro_library
    | macro_cannot_find_method
    | macro_expect_decl_not_enum_constructor
    | macro_expect_declaration
    | macro_expect_enum_constructor
    | macro_expect_one_enum_constructor
    | macro_expect_one_expr_or_pattern
    | macro_expect_one_expr
    | macro_unexpect_no_expr
    | macro_call_map_to_empty_value_token
    | macro_call_map_info_failed
    | macro_call_save_file_failed
    | macro_expand_code_should_not_have_macrocall
    | macro_expand_cannot_find_dependency
    | macro_expand_exception_occurred
    | macro_expand_failed_init_top_level
    | macro_named_parameter_after_unnamed
    | macro_unexpected_empty_parameter
    | macro_assert_parent_context_failed
    | macro_build_in_unexpect_params
    | macro_build_in_unexpect_params_attrs
    | macro_is_deprecated_error
    | macro_is_deprecated_warning
    | macro_expand_atexcl
    | macro_expand_diag_end
    | sema_diag_begin
    | sema_diag_report_error_message
    | sema_diag_report_note_message
    | sema_incompatible_expo_target_type
    | sema_ambiguous_expo_right_operand_type
    | sema_not_a_type
    | sema_incompatible_func_body_and_return_type
    | sema_type_must_toplevel
    | sema_undeclared_type_name
    | sema_undeclared_identifier
    | sema_redefinition
    | sema_expand_macro_redefinition
    | sema_previous_decl
    | sema_used_before_initialization
    | sema_global_var_used_before_initialization
    | sema_duplicated_item_in_enum
    | sema_invalid_constructor_in_enum
    | sema_multiple_constructor_in_enum
    | sema_enum_constructor_type_not_match
    | sema_invalid_enum_member_access
    | sema_invalid_type_param_of_enum_member_access
    | sema_invalid_loop_control
    | sema_cannot_currying
    | sema_value_type_recursive
    | sema_inheritance_cycle
    | sema_typealias_cycle
    | sema_typealias_external_refer_internal
    | sema_invalid_coalescing
    | sema_div_zero
    | sema_mod_zero
    | sema_arithmetical_op_overflow
    | sema_shift_count_overflow
    | sema_negative_shift_count
    | sema_func_capture_var_cannot_assign
    | sema_func_capture_var_cannot_return
    | sema_func_capture_var_cannot_param
    | sema_func_capture_var_cannot_expr
    | sema_invalid_unary_expr
    | sema_invalid_unary_expr_note
    | sema_fail_flow_expr_operand_has_named_param
    | sema_operator_overload_invalid_num_parameter
    | sema_operator_overload_built_in_unary_operator
    | sema_operator_overload_built_in_binary_operator
    | sema_operator_overload_can_not_has_default_param
    | sema_empty_arrayLit_type_undefined
    | sema_inconsistency_elemType
    | sema_tuple_pattern_not_match
    | sema_unsupport_operator
    | sema_array_size_type_error
    | sema_array_expression_param_type_error
    | sema_array_expression_type_error
    | sema_array_single_element_type_error
    | sema_array_element_type_error
    | sema_array_too_much_argument
    | sema_array_first_arg_cannot_be_named
    | sema_array_second_arg_cannot_be_named
    | sema_array_second_wrong_named_arg
    | sema_pointer_too_much_argument
    | sema_cfunc_too_many_arguments
    | sema_pointer_single_element_type_error
    | sema_pointer_unknow_generic_type
    | sema_builtin_invalid_index
    | sema_builtin_index_in_bound
    | sema_tuple_element_cmp_not_bool
    | sema_tuple_cmp_not_supported
    | sema_step_non_zero_range
    | sema_inconsistency_range_elemType
    | sema_range_step_not_int64
    | sema_no_match_function_declaration_for_call
    | sema_no_match_function_declaration_for_ref
    | sema_no_match_constructor
    | sema_ambiguous_arg_type
    | sema_ambiguous_match
    | sema_ambiguous_constructor_match
    | sema_ambiguous_func_ref
    | sema_mismatched_type_for_pattern_in_vardecl
    | sema_parameters_and_arguments_mismatch
    | sema_cstruct_cannot_autobox
    | sema_unit_cannot_as_cfunc_arg
    | sema_overload_conflicts
    | sema_no_match_operator_function_call
    | sema_pattern_can_not_be_assigned
    | sema_unknown_named_argument
    | sema_multiple_named_argument
    | sema_invalid_named_arguments
    | sema_unsupport_named_argument
    | sema_pattern_literal_expected
    | sema_pattern_not_match
    | sema_not_overload_in_match
    | sema_type_incompatible
    | sema_subscript_set_not_supported
    | sema_subscript_get_set_not_supported
    | sema_tuple_pattern_with_correct_size_expected
    | sema_enum_pattern_param_size_error
    | sema_match_case_must_have_default
    | sema_match_case_has_no_type
    | sema_package_internal_decl_obtain_illegal
    | sema_package_name_conflict
    | sema_invalid_access_control
    | sema_invalid_access_function
    | sema_invalid_file_hash
    | sema_func_no_override_or_redefine_modifier
    | sema_unexpected_param_for_entry
    | sema_unexpected_return_type_for_entry
    | sema_redefinition_entry
    | sema_missing_entry
    | sema_numeric_convert_must_be_numeric
    | sema_cfunc_ctor_must_be_cpointer
    | sema_ref_not_be_type
    | sema_expr_in_forin_must_has_iterator
    | sema_forin_pattern_must_be_irrefutable
    | sema_wrong_forin_guard
    | sema_generics_type_variable_not_defined
    | sema_generic_type_argument_not_match_constraint
    | sema_which_constraint_not_match
    | sema_generic_type_without_type_argument
    | sema_non_generic_function_with_type_argument
    | sema_throw_expr_with_wrong_type
    | sema_except_catch_type_error
    | sema_no_core_object
    | sema_invalid_intrinsic_decl
    | sema_generic_infinite_instantiation
    | sema_forbid_generic_nonstatic_method
    | sema_forbid_generic_constructor
    | sema_forbid_generic_finalizer
    | sema_import_not_in_current_module
    | sema_flow_expressions_use_this_or_super
    | sema_symbol_not_collected
    | sema_cannot_convert_literal
    | sema_cannot_have_parameter
    | sema_annotation_error_arg_num
    | sema_unexpected_wrapper
    | sema_native_var_error
    | sema_illegal_use_of_annotation
    | sema_cffi_cannot_have_type_param
    | sema_unsafe_function_invoke_failed
    | sema_func_capture_var_not_ctype
    | sema_cfunc_cannot_capture_var
    | sema_cfunc_cannot_capture_this
    | sema_illegal_ctype_generic_argument
    | sema_illegal_cpointer_generic_type
    | sema_invalid_cfunc_arg_type
    | sema_cfunc_type
    | sema_invalid_tuple_field_ctype
    | sema_enum_pattern_func_cty_error
    | sema_enum_pattern_func_param_cty_error
    | sema_illegal_ctype_member
    | sema_illegal_member_of_cstruct
    | sema_cfunc_cannot_have_unit_args
    | sema_cstruct_cannot_have_unit_fields
    | sema_cfunc_cannot_have_named_args
    | sema_cfunc_var_cannot_have_var_param
    | sema_inheritance_non_ref_type
    | sema_class_uninitialized_field
    | sema_this_or_super_not_allowed_to_initialize_non_static_member
    | sema_this_or_super_not_allowed_to_initialize_static_member
    | sema_illegal_usage_of_super_member
    | sema_illegal_usage_of_member
    | sema_invalid_assignment_to_this_expr
    | sema_invalid_override_member_in_class
    | sema_invalid_override_or_redefine_member_in_interface
    | sema_illegal_this_in_interface
    | sema_use_super_in_interface
    | sema_super_use_error_inside_non_class
    | sema_assignment_of_member_variable_cannot_use_this_or_super
    | sema_illegal_super_alone
    | sema_abstract_class_can_not_be_instantiated
    | sema_interface_can_not_be_instantiated
    | sema_non_inheritable_super_class
    | sema_superclass_must_be_placed_at_first
    | sema_illegal_multi_inheritance
    | sema_invalid_this_call_outside_ctor
    | sema_privated_abstract_func_in_class
    | sema_invalid_string_implementation
    | sema_invalid_tokens_implementation
    | sema_multiple_primary_constructors
    | sema_interface_is_not_inheritable
    | sema_interface_is_not_implementable
    | sema_inherit_duplicate_interface
    | sema_return_unit
    | sema_illegal_place_of_calling_this_or_super
    | sema_illegal_place_of_calling_this_primary_constructor
    | sema_this_super_use_error_outside_class
    | sema_missing_func_body
    | sema_interface_member_must_be_implemented
    | sema_interface_member_must_be_implemented_in_struct
    | sema_member_variable_can_not_shadow
    | sema_missing_overridden_func
    | sema_missing_redefined_func
    | sema_static_and_non_static_member_cannot_have_same_name
    | sema_generic_member_type_argument_different
    | sema_c_type_cannot_implement_interface
    | sema_illegal_access_non_static_member
    | sema_illegal_access_interface_field
    | sema_illegal_access_inner_classlike
    | sema_cannot_modify_var
    | sema_illegal_capture_this
    | sema_object_cannot_access_static_member
    | sema_abstract_method_cannot_be_accessed_directly
    | sema_return_type_invariance
    | sema_static_members_cannot_call_members
    | sema_class_inherit_non_class_nor_interface
    | sema_type_implement_non_interface
    | sema_interface_inherit_non_interface
    | sema_generic_in_operator_overload
    | sema_illegal_this_outside_struct_constructor
    | sema_static_function_cannot_access_non_static_member
    | sema_static_variable_cannot_access_non_static_member
    | sema_static_lambdaExpr_cannot_access_non_static
    | sema_redef_modify_static_func
    | sema_illegal_member_used_in_open_constructor
    | sema_finalizer_forbidden_in_class
    | sema_generic_no_member_match_in_upper_bounds
    | sema_generic_ambiguous_method_match_in_upper_bounds
    | sema_generic_no_method_match_in_upper_bounds
    | sema_cannot_instantiated_by_incomplete_type
    | sema_invalid_field_expose_access
    | sema_capture_this_or_instance_field_in_func
    | sema_use_this_as_an_expression_in_func
    | sema_incompatible_mut_modifier_between_struct_and_interface
    | sema_immutable_function_cannot_access_mutable_function
    | sema_invalid_position_of_this_type
    | sema_property_override_implement_type_diff
    | typealias_unused_type_parameters
    | sema_capture_has_shadow_variable
    | sema_useless_exception_type
    | sema_ignore_open
    | sema_found_candidate_decl
    | sema_found_possible_candidate_decl
    | sema_diag_end
}

public enum DiagKindRefactor {
    | chir_diag_begin
    | chir_used_before_initialization
    | chir_illegal_usage_of_member
    | chir_cannot_assign_initialized_let_variable
    | chir_class_uninitialized_field
    | chir_illegal_usage_of_super_member
    | chir_arithmetic_operator_overflow
    | chir_idx_out_of_bounds
    | chir_divisor_is_zero
    | chir_shift_length_overflow
    | chir_typecast_overflow
    | chir_step_non_zero_range
    | chir_dce_unreachable_statement
    | chir_dce_unreachable_function
    | chir_dce_unreachable_return
    | chir_dce_unreachable_if
    | chir_dce_unreachable
    | chir_dce_unreachable_expression_hint
    | chir_dce_unreachable_block_in_expression
    | chir_dce_unreachable_block
    | chir_dce_unused_expression
    | chir_dce_unused_function
    | chir_dce_unused_function_main
    | chir_dce_unreachable_expression
    | chir_dce_unused_variable
    | chir_dce_unused_operator
    | chir_unreachable_pattern
    | chir_eval_support
    | chir_annotation_not_applicable
    | chir_diag_end
    | conditional_compilation_diag_begin
    | conditional_compilation_not_support_op
    | conditional_compilation_not_support_this_condition
    | conditional_compilation_not_support_builtin_value
    | conditional_compilation_not_support_cjc_version_format
    | conditional_compilation_invalid_condition_expr
    | conditional_compilation_not_have_condition_expr
    | conditional_compilation_invalid_condition_value
    | conditional_compilation_just_support_block
    | conditional_compilation_unexpected_after_macro
    | conditional_compilation_diag_end
    | driver_diag_begin
    | no_such_file_or_directory
    | no_such_directory
    | not_a_directory
    | not_a_file
    | permission_denied
    | invalid_path
    | no_such_file_or_directory_of_macro_obj
    | input_file_overwritten_by_generated_output
    | bc_file_open_failed
    | bc_parse_failed
    | bc_invalid_package_name
    | driver_warning_no_such_file
    | driver_warning_no_such_file_or_directory
    | driver_warning_no_such_directory
    | driver_warning_not_a_directory
    | driver_warning_not_a_file
    | driver_warning_permission_denied
    | driver_warning_invalid_path
    | driver_warning_unexpected_file_extension
    | driver_warning_argument_unused
    | driver_warning_path_close_to_length_limit
    | driver_invalid_compile_target
    | driver_warning_unusable_static
    | driver_static_std_for_ohos
    | driver_warning_no_support_static
    | driver_require_package_directory
    | driver_require_package_directory_scan_dependency
    | driver_require_one_package_directory
    | driver_require_one_package_directory_scan_dependency
    | driver_source_cjo_empty
    | driver_not_accept_cjo_inputs_when
    | driver_source_file_empty
    | driver_invalid_source_file
    | driver_invalid_file_or_directory
    | driver_invalid_binary_file
    | driver_invalid_unsupport_extension
    | driver_invalid_require_extension
    | driver_path_exceeds_length_limit
    | driver_unsupported_target_cpu
    | driver_require_common_chir_for_each_common_cjo
    | driver_require_experimental
    | driver_static_dystd_conflict
    | driver_target_lto_unsupported
    | driver_cfg_value_err
    | driver_cfg_toml_content_err
    | dirver_cfg_invaild_identifier
    | dirver_cfg_same_with_builtin
    | dirver_cfg_key_repeat
    | dirver_cfg_not_a_dir
    | driver_cfg_file_read_failed
    | driver_cfg_path_ignored
    | driver_invalid_compile_as_exe
    | driver_invalid_compile_as_exe_platform
    | driver_invalid_visible_pkgs
    | driver_invalid_visible_pkgs_conflict
    | driver_visible_pkgs_only_for_dylib
    | driver_useless_option
    | driver_unsupport_compile_package_with_source_file
    | driver_unsupport_compile_source_file_with_path
    | driver_deprecated_option
    | driver_pgo_both_gen_and_use
    | driver_ohos_pgo_gen_without_file
    | driver_pgo_invalid_profile_extension
    | not_a_valid_plugin
    | plugin_throws_exception
    | driver_diag_end
    | frontend_diag_begin
    | frontend_failed_to_detect_cangjie_home
    | frontend_failed_to_detect_cangjie_modules
    | frontend_invalid_output_path
    | frontend_diag_end
    | incremental_compilation_diag_begin
    | cache_search_error
    | incremental_compilation_diag_end
    | lex_diag_begin
    | lex_unknown_start_of_token
    | lex_unexpected_digit
    | lex_cannot_start_with_digit
    | lex_expected_digit
    | lex_unexpected_decimal_point
    | lex_unexpected_exponent_part
    | lex_expected_exponent_part
    | lex_expected_identifier_after_dollar
    | lex_unrecognized_symbol
    | lex_expected_identifier
    | lex_expected_back_quote
    | lex_unterminated_single_line_string
    | lex_unterminated_multi_line_string
    | lex_unterminated_interpolation
    | lex_multiline_string_start_from_newline
    | lex_unterminated_raw_string
    | lex_expected_quote_in_raw_string
    | lex_unrecognized_escape
    | lex_unterminated_block_comment
    | lex_expected_left_bracket
    | lex_expected_right_bracket
    | lex_expected_right_bracket_or_hexadecimal
    | lex_expected_character
    | lex_expected_letter_after_underscore
    | lex_illegal_integer_suffix
    | lex_illegal_float_suffix
    | lex_illegal_non_decimal_float
    | lex_expected_character_in_char_literal
    | lex_unterminated_char_literal
    | lex_characters_overflow
    | lex_unknown_suffix
    | lex_illegal_UTF8_encoding_byte
    | lex_illegal_unicode
    | lex_unsecure_unicode
    | lex_illegal_uni_character_literal
    | lex_too_many_digits
    | lex_unrecognized_char_in_binary_string
    | lex_diag_end
    | module_diag_begin
    | module_read_file_to_buffer_failed
    | module_common_part_path_is_required
    | module_read_file_conflicted
    | module_version_not_identical
    | module_open_bcFile_failed
    | module_loaded_ast_failed
    | module_same_name_with_indirect_dependent_pkg
    | module_common_cjo_no_options
    | module_common_cjo_debug_mismatch
    | module_common_cjo_opt_mismatch
    | module_unsupport_circular_dependencies
    | module_common_cjo_wrong_package
    | module_diag_end
    | import_package_diag_begin
    | package_unsupport_save
    | package_unsupported_load
    | package_invalid_cjo_dependency
    | package_decl_not_find_in_package
    | package_search_error
    | bc_cjo_error
    | package_import_itself_illegal
    | package_missed_cjo_main_pkg_part_for_test_pkg
    | package_multiple_package_declarations
    | package_name_not_identical_lsp
    | package_name_inconsistent_with_macro
    | package_shadowed_import
    | package_conflict_import
    | package_cannot_export_macro_package
    | package_import_inconsistent
    | package_mocking_support_inconsistency
    | package_accessibility
    | package_re_export_package_name
    | package_root_package_should_be_public
    | packages_visibility_inconsistent
    | packages_macro_inconsistent
    | feature_already_seen_name
    | feature_null_declaration
    | feature_different_consistency
    | feature_is_not_subset_of_child_set
    | import_package_diag_end
    | parse_diag_begin
    | parse_expected_name
    | parse_unexpected_newline_between_at_and_mc
    | parse_expect_escape_dollar_token
    | parse_varray_type_parameter
    | parse_varray_type_args_mismatch
    | parse_expect_integer_literal_varray
    | parse_varray_with_paren
    | parse_expected_import
    | parse_expected_right_delimiter
    | parse_not_allowed_raw_identifier
    | parse_invalid_return_type
    | parse_unmatched_right_delimiter
    | parse_expected_literal
    | parse_expected_pattern
    | parse_expected_backarrow_in_let_cond
    | parse_expected_left_paren_after
    | parse_expected_left_angle_after
    | parse_expected_expr_or_decl_in
    | parse_expected_catch_or_finally_in_try
    | parse_expected_catch_or_handle_or_finally_in_try
    | parse_expected_colon_in_catch_pattern
    | parse_expected_colon_in_effect_pattern
    | parse_expected_wildcard_or_exception_pattern
    | parse_expected_wildcard_or_effect_pattern
    | parse_expected_double_arrow_in_case
    | parse_selector_or_match_expression_body
    | parse_expected_left_brace
    | parse_expected_left_paren
    | parse_expected_case
    | parse_unexpected_line_break
    | parse_expected_paren_or_brace_after_try
    | parse_expected_assignment
    | parse_expected_in_forin_expression
    | parse_expected_while_in_do_while
    | parse_expected_double_arrow_in_lambda
    | parse_expected_ccd_in_lambda
    | parse_expected_character
    | parse_expected_character_after
    | parse_importing_by_package_name_is_not_supported
    | parse_expected_decl
    | parse_expected_one_of_identifier_or_pattern
    | parse_expected_get_or_set_in_prop
    | parse_expected_where_brace
    | parse_expected_lt_brace
    | parse_expected_lt_paren
    | parse_expected_identifier_lp
    | parse_expected_dot_lparen
    | parse_expected_arrow_in_func_type
    | parse_unexpected_colon_in_range
    | parse_expected_lsquare_after
    | parse_expected_type_argument
    | parse_expected_parameter_rp
    | parse_expected_no_newline_after
    | parse_expected_if_let_andand
    | parse_duplicated_item
    | parse_nl_warning
    | parse_illegal_function_name
    | parse_expected_macro_decl_define_in_macro_package
    | parse_expected_public_before_macro_decl
    | parse_macro_unexpected_empty_parameter
    | parse_macro_expected_right_parameter_nums
    | parse_macro_illegal_param_type
    | parse_macro_illegal_ret_type
    | parse_macro_illegal_named_param
    | parse_macro_define_conflicted_with_builtin
    | parse_macro_call_illegal_with_builtin
    | parse_unexpected_declaration_in_scope
    | parse_const_expected_initializer
    | parse_unexpected_const_modifier_on_variable
    | parse_var_must_be_initialized
    | parse_expected_one_of_type_or_initializer
    | parse_expected_type_or_init_in_pattern
    | parse_named_parameter_after_unnamed
    | parse_member_parameter_after_regular
    | parse_decl_cannot_inherit_their_self
    | parse_intrinsic_function_must_be_toplevel
    | parse_intrinsic_function_cannot_have_body
    | parse_abstract_func_must_have_return_type
    | parse_duplicated_get_or_set
    | parse_unknown_enum_constructor
    | parse_getter_setter_cannot_be_generic
    | parse_unexpected_where
    | parse_setter_must_contain_one_parameter
    | parse_setter_can_only_accept_one_parameter
    | parse_duplicated_intrinsic_function
    | parse_missing_body
    | parse_invalid_super_declaration
    | parse_static_init_can_not_accept_any_parameter
    | parse_finalizer_can_not_accept_any_parameter
    | parse_invalid_quote_dollar_expr
    | parse_unexpected_lambda_expr_in_toplevel
    | parse_trailing_closure_only_follow_name
    | parse_invalid_left_hand_expr
    | parse_chained_none_associative
    | parse_duplicated_step_op
    | parse_invalid_step_op
    | parse_expected_expression
    | parse_invalid_incre_expr
    | parse_unrecognized_token_after_macro_node
    | parse_expected_operator_or_end
    | parse_cannot_have_assi_in_init
    | parse_case_body_cannot_be_empty
    | parse_redefined_resource_name
    | parse_newline_not_allowed_between_spawn_and_argument
    | parse_expected_no_arguments_in_spawn
    | parse_invalid_overloaded_operator
    | parse_empty_string_interpolation
    | parse_invalid_unicode_scalar
    | parse_wildcard_can_not_be_used_as_member_name
    | parse_unexpected_expected_found
    | parse_cannot_operator_a_tuple
    | parse_expected_parentheses
    | parse_this_type_not_allow
    | parse_unexpected_tuple_decl_type
    | parse_expected_type
    | parse_newline_not_allowed_between_quest_and_type
    | parse_redundant_arrow_after_func_type
    | parse_all_parameters_must_be_named
    | parse_only_tuple_and_func_type_allow_type_parameter_name
    | parse_illegal_declaration_pattern
    | parse_illegal_or_pattern
    | parse_tuple_pattern_expected_more_field
    | parse_type_pattern_in_let_cond
    | parse_expected_macro_decl_in_macro_package
    | parse_package_as_all
    | parse_package_name_length_overflow
    | parse_package_name_has_backtick
    | parse_illegal_macro_expand_input_args
    | parse_illegal_macro_expand_attr_args
    | parse_illegal_macro_expand_input_args_without_paren
    | parse_illegal_macro_expand_input_without_paren_in_paramlist
    | parse_ifavailable_arg_no_name
    | parse_ifavailable_not_lambda
    | parse_unexpected_anno_on
    | parse_unexpected_overflow_annotation
    | parse_unrecognized_expression_in_when
    | parse_unrecognized_attr_in_anno
    | parse_empty_attribute
    | parse_duplicated_attr_value
    | parse_unsafe_will_be_ignored
    | parse_duplicated_annotation
    | parse_conflict_annotation
    | parse_fail_expected_annotation
    | parse_common_function_must_have_return_type
    | parse_specific_function_must_have_return_type
    | parse_specific_function_parameter_cannot_have_default_value
    | parse_specific_member_must_have_implementation
    | parse_expected_type_with_cjmp_var
    | parse_cjmp_outdecl_miss_match
    | parse_cjmp_static_init
    | parse_unexpected_cjmp_decl
    | parse_cjmp_generic_decl
    | parse_cjmp_pattern_decl
    | parse_cjmp_in_common_ctor_required
    | parse_explicitly_abstract_only_for_cjmp_abstract_class
    | parse_illegal_modifier_in_scope
    | parse_conflict_modifier
    | parse_expected_no_modifier
    | parse_duplicate_modifier
    | parse_duplicate_type_parameter_name
    | parse_unexpected_type_in
    | parse_redundant_modifier
    | parse_variable_length_parameter_can_not_be_first
    | parse_variable_length_parameter_must_in_the_end
    | parse_variable_length_parameter_only_in_the_foreign_function
    | parse_foreign_func_should_not_be_generic
    | parse_foreign_func_must_declare_return_type
    | parse_foreign_function_with_body
    | parse_expected_static_for_const_member_var
    | parse_deprecated_wrong_argument
    | parse_deprecated_argument_duplication
    | parse_deprecated_arguments_must_be_lit_const_expr
    | parse_deprecated_empty_string_argument
    | parse_deprecated_unknown_argument
    | parse_deprecated_invalid_target
    | parse_annotation_max_one_argument
    | parse_annotation_one_argument
    | parse_annotation_no_arguments
    | parse_foreign_name_on_ffi_decl_member
    | parse_java_mirror_function_cannot_have_body
    | parse_java_mirror_function_must_have_return_type
    | parse_java_mirror_prop_is_forbidden
    | parse_java_mirror_decl_cannot_have_primary_ctor
    | parse_java_mirror_constructor_cannot_have_body
    | parse_java_mirror_cannot_have_private_member
    | parse_java_mirror_cannot_have_static_init
    | parse_java_mirror_cannot_have_finalizer
    | parse_java_mirror_cannot_have_const_member
    | parse_java_mirror_cannot_be_sealed
    | parse_java_impl_cannot_be_generic
    | parse_java_impl_cannot_be_abstract
    | parse_java_impl_cannot_be_sealed
    | parse_java_impl_cannot_have_static_init
    | parse_java_impl_cannot_be_open
    | parse_java_impl_cannot_be_interface
    | parse_objc_mirror_cannot_have_primary_ctor
    | parse_objc_mirror_ctor_cannot_have_body
    | parse_objc_mirror_method_cannot_have_body
    | parse_objc_mirror_method_must_have_return_type
    | parse_objc_mirror_cannot_be_sealed
    | parse_objc_mirror_cannot_have_private_member
    | parse_objc_mirror_cannot_have_static_init
    | parse_objc_mirror_cannot_have_finalizer
    | parse_objc_mirror_cannot_have_const_member
    | parse_objc_impl_cannot_be_generic
    | parse_objc_impl_cannot_be_abstract
    | parse_objc_impl_cannot_be_sealed
    | parse_objc_impl_cannot_have_static_init
    | parse_objc_impl_cannot_be_open
    | parse_objc_impl_cannot_be_interface
    | parse_objc_mirror_field_cannot_have_initializer
    | parse_objc_mirror_field_cannot_be_static
    | parse_objc_mirror_prop_cannot_have_getter
    | parse_objc_mirror_prop_cannot_have_setter
    | parse_objc_mirror_func_cannot_be_foreign
    | parse_objc_mirror_func_cannot_be_c
    | parse_objc_mirror_func_cannot_be_generic
    | parse_objc_mirror_func_cannot_have_body
    | parse_objc_mirror_func_must_have_explicit_type
    | parse_objc_mirror_func_cannot_be_const
    | parse_objc_mirror_func_must_be_top_level
    | parse_objc_init_method_must_be_static
    | parse_objc_init_method_must_be_in_mirror_class
    | parse_objc_optional_method_must_be_in_mirror_class
    | parse_objc_interop_not_supported
    | parse_diag_error
    | parse_diag_warning
    | parse_diag_end
    | parse_query_diag_begin
    | parse_query_expected_position_compare_operator
    | parse_query_expected_hash_id_compare_operator
    | parse_query_invalid_query_value
    | parse_query_expected_query_symbol
    | parse_query_expected_logic_symbol
    | parse_query_position_illegal_file_id
    | parse_query_position_illegal_line_num
    | parse_query_position_illegal_column_num
    | parse_query_position_comma_required
    | parse_query_hashid_illegal_file_hash
    | parse_query_hashid_illegal_fieldid
    | searcher_past_the_end_of_array
    | searcher_empty_number
    | searcher_invalid_number
    | searcher_invalid_scope_name
    | parse_query_diag_end
    | sema_diag_begin
    | sema_invalid_node_after_check
    | sema_unable_to_infer_decl
    | sema_mismatched_types
    | sema_mismatched_types_multiple_assign
    | sema_mismatched_types_because
    | sema_ambiguous_use
    | sema_undeclared_identifier
    | sema_undefined_variable
    | sema_redefinition
    | sema_conflict_with_sub_package
    | sema_core_object_not_found_when_no_prelude
    | sema_accessibility_with_main_hint
    | sema_accessibility
    | sema_param_miss_match
    | sema_unable_to_infer_return_type
    | sema_unable_to_infer_generic_func
    | sema_invalid_called_object
    | sema_invalid_return
    | sema_invalid_return_in_static_init
    | sema_wrong_number_of_arguments
    | sema_unordered_arguments
    | sema_param_named_mismatched
    | sema_need_named_argument
    | sema_invalid_subscript_assign_parameter
    | sema_invalid_subscript_assign_parameter_num
    | sema_invalid_subscript_assign_return
    | sema_overload_conflicts
    | sema_static_function_overload_conflicts
    | sema_use_mutable_func_alone
    | sema_unsafe_func_can_only_be_called
    | sema_ambiguous_match_primitive_extend
    | sema_immutable_access_mutable_func
    | sema_recursive_constructor_call
    | sema_cannot_have_default_param
    | sema_trailing_lambda_cannot_used_for_non_function
    | sema_unable_to_infer_expr
    | sema_exceed_num_value_range
    | sema_exceed_float_literal_range
    | sema_float_literal_too_large
    | sema_float_literal_too_small
    | sema_invalid_unary_expr
    | sema_invalid_unary_expr_with_target
    | sema_invalid_binary_expr
    | sema_invalid_subscript_expr
    | sema_cannot_assign_to_subscript
    | sema_not_member_of
    | sema_member_not_imported
    | sema_cannot_assign_to_immutable
    | sema_unqualified_left_value_assigned
    | sema_not_found_from_generic_upper_bounds
    | sema_different_or_pattern
    | sema_var_in_or_pattern
    | sema_var_in_or_condition
    | sema_nonexhuastive_patterns
    | sema_unreachable_pattern
    | sema_lambdaExpr_must_have_type_annotation
    | sema_use_func_capture_var_alone
    | sema_enum_constructor_with_param_must_have_args
    | sema_optional_chain_non_optional
    | sema_capture_before_initialization
    | sema_interpolation_in_const_pattern
    | sema_cannot_ref_to_pkg_name
    | sema_use_expr_without_import
    | sema_generic_func_without_type_arg
    | sema_generic_type_inconsistent
    | sema_generic_argument_no_match
    | sema_generic_constraint_not_looser
    | sema_generic_instantiation_causes_ambiguous_functions
    | sema_multiple_class_upperbounds
    | sema_generic_param_exist_in_class_irrelevant_upperbound_recursively
    | sema_generic_param_directly_recursive
    | sema_upper_bound_must_be_class_or_interface
    | sema_inherit_member_kind_inconsistent
    | sema_inherit_super_member_kind_inconsistent
    | sema_inherit_member_type_inconsistent
    | sema_inherit_abstract_class_static_unimplement_func
    | sema_cannot_override
    | sema_invalid_member_visibility_in_class
    | sema_weak_visibility
    | sema_cannot_inherit_sealed
    | sema_inherit_thread_context_invalid
    | sema_inherit_thread_context_not_open
    | sema_inherit_not_return_this
    | sema_return_type_incompatible
    | sema_spawn_arg_invalid
    | sema_spawn_arg_no_effect
    | sema_spawn_capture_var
    | sema_interface_call_with_unimplemented_call
    | sema_type_uninitialized_static_field
    | sema_instance_func_cannot_be_used_in_finalizer
    | sema_no_non_param_constructor_in_super_class
    | sema_non_abstract_class_cannot_be_sealed
    | sema_static_variable_use_generic_parameter
    | sema_cstruct_cannot_impl_interfaces
    | sema_class_need_abstract_modifier_or_func_need_impl
    | sema_need_member_implementation
    | sema_export_same_private_decl
    | sema_extend_function_cannot_overridden
    | sema_extend_member_cannot_shadow
    | sema_illegal_extended_type
    | sema_extend_generic_must_be_used
    | sema_extend_duplicate_interface
    | sema_extend_not_interface
    | sema_extend_illegal_member
    | sema_extend_use_super
    | sema_type_cannot_extend_imported_interface
    | sema_c_type_cannot_extend_interface
    | sema_immutable_type_extend_assignment_index_operator
    | sema_immutable_type_illegal_property
    | sema_interface_is_not_extendable
    | sema_invalid_mut_modifier_extend_of_struct
    | sema_extend_check_sequence_cannot_decide
    | sema_export_extend_depend_non_export_extend
    | sema_property_must_have_accessors
    | sema_immutable_property_with_setter
    | sema_property_have_same_declaration_in_inherit_mut
    | sema_property_have_same_declaration_in_inherit_immut
    | sema_property_must_implement_both
    | sema_expect_const
    | sema_cannot_define_var_in_const_funciton
    | sema_no_const_init
    | sema_class_const_init_with_var
    | sema_annotation_no_const_init
    | sema_annotation_arg_target
    | sema_annotation_arg_target_array_lit
    | sema_annotation_non_public
    | sema_annotation_custom_place
    | sema_inout_modify_cstring_or_zerosized
    | sema_inout_modify_non_ctype
    | sema_inout_must_be_var_variable
    | sema_inout_modify_heap_variable
    | sema_inout_can_only_used_in_cfunc_calling
    | sema_inout_mismatch
    | sema_annotation_error_arg_num
    | sema_annotation_error_arg_range
    | sema_annotation_error_object
    | sema_java_incorrect_use_between_types
    | sema_java_non_jtype
    | sema_java_invalid_unit
    | sema_java_app_inherit_ext
    | sema_java_unsupported_decl
    | sema_missing_java_interop_annotation
    | sema_generic_static_access
    | sema_primitive_type_as_generics_arg
    | sema_meet_constraint_indirectly
    | sema_static_member_in_interface_must_has_body
    | sema_extend_a_java_type
    | sema_generic_upper_bounds_must_be_java_in_java
    | sema_define_java_annotation
    | sema_invalid_use_of_java_annotation
    | sema_invalid_use_of_annotation_jffi
    | sema_annotation_not_applicable_jffi
    | sema_cannot_use_annotation_jffi
    | sema_shadow_cannot_in_type_args
    | sema_unsupported_type_argument_in_java_interop
    | sema_cjmapping_struct_generic_not_supported
    | sema_cjmapping_struct_inheritance_interface_not_supported
    | sema_cjmapping_decl_not_supported
    | sema_cjmapping_method_arg_not_supported
    | sema_cjmapping_method_ret_unsupported
    | sema_cj_mapping_generic_method_not_get_instance_config
    | sema_varray_size_match
    | sema_varray_args_number_mismatch
    | sema_varray_subscript_num
    | sema_varray_in_cfunc
    | sema_varray_arg_type_with_reftype
    | sema_only_cfunc_can_use_annotation
    | sema_annotation_calling_conv_not_support
    | sema_annotation_invalid_args_type
    | sema_illegal_scope_use_of_annotation
    | sema_invalid_cfunc_return_type
    | sema_mock_disabled
    | sema_mock_not_in_test_mode
    | sema_mock_unsupported_type
    | sema_mock_wrong_static_decl
    | sema_mock_doesnt_support_mocking
    | sema_mock_frozen_unsupported
    | sema_mock_frozen_required
    | sema_command_handle_type_error
    | sema_resumption_handle_type_error
    | sema_resumption_incorrect_return_type
    | sema_command_resumption_mismatch
    | sema_implicit_resume_outside_handler
    | sema_resume_no_with
    | sema_resume_wrong_resumption_type
    | sema_mismatching_handle_block
    | sema_return_in_try_handle_block
    | sema_try_handle_capture_var
    | sema_command_incompatible_type
    | sema_resume_throwing_mismatch_type
    | sema_useless_command_type
    | sema_deprecated_error
    | sema_deprecated_warning
    | sema_deprecation_weakening
    | sema_deprecation_override_error
    | sema_deprecation_override_warning
    | sema_deprecation_redef_error
    | sema_deprecation_redef_warning
    | sema_common_open_class_no_init
    | sema_multiple_common_implementations
    | sema_common_direct_extension_has_duplicate_private_members
    | sema_common_direct_extension_has_common_private_members
    | sema_not_matched
    | sema_specific_var_not_match_let
    | sema_specific_init_common_primary_constructor
    | specific_has_different_kind
    | sema_specific_primary_unmatched_var_decl
    | common_non_exaustive_platfrom_exaustive_mismatch
    | sema_specific_has_different_type
    | sema_specific_member_must_have_implementation
    | sema_specific_has_different_modifier
    | sema_specific_has_different_annotation
    | sema_specific_has_deprecated_annotation
    | sema_cjmp_parameter_default_value_both_sides
    | sema_specific_has_different_parameter
    | sema_specific_has_different_super_type
    | sema_specific_has_duplicate_extensions
    | sema_common_package_has_main
    | sema_common_static_let_cant_be_initialized_in_static_init
    | sema_common_assign_to_common_immutable_in_ctor
    | sema_cjmp_abstract_class_member_has_no_explicit_modifier
    | sema_explicitly_abstract_can_not_have_body
    | sema_explicitly_abstract_only_for_cjmp_abstract_class
    | sema_open_abstract_specific_can_not_replace_open_common
    | sema_cjmp_non_specific_abstract_member_in_specific_class
    | sema_common_generic_frozen_not_supported
    | sema_common_generic_rename_not_supported
    | sema_common_specific_annotation_not_allowed
    | sema_java_mirror_ctor_arg_must_be_java_mirror
    | sema_java_mirror_method_arg_must_be_java_mirror
    | sema_java_mirror_method_ret_unsupported
    | sema_java_mirror_prop_must_be_java_mirror
    | sema_java_mirror_subtype_must_be_annotated
    | sema_java_mirror_cannot_inherit_pure_cangjie_type
    | sema_java_impl_cannot_inherit_pure_cangjie_type
    | sema_java_mirror_subtype_anno_must_inherit_mirror
    | sema_java_mirror_cannot_be_extended_with_interface
    | sema_java_impl_cannot_be_extended_with_interface
    | sema_java_impl_redefinition
    | sema_java_mirror_interoplib_must_be_imported
    | sema_java_interop_not_supported
    | sema_extend_ref_target_cannot_be_java_impl
    | sema_generic_parameter_of_java_type
    | sema_java_interoplib_version_too_old
    | sema_java_interoplib_version_mismatch
    | sema_java_has_default_annotation_args
    | sema_java_has_default_annotation_is_in_wrong_place
    | sema_java_has_default_conflict_with_static
    | sema_objc_interop_ctor_param_must_be_objc_compatible
    | sema_objc_interop_method_param_must_be_objc_compatible
    | sema_objc_interop_method_ret_must_be_objc_compatible
    | sema_objc_interop_prop_must_be_objc_compatible
    | sema_objc_interop_field_must_be_objc_compatible
    | sema_objc_mirror_decl_cannot_inherit
    | sema_objc_mirror_subtype_cannot_multiple_inherit
    | sema_objc_mirror_subtype_must_be_annotated
    | sema_objc_mirror_subtype_must_inherit_mirror
    | sema_objc_mirror_must_inherit_mirror
    | sema_objc_mirror_interoplib_must_be_imported
    | sema_objc_interop_not_supported
    | sema_objc_pointer_argument_must_be_objc_compatible
    | sema_objc_interop_toplevel_param_must_be_objc_compatible
    | sema_objc_interop_toplevel_ret_must_be_objc_compatible
    | sema_objc_method_must_have_foreign_name
    | sema_objc_ctor_must_have_foreign_name
    | sema_objc_func_argument_must_be_objc_compatible
    | sema_objc_func_call_property_can_only_be_called
    | sema_objc_impl_must_have_objc_mirror_super_class
    | sema_objc_setter_name_on_immutable_prop
    | sema_objc_cjmapping_inheritance_interface_not_supported
    | sema_objc_cjmapping_generic_not_supported
    | sema_foreign_name_appeared_in_child
    | sema_foreign_name_conflicting_annotation
    | sema_foreign_name_conflicting_derived_annotation
    | sema_ifavailable_arg_no_name
    | sema_ifavailable_arg_not_literal
    | sema_ifavailable_unknow_arg_name
    | sema_apilevel_multi_anno
    | sema_apilevel_missing_arg
    | sema_apilevel_invalid_version_format
    | sema_only_literal_support
    | sema_apilevel_ref_higher
    | sema_apilevel_syscap_warning
    | sema_apilevel_syscap_error
    | sema_apilevel_multi_diff_syscap
    | sema_apilevel_integer_form_unsupported
    | sema_ifavailable_level_limit
    | sema_hide_multi_annotation
    | sema_hide_at_func_param
    | sema_hide_missing_hide
    | sema_hide_compile_time_invisible
    | sema_hide_diff_param
    | sema_hide_must_at_end
    | sema_unused_import
    | sema_diag_end
}

public class ErrorData {
    public let message: String
    public let mainHint: String
    public let otherHints: Array<String>

    public init(message!: String = "", mainHint!: String = "", otherHints!: Array<String> = Array<String>()) {
        this.message = message
        this.mainHint = mainHint
        this.otherHints = otherHints
    }
}

public let DEFAULT_KIND: DiagKind = DiagKind.sema_diag_begin

public let DIAG_KIND_STR: Array<String> = [
    "chir_diag_begin",
    "chir_var_might_circular_dependency",
    "chir_file_might_circular_dependency",
    "chir_used_before_initialization",
    "chir_sancov_illegal_usage_of_pc_table",
    "chir_sancov_illegal_usage_of_level",
    "interp_cannot_interp_node",
    "interp_malloc_failed",
    "interp_unsupported",
    "interp_unsupported_type",
    "interp_cannot_convert_array2ffi",
    "interp_cannot_load_incremental_bchir",
    "const_eval_exception",
    "const_eval_load_dep",
    "const_eval_unsupported",
    "chir_diag_end",
    "macro_expand_diag_begin",
    "macro_undeclared_identifier",
    "macro_expect_attributed_macro",
    "macro_evaluate_failed",
    "macro_expect_macro_definition",
    "macro_undefined_pkg_name",
    "macro_expect_plain_macro",
    "macro_expand_invalid_attr_tokens",
    "macro_expand_invalid_input_tokens",
    "macro_expand_invalid_escape",
    "macro_unexpect_def_and_call_in_same_pkg",
    "macro_init_interpter_faild",
    "macro_expand_invalid_node_replace",
    "macro_ambiguous_match",
    "macro_using_error",
    "macro_expand_failed",
    "not_find_macro_library",
    "can_not_open_macro_library",
    "macro_cannot_find_method",
    "macro_expect_decl_not_enum_constructor",
    "macro_expect_declaration",
    "macro_expect_enum_constructor",
    "macro_expect_one_enum_constructor",
    "macro_expect_one_expr_or_pattern",
    "macro_expect_one_expr",
    "macro_unexpect_no_expr",
    "macro_call_map_to_empty_value_token",
    "macro_call_map_info_failed",
    "macro_call_save_file_failed",
    "macro_expand_code_should_not_have_macrocall",
    "macro_expand_cannot_find_dependency",
    "macro_expand_exception_occurred",
    "macro_expand_failed_init_top_level",
    "macro_named_parameter_after_unnamed",
    "macro_unexpected_empty_parameter",
    "macro_assert_parent_context_failed",
    "macro_build_in_unexpect_params",
    "macro_build_in_unexpect_params_attrs",
    "macro_is_deprecated_error",
    "macro_is_deprecated_warning",
    "macro_expand_atexcl",
    "macro_expand_diag_end",
    "sema_diag_begin",
    "sema_diag_report_error_message",
    "sema_diag_report_note_message",
    "sema_incompatible_expo_target_type",
    "sema_ambiguous_expo_right_operand_type",
    "sema_not_a_type",
    "sema_incompatible_func_body_and_return_type",
    "sema_type_must_toplevel",
    "sema_undeclared_type_name",
    "sema_undeclared_identifier",
    "sema_redefinition",
    "sema_expand_macro_redefinition",
    "sema_previous_decl",
    "sema_used_before_initialization",
    "sema_global_var_used_before_initialization",
    "sema_duplicated_item_in_enum",
    "sema_invalid_constructor_in_enum",
    "sema_multiple_constructor_in_enum",
    "sema_enum_constructor_type_not_match",
    "sema_invalid_enum_member_access",
    "sema_invalid_type_param_of_enum_member_access",
    "sema_invalid_loop_control",
    "sema_cannot_currying",
    "sema_value_type_recursive",
    "sema_inheritance_cycle",
    "sema_typealias_cycle",
    "sema_typealias_external_refer_internal",
    "sema_invalid_coalescing",
    "sema_div_zero",
    "sema_mod_zero",
    "sema_arithmetical_op_overflow",
    "sema_shift_count_overflow",
    "sema_negative_shift_count",
    "sema_func_capture_var_cannot_assign",
    "sema_func_capture_var_cannot_return",
    "sema_func_capture_var_cannot_param",
    "sema_func_capture_var_cannot_expr",
    "sema_invalid_unary_expr",
    "sema_invalid_unary_expr_note",
    "sema_fail_flow_expr_operand_has_named_param",
    "sema_operator_overload_invalid_num_parameter",
    "sema_operator_overload_built_in_unary_operator",
    "sema_operator_overload_built_in_binary_operator",
    "sema_operator_overload_can_not_has_default_param",
    "sema_empty_arrayLit_type_undefined",
    "sema_inconsistency_elemType",
    "sema_tuple_pattern_not_match",
    "sema_unsupport_operator",
    "sema_array_size_type_error",
    "sema_array_expression_param_type_error",
    "sema_array_expression_type_error",
    "sema_array_single_element_type_error",
    "sema_array_element_type_error",
    "sema_array_too_much_argument",
    "sema_array_first_arg_cannot_be_named",
    "sema_array_second_arg_cannot_be_named",
    "sema_array_second_wrong_named_arg",
    "sema_pointer_too_much_argument",
    "sema_cfunc_too_many_arguments",
    "sema_pointer_single_element_type_error",
    "sema_pointer_unknow_generic_type",
    "sema_builtin_invalid_index",
    "sema_builtin_index_in_bound",
    "sema_tuple_element_cmp_not_bool",
    "sema_tuple_cmp_not_supported",
    "sema_step_non_zero_range",
    "sema_inconsistency_range_elemType",
    "sema_range_step_not_int64",
    "sema_no_match_function_declaration_for_call",
    "sema_no_match_function_declaration_for_ref",
    "sema_no_match_constructor",
    "sema_ambiguous_arg_type",
    "sema_ambiguous_match",
    "sema_ambiguous_constructor_match",
    "sema_ambiguous_func_ref",
    "sema_mismatched_type_for_pattern_in_vardecl",
    "sema_parameters_and_arguments_mismatch",
    "sema_cstruct_cannot_autobox",
    "sema_unit_cannot_as_cfunc_arg",
    "sema_overload_conflicts",
    "sema_no_match_operator_function_call",
    "sema_pattern_can_not_be_assigned",
    "sema_unknown_named_argument",
    "sema_multiple_named_argument",
    "sema_invalid_named_arguments",
    "sema_unsupport_named_argument",
    "sema_pattern_literal_expected",
    "sema_pattern_not_match",
    "sema_not_overload_in_match",
    "sema_type_incompatible",
    "sema_subscript_set_not_supported",
    "sema_subscript_get_set_not_supported",
    "sema_tuple_pattern_with_correct_size_expected",
    "sema_enum_pattern_param_size_error",
    "sema_match_case_must_have_default",
    "sema_match_case_has_no_type",
    "sema_package_internal_decl_obtain_illegal",
    "sema_package_name_conflict",
    "sema_invalid_access_control",
    "sema_invalid_access_function",
    "sema_invalid_file_hash",
    "sema_func_no_override_or_redefine_modifier",
    "sema_unexpected_param_for_entry",
    "sema_unexpected_return_type_for_entry",
    "sema_redefinition_entry",
    "sema_missing_entry",
    "sema_numeric_convert_must_be_numeric",
    "sema_cfunc_ctor_must_be_cpointer",
    "sema_ref_not_be_type",
    "sema_expr_in_forin_must_has_iterator",
    "sema_forin_pattern_must_be_irrefutable",
    "sema_wrong_forin_guard",
    "sema_generics_type_variable_not_defined",
    "sema_generic_type_argument_not_match_constraint",
    "sema_which_constraint_not_match",
    "sema_generic_type_without_type_argument",
    "sema_non_generic_function_with_type_argument",
    "sema_throw_expr_with_wrong_type",
    "sema_except_catch_type_error",
    "sema_no_core_object",
    "sema_invalid_intrinsic_decl",
    "sema_generic_infinite_instantiation",
    "sema_forbid_generic_nonstatic_method",
    "sema_forbid_generic_constructor",
    "sema_forbid_generic_finalizer",
    "sema_import_not_in_current_module",
    "sema_flow_expressions_use_this_or_super",
    "sema_symbol_not_collected",
    "sema_cannot_convert_literal",
    "sema_cannot_have_parameter",
    "sema_annotation_error_arg_num",
    "sema_unexpected_wrapper",
    "sema_native_var_error",
    "sema_illegal_use_of_annotation",
    "sema_cffi_cannot_have_type_param",
    "sema_unsafe_function_invoke_failed",
    "sema_func_capture_var_not_ctype",
    "sema_cfunc_cannot_capture_var",
    "sema_cfunc_cannot_capture_this",
    "sema_illegal_ctype_generic_argument",
    "sema_illegal_cpointer_generic_type",
    "sema_invalid_cfunc_arg_type",
    "sema_cfunc_type",
    "sema_invalid_tuple_field_ctype",
    "sema_enum_pattern_func_cty_error",
    "sema_enum_pattern_func_param_cty_error",
    "sema_illegal_ctype_member",
    "sema_illegal_member_of_cstruct",
    "sema_cfunc_cannot_have_unit_args",
    "sema_cstruct_cannot_have_unit_fields",
    "sema_cfunc_cannot_have_named_args",
    "sema_cfunc_var_cannot_have_var_param",
    "sema_inheritance_non_ref_type",
    "sema_class_uninitialized_field",
    "sema_this_or_super_not_allowed_to_initialize_non_static_member",
    "sema_this_or_super_not_allowed_to_initialize_static_member",
    "sema_illegal_usage_of_super_member",
    "sema_illegal_usage_of_member",
    "sema_invalid_assignment_to_this_expr",
    "sema_invalid_override_member_in_class",
    "sema_invalid_override_or_redefine_member_in_interface",
    "sema_illegal_this_in_interface",
    "sema_use_super_in_interface",
    "sema_super_use_error_inside_non_class",
    "sema_assignment_of_member_variable_cannot_use_this_or_super",
    "sema_illegal_super_alone",
    "sema_abstract_class_can_not_be_instantiated",
    "sema_interface_can_not_be_instantiated",
    "sema_non_inheritable_super_class",
    "sema_superclass_must_be_placed_at_first",
    "sema_illegal_multi_inheritance",
    "sema_invalid_this_call_outside_ctor",
    "sema_privated_abstract_func_in_class",
    "sema_invalid_string_implementation",
    "sema_invalid_tokens_implementation",
    "sema_multiple_primary_constructors",
    "sema_interface_is_not_inheritable",
    "sema_interface_is_not_implementable",
    "sema_inherit_duplicate_interface",
    "sema_return_unit",
    "sema_illegal_place_of_calling_this_or_super",
    "sema_illegal_place_of_calling_this_primary_constructor",
    "sema_this_super_use_error_outside_class",
    "sema_missing_func_body",
    "sema_interface_member_must_be_implemented",
    "sema_interface_member_must_be_implemented_in_struct",
    "sema_member_variable_can_not_shadow",
    "sema_missing_overridden_func",
    "sema_missing_redefined_func",
    "sema_static_and_non_static_member_cannot_have_same_name",
    "sema_generic_member_type_argument_different",
    "sema_c_type_cannot_implement_interface",
    "sema_illegal_access_non_static_member",
    "sema_illegal_access_interface_field",
    "sema_illegal_access_inner_classlike",
    "sema_cannot_modify_var",
    "sema_illegal_capture_this",
    "sema_object_cannot_access_static_member",
    "sema_abstract_method_cannot_be_accessed_directly",
    "sema_return_type_invariance",
    "sema_static_members_cannot_call_members",
    "sema_class_inherit_non_class_nor_interface",
    "sema_type_implement_non_interface",
    "sema_interface_inherit_non_interface",
    "sema_generic_in_operator_overload",
    "sema_illegal_this_outside_struct_constructor",
    "sema_static_function_cannot_access_non_static_member",
    "sema_static_variable_cannot_access_non_static_member",
    "sema_static_lambdaExpr_cannot_access_non_static",
    "sema_redef_modify_static_func",
    "sema_illegal_member_used_in_open_constructor",
    "sema_finalizer_forbidden_in_class",
    "sema_generic_no_member_match_in_upper_bounds",
    "sema_generic_ambiguous_method_match_in_upper_bounds",
    "sema_generic_no_method_match_in_upper_bounds",
    "sema_cannot_instantiated_by_incomplete_type",
    "sema_invalid_field_expose_access",
    "sema_capture_this_or_instance_field_in_func",
    "sema_use_this_as_an_expression_in_func",
    "sema_incompatible_mut_modifier_between_struct_and_interface",
    "sema_immutable_function_cannot_access_mutable_function",
    "sema_invalid_position_of_this_type",
    "sema_property_override_implement_type_diff",
    "typealias_unused_type_parameters",
    "sema_capture_has_shadow_variable",
    "sema_useless_exception_type",
    "sema_ignore_open",
    "sema_found_candidate_decl",
    "sema_found_possible_candidate_decl",
    "sema_diag_end",
]
public let DIAG_KIND_STR_SIZE: Int64 = 288

public let DiagSeveritys: Array<DiagSeverity> = [
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_NOTE,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_NOTE,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_NOTE,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_NOTE,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_NOTE,
    DiagSeverity.DS_NOTE,
    DiagSeverity.DS_ERROR,
]

public let DiagMessages: Array<String> = [
    "",
    "%s might have circular dependency",
    "%s might have file circular dependency",
    "variable '%s' is used before initialization",
    "use '--sanitizer-coverage-pc-table, [inline-bool-flag|inline-8bit-counters|trace-pc-guard]' instead",
    "'--sanitizer-coverage-level' is illegal here",
    "['%s'] failed to interpret node '%s'",
    "failed allocating memory",
    "['%s'] unsupported '%s'",
    "['%s'] unsupported type '%s'",
    "cannot convert array to FFI value",
    "could not load previous incremental BCHIR",
    "an exception was thrown while evaluating constant",
    "failed to load const eval dependency '%s'",
    "tried to run non-const code in const eval",
    "",
    "",
    "undeclared identifier '%s'",
    "expect an attributed macro '%s', but find a plain one",
    "macro evaluation has failed for macro call '%s'",
    "expect macro defintion '%s', but found another Declareation",
    "undefined macro package '%s', expect a right package name for macro",
    "expect a plain macro '%s', but find an attributed one",
    " illegal attribute tokens in macro call, which is '%s'",
    " illegal input tokens in macro call",
    " illegal escape in macro call",
    "macro's call and definition can not in one package",
    "initialization of interpreter for macro expansion failed",
    "invalid node expanded in macro call's father node",
    "ambiguous match for macro call %s",
    "macro using error, '%s'",
    "macro expansion failed for macro call '%s'",
    "not find macro definition library path",
    "Cannot dlopen from the dynamic library '%s' for macro",
    "Cannot find method from dynamic libs for macro call '%s'",
    "expected declaration, but found enum constructor %s",
    "expected declaration, but found other node",
    "expected an enum constructor",
    "expected one enum constructor, but found more than one node",
    "expected one expr or pattern, but found more than one node",
    "expected one expr, but found exprs or other node",
    "expected one expr, but not found expr",
    "Cannot handle result of macro call: token '%s' is empty",
    "Cannot map information for macro call due to token '%s' mismatch with '%s'",
    "Failed to save results of macro call to file",
    "Code generated by macro '%s' should not have macro call.",
    "cannot find BCHIR file for macro package dependency %s.",
    "exception occurred during macro expansion.",
    "Interpreter failed when initializing top-level.",
    "unnamed parameters must come before named parameters.",
    "unexpected empty tokens after the macro expansion for the func parameters.",
    "The macro call '%s' should with the surround code contains a call '%s'.",
    "The build-in macro '%s' expected an empty parameter, but found non-empty one.",
    "The build-in macro '%s' is a plain macro, but find an attributed one.",
    "macro '%s' is deprecated%s%s",
    "macro '%s' is deprecated%s%s",
    "macro expansion cannot be prefixed with '@!'",
    "",
    "",
    "%s",
    "%s",
    "the type of an exponentiation expression is either 'Int64' or 'Float64', which conflicts the type '%s' required by the context",
    "both 'Int64' and 'Float64' is compatible with the right operand's type of this exponentiation (assignment) expression; please give an explicit one",
    "'%s' is not a type",
    "the return type of this function cannot be calculated from the function body and all the return expressions",
    "%s type must be toplevel",
    "undeclared type name '%s'",
    "undeclared identifier '%s'",
    "redefinition of declaration '%s'",
    "redefinition of macro '%s'",
    "'%s' is previously declared here",
    "variable '%s' is used before initialization",
    "global/static variable '%s' is used before initialization during initializing '%s'",
    "'%s' is already exist in enum '%s'",
    "invalid constructor in enum declaration",
    "find multiple constructor '%s' of enum declaration",
    "no matching enum constructor '%s' for given arguments",
    "base of member access can not be enum variable",
    "type arguments cannot appear after '%s' when enum type '%s' is given",
    "'break' or 'continue' must be used inside a loop",
    "%s cannot have more than one parameter list",
    "value type recursive detected: '%s'",
    "inheritance cycle detected: '%s'",
    "type cycle detected: '%s'",
    "'%s' type '%s' refers to '%s' type '%s'",
    "type of left operand does not support coalescing operation. coalescing is only valid for 'Option'",
    "division by 0",
    "mod by 0",
    "overflow in '%s' calculation",
    "shift count overflow",
    "shift count is negative",
    "%s captured a mutable variable %s, %s cannot be assigned to a variable",
    "%s captured a mutable variable %s, %s cannot be used as a return value",
    "%s captured a mutable variable %s, %s cannot be used as a param",
    "%s captured a mutable variable %s, %s cannot be used as a expression",
    "invalid unary operator '%s' on type '%s'",
    "you may want to implement operator func %s() for type '%s'",
    "flow operand cannot contain named parameter",
    "invalid number of parameters for operator '%s'",
    "operator func %s() of type %s is a built-in function and cannot be overridden",
    "operator func %s(%s) of type %s is a built-in function and cannot be overridden",
    "optional parameter can not be used in operator overload function",
    "array literal type cannot be inferred",
    "inconsistent element type for %s literal",
    "%s isn't a tuple to match tuple pattern",
    "not supported operator: '%s'",
    "array size must be of type Int64",
    "array init expression parameter's type must be type Int64",
    "array init expression must has type (Int64)->T",
    "array init with single element must be subtype of 'List' or 'Collection'",
    "array initialize element type error",
    "too much arguments given for array constructor, only accept 0~2 arguments",
    "array's first argument cannot be named argument",
    "array's second argument cannot be named argument when type is (Int64)->T",
    "array's second argument must have named prefix 'repeat:' when type is T",
    "too much arguments given for CPointer constructor, only accept 0~1 arguments",
    "too many arguments given to CFunc constructor, only accept 1 argument",
    "the single argument of CPointer constructor must be 'CPointer' or 'CFunc'",
    "'CPointer' generic type cannot be inferred",
    "%s index must be an integer literal",
    "%s index must be in bounds",
    "the '%s' operation between type '%s' and type '%s' is not evaluated to a Bool",
    "operator '%s' between tuple type '%s' and '%s' is not supported",
    "step cannot be zero in range expression",
    "start and stop must be of the same type in range expression",
    "step must be Int64 in range expression",
    "no matching function declaration for function call '%s'",
    "no matching function declaration for function reference '%s'",
    "no matching constructor for call '%s'",
    "ambiguous arguments type in call expression",
    "ambiguous match for function call '%s'",
    "ambiguous match for constructor call '%s'",
    "ambiguous match for reference '%s'",
    "the pattern in this variable declaration can not match its type",
    "parameters and arguments mismatch",
    "struct with @C cannot implicitly used as '%s'",
    "Unit cannot be used as argument type of CFunc",
    "%s '%s' has overload conflicts",
    "no matching function for operator '()' function call",
    "the pattern isn't irrefutable pattern and it can not be initialized",
    "unknown named argument prefix '%s:'",
    "named argument prefix '%s:' cannot appeared more than once in call",
    "invalid named arguments prefix '%s:', target is not a named parameter",
    "named argument cannot be used in variable function call",
    "only const literal is allowed in const pattern",
    "%s pattern is not matched",
    "no overloaded '==' function in match case pattern",
    "type incompatible in this %s",
    "type %s does not have operator func [](index, value) for index type %s",
    "type %s does not have both operator func [](index) and operator func [](index, value) for index type %s",
    "tuple pattern with correct size expected",
    "enum pattern's parameters size is wrong",
    "at least one default case, such as wildcard pattern, variable pattern or '[...]' for sequence pattern in match case.",
    "this match case has no type",
    "%s '%s' in package '%s' cannot be obtained",
    "package name '%s' is conflicted with other imported package name, please use 'as' to eliminate conflict.",
    "can not access field '%s'",
    "can not access function '%s'",
    "There is invalid file hash in access control check",
    "do not need '%s' modifier for %s '%s'",
    "'main' cannot be defined with parameter whose type is not 'Array<String>'",
    "return type of 'main' is not 'Integer' or 'Unit'",
    "multiple 'main's are found in source files",
    "'main' is missing",
    "the expression for numeric type conversion must have a numeric type",
    "argument type of 'CFunc' constructor must be of type 'CPointer'",
    "expected member name or constructor call after '%s' type name",
    "the type %s of expression in for-in expression does not implement Iterator",
    "the pattern in for-in expression must be irrefutable",
    "pattern guard should be Boolean type",
    "generics type variable '%s' has not defined",
    "generics type arguments do not match the constraint of '%s'",
    "'%s' is not a subtype of %s",
    "generic type should be used with type argument",
    "non-generic function should not be used with type argument",
    "the object thrown must derive from `core.Exception`",
    "the exception catch type must be class and extends from core.Exception or core.Error",
    "`core` package should be imported",
    "intrinsic function '%s' cannot be declared in '%s' package",
    "generic infinite instantiation",
    "non-static generic member function '%s' is not supported",
    "generic constructor '%s' is not supported",
    "generic finalizer '%s' is not supported",
    "this package does not belong to the current module, please write its module name explicitly.",
    "'%s' is not allowed to be used in flow expressions",
    "reference node named '%s' is not collected in symbol table.",
    "cannot convert %s literal to type '%s'",
    "%s cannot have parameter",
    "'%s' should have %s arg",
    "unexpected %s",
    "variable can not be modified with 'foreign' and implicit @C.",
    "%s cannot be modified with '%s'",
    "%s cannot have type parameters",
    "unsafe function or native function should be invoked in unsafe context.",
    "captured variable mustn't be struct with @C",
    "cannot capture variable %s in CFunc lambda expression",
    "'%s' is not allowed to be captured in CFunc lambda expression",
    "generic argument mustn't be struct with @C",
    "generic type of CPointer must be instantiated with CType",
    "arguments type of CFunc must be instantiated with CType",
    "cfunc type must be a function type",
    "tuple member mustn't be struct with @C",
    "member func '%s' is forbidden in enum '%s' with @C",
    "member func '%s' of enum '%s' mustn't has struct with @C",
    "non-static member variable '%s' of %s '%s' cannot be struct with @C",
    "member variable '%s' of struct '%s' with @C must be instantiated with CType",
    "CFunc cannot have arguments of type Unit",
    "member variables cannot be type Unit in struct with @C",
    "CFunc cannot have named arguments",
    "CFunc with variable-length parameters cannot be assigned to variables",
    "inheritance is not a ref type: '%s'",
    "the uninitialized member variable '%s' is not initialized in the constructor of class or struct",
    "'%s' is not allowed to initialize non-static member",
    "'%s' is not allowed to initialize static member",
    "super member '%s' is not allowed to be used before calling super()",
    "'%s' is not allowed to be accessed before all member variables are initialized",
    "cannot assign a value to 'this'",
    "cannot override non-abstract %s '%s' with abstract %s",
    "cannot override implemented interface %s '%s' with abstract %s",
    "'this' can not be used in interface",
    "'super' cannot be used in interface",
    "'super' can only be used in class",
    "'%s' is not allowed to be used in %s",
    "invalid super expression, it can only be used on the left-hand side of a dot",
    "abstract class '%s' can not be instantiated",
    "interface '%s' can not be instantiated",
    "super class '%s' is not inheritable",
    "super class '%s' must be placed at the beginning of supertype list",
    "only one super class may appear in supertype list of class '%s'",
    "invalid calling '%s' outside the constructor",
    "private abstract %s is forbidden in abstract class '%s'",
    "the type '%s' should implement interface 'ToString' in the 'core' package",
    "the type '%s' should implement interface 'ToTokens' in the 'ast' package",
    "%s '%s' cannot have more than one primary constructor",
    "'%s' interface is not able to be inherited",
    "'%s' interface is not able to be implemented explicitly",
    "%s '%s' inherits or implements duplicate interface '%s'",
    "return expressions in a constructor must be either 'return' or 'return ()'",
    "call to '%s' must be first expression in constructor of %s '%s'",
    "invalid calling 'this' in primary constructor ",
    "'%s' cannot be used outside class or struct or interface",
    "%s '%s' can not be abstract",
    "interface %s '%s' must be implemented in '%s'",
    "interface %s '%s' must be implemented in '%s'",
    "the variable '%s' must not shadow a member variable of the supertype",
    "'override' %s '%s' does not have an overridden %s in its supertype",
    "'redef' %s '%s' does not have a redefined 'static' %s in its supertype",
    "%s member '%s' cannot have the same name with %s member in %s",
    " type argument of function '%s' is different in parent class or interfaces",
    "c type '%s' cannot implement interface",
    "'%s' is non-static member, cannot access by type name",
    "field '%s' cannot be accessed without interface name '%s'",
    "inner %s '%s' cannot be accessed without name '%s'",
    "instance member variable '%s' cannot be modified in immutable function",
    "'this' is not allowed to be captured in constructor of %s",
    "object cannot access static member '%s'",
    "abstract method '%s' cannot be accessed directly",
    "return type of '%s' can only be class/interface type which implements or inherits the interface type '%s'",
    "non-static variable '%s' cannot be referenced from a static context",
    "class '%s' can only inherit a class or implement interfaces",
    "%s '%s' can only implement interface",
    "interface '%s' can only inherit interface",
    "generic is not allowed in operator overload function",
    "'this' is only allowed to be used inside constructor or function for struct",
    "'%s' is non-static member, cannot be accessed by static function '%s'",
    "'%s' is non-static member, cannot be accessed by static variable",
    "invalid use of non-static member '%s' in static lambda expression",
    "'redef' cannot be used to modify an instance '%s'",
    "instance member %s '%s' cannot be accessed in the constructor of open class '%s'",
    "finalizer is forbidden in class '%s' that is %s",
    "no member match for generic member access when searching in upper bounds",
    "ambiguous method '%s' match for generic member access function call when searching in upper bounds",
    "no method '%s' match for generic member access function call when searching in upper bounds",
    "can not instantiate '%s' by %s for it has unimplemented static member",
    "'%s' is not a static member of %s '%s'",
    "'%s' cannot be captured in the %s",
    "'this' cannot be used as an expression in the %s",
    "'mut' modifier of '%s' is incompatible with that in interface '%s'",
    "immutable function '%s' cannot access mutable function '%s'",
    "'This' type is not allowed here",
    "The type of the override/implement property must be the same",
    "type arg(s) %s are not used",
    "the variable '%s' actually captures this decl %p, can not captures the decl %p",
    "useless exception type",
    "the current member should not have 'open' modifier because it is in a non-inheritable class",
    "found candidate",
    "found possible candidate",
    "",
]

public let warnGroups: Array<WarnGroup> = [
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.DEPRECATED,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.UNUSED,
    WarnGroup.SEMANTICS,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
]

public let errorData: Array<ErrorData> = [
    ErrorData(message: "chir_diag_begin", mainHint: "", otherHints: []),
    ErrorData(message: "variable '%s' is used before initialization", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' is not allowed to be accessed before all member variables are initialized", mainHint: "", otherHints: []),
    ErrorData(message: "cannot assign to value which is an initialized 'let' constant", mainHint: "", otherHints: []),
    ErrorData(message: "not all the member variables are initialized in this constructor", mainHint: "", otherHints: []),
    ErrorData(message: "super member '%s' is not allowed to be used before calling super()", mainHint: "", otherHints: []),
    ErrorData(message: "arithmetic operation '%s' overflow", mainHint: "operation '%s' would overflow", otherHints: []),
    ErrorData(message: "array index is out of bounds", mainHint: "%s", otherHints: []),
    ErrorData(message: "%s by zero", mainHint: "attempt to %s by zero", otherHints: []),
    ErrorData(message: "shift operation overflow", mainHint: "attempt to shift %s bits on %s type", otherHints: []),
    ErrorData(message: "integer type conversion overflow", mainHint: "type conversion from %s to %s would overflow", otherHints: []),
    ErrorData(message: "step cannot be zero in range expression", mainHint: "", otherHints: []),
    ErrorData(message: "unreachable statement", mainHint: "unreachable statement", otherHints: ["any code following this expression is unreachable"]),
    ErrorData(message: "unreachable function ", mainHint: "function with parameter of nothing type will never be executed", otherHints: []),
    ErrorData(message: "unreachable return", mainHint: "unreachable return", otherHints: []),
    ErrorData(message: "unreachable '%s' expression", mainHint: "unreachable '%s' expression", otherHints: ["any code following this expression is unreachable"]),
    ErrorData(message: "unreachable '%s'", mainHint: "unreachable '%s'", otherHints: ["any code following this expression is unreachable"]),
    ErrorData(message: "unreachable expression", mainHint: "unreachable expression", otherHints: ["any code following this expression is unreachable"]),
    ErrorData(message: "unreachable block in '%s' expression", mainHint: "unreachable block in '%s' expression", otherHints: []),
    ErrorData(message: "unreachable block", mainHint: "unreachable block", otherHints: []),
    ErrorData(message: "unused expression", mainHint: "unused expression", otherHints: []),
    ErrorData(message: "unused function:'%s'", mainHint: "unused function", otherHints: []),
    ErrorData(message: "unused function:'main'", mainHint: "unused function", otherHints: []),
    ErrorData(message: "unreachable expression", mainHint: "unreachable expression", otherHints: []),
    ErrorData(message: "unused variable:'%s'", mainHint: "unused variable", otherHints: []),
    ErrorData(message: "unused result of the operator:'%s'", mainHint: "unused result of the operator", otherHints: []),
    ErrorData(message: "unreachable pattern", mainHint: "", otherHints: []),
    ErrorData(message: "const evaluation has been disabled by compiler option `--no-interp-const-eval`", mainHint: "", otherHints: []),
    ErrorData(message: "'@%s' not applicable to %s", mainHint: "", otherHints: []),
    ErrorData(message: "chir_diag_end", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "conditional compilation '%s' not support this op '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "conditional compilation have not supported this condition: '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "builtin condition '%s' do not support '%s', supported listed: '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "cjc version's format should be 'xx.xx.xx'", mainHint: "", otherHints: []),
    ErrorData(message: "conditional compilation not support this expression", mainHint: "", otherHints: []),
    ErrorData(message: "conditional compilation should have condition expression", mainHint: "", otherHints: []),
    ErrorData(message: "conditional compilation's condition value should be string literal without interpolation", mainHint: "", otherHints: []),
    ErrorData(message: "conditional compilation macro '@If' and '@Else' only support used in block", mainHint: "", otherHints: []),
    ErrorData(message: "unexpected conditional compilation directive", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "No such file or directory: '%s'.", mainHint: "", otherHints: []),
    ErrorData(message: "No such directory: '%s'.", mainHint: "", otherHints: []),
    ErrorData(message: "Not a directory: '%s'.", mainHint: "", otherHints: []),
    ErrorData(message: "Not a file: '%s'.", mainHint: "", otherHints: []),
    ErrorData(message: "Permission denied: '%s'.", mainHint: "", otherHints: []),
    ErrorData(message: "Invalid path: '%s'.", mainHint: "", otherHints: []),
    ErrorData(message: "No such file or directory: '%s', please check if input file exists, separate paths by space if there are multiple input files", mainHint: "", otherHints: []),
    ErrorData(message: "The input file '%s' would be overwritten by the generated output.", mainHint: "", otherHints: []),
    ErrorData(message: "cannot open bitcode file '%s': %s", mainHint: "", otherHints: []),
    ErrorData(message: "failed to parse bitcode file: %s", mainHint: "", otherHints: []),
    ErrorData(message: "invalid package name format in bitcode file: %s", mainHint: "", otherHints: []),
    ErrorData(message: "No such file: '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "No such file or directory: '%s'.%s", mainHint: "", otherHints: []),
    ErrorData(message: "No such directory: '%s'.%s", mainHint: "", otherHints: []),
    ErrorData(message: "Not a directory: '%s'.%s", mainHint: "", otherHints: []),
    ErrorData(message: "Not a file: '%s'.%s", mainHint: "", otherHints: []),
    ErrorData(message: "Permission denied: '%s'.%s", mainHint: "", otherHints: []),
    ErrorData(message: "Invalid path: '%s'.%s", mainHint: "", otherHints: []),
    ErrorData(message: "Not a .%s file: '%s' ('%s').%s", mainHint: "", otherHints: []),
    ErrorData(message: "the arg '%s' may be unused", mainHint: "", otherHints: []),
    ErrorData(message: "the path length for %s is close to the system limit (%s characters). The compilation has a possibility to fail.", mainHint: "", otherHints: []),
    ErrorData(message: "--compile-target only takes effect when --output-type=obj, this option will be ignored in other scenarios", mainHint: "", otherHints: []),
    ErrorData(message: "'--static' option is only effective when compiling executables.", mainHint: "", otherHints: []),
    ErrorData(message: "Statically link packages of the std module is not supported for OHOS", mainHint: "", otherHints: []),
    ErrorData(message: "'--static' option is not supported when targeting '%s'.", mainHint: "", otherHints: []),
    ErrorData(message: "expected one package path to build", mainHint: "", otherHints: []),
    ErrorData(message: "expected one package path to scan dependency", mainHint: "", otherHints: []),
    ErrorData(message: "expect exact one package path to build", mainHint: "", otherHints: []),
    ErrorData(message: "expect exact one .cjo file to scan dependency", mainHint: "", otherHints: []),
    ErrorData(message: "expected one .cjo file to scan dependency", mainHint: "", otherHints: []),
    ErrorData(message: "not accept .cjo inputs when %s is specified", mainHint: "", otherHints: []),
    ErrorData(message: "expected at least one source code file when compiling source code", mainHint: "", otherHints: []),
    ErrorData(message: "source file '%s' doesn't exist", mainHint: "", otherHints: []),
    ErrorData(message: "invalid file or directory '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "invalid binary file '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "unsupported output extension '.%s', extension '.%s' is required", mainHint: "", otherHints: []),
    ErrorData(message: "output to '%s' is not allowed, extension '.%s' is required", mainHint: "", otherHints: []),
    ErrorData(message: "the path length for %s exceeds the system limit (%s characters)", mainHint: "", otherHints: []),
    ErrorData(message: "cpu type '%s' is not supported for the current target", mainHint: "", otherHints: []),
    ErrorData(message: "common .chir files count should be equal to common .cjo files count", mainHint: "", otherHints: []),
    ErrorData(message: "compilation with input object files is currently experimental and requires the --experimental flag to be enabled", mainHint: "", otherHints: []),
    ErrorData(message: "options --static and --dy-std are mutually exclusive", mainHint: "", otherHints: []),
    ErrorData(message: "%s does not support LTO.", mainHint: "", otherHints: []),
    ErrorData(message: "user defined condition should be like: k1=v1,k2=v2 or <directory path of cfg.toml>", mainHint: "", otherHints: []),
    ErrorData(message: "user defined condition in cfg.toml should be like: k1 = \"v1\", and each key-value pair occupies a separate line.", mainHint: "", otherHints: []),
    ErrorData(message: "user defined condition variable should be a vaild identifier", mainHint: "", otherHints: []),
    ErrorData(message: "user defined condition's key can not be the same with builtin condition", mainHint: "", otherHints: []),
    ErrorData(message: "user defined condition's key can not repeat", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' is not a vaild directory path, please check it or pass the key-value pair like: k1=v1,k2=v2.", mainHint: "", otherHints: []),
    ErrorData(message: "read '%s' failed, due to '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "conditional compilation has been set by key-value mode, cfg.toml will be ignored", mainHint: "", otherHints: []),
    ErrorData(message: "--compile-as-exe only takes effect when lto mode is enabled", mainHint: "", otherHints: []),
    ErrorData(message: "Windows, Mac, IOS does not support --compile-as-exe", mainHint: "", otherHints: []),
    ErrorData(message: "--lto-keep-pkg-visibility only takes effect when lto mode is enabled", mainHint: "", otherHints: []),
    ErrorData(message: "--lto-keep-pkg-visibility and --compile-as-exe cannot be used together", mainHint: "", otherHints: []),
    ErrorData(message: "--lto-keep-pkg-visibility only takes effect when outputting a dylib", mainHint: "", otherHints: []),
    ErrorData(message: "option '%s' is deprecated and will be removed in the future", mainHint: "", otherHints: []),
    ErrorData(message: "when having --package flag, not support compiling packages with source file '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "when compiling source file, not support compiling it with directory '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "option '%s' is deprecated and will be removed in future%s.", mainHint: "", otherHints: []),
    ErrorData(message: "using both '--pgo-instr-gen' and '--pgo-instr-use' is not allowed.", mainHint: "", otherHints: []),
    ErrorData(message: "using '--pgo-instr-gen' on ohos targets needs to specify the profile generation path, like '--pgo-instr-gen=/data/storage/el2/base/cjpgo/cj_%m_%p.profraw'.", mainHint: "", otherHints: []),
    ErrorData(message: "Not a .profdata file: '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' is not a valid compiler plugin to be loaded or executed", mainHint: "", otherHints: []),
    ErrorData(message: "exception occurs while executing compiler plugin(s)", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "failed to detect cangjie home, reason: %s", mainHint: "", otherHints: []),
    ErrorData(message: "failed to detect cangjie modules, reason: %s", mainHint: "", otherHints: []),
    ErrorData(message: "can not generate file to path: '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "compilation cache '%s' is missing", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "lex_diag_begin", mainHint: "", otherHints: []),
    ErrorData(message: "unknown start of token: %s", mainHint: "unknown start of token: %s", otherHints: []),
    ErrorData(message: "unexpected digit '%s' in %s", mainHint: "unexpected digit", otherHints: ["because %s"]),
    ErrorData(message: "cannot start a(n) %s literal with a '%s' digit", mainHint: "unexpected digit", otherHints: []),
    ErrorData(message: "expected %s digit, found '%s'", mainHint: "expected %s digit", otherHints: []),
    ErrorData(message: "unexpected decimal point '.' in %s base number", mainHint: "unexpected decimal point", otherHints: ["because of this %s prefix"]),
    ErrorData(message: "unexpected exponent part '%s__' in %s", mainHint: "unexpected exponent part", otherHints: ["because %s"]),
    ErrorData(message: "expected exponent part in hexadecimal float number '%s'", mainHint: "expected exponent part", otherHints: ["because it is hexadecimal float number"]),
    ErrorData(message: "expected identifier after '$', found %s", mainHint: "expected identifier after '$'", otherHints: []),
    ErrorData(message: "unrecognized symbol '%s'", mainHint: "unrecognized symbol", otherHints: []),
    ErrorData(message: "expected identifier, found '%s'", mainHint: "expected identifier", otherHints: []),
    ErrorData(message: "expected '`', found '%s'", mainHint: "expected '`'", otherHints: ["to match this opening backquote"]),
    ErrorData(message: "unterminated single-line string", mainHint: "unterminated single-line string", otherHints: ["because this interpolation is not terminated with a '}'"]),
    ErrorData(message: "unterminated multi-line string", mainHint: "unterminated multi-line string", otherHints: ["because this interpolation is not terminated with a '}'"]),
    ErrorData(message: "unterminated string interpolation", mainHint: "unterminated string interpolation", otherHints: ["because it is in single-line string"]),
    ErrorData(message: "multi-line string must start with newline character", mainHint: "expected to start with newline character", otherHints: ["because it is in multi-line string"]),
    ErrorData(message: "unterminated raw string", mainHint: "unterminated raw string", otherHints: ["because it interpolation is not terminated with a '}'"]),
    ErrorData(message: "expected '#' or '\"' in raw string, found '%s'", mainHint: "expected '#' or '\"'", otherHints: ["because it is raw string prefix"]),
    ErrorData(message: "unrecognized escape '%s' in %s literal", mainHint: "unrecognized escape", otherHints: ["because it is in %s literal"]),
    ErrorData(message: "unterminated block comment", mainHint: "unterminated block comment", otherHints: []),
    ErrorData(message: "expected '{' in unicode escape, found '%s'", mainHint: "expected '{'", otherHints: ["because it is in this Unicode escape"]),
    ErrorData(message: "expected '}', found '%s'", mainHint: "expected '}'", otherHints: ["to match this opening '{'"]),
    ErrorData(message: "expected '}' or hexadecimal digit in unicode escape, found '%s'", mainHint: "expected '}' or hexadecimal digit", otherHints: ["because it is in this Unicode escape"]),
    ErrorData(message: "expected a character in rune literal, found '%s'", mainHint: "expected a character", otherHints: ["because it is in rune literal"]),
    ErrorData(message: "this cannot be an identifier", mainHint: "expected a Unicode XID_Continue after underscore", otherHints: []),
    ErrorData(message: "illegal integer suffix '%s'", mainHint: "expected valid integer type suffix", otherHints: ["invalid type suffix"]),
    ErrorData(message: "illegal float number suffix '%s'", mainHint: "expected valid float number type suffix", otherHints: ["invalid type suffix"]),
    ErrorData(message: "float suffix can only be in decimal", mainHint: "expected valid digits", otherHints: ["invalid type suffix"]),
    ErrorData(message: "expected one character in rune literal", mainHint: "expected one character in rune literal", otherHints: []),
    ErrorData(message: "unterminated rune literal", mainHint: "unterminated rune literal", otherHints: []),
    ErrorData(message: "rune literal may only contain one character", mainHint: "may only contain one character", otherHints: []),
    ErrorData(message: "unknown suffix '%s' for number literal", mainHint: "unknown suffix '%s'", otherHints: []),
    ErrorData(message: "illegal byte '%s' in UTF-8 encoding", mainHint: "illegal byte in UTF-8 encoding", otherHints: []),
    ErrorData(message: "illegal character:%s", mainHint: "illegal character:%s", otherHints: []),
    ErrorData(message: "unsecure character:%s", mainHint: "unsecure character:%s", otherHints: []),
    ErrorData(message: "illegal unicode scalar value '\\u{%s}'", mainHint: "unicode scalar value must be in range '\\u{0000}' to '\\u{D7FF}' or '\\u{E000}' to '\\u{10FFFF}'", otherHints: []),
    ErrorData(message: "%s contains too many digits", mainHint: "too many digits for \\u", otherHints: ["at most 2 digits in an escaped byte character"]),
    ErrorData(message: "unrecognized character '%s' in %s", mainHint: "unrecognized character here", otherHints: ["in %s"]),
    ErrorData(message: "lex_diag_end", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "read file '%s' failed, reason: '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "specify common part path of when compiling specific part of package.", mainHint: "", otherHints: []),
    ErrorData(message: "the file '%s' is a duplicate source file", mainHint: "", otherHints: []),
    ErrorData(message: "ast file for '%s' created by cjc which version is '%s' and current cjc version is '%s', it may cause crash because lack information of declaration", mainHint: "", otherHints: []),
    ErrorData(message: "can't open output file '%s': '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "validation of %s file '%s' failed, please confirm it was created by compiler whose version is '%s'.", mainHint: "", otherHints: []),
    ErrorData(message: "failed to load dependent package '%s' for package '%s', which have same package name with source package", mainHint: "", otherHints: []),
    ErrorData(message: "common part cjo is missing serialized options, possibly compiled by an old cjc", mainHint: "", otherHints: []),
    ErrorData(message: "common part is compiled with different debug mode: %s in common and %s in current", mainHint: "", otherHints: []),
    ErrorData(message: "common part is compiled with different optimization level: %s in common and %s in the current compilation", mainHint: "", otherHints: []),
    ErrorData(message: "packages %s are in circular dependencies.", mainHint: "", otherHints: []),
    ErrorData(message: "common part is for another package '%s', expected the same as for current package '%s'.", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "unsupported %s '%s' when saving AST", mainHint: "", otherHints: []),
    ErrorData(message: "unsupported %s when loading AST", mainHint: "", otherHints: []),
    ErrorData(message: "version of package '%s' and its dependent package '%s' are incompatible", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' is not accessible in package '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "can not find package '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "std lib dependency resolution failed for .bc input: please check the availability of '%s.cjo'", mainHint: "", otherHints: []),
    ErrorData(message: "package '%s' should not import itself", mainHint: "", otherHints: []),
    ErrorData(message: "package '%s' is being compiled with --test-only option, but no dependency for production part of this package provided", mainHint: "", otherHints: []),
    ErrorData(message: "found more than one package declaration for the package", mainHint: "", otherHints: []),
    ErrorData(message: "package name supposed to be '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "package name with macro should be consistent in the same package.", mainHint: "", otherHints: []),
    ErrorData(message: "imported decl '%s' is shadowed, it will be ignored by compiler", mainHint: "", otherHints: []),
    ErrorData(message: "imported decl '%s' is conflicted with other import", mainHint: "", otherHints: []),
    ErrorData(message: "it is not allowed to re-export a macro package in a package.", mainHint: "", otherHints: []),
    ErrorData(message: "The imported cjo file failed verification, the package name is %s which is not '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "dependent package '%s' is compiled with mocking support, the current package must be compiled with mocking support too (pass '%s' compilation option)", mainHint: "", otherHints: []),
    ErrorData(message: "package '%s' is '%s' which cannot be imported by %s package '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "imported package name '%s' cannot be modified by '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "root package can only modified by 'public'", mainHint: "", otherHints: []),
    ErrorData(message: "package must have one visibility level (%s != %s)", mainHint: "", otherHints: []),
    ErrorData(message: "package must be either macro or not", mainHint: "", otherHints: []),
    ErrorData(message: "feature is already declared", mainHint: "", otherHints: []),
    ErrorData(message: "features declaration must be included in every file within the source set where it is used", mainHint: "", otherHints: []),
    ErrorData(message: "feature names must be consistent across all files within a source set", mainHint: "", otherHints: []),
    ErrorData(message: "parent feature set must be subset of child feature set, package: '%s', file with conflicted features: '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "expected %s %s, found %s", mainHint: "expected %s here", otherHints: ["%s"]),
    ErrorData(message: "unexpected '<NL>' between '@' and the macro invocation '%s'", mainHint: "unexpected '<NL>' here", otherHints: []),
    ErrorData(message: "expected identifier or '(' after '$'", mainHint: "", otherHints: []),
    ErrorData(message: "expected type parameters after 'VArray' keyword", mainHint: "", otherHints: []),
    ErrorData(message: "expected %s between '<' and '>' of 'VArray' type", mainHint: "", otherHints: []),
    ErrorData(message: "expected an integer literal than or equal to 0 after '$' to specificate the size of 'VArray' type", mainHint: "", otherHints: []),
    ErrorData(message: "expected '(' or '{' after 'VArray' for 'VArray' constructor", mainHint: "", otherHints: []),
    ErrorData(message: "expected 'import' after module name, found %s", mainHint: "expected 'import' here", otherHints: ["after module name"]),
    ErrorData(message: "unclosed delimiter: '%s'", mainHint: "expected '%s' here", otherHints: ["to match this opening '%s'"]),
    ErrorData(message: "escaped identifier with backticks '%s' is not allowed", mainHint: "don't use backticks here", otherHints: []),
    ErrorData(message: "there should be no return type in a %s", mainHint: "", otherHints: []),
    ErrorData(message: "unmatched delimiter: '%s'", mainHint: "unmatched delimiter", otherHints: []),
    ErrorData(message: "expected literal after '-', found %s", mainHint: "expected literal here", otherHints: ["after this"]),
    ErrorData(message: "expected pattern, found %s", mainHint: "expected pattern here", otherHints: []),
    ErrorData(message: "expected '<-' in %s expression, found %s", mainHint: "expected '<-' here", otherHints: []),
    ErrorData(message: "expected '(' after '%s', found %s", mainHint: "expected '(' here", otherHints: ["after this"]),
    ErrorData(message: "expected '<' after '%s', found %s", mainHint: "expected '<' here", otherHints: ["after this"]),
    ErrorData(message: "expected expression or declaration, found %s", mainHint: "expected expression or declaration here", otherHints: []),
    ErrorData(message: "expected 'catch' or 'finally' after try block, found %s", mainHint: "expected 'catch' or 'finally' here", otherHints: ["after try block"]),
    ErrorData(message: "expected 'catch', 'handle' or 'finally' after try block, found %s", mainHint: "expected 'catch', 'handle' or 'finally' here", otherHints: ["after try block"]),
    ErrorData(message: "expected ':' in exception type pattern, found %s", mainHint: "expected ':' here", otherHints: []),
    ErrorData(message: "expected ':' in effect type pattern, found %s", mainHint: "expected ':' here", otherHints: []),
    ErrorData(message: "expected wildcard or exception type pattern, found %s", mainHint: "expected wildcard or exception type pattern here", otherHints: []),
    ErrorData(message: "expected wildcard or effect type pattern, found %s", mainHint: "expected wildcard or effect type pattern here", otherHints: []),
    ErrorData(message: "expected '=>' in case, found %s", mainHint: "expected '=>' here", otherHints: []),
    ErrorData(message: "expected '(' or '{' after 'match', found %s", mainHint: "expected '(' or '{' here", otherHints: []),
    ErrorData(message: "expected '{', found %s", mainHint: "expected '{' here", otherHints: []),
    ErrorData(message: "expected '(', found %s", mainHint: "expected '(' here", otherHints: []),
    ErrorData(message: "expected 'case' in match, found %s", mainHint: "expected 'case' here", otherHints: []),
    ErrorData(message: "expected '(' after 'quote', found line break", mainHint: "unexpected line break here", otherHints: []),
    ErrorData(message: "expected '(' or '{' after 'try', found %s", mainHint: "expected '(' or '{' here", otherHints: ["after this"]),
    ErrorData(message: "expected '=', found %s", mainHint: "expected '=' here", otherHints: []),
    ErrorData(message: "expected 'in' in for-in expression, found %s", mainHint: "expected 'in' here", otherHints: []),
    ErrorData(message: "expected 'while' in do-while expression, found %s", mainHint: "expected 'while' here", otherHints: []),
    ErrorData(message: "expected '=>' in lambda expression, found %s", mainHint: "expected '=>' here", otherHints: []),
    ErrorData(message: "expected one of ',', ':' or '=>', found %s", mainHint: "expected one of ',', ':' or '=>' here", otherHints: []),
    ErrorData(message: "expected %s, found %s", mainHint: "expected %s here", otherHints: []),
    ErrorData(message: "expected %s after '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "expected '.'", mainHint: "expected '.' here", otherHints: []),
    ErrorData(message: "expected declaration, found %s", mainHint: "expected declaration here", otherHints: []),
    ErrorData(message: "expected identifier or pattern after '%s', found %s", mainHint: "expected identifier or pattern here", otherHints: []),
    ErrorData(message: "expected 'get' or 'set' in prop body, found %s", mainHint: "expected 'get' or 'set' here", otherHints: []),
    ErrorData(message: "expected '{' or 'where', found %s", mainHint: "expected '{' or 'where' here", otherHints: []),
    ErrorData(message: "expected '{' or '<', found %s", mainHint: "expected '{' or '<' here", otherHints: []),
    ErrorData(message: "expected '(' or '<', found %s", mainHint: "expected '(' or '<' here", otherHints: []),
    ErrorData(message: "expected ')' or identifier, found %s", mainHint: "expected ')' or identifier here", otherHints: []),
    ErrorData(message: "expected ',' or ')', found %s", mainHint: "expected ',' or ')' here", otherHints: []),
    ErrorData(message: "expected '->' in function type", mainHint: "", otherHints: []),
    ErrorData(message: "unexpected ':' in index access", mainHint: "unexpected ':' here", otherHints: []),
    ErrorData(message: "expected '[' after '%s', found %s", mainHint: "expected '[' here", otherHints: []),
    ErrorData(message: "expected type argument", mainHint: "", otherHints: []),
    ErrorData(message: "expected one parameter name or ')', found %s", mainHint: "expected one parameter name or ')' here", otherHints: []),
    ErrorData(message: "expected no new-line character after %s", mainHint: "expected no new-line character here", otherHints: ["after %s"]),
    ErrorData(message: "expected '&&', '||', or ')', got 'where'", mainHint: "did you mean to write '&&'", otherHints: []),
    ErrorData(message: "duplicated %s '%s'%s", mainHint: "duplicated %s", otherHints: ["previous one is here"]),
    ErrorData(message: "possibly confusing line terminator", mainHint: "", otherHints: ["possibly confusing line terminator between '%s' and '%s'"]),
    ErrorData(message: "'main' declaration doesn't need 'func' keyword", mainHint: "", otherHints: ["help: try to remove 'func' keyword"]),
    ErrorData(message: "macro declaration must be defined in macro package", mainHint: "expected to be defined in macro package", otherHints: []),
    ErrorData(message: "macro declaration must be modified with 'public'", mainHint: "expected 'public' before here", otherHints: []),
    ErrorData(message: "unexpected empty parameters in macro declaration", mainHint: "expected paratmeters here", otherHints: []),
    ErrorData(message: "too many parameters in macro declaration", mainHint: "too many parameters here", otherHints: []),
    ErrorData(message: "macro declaration's parameter type must be 'Tokens'", mainHint: "expected 'Tokens' here", otherHints: []),
    ErrorData(message: "macro declaration's return type must be 'Tokens'", mainHint: "expected 'Tokens' here, got '%s'", otherHints: []),
    ErrorData(message: "cannot use named parameter in macro declaration", mainHint: "unexpected '!' here", otherHints: ["expected '%s : Tokens' here"]),
    ErrorData(message: "macro declaration name '%s' is conflicted with builtin %s identifier", mainHint: "unexpected macro identifier here", otherHints: []),
    ErrorData(message: "unexpected '[' for builtin macro '%s'", mainHint: "expected '(' here", otherHints: []),
    ErrorData(message: "unexpected %s in %s", mainHint: "unexpected %s", otherHints: ["in %s"]),
    ErrorData(message: "const variable declaration must be initialized", mainHint: "expected a initializer here", otherHints: []),
    ErrorData(message: "unexpected modifier 'const' on var or let variable", mainHint: "unexpected modifier", otherHints: []),
    ErrorData(message: "variable in top-level scope must be initialized ", mainHint: "expected '=' here", otherHints: []),
    ErrorData(message: "variable declaration '%s' needs either type or initializer", mainHint: "expected ':' or '=' after variable name", otherHints: []),
    ErrorData(message: "variable declaration in pattern needs either type or initializer", mainHint: "expected ':' or '=' after pattern", otherHints: []),
    ErrorData(message: "unnamed parameters must come before named parameters", mainHint: "unexpected unnamed parameter here", otherHints: ["because it must come before this named parameter"]),
    ErrorData(message: "regular parameters must come before member variable parameters", mainHint: "unexpected parameter here", otherHints: ["because it must come before this member variable parameter"]),
    ErrorData(message: "declaration '%s' cannot inherit itself", mainHint: "illegal super declaration here", otherHints: ["because '%s' cannot inherit itself"]),
    ErrorData(message: "intrinsic function must be toplevel scope", mainHint: "intrinsic function must be toplevel scope", otherHints: []),
    ErrorData(message: "intrinsic function cannot have body", mainHint: "intrinsic function cannot have body", otherHints: []),
    ErrorData(message: "abstract function must have return type", mainHint: "abstract function must have return type", otherHints: []),
    ErrorData(message: "duplicated '%s' in prop", mainHint: "duplicated '%s'", otherHints: ["previous one"]),
    ErrorData(message: "unknown enum constructor", mainHint: "unknown enum constructor", otherHints: []),
    ErrorData(message: "'%s' cannot be generic", mainHint: "unexpected generic here", otherHints: ["in '%s'"]),
    ErrorData(message: "unexpected 'where' in non-generic declaration", mainHint: "unexpected 'where' here", otherHints: ["because this declaration is non-generic"]),
    ErrorData(message: "setter must contain 1 parameter", mainHint: "expected 1 parameter inside", otherHints: []),
    ErrorData(message: "setter can only accept 1 parameter", mainHint: "can only accept 1 parameter", otherHints: []),
    ErrorData(message: "duplicated intrinsic function '%s'", mainHint: "duplicated intrinsic function", otherHints: ["the previous one is here"]),
    ErrorData(message: "body of %s is missing", mainHint: "missing %s body here", otherHints: []),
    ErrorData(message: "cannot inherit from type: '%s'", mainHint: "this type cannot be inherited", otherHints: []),
    ErrorData(message: "static initializer cannot have any parameter", mainHint: "", otherHints: []),
    ErrorData(message: "finalizer cannot have any parameter", mainHint: "", otherHints: []),
    ErrorData(message: "invalid expression after the operator '$'", mainHint: "", otherHints: []),
    ErrorData(message: "unexpected lambda expression in top-level scope", mainHint: "unexpected lambda expression in top-level scope", otherHints: []),
    ErrorData(message: "trailing closure can only be used on function calls with function or variable names", mainHint: "", otherHints: []),
    ErrorData(message: "invalid left-hand expression of assignment '%s'", mainHint: "", otherHints: ["cannot assign to this expression"]),
    ErrorData(message: "%s operators cannot be chained", mainHint: "", otherHints: []),
    ErrorData(message: "duplicated step operator ':' on range expression", mainHint: "redundant operator", otherHints: ["previous one", "on range expression"]),
    ErrorData(message: "invalid step operator ':' on %s expression", mainHint: "invalid operator", otherHints: ["on %s expression"]),
    ErrorData(message: "expected expression after %s, found %s", mainHint: "expected expression here", otherHints: []),
    ErrorData(message: "cannot %s a un-assignable expression", mainHint: "", otherHints: ["cannot assign to this expression"]),
    ErrorData(message: "unrecognized operator %s after declaration", mainHint: "unrecognized operator", otherHints: ["after declaration"]),
    ErrorData(message: "expected operator or end of expression, found %s", mainHint: "expected operator or end of expression", otherHints: []),
    ErrorData(message: "cannot have assignment expression in initializer", mainHint: "cannot have assignment expression here", otherHints: []),
    ErrorData(message: "match case cannot be empty", mainHint: "match case cannot be empty", otherHints: []),
    ErrorData(message: "resource name '%s' is already defined", mainHint: "redefinition of resource name", otherHints: ["previous one"]),
    ErrorData(message: "unexpected newlines between 'spawn' and the argument followed it", mainHint: "", otherHints: []),
    ErrorData(message: "expected no %s in lambda expression of spawn", mainHint: "cannot contain %s", otherHints: ["in spawn"]),
    ErrorData(message: "cannot overload operator %s ", mainHint: "cannot overload this operator", otherHints: []),
    ErrorData(message: "string interpolation cannot be empty", mainHint: "empty string interpolation", otherHints: []),
    ErrorData(message: "code point '%s' is too large", mainHint: "unrecognized code point", otherHints: []),
    ErrorData(message: "wildcard cannot be used as member name", mainHint: "", otherHints: []),
    ErrorData(message: "unexpected %s", mainHint: "expected %s, found %s", otherHints: []),
    ErrorData(message: "cannot '%s' a tuple", mainHint: "", otherHints: []),
    ErrorData(message: "type before arrow of function type should be surrounded by parentheses", mainHint: "", otherHints: []),
    ErrorData(message: "'This' type is not allowed", mainHint: "", otherHints: []),
    ErrorData(message: "Legacy tuple type syntax no longer allowed after version 0.28.4", mainHint: "use ',' instead", otherHints: []),
    ErrorData(message: "expected type name after %s, found %s", mainHint: "expected type name here", otherHints: ["after %s"]),
    ErrorData(message: "unexpected newlines between '?' and the type followed it", mainHint: "", otherHints: []),
    ErrorData(message: "redundant '->' after function type", mainHint: "", otherHints: []),
    ErrorData(message: "in a parameter type list, either all parameters must be named, or none of them; mixed is not allowed", mainHint: "", otherHints: []),
    ErrorData(message: "unexpected %s", mainHint: "", otherHints: []),
    ErrorData(message: "%s patterns cannot be used in class or struct body", mainHint: "", otherHints: ["in %s body"]),
    ErrorData(message: "'|' is not allowed here", mainHint: "expected ',' or ')', found '|'", otherHints: []),
    ErrorData(message: "1-element tuple pattern is not allowed", mainHint: "1-element tuple pattern is not allowed", otherHints: []),
    ErrorData(message: "type pattern is not allowed in %s expression", mainHint: "type pattern is not allowed here", otherHints: []),
    ErrorData(message: "cannot use 'public' on %s declarations in a macro package", mainHint: "", otherHints: ["macro package defined here"]),
    ErrorData(message: "The alias name should contain '.*' suffix after import-all", mainHint: "expected '%s*'", otherHints: ["after import-all"]),
    ErrorData(message: "length of package name '%s' overflow", mainHint: "length overflow", otherHints: []),
    ErrorData(message: "cannot using '`' in package name", mainHint: "", otherHints: []),
    ErrorData(message: "unexpected '[' after '\\' for macro argument", mainHint: "", otherHints: []),
    ErrorData(message: "unexpected '(' after '\\' for macro attribute argument", mainHint: "", otherHints: []),
    ErrorData(message: "unexpected parameters for macro invocation here", mainHint: "expected declaration like: function, enum, class, interface, variable, property, extend ...", otherHints: []),
    ErrorData(message: "unexpected parameters for macro invocation", mainHint: "expected '(' here", otherHints: []),
    ErrorData(message: "@IfAvailable expect an argument name", mainHint: "", otherHints: []),
    ErrorData(message: "@IfAvailable expect a literal lambda here", mainHint: "", otherHints: []),
    ErrorData(message: "unexpected annotation '%s' on %s", mainHint: "unexpected annotation here", otherHints: ["on %s"]),
    ErrorData(message: "unexpected overflow annotation before '%s'", mainHint: "unexpected overflow annotation", otherHints: ["before this"]),
    ErrorData(message: "unrecognized expression '%s' in annotation '@When'", mainHint: "unrecognized expression here", otherHints: []),
    ErrorData(message: "unrecognized attribute '%s' in annotation '@%s'", mainHint: "unexpected attribute here", otherHints: []),
    ErrorData(message: "empty attribute of annotation '@%s'", mainHint: "empty attribute here", otherHints: []),
    ErrorData(message: "duplicated attribute value: '%s'", mainHint: "duplicated value here", otherHints: ["the previous one is here"]),
    ErrorData(message: "'unsafe' modifier will be ignored in backend '%s'", mainHint: "will be ignored in backend '%s'", otherHints: []),
    ErrorData(message: "duplicated annotation: '%s'", mainHint: "duplicated annotation here", otherHints: ["the previous one is here"]),
    ErrorData(message: "'%s' and '%s' annotations conflict on %s", mainHint: "unexpected annotation", otherHints: ["because it is conflicted with this"]),
    ErrorData(message: "expected annotation '%s'", mainHint: "declare annotation before this", otherHints: []),
    ErrorData(message: "'common' function return type must be specified", mainHint: "", otherHints: []),
    ErrorData(message: "'specific' function return type must be specified", mainHint: "", otherHints: []),
    ErrorData(message: "'specific' %s parameter can not have default value", mainHint: "", otherHints: []),
    ErrorData(message: "the member %s must have body in 'specific' %s", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' %s type must be specified", mainHint: "", otherHints: []),
    ErrorData(message: "%s is %s, but %s is not %s", mainHint: "", otherHints: []),
    ErrorData(message: "static init can not be '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "to compile with common/specific declarations, correct compiler options must be specified", mainHint: "", otherHints: []),
    ErrorData(message: "generic declaration can not be '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "%s pattern can not be '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "at least one constructor is required in common %s '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "only common/specific or Native FFI mirror abstract classes can have explicitly abstract %s", mainHint: "", otherHints: []),
    ErrorData(message: "unexpected modifier '%s' on %s%s", mainHint: "unexpected modifier", otherHints: ["on %s", "in %s"]),
    ErrorData(message: "'%s' and '%s' modifiers conflict on %s", mainHint: "unexpected modifier", otherHints: ["because it is conflicted with this", "on %s"]),
    ErrorData(message: "expected no modifier before %s, found '%s'", mainHint: "expected no modifier here", otherHints: ["before %s"]),
    ErrorData(message: "duplicated modifier: '%s'", mainHint: "duplicated modifier", otherHints: ["previous one is here"]),
    ErrorData(message: "duplicated type parameter name: '%s'", mainHint: "duplicated type parameter name", otherHints: ["previous one is here"]),
    ErrorData(message: "unexpected type in '%s'", mainHint: "unexpected type here", otherHints: ["in %s"]),
    ErrorData(message: "redundant modifier: '%s'", mainHint: "%s implies '%s'", otherHints: []),
    ErrorData(message: "variable length parameter can not be the first parameter", mainHint: "", otherHints: []),
    ErrorData(message: "variable length parameter must in the end of the parameter list", mainHint: "", otherHints: []),
    ErrorData(message: "variable length parameter can only show in the foreign function", mainHint: "", otherHints: []),
    ErrorData(message: "foreign function should not be generic function", mainHint: "", otherHints: []),
    ErrorData(message: "foreign function must declare its return type", mainHint: "", otherHints: []),
    ErrorData(message: "foreign function can not have body", mainHint: "", otherHints: []),
    ErrorData(message: "expected static before const member variable", mainHint: "const member variable must be modified by static", otherHints: []),
    ErrorData(message: "argument '%s' of @Deprecated should be %s", mainHint: "", otherHints: []),
    ErrorData(message: "argument '%s' of @Deprecated can not be duplicated", mainHint: "", otherHints: []),
    ErrorData(message: "argument of @Deprecated is not string literal or boolean value. Variables not allowed", mainHint: "", otherHints: []),
    ErrorData(message: "argument '%s' of @Deprecated must not be empty string", mainHint: "", otherHints: []),
    ErrorData(message: "unknown argument '%s' in @Deprecated", mainHint: "", otherHints: []),
    ErrorData(message: "%s can not be target of @Deprecated", mainHint: "", otherHints: []),
    ErrorData(message: "%s requires zero or one%s argument", mainHint: "expected %s here", otherHints: []),
    ErrorData(message: "%s requires exactly one%s argument", mainHint: "expected %s here", otherHints: []),
    ErrorData(message: "%s accepts no arguments", mainHint: "unexpected argument(s)", otherHints: []),
    ErrorData(message: "@ForeignName could only be used on FFI declaration member", mainHint: "", otherHints: []),
    ErrorData(message: "java-mirrored function '%s' cannot have body", mainHint: "java-mirrored function cannot have body", otherHints: []),
    ErrorData(message: "java-mirrored function must have return type", mainHint: "java-mirrored function must have return type", otherHints: []),
    ErrorData(message: "java-mirrored property is forbidden, use field instead", mainHint: "", otherHints: []),
    ErrorData(message: "java-mirrored declaration cannot have primary constructor", mainHint: "java-mirrored declaration cannot have primary constructor", otherHints: []),
    ErrorData(message: "java-mirrored constructor cannot have body", mainHint: "java-mirrored constructor cannot have body", otherHints: []),
    ErrorData(message: "java-mirrored declaration cannot have private member", mainHint: "", otherHints: []),
    ErrorData(message: "java-mirrored declaration cannot have static initializer", mainHint: "", otherHints: []),
    ErrorData(message: "java-mirrored declaration cannot have finalizer", mainHint: "", otherHints: []),
    ErrorData(message: "java-mirrored declaration cannot have const member", mainHint: "", otherHints: []),
    ErrorData(message: "@JavaMirror declaration cannot be sealed", mainHint: "", otherHints: []),
    ErrorData(message: "@JavaImpl declaration cannot be generic", mainHint: "", otherHints: []),
    ErrorData(message: "@JavaImpl declaration cannot be abstract", mainHint: "", otherHints: []),
    ErrorData(message: "@JavaImpl declaration cannot be sealed", mainHint: "", otherHints: []),
    ErrorData(message: "@JavaImpl declaration cannot have static initializer", mainHint: "", otherHints: []),
    ErrorData(message: "@JavaImpl class cannot be open", mainHint: "", otherHints: []),
    ErrorData(message: "interface cannot be @JavaImpl", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration cannot have primary constructor", mainHint: "@ObjCMirror declaration cannot have primary constructor", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration constructor cannot have body", mainHint: "@ObjCMirror declaration constructor cannot have body", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration method '%s' cannot have body", mainHint: "@ObjCMirror declaration method cannot have body", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration method must have return type", mainHint: "@ObjCMirror declaration method must have return type", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration cannot be sealed", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration cannot have private member", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration cannot have static initializer", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration cannot have finalizer", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration cannot have const member", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCImpl declaration cannot be generic", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCImpl declaration cannot be abstract", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCImpl declaration cannot be sealed", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCImpl declaration cannot have static initializer", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCImpl class cannot be open", mainHint: "", otherHints: []),
    ErrorData(message: "interface cannot be @ObjCImpl", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration field cannot have initializer", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration field cannot be 'static'", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration property '%s' cannot have getter", mainHint: "@ObjCMirror declaration property cannot have getter", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration property '%s' cannot have setter", mainHint: "@ObjCMirror declaration property cannot have setter", otherHints: []),
    ErrorData(message: "@ObjCMirror top-level function '%s' cannot be foreign", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror top-level function '%s' cannot be @C", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror top-level function '%s' cannot be generic", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror top-level function '%s' cannot have body", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror top-level function '%s' must have result type explicitly specified", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror top-level function '%s' cannot be const", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror function '%s' can only be declared on top-level", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCInit method must be modified with 'static'", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCInit method must be declared within '@ObjCMirror' class", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCOptional method must be declared within '@ObjCMirror' interface", mainHint: "", otherHints: []),
    ErrorData(message: "Objective-C interoperability feature '%s' is not yet supported", mainHint: "", otherHints: []),
    ErrorData(message: "%s", mainHint: "%s", otherHints: []),
    ErrorData(message: "%s", mainHint: "%s", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "expected '= or < or <='", mainHint: "", otherHints: []),
    ErrorData(message: "expected '='", mainHint: "", otherHints: []),
    ErrorData(message: "should be identifer, positive integer, 'foo*' or '*foo'", mainHint: "", otherHints: []),
    ErrorData(message: "expected identifier or '( # _'", mainHint: "", otherHints: []),
    ErrorData(message: "expected '&&' or '||', but got '%s' here", mainHint: "", otherHints: []),
    ErrorData(message: "the first element of position tuple should be file id", mainHint: "", otherHints: []),
    ErrorData(message: "the second element of position tuple should be line number", mainHint: "", otherHints: []),
    ErrorData(message: "the third element of position tuple should be column number", mainHint: "", otherHints: []),
    ErrorData(message: "comma required here to seperate position tuple", mainHint: "", otherHints: []),
    ErrorData(message: "the first element of hash id should be file hash", mainHint: "", otherHints: []),
    ErrorData(message: "the second element of hash id should be field id", mainHint: "", otherHints: []),
    ErrorData(message: "Searcher error: id number '%s' past the end of array and it would be ignored.", mainHint: "", otherHints: []),
    ErrorData(message: "Searcher error: number empty.", mainHint: "", otherHints: []),
    ErrorData(message: "Searcher error: number '%s' must be positive integer.", mainHint: "", otherHints: []),
    ErrorData(message: "Searcher error: scope name doesn't support suffix search *'%s'.", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
    ErrorData(message: "semantic error", mainHint: "", otherHints: []),
    ErrorData(message: "unable to infer declaration type, please add type annotation", mainHint: "", otherHints: []),
    ErrorData(message: "mismatched types", mainHint: "expected '%s', found '%s'", otherHints: []),
    ErrorData(message: "mismatched types", mainHint: "the expression has type '%s'", otherHints: []),
    ErrorData(message: "mismatched types", mainHint: "expected '%s', found '%s'", otherHints: ["expected '%s' because of %s"]),
    ErrorData(message: "ambiguous use of '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "undeclared identifier '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "variable '%s' is used before being defined", mainHint: "", otherHints: []),
    ErrorData(message: "redefinition of declaration '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "top-level declaration '%s' is conflicted with possible sub-package '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "class 'Object' of package 'std/core' is not found, cannot use '--no-prelude' option", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' declaration uses %s types", mainHint: "%s '%s' contains %s type", otherHints: []),
    ErrorData(message: "'%s' declaration uses %s types", mainHint: "", otherHints: []),
    ErrorData(message: "mismatched number of parameters", mainHint: "expected '%s', found '%s'", otherHints: []),
    ErrorData(message: "unable to infer return type, please add type annotation", mainHint: "", otherHints: []),
    ErrorData(message: "unable to infer generic argument of this function", mainHint: "", otherHints: []),
    ErrorData(message: "called object is not a function or constructor", mainHint: "", otherHints: []),
    ErrorData(message: "'return' must be used inside a function body", mainHint: "", otherHints: []),
    ErrorData(message: "'return' cannot be used inside the static initializer", mainHint: "", otherHints: []),
    ErrorData(message: "%s for parameter list '%s' in call", mainHint: "expected %s, found %s", otherHints: []),
    ErrorData(message: "positional argument cannot appear after named argument", mainHint: "", otherHints: []),
    ErrorData(message: "parameter name mismatched", mainHint: "", otherHints: []),
    ErrorData(message: "missing argument prefix %s for named parameter", mainHint: "", otherHints: []),
    ErrorData(message: "overloaded operator '[]' can only have one named parameter 'value'", mainHint: "", otherHints: []),
    ErrorData(message: "overloaded operator '[]' should have at least one positional parameter for index", mainHint: "", otherHints: []),
    ErrorData(message: "the return type of subscript assignment must be 'Unit'", mainHint: "", otherHints: []),
    ErrorData(message: "%s '%s' has overload conflicts", mainHint: "", otherHints: []),
    ErrorData(message: "overloaded functions '%s' cannot mix static and non-static", mainHint: "", otherHints: []),
    ErrorData(message: "mutable function '%s' cannot be used alone as reference", mainHint: "", otherHints: []),
    ErrorData(message: "the unsafe function can only be called rather than as name reference", mainHint: "", otherHints: []),
    ErrorData(message: "ambiguous match for function call '%s' of these extended type: %s", mainHint: "", otherHints: []),
    ErrorData(message: "cannot use mutable function on immutable value", mainHint: "is immutable", otherHints: []),
    ErrorData(message: "recursive constructor calling detected", mainHint: "", otherHints: []),
    ErrorData(message: "optional parameter cannot be used in %s function", mainHint: "", otherHints: []),
    ErrorData(message: "trailing lambda cannot be used for %s", mainHint: "declaration type of parameter: '%s'", otherHints: []),
    ErrorData(message: "unable to infer the type of this expression, please add type annotation", mainHint: "", otherHints: []),
    ErrorData(message: "the number '%s' exceeds the value range of type '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "the number '%s' exceeds the value range of floating-point literal", mainHint: "", otherHints: []),
    ErrorData(message: "magnitude of floating-point literal too large for type '%s', maximum is %s", mainHint: "", otherHints: []),
    ErrorData(message: "magnitude of floating-point literal too small for type '%s', minimum is %s", mainHint: "", otherHints: []),
    ErrorData(message: "invalid unary operator '%s' on type '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "invalid unary operator '%s' on type '%s' with return type '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "invalid binary operator '%s' on type '%s' and '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "invalid subscript operator [] on type '%s' with index %s", mainHint: "", otherHints: []),
    ErrorData(message: "cannot assign to this subscript expression", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' is not a member of %s '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' is not imported", mainHint: "", otherHints: []),
    ErrorData(message: "cannot assign to immutable value", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' can not be assigned", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' is not found for generic type '%s' in its upper bounds", mainHint: "", otherHints: []),
    ErrorData(message: "patterns connected by '|' should be of the same kind", mainHint: "%s", otherHints: []),
    ErrorData(message: "cannot introduce variables in patterns connected by '|'", mainHint: "", otherHints: []),
    ErrorData(message: "cannot introduce variables in conditions connected by '||'", mainHint: "", otherHints: []),
    ErrorData(message: "non-exhaustive patterns", mainHint: "the selector is of type '%s'", otherHints: []),
    ErrorData(message: "unreachable pattern", mainHint: "", otherHints: []),
    ErrorData(message: "parameters of this lambda expression must have type annotations", mainHint: "", otherHints: []),
    ErrorData(message: "%s capturing mutable variables needs to be called directly", mainHint: "", otherHints: []),
    ErrorData(message: "enum constructor '%s' must be used with arguments", mainHint: "", otherHints: []),
    ErrorData(message: "cannot use optional chaining", mainHint: "cannot use optional chaining on non-optional value of type '%s'", otherHints: []),
    ErrorData(message: "cannot capture variable '%s' before initialization", mainHint: "", otherHints: []),
    ErrorData(message: "cannot use string interpolation in constant pattern", mainHint: "", otherHints: []),
    ErrorData(message: "package name cannot be referred independently", mainHint: "", otherHints: []),
    ErrorData(message: "import '%s' to use the '%s' expression", mainHint: "", otherHints: []),
    ErrorData(message: "type arguments needed for the generic function%s", mainHint: "cannot infer type arguments for the generic function", otherHints: []),
    ErrorData(message: "generic types substitutions are inconsistent for '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "type argument's number does not match type parameter's number", mainHint: "", otherHints: []),
    ErrorData(message: "the constraint of type parameter is not looser than parent's constraint", mainHint: "", otherHints: []),
    ErrorData(message: "generic instantiation '%s' causes ambiguous function '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "generic parameter '%s' cannot have two or more class upper bounds '%s' without subtype relation", mainHint: "", otherHints: []),
    ErrorData(message: "generic parameter '%s' cannot be used in class irrelevant upper bounds '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "generic parameter '%s' is bounded directly recursively with '%s' which is forbidden", mainHint: "", otherHints: []),
    ErrorData(message: "the upper bound '%s' of generic parameter '%s' must be class or interface", mainHint: "", otherHints: []),
    ErrorData(message: "%s member '%s' cannot have the same name with %s member in %s", mainHint: "", otherHints: []),
    ErrorData(message: "inherited members '%s' have inconsistent decl types", mainHint: "", otherHints: []),
    ErrorData(message: "%s of the inherited %s members '%s' are not identical and not in subtype relation", mainHint: "", otherHints: []),
    ErrorData(message: "abstract class '%s' cannot contain unimplemented static %s '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "cannot override %s '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "the visibility of an '%s' %s must be 'public' or 'protected'", mainHint: "", otherHints: []),
    ErrorData(message: "a deriving member must be at least as visible as its base member", mainHint: "%s", otherHints: []),
    ErrorData(message: "cannot %s %s 'sealed' %s '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "user defined decl '%s' not support to inherit, implement or extend 'ThreadContext'", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' cannot be modified with 'open' when inherit, implement or extend 'ThreadContext'", mainHint: "", otherHints: []),
    ErrorData(message: "an open function that returns 'This' must keep the return type 'This' when overridden", mainHint: "", otherHints: []),
    ErrorData(message: "return type of '%s' is not identical or not a subtype of the overridden/redefined/implement function", mainHint: "", otherHints: []),
    ErrorData(message: "invalid argument of spawn expr, user-defined `ThreadContext` types are prohibited now", mainHint: "", otherHints: []),
    ErrorData(message: "argument of spawn expr does not take effect at current backend", mainHint: "", otherHints: []),
    ErrorData(message: "'spawn' expressions cannot capture mutable variables; consider using 'let' or boxing", mainHint: "", otherHints: []),
    ErrorData(message: "static invocation contains unimplemented static %s '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "the static member variable '%s' is not initialized", mainHint: "", otherHints: []),
    ErrorData(message: "instance %s cannot be used in the finalizer", mainHint: "", otherHints: []),
    ErrorData(message: "there is no non-parameter constructor in super class, please invoke super call explicitly", mainHint: "", otherHints: []),
    ErrorData(message: "non-abstract class cannot be modified by 'sealed'", mainHint: "", otherHints: []),
    ErrorData(message: "static member cannot depend on generic parameter '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "struct with @C cannot implement interfaces", mainHint: "", otherHints: []),
    ErrorData(message: "class '%s' missing abstract modifier, otherwise abstract function or property should be implemented", mainHint: "", otherHints: []),
    ErrorData(message: "implementation of function or property is needed in '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "currently, it is not possible to export two private declarations with the same name", mainHint: "", otherHints: []),
    ErrorData(message: "cannot override %s '%s' in extend of supertype", mainHint: "", otherHints: []),
    ErrorData(message: "extend member '%s' is not allowed to shadow members of '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "extending type '%s' is not allowed", mainHint: "", otherHints: []),
    ErrorData(message: "type parameter%s must be used in extended type", mainHint: "", otherHints: []),
    ErrorData(message: "interface '%s' has been implemented by '%s', please remove it", mainHint: "", otherHints: []),
    ErrorData(message: "expected an interface, found non-interface type", mainHint: "expected an interface here", otherHints: []),
    ErrorData(message: "illegal extend member, only functions, props, associated types are allowed", mainHint: "", otherHints: []),
    ErrorData(message: "'super' is not allowed inside an extend declaration", mainHint: "", otherHints: []),
    ErrorData(message: "%s type '%s' cannot extend imported interface", mainHint: "", otherHints: []),
    ErrorData(message: "c type '%s' cannot support interface extend", mainHint: "", otherHints: []),
    ErrorData(message: "it's illegal to extend index assignment operator '[](index, value)' for immutable type", mainHint: "", otherHints: []),
    ErrorData(message: "there cannot have mutable property in immutable type", mainHint: "", otherHints: []),
    ErrorData(message: "interface '%s' is not able to be extended", mainHint: "", otherHints: []),
    ErrorData(message: "'mut' modifier is illegal in extend body of '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "unable to decide which extension happens first", mainHint: "", otherHints: []),
    ErrorData(message: "exported extension cannot indirectly export the functions '%s' of the non-exported extension", mainHint: "", otherHints: []),
    ErrorData(message: "property must have accessors", mainHint: "", otherHints: []),
    ErrorData(message: "immutable property cannot have setter", mainHint: "", otherHints: []),
    ErrorData(message: "property '%s' should have 'mut' modifier", mainHint: "", otherHints: []),
    ErrorData(message: "property '%s' should be immutable", mainHint: "", otherHints: []),
    ErrorData(message: "property must implement both getter/setter of interface property '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "expected 'const' %s", mainHint: "%s", otherHints: []),
    ErrorData(message: "cannot define 'var' variable in 'const' function", mainHint: "", otherHints: []),
    ErrorData(message: "cannot define 'const' member function without 'const' constructor", mainHint: "", otherHints: []),
    ErrorData(message: "cannot define 'const' constructor with 'var' members in class", mainHint: "", otherHints: []),
    ErrorData(message: "class with '@Annotation' should have 'const' constructor", mainHint: "", otherHints: []),
    ErrorData(message: "'@Annotation' can only have one named argument 'target'", mainHint: "", otherHints: []),
    ErrorData(message: "the argument of '@Annotation' should be array literal", mainHint: "", otherHints: []),
    ErrorData(message: "'@Annotation' modifying non-'public' class is invisible at runtime", mainHint: "", otherHints: []),
    ErrorData(message: "cannot use custom annotation", mainHint: "", otherHints: []),
    ErrorData(message: "the expression qualified by 'inout' cannot be of %s", mainHint: "", otherHints: []),
    ErrorData(message: "the type of experssion qualified by 'inout' must meet 'CType' constraint", mainHint: "", otherHints: []),
    ErrorData(message: "'inout' can only qualify variable defined with 'var'", mainHint: "%s", otherHints: []),
    ErrorData(message: "the variable qualified by 'inout' cannot be directly or indirectly derived from an instance of a 'class'", mainHint: "", otherHints: []),
    ErrorData(message: "'inout' can only be used in a 'CFunc' calling", mainHint: "", otherHints: []),
    ErrorData(message: "mismatch 'inout' of function argument with type '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' should have %s arg", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' only supports %s as arg", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' can only modify %s", mainHint: "", otherHints: []),
    ErrorData(message: "type annotated with '@Java[\"ext\"]' can only be used within the declaration which has '@Java[\"ext\"]' annotation", mainHint: "", otherHints: []),
    ErrorData(message: "%s type in %s '%s' with '@Java' must meet JType constraint", mainHint: "", otherHints: []),
    ErrorData(message: "%s type in %s '%s' with '@Java' can not be 'Unit'", mainHint: "", otherHints: []),
    ErrorData(message: "only types annotated with '@Java[\"ext\"] can %s from a type annotated with '@Java[\"ext\"]'", mainHint: "", otherHints: []),
    ErrorData(message: "%s is not supported in %s '%s' annotated with '@Java'", mainHint: "", otherHints: []),
    ErrorData(message: "%s '%s' should have '@Java' annotation", mainHint: "", otherHints: []),
    ErrorData(message: "cannot access static member with generic parameter in '@Java' types", mainHint: "", otherHints: []),
    ErrorData(message: "only reference types are available for '@Java' generics", mainHint: "", otherHints: []),
    ErrorData(message: "types that meet constraints by 'extend' cannot be used in '@Java' generics", mainHint: "", otherHints: []),
    ErrorData(message: "static functions in '@Java'-annotated interfaces must have a body", mainHint: "", otherHints: []),
    ErrorData(message: "types annotated with '@Java' cannot be extended", mainHint: "", otherHints: []),
    ErrorData(message: "generic type's upper bound in types annotated with '@Java' should be annotated with '@Java' too", mainHint: "", otherHints: []),
    ErrorData(message: "types annotated with '@Java' cannot be annotated with '@Annotation' together", mainHint: "", otherHints: []),
    ErrorData(message: "imported Java annotations can only be used with types annotated with '@Java'", mainHint: "", otherHints: []),
    ErrorData(message: "only imported Java annotations can be used with types annotated with '@Java'", mainHint: "", otherHints: []),
    ErrorData(message: "'@%s' not applicable to %s", mainHint: "", otherHints: []),
    ErrorData(message: "cannot use annotation here", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' is not allowd to be used here as type argument, because it shadows field '%s' with its super type '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "type argument in java interoperation should meet 'JType' constraint", mainHint: "", otherHints: []),
    ErrorData(message: "cangjie mirror struct type generic %s is not supported", mainHint: "", otherHints: []),
    ErrorData(message: "cangjie mirror struct type inheritance interface is not supported", mainHint: "", otherHints: []),
    ErrorData(message: "cangjie mirror decl type is not supported for %s", mainHint: "", otherHints: []),
    ErrorData(message: "argument type of cangjie mirror decl type member function is not supported", mainHint: "", otherHints: []),
    ErrorData(message: "return type '%s' of function inside %s type is not supported", mainHint: "", otherHints: []),
    ErrorData(message: "Instance configuration '%s' has incorrect format.", mainHint: "", otherHints: []),
    ErrorData(message: "mismatch 'VArray' type's size", mainHint: "expected size is %s, found %s", otherHints: []),
    ErrorData(message: "'VArray' constructor accepts only one argument", mainHint: "", otherHints: []),
    ErrorData(message: "'VArray' accepts exactly one subscript index with type of 'Int64'", mainHint: "", otherHints: []),
    ErrorData(message: "return type of CFunc cannot be 'VArray' type", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' directly or indirectly contains an unsupported type", mainHint: "contain unsupported instance member variable with type '%s'", otherHints: []),
    ErrorData(message: "only CFunc can use '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "'@CallingConv' have not supported '%s' yet", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' arg should be right type", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' can only be used in top-level scope", mainHint: "", otherHints: []),
    ErrorData(message: "return type of CFunc must be instantiated with CType", mainHint: "", otherHints: []),
    ErrorData(message: "mocking features are disabled, you can enable them by passing %s compilation option explicitly, or using default mode", mainHint: "", otherHints: []),
    ErrorData(message: "mocking features can be used only in the test mode, please pass %s compilation option to compile the package in the test mode", mainHint: "", otherHints: []),
    ErrorData(message: "only mocking of classes or interfaces is supported", mainHint: "", otherHints: []),
    ErrorData(message: "static/top-level declaration to mock shouldn't be private, local, constant or constructor", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' doesn't support mocking, please be sure that its package '%s' is mock-compatible (was compiled with %s compilation option)", mainHint: "", otherHints: []),
    ErrorData(message: "mocking of frozen declarations (marked with @Frozen annotation) are not supported", mainHint: "", otherHints: []),
    ErrorData(message: "generic wrapper function '%s' for createMock/createSpy calls should be marked with @Frozen annotation", mainHint: "", otherHints: []),
    ErrorData(message: "the command handle type must implement 'effect.Command<T>'", mainHint: "", otherHints: []),
    ErrorData(message: "the type of the resumption must extend 'effect.Resumption'", mainHint: "", otherHints: []),
    ErrorData(message: "the return type of the resumption ('%s') does not match the type of the try block ('%s')", mainHint: "", otherHints: []),
    ErrorData(message: "the parameter type of the resumption ('%s') does not match the result type of the command ('%s')", mainHint: "", otherHints: []),
    ErrorData(message: "'resume' outside of an immediate handler must have a resumption argument", mainHint: "", otherHints: []),
    ErrorData(message: "a resumption of non-Unit type '%s' must have a 'with' or 'throwing' clause", mainHint: "", otherHints: []),
    ErrorData(message: "resumptions must be of type 'core.Resumption<T>', but actual type is '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "The type of this handle block is '%s', which mismatches the smallest common supertype '%s' of previous branches.", mainHint: "", otherHints: []),
    ErrorData(message: "Return statements are not allowed within try/handle blocks", mainHint: "", otherHints: []),
    ErrorData(message: "'try'-'handle' expressions cannot capture mutable variables; consider using 'let' or boxing", mainHint: "", otherHints: []),
    ErrorData(message: "type '%s' does not implement compatible instantiations of 'Command<T>'", mainHint: "", otherHints: []),
    ErrorData(message: "the type of the `resume throwing` must be a subtype of core.Exception or core.Error", mainHint: "", otherHints: []),
    ErrorData(message: "useless command type", mainHint: "", otherHints: []),
    ErrorData(message: "%s '%s' is deprecated%s%s", mainHint: "deprecated", otherHints: []),
    ErrorData(message: "%s '%s' is deprecated%s%s", mainHint: "deprecated", otherHints: []),
    ErrorData(message: "strictness of @Deprecated can not be weaken on inheritors", mainHint: "", otherHints: []),
    ErrorData(message: "overridden %s '%s' should be marked with @Deprecated", mainHint: "", otherHints: []),
    ErrorData(message: "overridden %s '%s' should be marked with @Deprecated", mainHint: "", otherHints: []),
    ErrorData(message: "redefined %s '%s' should be marked with @Deprecated", mainHint: "", otherHints: []),
    ErrorData(message: "redefined %s '%s' should be marked with @Deprecated", mainHint: "", otherHints: []),
    ErrorData(message: "please implement the constructor explicitly for common open class '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "'common' %s has several specific implementations", mainHint: "", otherHints: []),
    ErrorData(message: "declaration 'common' extend '%s' has a conflicting private %s '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "'common' and 'private' modifier conflict on %s '%s' declaration", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' %s can not find '%s' match", mainHint: "", otherHints: []),
    ErrorData(message: "'specific' '%s' can not match 'common' '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "'specific' init can not be used to implement primary 'common' constructor", mainHint: "", otherHints: []),
    ErrorData(message: "'specific' decl kind(%s) is not equal to 'common'(%s)", mainHint: "", otherHints: []),
    ErrorData(message: "parameter in 'specific' primary constructor must also be a member variable declaration if it's a member variable declaration in 'common' primary constructor", mainHint: "", otherHints: []),
    ErrorData(message: "exhaustive 'common' %s cannot be matched with non-exhaustive 'specific' %s", mainHint: "", otherHints: []),
    ErrorData(message: "'specific' %s type is not equal to 'common' type", mainHint: "", otherHints: []),
    ErrorData(message: "the member %s must have body in 'specific' %s", mainHint: "", otherHints: []),
    ErrorData(message: "'specific' %s modifier is not match 'common' modifier", mainHint: "", otherHints: []),
    ErrorData(message: "'specific' %s annotation is not match 'common' annotation", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' annotation is not allowed on specific %s '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "parameter default value should be on either 'common' or 'specific' side, not both", mainHint: "", otherHints: []),
    ErrorData(message: "'specific' function parameter is not match 'common' parameter", mainHint: "", otherHints: []),
    ErrorData(message: "'specific' %s super types is not match 'common' super types", mainHint: "", otherHints: []),
    ErrorData(message: "declaration 'specific' extend '%s' has a conflicting extension", mainHint: "", otherHints: []),
    ErrorData(message: "main function cannot be used in common package part", mainHint: "", otherHints: []),
    ErrorData(message: "'common' static let '%s' can not be initialized in static init", mainHint: "", otherHints: []),
    ErrorData(message: "cannot assign to immutable variable '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "'%s' abstract class %s must have explicit '%s' or 'abstract' modifier", mainHint: "", otherHints: []),
    ErrorData(message: "abstract %s can not have body", mainHint: "", otherHints: []),
    ErrorData(message: "only common/specific class can have explicitly abstract %s", mainHint: "", otherHints: []),
    ErrorData(message: "open common %s can not be overridden with abstract specific %s", mainHint: "", otherHints: []),
    ErrorData(message: "specific abstract class '%s' cannot have non-specific abstract %s", mainHint: "", otherHints: []),
    ErrorData(message: "common/specific declaration %s with generics cannot be @Frozen", mainHint: "", otherHints: []),
    ErrorData(message: "common/specific generic rename is not supported yet", mainHint: "", otherHints: []),
    ErrorData(message: "annotation %s is not allowed on a common/specific declaration", mainHint: "", otherHints: []),
    ErrorData(message: "argument type of java-mirrored constructor must be of @JavaMirror type", mainHint: "", otherHints: []),
    ErrorData(message: "argument type of java-mirrored function must be of @JavaMirror type", mainHint: "", otherHints: []),
    ErrorData(message: "return type '%s' of function inside %s class is not supported", mainHint: "", otherHints: []),
    ErrorData(message: "property of java-mirrored declaration must be of @JavaMirror type", mainHint: "", otherHints: []),
    ErrorData(message: "super declaration '%s' is inheritable only for declaration annotated with @JavaMirror or @JavaImpl", mainHint: "", otherHints: []),
    ErrorData(message: "@JavaMirror-annotated declaration cannot inherit pure cangjie type", mainHint: "", otherHints: []),
    ErrorData(message: "@JavaImpl-annotated declaration cannot inherit pure cangjie type", mainHint: "", otherHints: []),
    ErrorData(message: "@JavaImpl-annotated declaration must inherit @JavaMirror-annotated declaration", mainHint: "", otherHints: []),
    ErrorData(message: "@JavaMirror class cannot be extended with interface", mainHint: "", otherHints: []),
    ErrorData(message: "@JavaImpl class cannot be extended with interface", mainHint: "", otherHints: []),
    ErrorData(message: "redefinition of java declaration '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "java.lang must be imported to use java interoperability", mainHint: "", otherHints: []),
    ErrorData(message: "Java interoperability feature '%s' is not yet supported", mainHint: "", otherHints: []),
    ErrorData(message: "extend declaration ref target cannot be java impl", mainHint: "", otherHints: []),
    ErrorData(message: "Can not instantiate generic '%s' with java interoperability type '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "java.internal runtime version cannot be determined, compiler was built expecting version '%s'. Compatibility problems could happen. Use it at your own risk", mainHint: "", otherHints: []),
    ErrorData(message: "java.internal runtime version is '%s', but compiler was built expecting version '%s'. Compatibility problems could happen. Use it at your own risk", mainHint: "", otherHints: []),
    ErrorData(message: "'@JavaHasDefault' can't have arguments", mainHint: "", otherHints: []),
    ErrorData(message: "'@JavaHasDefault' can be used only on @JavaMirror interface methods.", mainHint: "", otherHints: []),
    ErrorData(message: "Illegal combination of '@JavaHasDefault' annotation and 'static' modifier.", mainHint: "", otherHints: []),
    ErrorData(message: "param type of %s constructor must be Objective-C compatible", mainHint: "", otherHints: []),
    ErrorData(message: "param type of %s method must be Objective-C compatible", mainHint: "", otherHints: []),
    ErrorData(message: "return type of %s method must be Objective-C compatible", mainHint: "", otherHints: []),
    ErrorData(message: "%s property type must be Objective-C compatible", mainHint: "", otherHints: []),
    ErrorData(message: "%s field type must be Objective-C compatible", mainHint: "", otherHints: []),
    ErrorData(message: "Objective-C mirror cannot inherit other supertypes", mainHint: "", otherHints: []),
    ErrorData(message: "Objective-C mirror subtype cannot inherit multiple types (only 1 interface or 1 class is allowed)", mainHint: "", otherHints: []),
    ErrorData(message: "Objective-C mirror subtype must be annotated with @ObjCMirror or @ObjCImpl", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCImpl declaration must inherit @ObjCMirror", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCMirror declaration cannot inherit not @ObjCMirror declarations", mainHint: "", otherHints: []),
    ErrorData(message: "objc.lang must be imported to use Objective-C interoperability", mainHint: "", otherHints: []),
    ErrorData(message: "Objective-C interoperability feature '%s' is not yet supported", mainHint: "", otherHints: []),
    ErrorData(message: "ObjCPointer can only be used with Objective-C compatible types", mainHint: "", otherHints: []),
    ErrorData(message: "param type of Objective-C mirror top-level function '%s' must be Objective-C compatible", mainHint: "", otherHints: []),
    ErrorData(message: "return type of Objective-C mirror top-level function '%s' must be Objective-C compatible", mainHint: "", otherHints: []),
    ErrorData(message: "%s declaration method '%s' with more than one parameter must have @ForeignName annotation", mainHint: "%s declaration method with more than one parameter must have must have @ForeignName annotation", otherHints: []),
    ErrorData(message: "%s declaration constructor with more than one parameter must have @ForeignName annotation", mainHint: "", otherHints: []),
    ErrorData(message: "%s can only be used with function type over Objective-C compatible types", mainHint: "", otherHints: []),
    ErrorData(message: "%s property 'call' can only be called directly, no other operations are permitted", mainHint: "", otherHints: []),
    ErrorData(message: "@ObjCImpl class must have @ObjCMirror super class", mainHint: "", otherHints: []),
    ErrorData(message: "@ForeignSetterName cannot be specified on immutable property", mainHint: "", otherHints: []),
    ErrorData(message: "cangjie mirror decl type inheritance interface is not supported", mainHint: "", otherHints: []),
    ErrorData(message: "cangjie mirror decl type generic %s is not supported", mainHint: "", otherHints: []),
    ErrorData(message: "@%s could not appear on overridden declaration", mainHint: "", otherHints: []),
    ErrorData(message: "Declaration '%s' has a conflicting @%s annotation", mainHint: "", otherHints: []),
    ErrorData(message: "Declaration '%s' has a conflicting derived @%s '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "the first argument of @IfAvailable expression must have a name", mainHint: "", otherHints: []),
    ErrorData(message: "the first argument of @IfAvailable expression must be a literal expression", mainHint: "", otherHints: []),
    ErrorData(message: "unknown parameter name '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "annotate more than one '@!APILevel'", mainHint: "", otherHints: []),
    ErrorData(message: "'@!APILevel' annotation provides no valid '%s'; any accompanying error explains the specific cause", mainHint: "", otherHints: []),
    ErrorData(message: "invalid version format '%s' in @!APILevel 'since', expected 'major[.minor[.patch]]' with non-negative integers", mainHint: "", otherHints: []),
    ErrorData(message: "only %s literal values are supported for now", mainHint: "", otherHints: []),
    ErrorData(message: "cannot reference '%s'(level: %s) which higher than level of the current scope(level: %s)", mainHint: "", otherHints: []),
    ErrorData(message: "inappropriate syscap '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "inappropriate syscap '%s'", mainHint: "", otherHints: []),
    ErrorData(message: "declaration mark with different syscap", mainHint: "", otherHints: []),
    ErrorData(message: "'@!APILevel' no longer accepts an integer version literal; use '@!APILevel[since: \"X.Y.Z\"]' with a dotted semantic version string instead", mainHint: "", otherHints: []),
    ErrorData(message: "`@IfAvaliable` feature is not avaliable in device where the APILevel is less than 19 due to missing capatability in ROM", mainHint: "", otherHints: []),
    ErrorData(message: "cannot be annotated with '@!Hide' more than once", mainHint: "", otherHints: []),
    ErrorData(message: "function parameter cannot be annotated with '@!Hide'", mainHint: "", otherHints: []),
    ErrorData(message: "should be marked with '@!Hide' to be hidden", mainHint: "", otherHints: []),
    ErrorData(message: "'@!Hide' annotation must be visible at compile time", mainHint: "", otherHints: []),
    ErrorData(message: "the parameter 'isChecked' of '@!Hide' is %s", mainHint: "", otherHints: []),
    ErrorData(message: "annotation '%s' must be placed below all macros and annotations", mainHint: "", otherHints: []),
    ErrorData(message: "unused import '%s'", mainHint: "unused import", otherHints: []),
    ErrorData(message: "", mainHint: "", otherHints: []),
]

public let rDiagSeveritys: Array<DiagSeverity> = [
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_ERROR,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_WARNING,
    DiagSeverity.DS_ERROR,
]

public let rWarnGroups: Array<WarnGroup> = [
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.UNUSED,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DRIVER_ARG,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.DRIVER_ARG,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.DRIVER_ARG,
    WarnGroup.DEPRECATED,
    WarnGroup.UNSUPPORT_COMPILE_SOURCE,
    WarnGroup.UNSUPPORT_COMPILE_SOURCE,
    WarnGroup.DEPRECATED,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.PARSER,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.PACKAGE_IMPORT,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.DEPRECATED,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.PACKAGE_IMPORT,
    WarnGroup.PACKAGE_IMPORT,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.PACKAGE_IMPORT,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.PARSER,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.PARSER,
    WarnGroup.PARSER,
    WarnGroup.PARSER,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.PARSER,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.PARSER,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.UNGROUPED,
    WarnGroup.UNGROUPED,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.UNUSED,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.UNGROUPED,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.UNGROUPED,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.UNUSED,
    WarnGroup.NONE,
    WarnGroup.DEPRECATED,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.DEPRECATED,
    WarnGroup.NONE,
    WarnGroup.DEPRECATED,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.UNGROUPED,
    WarnGroup.UNGROUPED,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.APILEVEL_CHECK,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.APILEVEL_CHECK,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.NONE,
    WarnGroup.APILEVEL_CHECK,
    WarnGroup.UNUSED,
    WarnGroup.NONE,
]

public let warnGroupDescrs: Array<String> = [
    "unused",
    "unused-main",
    "driver-arg",
    "deprecated",
    "unsupport-compile-source",
    "package-import",
    "parser",
    "semantics",
    "interpreter",
    "apilevel-check",
]
public let WARN_GROUP_DESCRS_SIZE: Int64 = 10

public let RE_DIAG_KIND_STR: Array<String> = [
    "chir_diag_begin",
    "chir_used_before_initialization",
    "chir_illegal_usage_of_member",
    "chir_cannot_assign_initialized_let_variable",
    "chir_class_uninitialized_field",
    "chir_illegal_usage_of_super_member",
    "chir_arithmetic_operator_overflow",
    "chir_idx_out_of_bounds",
    "chir_divisor_is_zero",
    "chir_shift_length_overflow",
    "chir_typecast_overflow",
    "chir_step_non_zero_range",
    "chir_dce_unreachable_statement",
    "chir_dce_unreachable_function",
    "chir_dce_unreachable_return",
    "chir_dce_unreachable_if",
    "chir_dce_unreachable",
    "chir_dce_unreachable_expression_hint",
    "chir_dce_unreachable_block_in_expression",
    "chir_dce_unreachable_block",
    "chir_dce_unused_expression",
    "chir_dce_unused_function",
    "chir_dce_unused_function_main",
    "chir_dce_unreachable_expression",
    "chir_dce_unused_variable",
    "chir_dce_unused_operator",
    "chir_unreachable_pattern",
    "chir_eval_support",
    "chir_annotation_not_applicable",
    "chir_diag_end",
    "conditional_compilation_diag_begin",
    "conditional_compilation_not_support_op",
    "conditional_compilation_not_support_this_condition",
    "conditional_compilation_not_support_builtin_value",
    "conditional_compilation_not_support_cjc_version_format",
    "conditional_compilation_invalid_condition_expr",
    "conditional_compilation_not_have_condition_expr",
    "conditional_compilation_invalid_condition_value",
    "conditional_compilation_just_support_block",
    "conditional_compilation_unexpected_after_macro",
    "conditional_compilation_diag_end",
    "driver_diag_begin",
    "no_such_file_or_directory",
    "no_such_directory",
    "not_a_directory",
    "not_a_file",
    "permission_denied",
    "invalid_path",
    "no_such_file_or_directory_of_macro_obj",
    "input_file_overwritten_by_generated_output",
    "bc_file_open_failed",
    "bc_parse_failed",
    "bc_invalid_package_name",
    "driver_warning_no_such_file",
    "driver_warning_no_such_file_or_directory",
    "driver_warning_no_such_directory",
    "driver_warning_not_a_directory",
    "driver_warning_not_a_file",
    "driver_warning_permission_denied",
    "driver_warning_invalid_path",
    "driver_warning_unexpected_file_extension",
    "driver_warning_argument_unused",
    "driver_warning_path_close_to_length_limit",
    "driver_invalid_compile_target",
    "driver_warning_unusable_static",
    "driver_static_std_for_ohos",
    "driver_warning_no_support_static",
    "driver_require_package_directory",
    "driver_require_package_directory_scan_dependency",
    "driver_require_one_package_directory",
    "driver_require_one_package_directory_scan_dependency",
    "driver_source_cjo_empty",
    "driver_not_accept_cjo_inputs_when",
    "driver_source_file_empty",
    "driver_invalid_source_file",
    "driver_invalid_file_or_directory",
    "driver_invalid_binary_file",
    "driver_invalid_unsupport_extension",
    "driver_invalid_require_extension",
    "driver_path_exceeds_length_limit",
    "driver_unsupported_target_cpu",
    "driver_require_common_chir_for_each_common_cjo",
    "driver_require_experimental",
    "driver_static_dystd_conflict",
    "driver_target_lto_unsupported",
    "driver_cfg_value_err",
    "driver_cfg_toml_content_err",
    "dirver_cfg_invaild_identifier",
    "dirver_cfg_same_with_builtin",
    "dirver_cfg_key_repeat",
    "dirver_cfg_not_a_dir",
    "driver_cfg_file_read_failed",
    "driver_cfg_path_ignored",
    "driver_invalid_compile_as_exe",
    "driver_invalid_compile_as_exe_platform",
    "driver_invalid_visible_pkgs",
    "driver_invalid_visible_pkgs_conflict",
    "driver_visible_pkgs_only_for_dylib",
    "driver_useless_option",
    "driver_unsupport_compile_package_with_source_file",
    "driver_unsupport_compile_source_file_with_path",
    "driver_deprecated_option",
    "driver_pgo_both_gen_and_use",
    "driver_ohos_pgo_gen_without_file",
    "driver_pgo_invalid_profile_extension",
    "not_a_valid_plugin",
    "plugin_throws_exception",
    "driver_diag_end",
    "frontend_diag_begin",
    "frontend_failed_to_detect_cangjie_home",
    "frontend_failed_to_detect_cangjie_modules",
    "frontend_invalid_output_path",
    "frontend_diag_end",
    "incremental_compilation_diag_begin",
    "cache_search_error",
    "incremental_compilation_diag_end",
    "lex_diag_begin",
    "lex_unknown_start_of_token",
    "lex_unexpected_digit",
    "lex_cannot_start_with_digit",
    "lex_expected_digit",
    "lex_unexpected_decimal_point",
    "lex_unexpected_exponent_part",
    "lex_expected_exponent_part",
    "lex_expected_identifier_after_dollar",
    "lex_unrecognized_symbol",
    "lex_expected_identifier",
    "lex_expected_back_quote",
    "lex_unterminated_single_line_string",
    "lex_unterminated_multi_line_string",
    "lex_unterminated_interpolation",
    "lex_multiline_string_start_from_newline",
    "lex_unterminated_raw_string",
    "lex_expected_quote_in_raw_string",
    "lex_unrecognized_escape",
    "lex_unterminated_block_comment",
    "lex_expected_left_bracket",
    "lex_expected_right_bracket",
    "lex_expected_right_bracket_or_hexadecimal",
    "lex_expected_character",
    "lex_expected_letter_after_underscore",
    "lex_illegal_integer_suffix",
    "lex_illegal_float_suffix",
    "lex_illegal_non_decimal_float",
    "lex_expected_character_in_char_literal",
    "lex_unterminated_char_literal",
    "lex_characters_overflow",
    "lex_unknown_suffix",
    "lex_illegal_UTF8_encoding_byte",
    "lex_illegal_unicode",
    "lex_unsecure_unicode",
    "lex_illegal_uni_character_literal",
    "lex_too_many_digits",
    "lex_unrecognized_char_in_binary_string",
    "lex_diag_end",
    "module_diag_begin",
    "module_read_file_to_buffer_failed",
    "module_common_part_path_is_required",
    "module_read_file_conflicted",
    "module_version_not_identical",
    "module_open_bcFile_failed",
    "module_loaded_ast_failed",
    "module_same_name_with_indirect_dependent_pkg",
    "module_common_cjo_no_options",
    "module_common_cjo_debug_mismatch",
    "module_common_cjo_opt_mismatch",
    "module_unsupport_circular_dependencies",
    "module_common_cjo_wrong_package",
    "module_diag_end",
    "import_package_diag_begin",
    "package_unsupport_save",
    "package_unsupported_load",
    "package_invalid_cjo_dependency",
    "package_decl_not_find_in_package",
    "package_search_error",
    "bc_cjo_error",
    "package_import_itself_illegal",
    "package_missed_cjo_main_pkg_part_for_test_pkg",
    "package_multiple_package_declarations",
    "package_name_not_identical_lsp",
    "package_name_inconsistent_with_macro",
    "package_shadowed_import",
    "package_conflict_import",
    "package_cannot_export_macro_package",
    "package_import_inconsistent",
    "package_mocking_support_inconsistency",
    "package_accessibility",
    "package_re_export_package_name",
    "package_root_package_should_be_public",
    "packages_visibility_inconsistent",
    "packages_macro_inconsistent",
    "feature_already_seen_name",
    "feature_null_declaration",
    "feature_different_consistency",
    "feature_is_not_subset_of_child_set",
    "import_package_diag_end",
    "parse_diag_begin",
    "parse_expected_name",
    "parse_unexpected_newline_between_at_and_mc",
    "parse_expect_escape_dollar_token",
    "parse_varray_type_parameter",
    "parse_varray_type_args_mismatch",
    "parse_expect_integer_literal_varray",
    "parse_varray_with_paren",
    "parse_expected_import",
    "parse_expected_right_delimiter",
    "parse_not_allowed_raw_identifier",
    "parse_invalid_return_type",
    "parse_unmatched_right_delimiter",
    "parse_expected_literal",
    "parse_expected_pattern",
    "parse_expected_backarrow_in_let_cond",
    "parse_expected_left_paren_after",
    "parse_expected_left_angle_after",
    "parse_expected_expr_or_decl_in",
    "parse_expected_catch_or_finally_in_try",
    "parse_expected_catch_or_handle_or_finally_in_try",
    "parse_expected_colon_in_catch_pattern",
    "parse_expected_colon_in_effect_pattern",
    "parse_expected_wildcard_or_exception_pattern",
    "parse_expected_wildcard_or_effect_pattern",
    "parse_expected_double_arrow_in_case",
    "parse_selector_or_match_expression_body",
    "parse_expected_left_brace",
    "parse_expected_left_paren",
    "parse_expected_case",
    "parse_unexpected_line_break",
    "parse_expected_paren_or_brace_after_try",
    "parse_expected_assignment",
    "parse_expected_in_forin_expression",
    "parse_expected_while_in_do_while",
    "parse_expected_double_arrow_in_lambda",
    "parse_expected_ccd_in_lambda",
    "parse_expected_character",
    "parse_expected_character_after",
    "parse_importing_by_package_name_is_not_supported",
    "parse_expected_decl",
    "parse_expected_one_of_identifier_or_pattern",
    "parse_expected_get_or_set_in_prop",
    "parse_expected_where_brace",
    "parse_expected_lt_brace",
    "parse_expected_lt_paren",
    "parse_expected_identifier_lp",
    "parse_expected_dot_lparen",
    "parse_expected_arrow_in_func_type",
    "parse_unexpected_colon_in_range",
    "parse_expected_lsquare_after",
    "parse_expected_type_argument",
    "parse_expected_parameter_rp",
    "parse_expected_no_newline_after",
    "parse_expected_if_let_andand",
    "parse_duplicated_item",
    "parse_nl_warning",
    "parse_illegal_function_name",
    "parse_expected_macro_decl_define_in_macro_package",
    "parse_expected_public_before_macro_decl",
    "parse_macro_unexpected_empty_parameter",
    "parse_macro_expected_right_parameter_nums",
    "parse_macro_illegal_param_type",
    "parse_macro_illegal_ret_type",
    "parse_macro_illegal_named_param",
    "parse_macro_define_conflicted_with_builtin",
    "parse_macro_call_illegal_with_builtin",
    "parse_unexpected_declaration_in_scope",
    "parse_const_expected_initializer",
    "parse_unexpected_const_modifier_on_variable",
    "parse_var_must_be_initialized",
    "parse_expected_one_of_type_or_initializer",
    "parse_expected_type_or_init_in_pattern",
    "parse_named_parameter_after_unnamed",
    "parse_member_parameter_after_regular",
    "parse_decl_cannot_inherit_their_self",
    "parse_intrinsic_function_must_be_toplevel",
    "parse_intrinsic_function_cannot_have_body",
    "parse_abstract_func_must_have_return_type",
    "parse_duplicated_get_or_set",
    "parse_unknown_enum_constructor",
    "parse_getter_setter_cannot_be_generic",
    "parse_unexpected_where",
    "parse_setter_must_contain_one_parameter",
    "parse_setter_can_only_accept_one_parameter",
    "parse_duplicated_intrinsic_function",
    "parse_missing_body",
    "parse_invalid_super_declaration",
    "parse_static_init_can_not_accept_any_parameter",
    "parse_finalizer_can_not_accept_any_parameter",
    "parse_invalid_quote_dollar_expr",
    "parse_unexpected_lambda_expr_in_toplevel",
    "parse_trailing_closure_only_follow_name",
    "parse_invalid_left_hand_expr",
    "parse_chained_none_associative",
    "parse_duplicated_step_op",
    "parse_invalid_step_op",
    "parse_expected_expression",
    "parse_invalid_incre_expr",
    "parse_unrecognized_token_after_macro_node",
    "parse_expected_operator_or_end",
    "parse_cannot_have_assi_in_init",
    "parse_case_body_cannot_be_empty",
    "parse_redefined_resource_name",
    "parse_newline_not_allowed_between_spawn_and_argument",
    "parse_expected_no_arguments_in_spawn",
    "parse_invalid_overloaded_operator",
    "parse_empty_string_interpolation",
    "parse_invalid_unicode_scalar",
    "parse_wildcard_can_not_be_used_as_member_name",
    "parse_unexpected_expected_found",
    "parse_cannot_operator_a_tuple",
    "parse_expected_parentheses",
    "parse_this_type_not_allow",
    "parse_unexpected_tuple_decl_type",
    "parse_expected_type",
    "parse_newline_not_allowed_between_quest_and_type",
    "parse_redundant_arrow_after_func_type",
    "parse_all_parameters_must_be_named",
    "parse_only_tuple_and_func_type_allow_type_parameter_name",
    "parse_illegal_declaration_pattern",
    "parse_illegal_or_pattern",
    "parse_tuple_pattern_expected_more_field",
    "parse_type_pattern_in_let_cond",
    "parse_expected_macro_decl_in_macro_package",
    "parse_package_as_all",
    "parse_package_name_length_overflow",
    "parse_package_name_has_backtick",
    "parse_illegal_macro_expand_input_args",
    "parse_illegal_macro_expand_attr_args",
    "parse_illegal_macro_expand_input_args_without_paren",
    "parse_illegal_macro_expand_input_without_paren_in_paramlist",
    "parse_ifavailable_arg_no_name",
    "parse_ifavailable_not_lambda",
    "parse_unexpected_anno_on",
    "parse_unexpected_overflow_annotation",
    "parse_unrecognized_expression_in_when",
    "parse_unrecognized_attr_in_anno",
    "parse_empty_attribute",
    "parse_duplicated_attr_value",
    "parse_unsafe_will_be_ignored",
    "parse_duplicated_annotation",
    "parse_conflict_annotation",
    "parse_fail_expected_annotation",
    "parse_common_function_must_have_return_type",
    "parse_specific_function_must_have_return_type",
    "parse_specific_function_parameter_cannot_have_default_value",
    "parse_specific_member_must_have_implementation",
    "parse_expected_type_with_cjmp_var",
    "parse_cjmp_outdecl_miss_match",
    "parse_cjmp_static_init",
    "parse_unexpected_cjmp_decl",
    "parse_cjmp_generic_decl",
    "parse_cjmp_pattern_decl",
    "parse_cjmp_in_common_ctor_required",
    "parse_explicitly_abstract_only_for_cjmp_abstract_class",
    "parse_illegal_modifier_in_scope",
    "parse_conflict_modifier",
    "parse_expected_no_modifier",
    "parse_duplicate_modifier",
    "parse_duplicate_type_parameter_name",
    "parse_unexpected_type_in",
    "parse_redundant_modifier",
    "parse_variable_length_parameter_can_not_be_first",
    "parse_variable_length_parameter_must_in_the_end",
    "parse_variable_length_parameter_only_in_the_foreign_function",
    "parse_foreign_func_should_not_be_generic",
    "parse_foreign_func_must_declare_return_type",
    "parse_foreign_function_with_body",
    "parse_expected_static_for_const_member_var",
    "parse_deprecated_wrong_argument",
    "parse_deprecated_argument_duplication",
    "parse_deprecated_arguments_must_be_lit_const_expr",
    "parse_deprecated_empty_string_argument",
    "parse_deprecated_unknown_argument",
    "parse_deprecated_invalid_target",
    "parse_annotation_max_one_argument",
    "parse_annotation_one_argument",
    "parse_annotation_no_arguments",
    "parse_foreign_name_on_ffi_decl_member",
    "parse_java_mirror_function_cannot_have_body",
    "parse_java_mirror_function_must_have_return_type",
    "parse_java_mirror_prop_is_forbidden",
    "parse_java_mirror_decl_cannot_have_primary_ctor",
    "parse_java_mirror_constructor_cannot_have_body",
    "parse_java_mirror_cannot_have_private_member",
    "parse_java_mirror_cannot_have_static_init",
    "parse_java_mirror_cannot_have_finalizer",
    "parse_java_mirror_cannot_have_const_member",
    "parse_java_mirror_cannot_be_sealed",
    "parse_java_impl_cannot_be_generic",
    "parse_java_impl_cannot_be_abstract",
    "parse_java_impl_cannot_be_sealed",
    "parse_java_impl_cannot_have_static_init",
    "parse_java_impl_cannot_be_open",
    "parse_java_impl_cannot_be_interface",
    "parse_objc_mirror_cannot_have_primary_ctor",
    "parse_objc_mirror_ctor_cannot_have_body",
    "parse_objc_mirror_method_cannot_have_body",
    "parse_objc_mirror_method_must_have_return_type",
    "parse_objc_mirror_cannot_be_sealed",
    "parse_objc_mirror_cannot_have_private_member",
    "parse_objc_mirror_cannot_have_static_init",
    "parse_objc_mirror_cannot_have_finalizer",
    "parse_objc_mirror_cannot_have_const_member",
    "parse_objc_impl_cannot_be_generic",
    "parse_objc_impl_cannot_be_abstract",
    "parse_objc_impl_cannot_be_sealed",
    "parse_objc_impl_cannot_have_static_init",
    "parse_objc_impl_cannot_be_open",
    "parse_objc_impl_cannot_be_interface",
    "parse_objc_mirror_field_cannot_have_initializer",
    "parse_objc_mirror_field_cannot_be_static",
    "parse_objc_mirror_prop_cannot_have_getter",
    "parse_objc_mirror_prop_cannot_have_setter",
    "parse_objc_mirror_func_cannot_be_foreign",
    "parse_objc_mirror_func_cannot_be_c",
    "parse_objc_mirror_func_cannot_be_generic",
    "parse_objc_mirror_func_cannot_have_body",
    "parse_objc_mirror_func_must_have_explicit_type",
    "parse_objc_mirror_func_cannot_be_const",
    "parse_objc_mirror_func_must_be_top_level",
    "parse_objc_init_method_must_be_static",
    "parse_objc_init_method_must_be_in_mirror_class",
    "parse_objc_optional_method_must_be_in_mirror_class",
    "parse_objc_interop_not_supported",
    "parse_diag_error",
    "parse_diag_warning",
    "parse_diag_end",
    "parse_query_diag_begin",
    "parse_query_expected_position_compare_operator",
    "parse_query_expected_hash_id_compare_operator",
    "parse_query_invalid_query_value",
    "parse_query_expected_query_symbol",
    "parse_query_expected_logic_symbol",
    "parse_query_position_illegal_file_id",
    "parse_query_position_illegal_line_num",
    "parse_query_position_illegal_column_num",
    "parse_query_position_comma_required",
    "parse_query_hashid_illegal_file_hash",
    "parse_query_hashid_illegal_fieldid",
    "searcher_past_the_end_of_array",
    "searcher_empty_number",
    "searcher_invalid_number",
    "searcher_invalid_scope_name",
    "parse_query_diag_end",
    "sema_diag_begin",
    "sema_invalid_node_after_check",
    "sema_unable_to_infer_decl",
    "sema_mismatched_types",
    "sema_mismatched_types_multiple_assign",
    "sema_mismatched_types_because",
    "sema_ambiguous_use",
    "sema_undeclared_identifier",
    "sema_undefined_variable",
    "sema_redefinition",
    "sema_conflict_with_sub_package",
    "sema_core_object_not_found_when_no_prelude",
    "sema_accessibility_with_main_hint",
    "sema_accessibility",
    "sema_param_miss_match",
    "sema_unable_to_infer_return_type",
    "sema_unable_to_infer_generic_func",
    "sema_invalid_called_object",
    "sema_invalid_return",
    "sema_invalid_return_in_static_init",
    "sema_wrong_number_of_arguments",
    "sema_unordered_arguments",
    "sema_param_named_mismatched",
    "sema_need_named_argument",
    "sema_invalid_subscript_assign_parameter",
    "sema_invalid_subscript_assign_parameter_num",
    "sema_invalid_subscript_assign_return",
    "sema_overload_conflicts",
    "sema_static_function_overload_conflicts",
    "sema_use_mutable_func_alone",
    "sema_unsafe_func_can_only_be_called",
    "sema_ambiguous_match_primitive_extend",
    "sema_immutable_access_mutable_func",
    "sema_recursive_constructor_call",
    "sema_cannot_have_default_param",
    "sema_trailing_lambda_cannot_used_for_non_function",
    "sema_unable_to_infer_expr",
    "sema_exceed_num_value_range",
    "sema_exceed_float_literal_range",
    "sema_float_literal_too_large",
    "sema_float_literal_too_small",
    "sema_invalid_unary_expr",
    "sema_invalid_unary_expr_with_target",
    "sema_invalid_binary_expr",
    "sema_invalid_subscript_expr",
    "sema_cannot_assign_to_subscript",
    "sema_not_member_of",
    "sema_member_not_imported",
    "sema_cannot_assign_to_immutable",
    "sema_unqualified_left_value_assigned",
    "sema_not_found_from_generic_upper_bounds",
    "sema_different_or_pattern",
    "sema_var_in_or_pattern",
    "sema_var_in_or_condition",
    "sema_nonexhuastive_patterns",
    "sema_unreachable_pattern",
    "sema_lambdaExpr_must_have_type_annotation",
    "sema_use_func_capture_var_alone",
    "sema_enum_constructor_with_param_must_have_args",
    "sema_optional_chain_non_optional",
    "sema_capture_before_initialization",
    "sema_interpolation_in_const_pattern",
    "sema_cannot_ref_to_pkg_name",
    "sema_use_expr_without_import",
    "sema_generic_func_without_type_arg",
    "sema_generic_type_inconsistent",
    "sema_generic_argument_no_match",
    "sema_generic_constraint_not_looser",
    "sema_generic_instantiation_causes_ambiguous_functions",
    "sema_multiple_class_upperbounds",
    "sema_generic_param_exist_in_class_irrelevant_upperbound_recursively",
    "sema_generic_param_directly_recursive",
    "sema_upper_bound_must_be_class_or_interface",
    "sema_inherit_member_kind_inconsistent",
    "sema_inherit_super_member_kind_inconsistent",
    "sema_inherit_member_type_inconsistent",
    "sema_inherit_abstract_class_static_unimplement_func",
    "sema_cannot_override",
    "sema_invalid_member_visibility_in_class",
    "sema_weak_visibility",
    "sema_cannot_inherit_sealed",
    "sema_inherit_thread_context_invalid",
    "sema_inherit_thread_context_not_open",
    "sema_inherit_not_return_this",
    "sema_return_type_incompatible",
    "sema_spawn_arg_invalid",
    "sema_spawn_arg_no_effect",
    "sema_spawn_capture_var",
    "sema_interface_call_with_unimplemented_call",
    "sema_type_uninitialized_static_field",
    "sema_instance_func_cannot_be_used_in_finalizer",
    "sema_no_non_param_constructor_in_super_class",
    "sema_non_abstract_class_cannot_be_sealed",
    "sema_static_variable_use_generic_parameter",
    "sema_cstruct_cannot_impl_interfaces",
    "sema_class_need_abstract_modifier_or_func_need_impl",
    "sema_need_member_implementation",
    "sema_export_same_private_decl",
    "sema_extend_function_cannot_overridden",
    "sema_extend_member_cannot_shadow",
    "sema_illegal_extended_type",
    "sema_extend_generic_must_be_used",
    "sema_extend_duplicate_interface",
    "sema_extend_not_interface",
    "sema_extend_illegal_member",
    "sema_extend_use_super",
    "sema_type_cannot_extend_imported_interface",
    "sema_c_type_cannot_extend_interface",
    "sema_immutable_type_extend_assignment_index_operator",
    "sema_immutable_type_illegal_property",
    "sema_interface_is_not_extendable",
    "sema_invalid_mut_modifier_extend_of_struct",
    "sema_extend_check_sequence_cannot_decide",
    "sema_export_extend_depend_non_export_extend",
    "sema_property_must_have_accessors",
    "sema_immutable_property_with_setter",
    "sema_property_have_same_declaration_in_inherit_mut",
    "sema_property_have_same_declaration_in_inherit_immut",
    "sema_property_must_implement_both",
    "sema_expect_const",
    "sema_cannot_define_var_in_const_funciton",
    "sema_no_const_init",
    "sema_class_const_init_with_var",
    "sema_annotation_no_const_init",
    "sema_annotation_arg_target",
    "sema_annotation_arg_target_array_lit",
    "sema_annotation_non_public",
    "sema_annotation_custom_place",
    "sema_inout_modify_cstring_or_zerosized",
    "sema_inout_modify_non_ctype",
    "sema_inout_must_be_var_variable",
    "sema_inout_modify_heap_variable",
    "sema_inout_can_only_used_in_cfunc_calling",
    "sema_inout_mismatch",
    "sema_annotation_error_arg_num",
    "sema_annotation_error_arg_range",
    "sema_annotation_error_object",
    "sema_java_incorrect_use_between_types",
    "sema_java_non_jtype",
    "sema_java_invalid_unit",
    "sema_java_app_inherit_ext",
    "sema_java_unsupported_decl",
    "sema_missing_java_interop_annotation",
    "sema_generic_static_access",
    "sema_primitive_type_as_generics_arg",
    "sema_meet_constraint_indirectly",
    "sema_static_member_in_interface_must_has_body",
    "sema_extend_a_java_type",
    "sema_generic_upper_bounds_must_be_java_in_java",
    "sema_define_java_annotation",
    "sema_invalid_use_of_java_annotation",
    "sema_invalid_use_of_annotation_jffi",
    "sema_annotation_not_applicable_jffi",
    "sema_cannot_use_annotation_jffi",
    "sema_shadow_cannot_in_type_args",
    "sema_unsupported_type_argument_in_java_interop",
    "sema_cjmapping_struct_generic_not_supported",
    "sema_cjmapping_struct_inheritance_interface_not_supported",
    "sema_cjmapping_decl_not_supported",
    "sema_cjmapping_method_arg_not_supported",
    "sema_cjmapping_method_ret_unsupported",
    "sema_cj_mapping_generic_method_not_get_instance_config",
    "sema_varray_size_match",
    "sema_varray_args_number_mismatch",
    "sema_varray_subscript_num",
    "sema_varray_in_cfunc",
    "sema_varray_arg_type_with_reftype",
    "sema_only_cfunc_can_use_annotation",
    "sema_annotation_calling_conv_not_support",
    "sema_annotation_invalid_args_type",
    "sema_illegal_scope_use_of_annotation",
    "sema_invalid_cfunc_return_type",
    "sema_mock_disabled",
    "sema_mock_not_in_test_mode",
    "sema_mock_unsupported_type",
    "sema_mock_wrong_static_decl",
    "sema_mock_doesnt_support_mocking",
    "sema_mock_frozen_unsupported",
    "sema_mock_frozen_required",
    "sema_command_handle_type_error",
    "sema_resumption_handle_type_error",
    "sema_resumption_incorrect_return_type",
    "sema_command_resumption_mismatch",
    "sema_implicit_resume_outside_handler",
    "sema_resume_no_with",
    "sema_resume_wrong_resumption_type",
    "sema_mismatching_handle_block",
    "sema_return_in_try_handle_block",
    "sema_try_handle_capture_var",
    "sema_command_incompatible_type",
    "sema_resume_throwing_mismatch_type",
    "sema_useless_command_type",
    "sema_deprecated_error",
    "sema_deprecated_warning",
    "sema_deprecation_weakening",
    "sema_deprecation_override_error",
    "sema_deprecation_override_warning",
    "sema_deprecation_redef_error",
    "sema_deprecation_redef_warning",
    "sema_common_open_class_no_init",
    "sema_multiple_common_implementations",
    "sema_common_direct_extension_has_duplicate_private_members",
    "sema_common_direct_extension_has_common_private_members",
    "sema_not_matched",
    "sema_specific_var_not_match_let",
    "sema_specific_init_common_primary_constructor",
    "specific_has_different_kind",
    "sema_specific_primary_unmatched_var_decl",
    "common_non_exaustive_platfrom_exaustive_mismatch",
    "sema_specific_has_different_type",
    "sema_specific_member_must_have_implementation",
    "sema_specific_has_different_modifier",
    "sema_specific_has_different_annotation",
    "sema_specific_has_deprecated_annotation",
    "sema_cjmp_parameter_default_value_both_sides",
    "sema_specific_has_different_parameter",
    "sema_specific_has_different_super_type",
    "sema_specific_has_duplicate_extensions",
    "sema_common_package_has_main",
    "sema_common_static_let_cant_be_initialized_in_static_init",
    "sema_common_assign_to_common_immutable_in_ctor",
    "sema_cjmp_abstract_class_member_has_no_explicit_modifier",
    "sema_explicitly_abstract_can_not_have_body",
    "sema_explicitly_abstract_only_for_cjmp_abstract_class",
    "sema_open_abstract_specific_can_not_replace_open_common",
    "sema_cjmp_non_specific_abstract_member_in_specific_class",
    "sema_common_generic_frozen_not_supported",
    "sema_common_generic_rename_not_supported",
    "sema_common_specific_annotation_not_allowed",
    "sema_java_mirror_ctor_arg_must_be_java_mirror",
    "sema_java_mirror_method_arg_must_be_java_mirror",
    "sema_java_mirror_method_ret_unsupported",
    "sema_java_mirror_prop_must_be_java_mirror",
    "sema_java_mirror_subtype_must_be_annotated",
    "sema_java_mirror_cannot_inherit_pure_cangjie_type",
    "sema_java_impl_cannot_inherit_pure_cangjie_type",
    "sema_java_mirror_subtype_anno_must_inherit_mirror",
    "sema_java_mirror_cannot_be_extended_with_interface",
    "sema_java_impl_cannot_be_extended_with_interface",
    "sema_java_impl_redefinition",
    "sema_java_mirror_interoplib_must_be_imported",
    "sema_java_interop_not_supported",
    "sema_extend_ref_target_cannot_be_java_impl",
    "sema_generic_parameter_of_java_type",
    "sema_java_interoplib_version_too_old",
    "sema_java_interoplib_version_mismatch",
    "sema_java_has_default_annotation_args",
    "sema_java_has_default_annotation_is_in_wrong_place",
    "sema_java_has_default_conflict_with_static",
    "sema_objc_interop_ctor_param_must_be_objc_compatible",
    "sema_objc_interop_method_param_must_be_objc_compatible",
    "sema_objc_interop_method_ret_must_be_objc_compatible",
    "sema_objc_interop_prop_must_be_objc_compatible",
    "sema_objc_interop_field_must_be_objc_compatible",
    "sema_objc_mirror_decl_cannot_inherit",
    "sema_objc_mirror_subtype_cannot_multiple_inherit",
    "sema_objc_mirror_subtype_must_be_annotated",
    "sema_objc_mirror_subtype_must_inherit_mirror",
    "sema_objc_mirror_must_inherit_mirror",
    "sema_objc_mirror_interoplib_must_be_imported",
    "sema_objc_interop_not_supported",
    "sema_objc_pointer_argument_must_be_objc_compatible",
    "sema_objc_interop_toplevel_param_must_be_objc_compatible",
    "sema_objc_interop_toplevel_ret_must_be_objc_compatible",
    "sema_objc_method_must_have_foreign_name",
    "sema_objc_ctor_must_have_foreign_name",
    "sema_objc_func_argument_must_be_objc_compatible",
    "sema_objc_func_call_property_can_only_be_called",
    "sema_objc_impl_must_have_objc_mirror_super_class",
    "sema_objc_setter_name_on_immutable_prop",
    "sema_objc_cjmapping_inheritance_interface_not_supported",
    "sema_objc_cjmapping_generic_not_supported",
    "sema_foreign_name_appeared_in_child",
    "sema_foreign_name_conflicting_annotation",
    "sema_foreign_name_conflicting_derived_annotation",
    "sema_ifavailable_arg_no_name",
    "sema_ifavailable_arg_not_literal",
    "sema_ifavailable_unknow_arg_name",
    "sema_apilevel_multi_anno",
    "sema_apilevel_missing_arg",
    "sema_apilevel_invalid_version_format",
    "sema_only_literal_support",
    "sema_apilevel_ref_higher",
    "sema_apilevel_syscap_warning",
    "sema_apilevel_syscap_error",
    "sema_apilevel_multi_diff_syscap",
    "sema_apilevel_integer_form_unsupported",
    "sema_ifavailable_level_limit",
    "sema_hide_multi_annotation",
    "sema_hide_at_func_param",
    "sema_hide_missing_hide",
    "sema_hide_compile_time_invisible",
    "sema_hide_diff_param",
    "sema_hide_must_at_end",
    "sema_unused_import",
    "sema_diag_end",
]
public let RE_DIAG_KIND_STR_SIZE: Int64 = 738

public func DiagKindIndex(kind: DiagKind): Int64 {
    return match (kind) {
        case DiagKind.chir_diag_begin => 0
        case DiagKind.chir_var_might_circular_dependency => 1
        case DiagKind.chir_file_might_circular_dependency => 2
        case DiagKind.chir_used_before_initialization => 3
        case DiagKind.chir_sancov_illegal_usage_of_pc_table => 4
        case DiagKind.chir_sancov_illegal_usage_of_level => 5
        case DiagKind.interp_cannot_interp_node => 6
        case DiagKind.interp_malloc_failed => 7
        case DiagKind.interp_unsupported => 8
        case DiagKind.interp_unsupported_type => 9
        case DiagKind.interp_cannot_convert_array2ffi => 10
        case DiagKind.interp_cannot_load_incremental_bchir => 11
        case DiagKind.const_eval_exception => 12
        case DiagKind.const_eval_load_dep => 13
        case DiagKind.const_eval_unsupported => 14
        case DiagKind.chir_diag_end => 15
        case DiagKind.macro_expand_diag_begin => 16
        case DiagKind.macro_undeclared_identifier => 17
        case DiagKind.macro_expect_attributed_macro => 18
        case DiagKind.macro_evaluate_failed => 19
        case DiagKind.macro_expect_macro_definition => 20
        case DiagKind.macro_undefined_pkg_name => 21
        case DiagKind.macro_expect_plain_macro => 22
        case DiagKind.macro_expand_invalid_attr_tokens => 23
        case DiagKind.macro_expand_invalid_input_tokens => 24
        case DiagKind.macro_expand_invalid_escape => 25
        case DiagKind.macro_unexpect_def_and_call_in_same_pkg => 26
        case DiagKind.macro_init_interpter_faild => 27
        case DiagKind.macro_expand_invalid_node_replace => 28
        case DiagKind.macro_ambiguous_match => 29
        case DiagKind.macro_using_error => 30
        case DiagKind.macro_expand_failed => 31
        case DiagKind.not_find_macro_library => 32
        case DiagKind.can_not_open_macro_library => 33
        case DiagKind.macro_cannot_find_method => 34
        case DiagKind.macro_expect_decl_not_enum_constructor => 35
        case DiagKind.macro_expect_declaration => 36
        case DiagKind.macro_expect_enum_constructor => 37
        case DiagKind.macro_expect_one_enum_constructor => 38
        case DiagKind.macro_expect_one_expr_or_pattern => 39
        case DiagKind.macro_expect_one_expr => 40
        case DiagKind.macro_unexpect_no_expr => 41
        case DiagKind.macro_call_map_to_empty_value_token => 42
        case DiagKind.macro_call_map_info_failed => 43
        case DiagKind.macro_call_save_file_failed => 44
        case DiagKind.macro_expand_code_should_not_have_macrocall => 45
        case DiagKind.macro_expand_cannot_find_dependency => 46
        case DiagKind.macro_expand_exception_occurred => 47
        case DiagKind.macro_expand_failed_init_top_level => 48
        case DiagKind.macro_named_parameter_after_unnamed => 49
        case DiagKind.macro_unexpected_empty_parameter => 50
        case DiagKind.macro_assert_parent_context_failed => 51
        case DiagKind.macro_build_in_unexpect_params => 52
        case DiagKind.macro_build_in_unexpect_params_attrs => 53
        case DiagKind.macro_is_deprecated_error => 54
        case DiagKind.macro_is_deprecated_warning => 55
        case DiagKind.macro_expand_atexcl => 56
        case DiagKind.macro_expand_diag_end => 57
        case DiagKind.sema_diag_begin => 58
        case DiagKind.sema_diag_report_error_message => 59
        case DiagKind.sema_diag_report_note_message => 60
        case DiagKind.sema_incompatible_expo_target_type => 61
        case DiagKind.sema_ambiguous_expo_right_operand_type => 62
        case DiagKind.sema_not_a_type => 63
        case DiagKind.sema_incompatible_func_body_and_return_type => 64
        case DiagKind.sema_type_must_toplevel => 65
        case DiagKind.sema_undeclared_type_name => 66
        case DiagKind.sema_undeclared_identifier => 67
        case DiagKind.sema_redefinition => 68
        case DiagKind.sema_expand_macro_redefinition => 69
        case DiagKind.sema_previous_decl => 70
        case DiagKind.sema_used_before_initialization => 71
        case DiagKind.sema_global_var_used_before_initialization => 72
        case DiagKind.sema_duplicated_item_in_enum => 73
        case DiagKind.sema_invalid_constructor_in_enum => 74
        case DiagKind.sema_multiple_constructor_in_enum => 75
        case DiagKind.sema_enum_constructor_type_not_match => 76
        case DiagKind.sema_invalid_enum_member_access => 77
        case DiagKind.sema_invalid_type_param_of_enum_member_access => 78
        case DiagKind.sema_invalid_loop_control => 79
        case DiagKind.sema_cannot_currying => 80
        case DiagKind.sema_value_type_recursive => 81
        case DiagKind.sema_inheritance_cycle => 82
        case DiagKind.sema_typealias_cycle => 83
        case DiagKind.sema_typealias_external_refer_internal => 84
        case DiagKind.sema_invalid_coalescing => 85
        case DiagKind.sema_div_zero => 86
        case DiagKind.sema_mod_zero => 87
        case DiagKind.sema_arithmetical_op_overflow => 88
        case DiagKind.sema_shift_count_overflow => 89
        case DiagKind.sema_negative_shift_count => 90
        case DiagKind.sema_func_capture_var_cannot_assign => 91
        case DiagKind.sema_func_capture_var_cannot_return => 92
        case DiagKind.sema_func_capture_var_cannot_param => 93
        case DiagKind.sema_func_capture_var_cannot_expr => 94
        case DiagKind.sema_invalid_unary_expr => 95
        case DiagKind.sema_invalid_unary_expr_note => 96
        case DiagKind.sema_fail_flow_expr_operand_has_named_param => 97
        case DiagKind.sema_operator_overload_invalid_num_parameter => 98
        case DiagKind.sema_operator_overload_built_in_unary_operator => 99
        case DiagKind.sema_operator_overload_built_in_binary_operator => 100
        case DiagKind.sema_operator_overload_can_not_has_default_param => 101
        case DiagKind.sema_empty_arrayLit_type_undefined => 102
        case DiagKind.sema_inconsistency_elemType => 103
        case DiagKind.sema_tuple_pattern_not_match => 104
        case DiagKind.sema_unsupport_operator => 105
        case DiagKind.sema_array_size_type_error => 106
        case DiagKind.sema_array_expression_param_type_error => 107
        case DiagKind.sema_array_expression_type_error => 108
        case DiagKind.sema_array_single_element_type_error => 109
        case DiagKind.sema_array_element_type_error => 110
        case DiagKind.sema_array_too_much_argument => 111
        case DiagKind.sema_array_first_arg_cannot_be_named => 112
        case DiagKind.sema_array_second_arg_cannot_be_named => 113
        case DiagKind.sema_array_second_wrong_named_arg => 114
        case DiagKind.sema_pointer_too_much_argument => 115
        case DiagKind.sema_cfunc_too_many_arguments => 116
        case DiagKind.sema_pointer_single_element_type_error => 117
        case DiagKind.sema_pointer_unknow_generic_type => 118
        case DiagKind.sema_builtin_invalid_index => 119
        case DiagKind.sema_builtin_index_in_bound => 120
        case DiagKind.sema_tuple_element_cmp_not_bool => 121
        case DiagKind.sema_tuple_cmp_not_supported => 122
        case DiagKind.sema_step_non_zero_range => 123
        case DiagKind.sema_inconsistency_range_elemType => 124
        case DiagKind.sema_range_step_not_int64 => 125
        case DiagKind.sema_no_match_function_declaration_for_call => 126
        case DiagKind.sema_no_match_function_declaration_for_ref => 127
        case DiagKind.sema_no_match_constructor => 128
        case DiagKind.sema_ambiguous_arg_type => 129
        case DiagKind.sema_ambiguous_match => 130
        case DiagKind.sema_ambiguous_constructor_match => 131
        case DiagKind.sema_ambiguous_func_ref => 132
        case DiagKind.sema_mismatched_type_for_pattern_in_vardecl => 133
        case DiagKind.sema_parameters_and_arguments_mismatch => 134
        case DiagKind.sema_cstruct_cannot_autobox => 135
        case DiagKind.sema_unit_cannot_as_cfunc_arg => 136
        case DiagKind.sema_overload_conflicts => 137
        case DiagKind.sema_no_match_operator_function_call => 138
        case DiagKind.sema_pattern_can_not_be_assigned => 139
        case DiagKind.sema_unknown_named_argument => 140
        case DiagKind.sema_multiple_named_argument => 141
        case DiagKind.sema_invalid_named_arguments => 142
        case DiagKind.sema_unsupport_named_argument => 143
        case DiagKind.sema_pattern_literal_expected => 144
        case DiagKind.sema_pattern_not_match => 145
        case DiagKind.sema_not_overload_in_match => 146
        case DiagKind.sema_type_incompatible => 147
        case DiagKind.sema_subscript_set_not_supported => 148
        case DiagKind.sema_subscript_get_set_not_supported => 149
        case DiagKind.sema_tuple_pattern_with_correct_size_expected => 150
        case DiagKind.sema_enum_pattern_param_size_error => 151
        case DiagKind.sema_match_case_must_have_default => 152
        case DiagKind.sema_match_case_has_no_type => 153
        case DiagKind.sema_package_internal_decl_obtain_illegal => 154
        case DiagKind.sema_package_name_conflict => 155
        case DiagKind.sema_invalid_access_control => 156
        case DiagKind.sema_invalid_access_function => 157
        case DiagKind.sema_invalid_file_hash => 158
        case DiagKind.sema_func_no_override_or_redefine_modifier => 159
        case DiagKind.sema_unexpected_param_for_entry => 160
        case DiagKind.sema_unexpected_return_type_for_entry => 161
        case DiagKind.sema_redefinition_entry => 162
        case DiagKind.sema_missing_entry => 163
        case DiagKind.sema_numeric_convert_must_be_numeric => 164
        case DiagKind.sema_cfunc_ctor_must_be_cpointer => 165
        case DiagKind.sema_ref_not_be_type => 166
        case DiagKind.sema_expr_in_forin_must_has_iterator => 167
        case DiagKind.sema_forin_pattern_must_be_irrefutable => 168
        case DiagKind.sema_wrong_forin_guard => 169
        case DiagKind.sema_generics_type_variable_not_defined => 170
        case DiagKind.sema_generic_type_argument_not_match_constraint => 171
        case DiagKind.sema_which_constraint_not_match => 172
        case DiagKind.sema_generic_type_without_type_argument => 173
        case DiagKind.sema_non_generic_function_with_type_argument => 174
        case DiagKind.sema_throw_expr_with_wrong_type => 175
        case DiagKind.sema_except_catch_type_error => 176
        case DiagKind.sema_no_core_object => 177
        case DiagKind.sema_invalid_intrinsic_decl => 178
        case DiagKind.sema_generic_infinite_instantiation => 179
        case DiagKind.sema_forbid_generic_nonstatic_method => 180
        case DiagKind.sema_forbid_generic_constructor => 181
        case DiagKind.sema_forbid_generic_finalizer => 182
        case DiagKind.sema_import_not_in_current_module => 183
        case DiagKind.sema_flow_expressions_use_this_or_super => 184
        case DiagKind.sema_symbol_not_collected => 185
        case DiagKind.sema_cannot_convert_literal => 186
        case DiagKind.sema_cannot_have_parameter => 187
        case DiagKind.sema_annotation_error_arg_num => 188
        case DiagKind.sema_unexpected_wrapper => 189
        case DiagKind.sema_native_var_error => 190
        case DiagKind.sema_illegal_use_of_annotation => 191
        case DiagKind.sema_cffi_cannot_have_type_param => 192
        case DiagKind.sema_unsafe_function_invoke_failed => 193
        case DiagKind.sema_func_capture_var_not_ctype => 194
        case DiagKind.sema_cfunc_cannot_capture_var => 195
        case DiagKind.sema_cfunc_cannot_capture_this => 196
        case DiagKind.sema_illegal_ctype_generic_argument => 197
        case DiagKind.sema_illegal_cpointer_generic_type => 198
        case DiagKind.sema_invalid_cfunc_arg_type => 199
        case DiagKind.sema_cfunc_type => 200
        case DiagKind.sema_invalid_tuple_field_ctype => 201
        case DiagKind.sema_enum_pattern_func_cty_error => 202
        case DiagKind.sema_enum_pattern_func_param_cty_error => 203
        case DiagKind.sema_illegal_ctype_member => 204
        case DiagKind.sema_illegal_member_of_cstruct => 205
        case DiagKind.sema_cfunc_cannot_have_unit_args => 206
        case DiagKind.sema_cstruct_cannot_have_unit_fields => 207
        case DiagKind.sema_cfunc_cannot_have_named_args => 208
        case DiagKind.sema_cfunc_var_cannot_have_var_param => 209
        case DiagKind.sema_inheritance_non_ref_type => 210
        case DiagKind.sema_class_uninitialized_field => 211
        case DiagKind.sema_this_or_super_not_allowed_to_initialize_non_static_member => 212
        case DiagKind.sema_this_or_super_not_allowed_to_initialize_static_member => 213
        case DiagKind.sema_illegal_usage_of_super_member => 214
        case DiagKind.sema_illegal_usage_of_member => 215
        case DiagKind.sema_invalid_assignment_to_this_expr => 216
        case DiagKind.sema_invalid_override_member_in_class => 217
        case DiagKind.sema_invalid_override_or_redefine_member_in_interface => 218
        case DiagKind.sema_illegal_this_in_interface => 219
        case DiagKind.sema_use_super_in_interface => 220
        case DiagKind.sema_super_use_error_inside_non_class => 221
        case DiagKind.sema_assignment_of_member_variable_cannot_use_this_or_super => 222
        case DiagKind.sema_illegal_super_alone => 223
        case DiagKind.sema_abstract_class_can_not_be_instantiated => 224
        case DiagKind.sema_interface_can_not_be_instantiated => 225
        case DiagKind.sema_non_inheritable_super_class => 226
        case DiagKind.sema_superclass_must_be_placed_at_first => 227
        case DiagKind.sema_illegal_multi_inheritance => 228
        case DiagKind.sema_invalid_this_call_outside_ctor => 229
        case DiagKind.sema_privated_abstract_func_in_class => 230
        case DiagKind.sema_invalid_string_implementation => 231
        case DiagKind.sema_invalid_tokens_implementation => 232
        case DiagKind.sema_multiple_primary_constructors => 233
        case DiagKind.sema_interface_is_not_inheritable => 234
        case DiagKind.sema_interface_is_not_implementable => 235
        case DiagKind.sema_inherit_duplicate_interface => 236
        case DiagKind.sema_return_unit => 237
        case DiagKind.sema_illegal_place_of_calling_this_or_super => 238
        case DiagKind.sema_illegal_place_of_calling_this_primary_constructor => 239
        case DiagKind.sema_this_super_use_error_outside_class => 240
        case DiagKind.sema_missing_func_body => 241
        case DiagKind.sema_interface_member_must_be_implemented => 242
        case DiagKind.sema_interface_member_must_be_implemented_in_struct => 243
        case DiagKind.sema_member_variable_can_not_shadow => 244
        case DiagKind.sema_missing_overridden_func => 245
        case DiagKind.sema_missing_redefined_func => 246
        case DiagKind.sema_static_and_non_static_member_cannot_have_same_name => 247
        case DiagKind.sema_generic_member_type_argument_different => 248
        case DiagKind.sema_c_type_cannot_implement_interface => 249
        case DiagKind.sema_illegal_access_non_static_member => 250
        case DiagKind.sema_illegal_access_interface_field => 251
        case DiagKind.sema_illegal_access_inner_classlike => 252
        case DiagKind.sema_cannot_modify_var => 253
        case DiagKind.sema_illegal_capture_this => 254
        case DiagKind.sema_object_cannot_access_static_member => 255
        case DiagKind.sema_abstract_method_cannot_be_accessed_directly => 256
        case DiagKind.sema_return_type_invariance => 257
        case DiagKind.sema_static_members_cannot_call_members => 258
        case DiagKind.sema_class_inherit_non_class_nor_interface => 259
        case DiagKind.sema_type_implement_non_interface => 260
        case DiagKind.sema_interface_inherit_non_interface => 261
        case DiagKind.sema_generic_in_operator_overload => 262
        case DiagKind.sema_illegal_this_outside_struct_constructor => 263
        case DiagKind.sema_static_function_cannot_access_non_static_member => 264
        case DiagKind.sema_static_variable_cannot_access_non_static_member => 265
        case DiagKind.sema_static_lambdaExpr_cannot_access_non_static => 266
        case DiagKind.sema_redef_modify_static_func => 267
        case DiagKind.sema_illegal_member_used_in_open_constructor => 268
        case DiagKind.sema_finalizer_forbidden_in_class => 269
        case DiagKind.sema_generic_no_member_match_in_upper_bounds => 270
        case DiagKind.sema_generic_ambiguous_method_match_in_upper_bounds => 271
        case DiagKind.sema_generic_no_method_match_in_upper_bounds => 272
        case DiagKind.sema_cannot_instantiated_by_incomplete_type => 273
        case DiagKind.sema_invalid_field_expose_access => 274
        case DiagKind.sema_capture_this_or_instance_field_in_func => 275
        case DiagKind.sema_use_this_as_an_expression_in_func => 276
        case DiagKind.sema_incompatible_mut_modifier_between_struct_and_interface => 277
        case DiagKind.sema_immutable_function_cannot_access_mutable_function => 278
        case DiagKind.sema_invalid_position_of_this_type => 279
        case DiagKind.sema_property_override_implement_type_diff => 280
        case DiagKind.typealias_unused_type_parameters => 281
        case DiagKind.sema_capture_has_shadow_variable => 282
        case DiagKind.sema_useless_exception_type => 283
        case DiagKind.sema_ignore_open => 284
        case DiagKind.sema_found_candidate_decl => 285
        case DiagKind.sema_found_possible_candidate_decl => 286
        case DiagKind.sema_diag_end => 287
    }
}

public func DiagKindRefactorIndex(kind: DiagKindRefactor): Int64 {
    return match (kind) {
        case DiagKindRefactor.chir_diag_begin => 0
        case DiagKindRefactor.chir_used_before_initialization => 1
        case DiagKindRefactor.chir_illegal_usage_of_member => 2
        case DiagKindRefactor.chir_cannot_assign_initialized_let_variable => 3
        case DiagKindRefactor.chir_class_uninitialized_field => 4
        case DiagKindRefactor.chir_illegal_usage_of_super_member => 5
        case DiagKindRefactor.chir_arithmetic_operator_overflow => 6
        case DiagKindRefactor.chir_idx_out_of_bounds => 7
        case DiagKindRefactor.chir_divisor_is_zero => 8
        case DiagKindRefactor.chir_shift_length_overflow => 9
        case DiagKindRefactor.chir_typecast_overflow => 10
        case DiagKindRefactor.chir_step_non_zero_range => 11
        case DiagKindRefactor.chir_dce_unreachable_statement => 12
        case DiagKindRefactor.chir_dce_unreachable_function => 13
        case DiagKindRefactor.chir_dce_unreachable_return => 14
        case DiagKindRefactor.chir_dce_unreachable_if => 15
        case DiagKindRefactor.chir_dce_unreachable => 16
        case DiagKindRefactor.chir_dce_unreachable_expression_hint => 17
        case DiagKindRefactor.chir_dce_unreachable_block_in_expression => 18
        case DiagKindRefactor.chir_dce_unreachable_block => 19
        case DiagKindRefactor.chir_dce_unused_expression => 20
        case DiagKindRefactor.chir_dce_unused_function => 21
        case DiagKindRefactor.chir_dce_unused_function_main => 22
        case DiagKindRefactor.chir_dce_unreachable_expression => 23
        case DiagKindRefactor.chir_dce_unused_variable => 24
        case DiagKindRefactor.chir_dce_unused_operator => 25
        case DiagKindRefactor.chir_unreachable_pattern => 26
        case DiagKindRefactor.chir_eval_support => 27
        case DiagKindRefactor.chir_annotation_not_applicable => 28
        case DiagKindRefactor.chir_diag_end => 29
        case DiagKindRefactor.conditional_compilation_diag_begin => 30
        case DiagKindRefactor.conditional_compilation_not_support_op => 31
        case DiagKindRefactor.conditional_compilation_not_support_this_condition => 32
        case DiagKindRefactor.conditional_compilation_not_support_builtin_value => 33
        case DiagKindRefactor.conditional_compilation_not_support_cjc_version_format => 34
        case DiagKindRefactor.conditional_compilation_invalid_condition_expr => 35
        case DiagKindRefactor.conditional_compilation_not_have_condition_expr => 36
        case DiagKindRefactor.conditional_compilation_invalid_condition_value => 37
        case DiagKindRefactor.conditional_compilation_just_support_block => 38
        case DiagKindRefactor.conditional_compilation_unexpected_after_macro => 39
        case DiagKindRefactor.conditional_compilation_diag_end => 40
        case DiagKindRefactor.driver_diag_begin => 41
        case DiagKindRefactor.no_such_file_or_directory => 42
        case DiagKindRefactor.no_such_directory => 43
        case DiagKindRefactor.not_a_directory => 44
        case DiagKindRefactor.not_a_file => 45
        case DiagKindRefactor.permission_denied => 46
        case DiagKindRefactor.invalid_path => 47
        case DiagKindRefactor.no_such_file_or_directory_of_macro_obj => 48
        case DiagKindRefactor.input_file_overwritten_by_generated_output => 49
        case DiagKindRefactor.bc_file_open_failed => 50
        case DiagKindRefactor.bc_parse_failed => 51
        case DiagKindRefactor.bc_invalid_package_name => 52
        case DiagKindRefactor.driver_warning_no_such_file => 53
        case DiagKindRefactor.driver_warning_no_such_file_or_directory => 54
        case DiagKindRefactor.driver_warning_no_such_directory => 55
        case DiagKindRefactor.driver_warning_not_a_directory => 56
        case DiagKindRefactor.driver_warning_not_a_file => 57
        case DiagKindRefactor.driver_warning_permission_denied => 58
        case DiagKindRefactor.driver_warning_invalid_path => 59
        case DiagKindRefactor.driver_warning_unexpected_file_extension => 60
        case DiagKindRefactor.driver_warning_argument_unused => 61
        case DiagKindRefactor.driver_warning_path_close_to_length_limit => 62
        case DiagKindRefactor.driver_invalid_compile_target => 63
        case DiagKindRefactor.driver_warning_unusable_static => 64
        case DiagKindRefactor.driver_static_std_for_ohos => 65
        case DiagKindRefactor.driver_warning_no_support_static => 66
        case DiagKindRefactor.driver_require_package_directory => 67
        case DiagKindRefactor.driver_require_package_directory_scan_dependency => 68
        case DiagKindRefactor.driver_require_one_package_directory => 69
        case DiagKindRefactor.driver_require_one_package_directory_scan_dependency => 70
        case DiagKindRefactor.driver_source_cjo_empty => 71
        case DiagKindRefactor.driver_not_accept_cjo_inputs_when => 72
        case DiagKindRefactor.driver_source_file_empty => 73
        case DiagKindRefactor.driver_invalid_source_file => 74
        case DiagKindRefactor.driver_invalid_file_or_directory => 75
        case DiagKindRefactor.driver_invalid_binary_file => 76
        case DiagKindRefactor.driver_invalid_unsupport_extension => 77
        case DiagKindRefactor.driver_invalid_require_extension => 78
        case DiagKindRefactor.driver_path_exceeds_length_limit => 79
        case DiagKindRefactor.driver_unsupported_target_cpu => 80
        case DiagKindRefactor.driver_require_common_chir_for_each_common_cjo => 81
        case DiagKindRefactor.driver_require_experimental => 82
        case DiagKindRefactor.driver_static_dystd_conflict => 83
        case DiagKindRefactor.driver_target_lto_unsupported => 84
        case DiagKindRefactor.driver_cfg_value_err => 85
        case DiagKindRefactor.driver_cfg_toml_content_err => 86
        case DiagKindRefactor.dirver_cfg_invaild_identifier => 87
        case DiagKindRefactor.dirver_cfg_same_with_builtin => 88
        case DiagKindRefactor.dirver_cfg_key_repeat => 89
        case DiagKindRefactor.dirver_cfg_not_a_dir => 90
        case DiagKindRefactor.driver_cfg_file_read_failed => 91
        case DiagKindRefactor.driver_cfg_path_ignored => 92
        case DiagKindRefactor.driver_invalid_compile_as_exe => 93
        case DiagKindRefactor.driver_invalid_compile_as_exe_platform => 94
        case DiagKindRefactor.driver_invalid_visible_pkgs => 95
        case DiagKindRefactor.driver_invalid_visible_pkgs_conflict => 96
        case DiagKindRefactor.driver_visible_pkgs_only_for_dylib => 97
        case DiagKindRefactor.driver_useless_option => 98
        case DiagKindRefactor.driver_unsupport_compile_package_with_source_file => 99
        case DiagKindRefactor.driver_unsupport_compile_source_file_with_path => 100
        case DiagKindRefactor.driver_deprecated_option => 101
        case DiagKindRefactor.driver_pgo_both_gen_and_use => 102
        case DiagKindRefactor.driver_ohos_pgo_gen_without_file => 103
        case DiagKindRefactor.driver_pgo_invalid_profile_extension => 104
        case DiagKindRefactor.not_a_valid_plugin => 105
        case DiagKindRefactor.plugin_throws_exception => 106
        case DiagKindRefactor.driver_diag_end => 107
        case DiagKindRefactor.frontend_diag_begin => 108
        case DiagKindRefactor.frontend_failed_to_detect_cangjie_home => 109
        case DiagKindRefactor.frontend_failed_to_detect_cangjie_modules => 110
        case DiagKindRefactor.frontend_invalid_output_path => 111
        case DiagKindRefactor.frontend_diag_end => 112
        case DiagKindRefactor.incremental_compilation_diag_begin => 113
        case DiagKindRefactor.cache_search_error => 114
        case DiagKindRefactor.incremental_compilation_diag_end => 115
        case DiagKindRefactor.lex_diag_begin => 116
        case DiagKindRefactor.lex_unknown_start_of_token => 117
        case DiagKindRefactor.lex_unexpected_digit => 118
        case DiagKindRefactor.lex_cannot_start_with_digit => 119
        case DiagKindRefactor.lex_expected_digit => 120
        case DiagKindRefactor.lex_unexpected_decimal_point => 121
        case DiagKindRefactor.lex_unexpected_exponent_part => 122
        case DiagKindRefactor.lex_expected_exponent_part => 123
        case DiagKindRefactor.lex_expected_identifier_after_dollar => 124
        case DiagKindRefactor.lex_unrecognized_symbol => 125
        case DiagKindRefactor.lex_expected_identifier => 126
        case DiagKindRefactor.lex_expected_back_quote => 127
        case DiagKindRefactor.lex_unterminated_single_line_string => 128
        case DiagKindRefactor.lex_unterminated_multi_line_string => 129
        case DiagKindRefactor.lex_unterminated_interpolation => 130
        case DiagKindRefactor.lex_multiline_string_start_from_newline => 131
        case DiagKindRefactor.lex_unterminated_raw_string => 132
        case DiagKindRefactor.lex_expected_quote_in_raw_string => 133
        case DiagKindRefactor.lex_unrecognized_escape => 134
        case DiagKindRefactor.lex_unterminated_block_comment => 135
        case DiagKindRefactor.lex_expected_left_bracket => 136
        case DiagKindRefactor.lex_expected_right_bracket => 137
        case DiagKindRefactor.lex_expected_right_bracket_or_hexadecimal => 138
        case DiagKindRefactor.lex_expected_character => 139
        case DiagKindRefactor.lex_expected_letter_after_underscore => 140
        case DiagKindRefactor.lex_illegal_integer_suffix => 141
        case DiagKindRefactor.lex_illegal_float_suffix => 142
        case DiagKindRefactor.lex_illegal_non_decimal_float => 143
        case DiagKindRefactor.lex_expected_character_in_char_literal => 144
        case DiagKindRefactor.lex_unterminated_char_literal => 145
        case DiagKindRefactor.lex_characters_overflow => 146
        case DiagKindRefactor.lex_unknown_suffix => 147
        case DiagKindRefactor.lex_illegal_UTF8_encoding_byte => 148
        case DiagKindRefactor.lex_illegal_unicode => 149
        case DiagKindRefactor.lex_unsecure_unicode => 150
        case DiagKindRefactor.lex_illegal_uni_character_literal => 151
        case DiagKindRefactor.lex_too_many_digits => 152
        case DiagKindRefactor.lex_unrecognized_char_in_binary_string => 153
        case DiagKindRefactor.lex_diag_end => 154
        case DiagKindRefactor.module_diag_begin => 155
        case DiagKindRefactor.module_read_file_to_buffer_failed => 156
        case DiagKindRefactor.module_common_part_path_is_required => 157
        case DiagKindRefactor.module_read_file_conflicted => 158
        case DiagKindRefactor.module_version_not_identical => 159
        case DiagKindRefactor.module_open_bcFile_failed => 160
        case DiagKindRefactor.module_loaded_ast_failed => 161
        case DiagKindRefactor.module_same_name_with_indirect_dependent_pkg => 162
        case DiagKindRefactor.module_common_cjo_no_options => 163
        case DiagKindRefactor.module_common_cjo_debug_mismatch => 164
        case DiagKindRefactor.module_common_cjo_opt_mismatch => 165
        case DiagKindRefactor.module_unsupport_circular_dependencies => 166
        case DiagKindRefactor.module_common_cjo_wrong_package => 167
        case DiagKindRefactor.module_diag_end => 168
        case DiagKindRefactor.import_package_diag_begin => 169
        case DiagKindRefactor.package_unsupport_save => 170
        case DiagKindRefactor.package_unsupported_load => 171
        case DiagKindRefactor.package_invalid_cjo_dependency => 172
        case DiagKindRefactor.package_decl_not_find_in_package => 173
        case DiagKindRefactor.package_search_error => 174
        case DiagKindRefactor.bc_cjo_error => 175
        case DiagKindRefactor.package_import_itself_illegal => 176
        case DiagKindRefactor.package_missed_cjo_main_pkg_part_for_test_pkg => 177
        case DiagKindRefactor.package_multiple_package_declarations => 178
        case DiagKindRefactor.package_name_not_identical_lsp => 179
        case DiagKindRefactor.package_name_inconsistent_with_macro => 180
        case DiagKindRefactor.package_shadowed_import => 181
        case DiagKindRefactor.package_conflict_import => 182
        case DiagKindRefactor.package_cannot_export_macro_package => 183
        case DiagKindRefactor.package_import_inconsistent => 184
        case DiagKindRefactor.package_mocking_support_inconsistency => 185
        case DiagKindRefactor.package_accessibility => 186
        case DiagKindRefactor.package_re_export_package_name => 187
        case DiagKindRefactor.package_root_package_should_be_public => 188
        case DiagKindRefactor.packages_visibility_inconsistent => 189
        case DiagKindRefactor.packages_macro_inconsistent => 190
        case DiagKindRefactor.feature_already_seen_name => 191
        case DiagKindRefactor.feature_null_declaration => 192
        case DiagKindRefactor.feature_different_consistency => 193
        case DiagKindRefactor.feature_is_not_subset_of_child_set => 194
        case DiagKindRefactor.import_package_diag_end => 195
        case DiagKindRefactor.parse_diag_begin => 196
        case DiagKindRefactor.parse_expected_name => 197
        case DiagKindRefactor.parse_unexpected_newline_between_at_and_mc => 198
        case DiagKindRefactor.parse_expect_escape_dollar_token => 199
        case DiagKindRefactor.parse_varray_type_parameter => 200
        case DiagKindRefactor.parse_varray_type_args_mismatch => 201
        case DiagKindRefactor.parse_expect_integer_literal_varray => 202
        case DiagKindRefactor.parse_varray_with_paren => 203
        case DiagKindRefactor.parse_expected_import => 204
        case DiagKindRefactor.parse_expected_right_delimiter => 205
        case DiagKindRefactor.parse_not_allowed_raw_identifier => 206
        case DiagKindRefactor.parse_invalid_return_type => 207
        case DiagKindRefactor.parse_unmatched_right_delimiter => 208
        case DiagKindRefactor.parse_expected_literal => 209
        case DiagKindRefactor.parse_expected_pattern => 210
        case DiagKindRefactor.parse_expected_backarrow_in_let_cond => 211
        case DiagKindRefactor.parse_expected_left_paren_after => 212
        case DiagKindRefactor.parse_expected_left_angle_after => 213
        case DiagKindRefactor.parse_expected_expr_or_decl_in => 214
        case DiagKindRefactor.parse_expected_catch_or_finally_in_try => 215
        case DiagKindRefactor.parse_expected_catch_or_handle_or_finally_in_try => 216
        case DiagKindRefactor.parse_expected_colon_in_catch_pattern => 217
        case DiagKindRefactor.parse_expected_colon_in_effect_pattern => 218
        case DiagKindRefactor.parse_expected_wildcard_or_exception_pattern => 219
        case DiagKindRefactor.parse_expected_wildcard_or_effect_pattern => 220
        case DiagKindRefactor.parse_expected_double_arrow_in_case => 221
        case DiagKindRefactor.parse_selector_or_match_expression_body => 222
        case DiagKindRefactor.parse_expected_left_brace => 223
        case DiagKindRefactor.parse_expected_left_paren => 224
        case DiagKindRefactor.parse_expected_case => 225
        case DiagKindRefactor.parse_unexpected_line_break => 226
        case DiagKindRefactor.parse_expected_paren_or_brace_after_try => 227
        case DiagKindRefactor.parse_expected_assignment => 228
        case DiagKindRefactor.parse_expected_in_forin_expression => 229
        case DiagKindRefactor.parse_expected_while_in_do_while => 230
        case DiagKindRefactor.parse_expected_double_arrow_in_lambda => 231
        case DiagKindRefactor.parse_expected_ccd_in_lambda => 232
        case DiagKindRefactor.parse_expected_character => 233
        case DiagKindRefactor.parse_expected_character_after => 234
        case DiagKindRefactor.parse_importing_by_package_name_is_not_supported => 235
        case DiagKindRefactor.parse_expected_decl => 236
        case DiagKindRefactor.parse_expected_one_of_identifier_or_pattern => 237
        case DiagKindRefactor.parse_expected_get_or_set_in_prop => 238
        case DiagKindRefactor.parse_expected_where_brace => 239
        case DiagKindRefactor.parse_expected_lt_brace => 240
        case DiagKindRefactor.parse_expected_lt_paren => 241
        case DiagKindRefactor.parse_expected_identifier_lp => 242
        case DiagKindRefactor.parse_expected_dot_lparen => 243
        case DiagKindRefactor.parse_expected_arrow_in_func_type => 244
        case DiagKindRefactor.parse_unexpected_colon_in_range => 245
        case DiagKindRefactor.parse_expected_lsquare_after => 246
        case DiagKindRefactor.parse_expected_type_argument => 247
        case DiagKindRefactor.parse_expected_parameter_rp => 248
        case DiagKindRefactor.parse_expected_no_newline_after => 249
        case DiagKindRefactor.parse_expected_if_let_andand => 250
        case DiagKindRefactor.parse_duplicated_item => 251
        case DiagKindRefactor.parse_nl_warning => 252
        case DiagKindRefactor.parse_illegal_function_name => 253
        case DiagKindRefactor.parse_expected_macro_decl_define_in_macro_package => 254
        case DiagKindRefactor.parse_expected_public_before_macro_decl => 255
        case DiagKindRefactor.parse_macro_unexpected_empty_parameter => 256
        case DiagKindRefactor.parse_macro_expected_right_parameter_nums => 257
        case DiagKindRefactor.parse_macro_illegal_param_type => 258
        case DiagKindRefactor.parse_macro_illegal_ret_type => 259
        case DiagKindRefactor.parse_macro_illegal_named_param => 260
        case DiagKindRefactor.parse_macro_define_conflicted_with_builtin => 261
        case DiagKindRefactor.parse_macro_call_illegal_with_builtin => 262
        case DiagKindRefactor.parse_unexpected_declaration_in_scope => 263
        case DiagKindRefactor.parse_const_expected_initializer => 264
        case DiagKindRefactor.parse_unexpected_const_modifier_on_variable => 265
        case DiagKindRefactor.parse_var_must_be_initialized => 266
        case DiagKindRefactor.parse_expected_one_of_type_or_initializer => 267
        case DiagKindRefactor.parse_expected_type_or_init_in_pattern => 268
        case DiagKindRefactor.parse_named_parameter_after_unnamed => 269
        case DiagKindRefactor.parse_member_parameter_after_regular => 270
        case DiagKindRefactor.parse_decl_cannot_inherit_their_self => 271
        case DiagKindRefactor.parse_intrinsic_function_must_be_toplevel => 272
        case DiagKindRefactor.parse_intrinsic_function_cannot_have_body => 273
        case DiagKindRefactor.parse_abstract_func_must_have_return_type => 274
        case DiagKindRefactor.parse_duplicated_get_or_set => 275
        case DiagKindRefactor.parse_unknown_enum_constructor => 276
        case DiagKindRefactor.parse_getter_setter_cannot_be_generic => 277
        case DiagKindRefactor.parse_unexpected_where => 278
        case DiagKindRefactor.parse_setter_must_contain_one_parameter => 279
        case DiagKindRefactor.parse_setter_can_only_accept_one_parameter => 280
        case DiagKindRefactor.parse_duplicated_intrinsic_function => 281
        case DiagKindRefactor.parse_missing_body => 282
        case DiagKindRefactor.parse_invalid_super_declaration => 283
        case DiagKindRefactor.parse_static_init_can_not_accept_any_parameter => 284
        case DiagKindRefactor.parse_finalizer_can_not_accept_any_parameter => 285
        case DiagKindRefactor.parse_invalid_quote_dollar_expr => 286
        case DiagKindRefactor.parse_unexpected_lambda_expr_in_toplevel => 287
        case DiagKindRefactor.parse_trailing_closure_only_follow_name => 288
        case DiagKindRefactor.parse_invalid_left_hand_expr => 289
        case DiagKindRefactor.parse_chained_none_associative => 290
        case DiagKindRefactor.parse_duplicated_step_op => 291
        case DiagKindRefactor.parse_invalid_step_op => 292
        case DiagKindRefactor.parse_expected_expression => 293
        case DiagKindRefactor.parse_invalid_incre_expr => 294
        case DiagKindRefactor.parse_unrecognized_token_after_macro_node => 295
        case DiagKindRefactor.parse_expected_operator_or_end => 296
        case DiagKindRefactor.parse_cannot_have_assi_in_init => 297
        case DiagKindRefactor.parse_case_body_cannot_be_empty => 298
        case DiagKindRefactor.parse_redefined_resource_name => 299
        case DiagKindRefactor.parse_newline_not_allowed_between_spawn_and_argument => 300
        case DiagKindRefactor.parse_expected_no_arguments_in_spawn => 301
        case DiagKindRefactor.parse_invalid_overloaded_operator => 302
        case DiagKindRefactor.parse_empty_string_interpolation => 303
        case DiagKindRefactor.parse_invalid_unicode_scalar => 304
        case DiagKindRefactor.parse_wildcard_can_not_be_used_as_member_name => 305
        case DiagKindRefactor.parse_unexpected_expected_found => 306
        case DiagKindRefactor.parse_cannot_operator_a_tuple => 307
        case DiagKindRefactor.parse_expected_parentheses => 308
        case DiagKindRefactor.parse_this_type_not_allow => 309
        case DiagKindRefactor.parse_unexpected_tuple_decl_type => 310
        case DiagKindRefactor.parse_expected_type => 311
        case DiagKindRefactor.parse_newline_not_allowed_between_quest_and_type => 312
        case DiagKindRefactor.parse_redundant_arrow_after_func_type => 313
        case DiagKindRefactor.parse_all_parameters_must_be_named => 314
        case DiagKindRefactor.parse_only_tuple_and_func_type_allow_type_parameter_name => 315
        case DiagKindRefactor.parse_illegal_declaration_pattern => 316
        case DiagKindRefactor.parse_illegal_or_pattern => 317
        case DiagKindRefactor.parse_tuple_pattern_expected_more_field => 318
        case DiagKindRefactor.parse_type_pattern_in_let_cond => 319
        case DiagKindRefactor.parse_expected_macro_decl_in_macro_package => 320
        case DiagKindRefactor.parse_package_as_all => 321
        case DiagKindRefactor.parse_package_name_length_overflow => 322
        case DiagKindRefactor.parse_package_name_has_backtick => 323
        case DiagKindRefactor.parse_illegal_macro_expand_input_args => 324
        case DiagKindRefactor.parse_illegal_macro_expand_attr_args => 325
        case DiagKindRefactor.parse_illegal_macro_expand_input_args_without_paren => 326
        case DiagKindRefactor.parse_illegal_macro_expand_input_without_paren_in_paramlist => 327
        case DiagKindRefactor.parse_ifavailable_arg_no_name => 328
        case DiagKindRefactor.parse_ifavailable_not_lambda => 329
        case DiagKindRefactor.parse_unexpected_anno_on => 330
        case DiagKindRefactor.parse_unexpected_overflow_annotation => 331
        case DiagKindRefactor.parse_unrecognized_expression_in_when => 332
        case DiagKindRefactor.parse_unrecognized_attr_in_anno => 333
        case DiagKindRefactor.parse_empty_attribute => 334
        case DiagKindRefactor.parse_duplicated_attr_value => 335
        case DiagKindRefactor.parse_unsafe_will_be_ignored => 336
        case DiagKindRefactor.parse_duplicated_annotation => 337
        case DiagKindRefactor.parse_conflict_annotation => 338
        case DiagKindRefactor.parse_fail_expected_annotation => 339
        case DiagKindRefactor.parse_common_function_must_have_return_type => 340
        case DiagKindRefactor.parse_specific_function_must_have_return_type => 341
        case DiagKindRefactor.parse_specific_function_parameter_cannot_have_default_value => 342
        case DiagKindRefactor.parse_specific_member_must_have_implementation => 343
        case DiagKindRefactor.parse_expected_type_with_cjmp_var => 344
        case DiagKindRefactor.parse_cjmp_outdecl_miss_match => 345
        case DiagKindRefactor.parse_cjmp_static_init => 346
        case DiagKindRefactor.parse_unexpected_cjmp_decl => 347
        case DiagKindRefactor.parse_cjmp_generic_decl => 348
        case DiagKindRefactor.parse_cjmp_pattern_decl => 349
        case DiagKindRefactor.parse_cjmp_in_common_ctor_required => 350
        case DiagKindRefactor.parse_explicitly_abstract_only_for_cjmp_abstract_class => 351
        case DiagKindRefactor.parse_illegal_modifier_in_scope => 352
        case DiagKindRefactor.parse_conflict_modifier => 353
        case DiagKindRefactor.parse_expected_no_modifier => 354
        case DiagKindRefactor.parse_duplicate_modifier => 355
        case DiagKindRefactor.parse_duplicate_type_parameter_name => 356
        case DiagKindRefactor.parse_unexpected_type_in => 357
        case DiagKindRefactor.parse_redundant_modifier => 358
        case DiagKindRefactor.parse_variable_length_parameter_can_not_be_first => 359
        case DiagKindRefactor.parse_variable_length_parameter_must_in_the_end => 360
        case DiagKindRefactor.parse_variable_length_parameter_only_in_the_foreign_function => 361
        case DiagKindRefactor.parse_foreign_func_should_not_be_generic => 362
        case DiagKindRefactor.parse_foreign_func_must_declare_return_type => 363
        case DiagKindRefactor.parse_foreign_function_with_body => 364
        case DiagKindRefactor.parse_expected_static_for_const_member_var => 365
        case DiagKindRefactor.parse_deprecated_wrong_argument => 366
        case DiagKindRefactor.parse_deprecated_argument_duplication => 367
        case DiagKindRefactor.parse_deprecated_arguments_must_be_lit_const_expr => 368
        case DiagKindRefactor.parse_deprecated_empty_string_argument => 369
        case DiagKindRefactor.parse_deprecated_unknown_argument => 370
        case DiagKindRefactor.parse_deprecated_invalid_target => 371
        case DiagKindRefactor.parse_annotation_max_one_argument => 372
        case DiagKindRefactor.parse_annotation_one_argument => 373
        case DiagKindRefactor.parse_annotation_no_arguments => 374
        case DiagKindRefactor.parse_foreign_name_on_ffi_decl_member => 375
        case DiagKindRefactor.parse_java_mirror_function_cannot_have_body => 376
        case DiagKindRefactor.parse_java_mirror_function_must_have_return_type => 377
        case DiagKindRefactor.parse_java_mirror_prop_is_forbidden => 378
        case DiagKindRefactor.parse_java_mirror_decl_cannot_have_primary_ctor => 379
        case DiagKindRefactor.parse_java_mirror_constructor_cannot_have_body => 380
        case DiagKindRefactor.parse_java_mirror_cannot_have_private_member => 381
        case DiagKindRefactor.parse_java_mirror_cannot_have_static_init => 382
        case DiagKindRefactor.parse_java_mirror_cannot_have_finalizer => 383
        case DiagKindRefactor.parse_java_mirror_cannot_have_const_member => 384
        case DiagKindRefactor.parse_java_mirror_cannot_be_sealed => 385
        case DiagKindRefactor.parse_java_impl_cannot_be_generic => 386
        case DiagKindRefactor.parse_java_impl_cannot_be_abstract => 387
        case DiagKindRefactor.parse_java_impl_cannot_be_sealed => 388
        case DiagKindRefactor.parse_java_impl_cannot_have_static_init => 389
        case DiagKindRefactor.parse_java_impl_cannot_be_open => 390
        case DiagKindRefactor.parse_java_impl_cannot_be_interface => 391
        case DiagKindRefactor.parse_objc_mirror_cannot_have_primary_ctor => 392
        case DiagKindRefactor.parse_objc_mirror_ctor_cannot_have_body => 393
        case DiagKindRefactor.parse_objc_mirror_method_cannot_have_body => 394
        case DiagKindRefactor.parse_objc_mirror_method_must_have_return_type => 395
        case DiagKindRefactor.parse_objc_mirror_cannot_be_sealed => 396
        case DiagKindRefactor.parse_objc_mirror_cannot_have_private_member => 397
        case DiagKindRefactor.parse_objc_mirror_cannot_have_static_init => 398
        case DiagKindRefactor.parse_objc_mirror_cannot_have_finalizer => 399
        case DiagKindRefactor.parse_objc_mirror_cannot_have_const_member => 400
        case DiagKindRefactor.parse_objc_impl_cannot_be_generic => 401
        case DiagKindRefactor.parse_objc_impl_cannot_be_abstract => 402
        case DiagKindRefactor.parse_objc_impl_cannot_be_sealed => 403
        case DiagKindRefactor.parse_objc_impl_cannot_have_static_init => 404
        case DiagKindRefactor.parse_objc_impl_cannot_be_open => 405
        case DiagKindRefactor.parse_objc_impl_cannot_be_interface => 406
        case DiagKindRefactor.parse_objc_mirror_field_cannot_have_initializer => 407
        case DiagKindRefactor.parse_objc_mirror_field_cannot_be_static => 408
        case DiagKindRefactor.parse_objc_mirror_prop_cannot_have_getter => 409
        case DiagKindRefactor.parse_objc_mirror_prop_cannot_have_setter => 410
        case DiagKindRefactor.parse_objc_mirror_func_cannot_be_foreign => 411
        case DiagKindRefactor.parse_objc_mirror_func_cannot_be_c => 412
        case DiagKindRefactor.parse_objc_mirror_func_cannot_be_generic => 413
        case DiagKindRefactor.parse_objc_mirror_func_cannot_have_body => 414
        case DiagKindRefactor.parse_objc_mirror_func_must_have_explicit_type => 415
        case DiagKindRefactor.parse_objc_mirror_func_cannot_be_const => 416
        case DiagKindRefactor.parse_objc_mirror_func_must_be_top_level => 417
        case DiagKindRefactor.parse_objc_init_method_must_be_static => 418
        case DiagKindRefactor.parse_objc_init_method_must_be_in_mirror_class => 419
        case DiagKindRefactor.parse_objc_optional_method_must_be_in_mirror_class => 420
        case DiagKindRefactor.parse_objc_interop_not_supported => 421
        case DiagKindRefactor.parse_diag_error => 422
        case DiagKindRefactor.parse_diag_warning => 423
        case DiagKindRefactor.parse_diag_end => 424
        case DiagKindRefactor.parse_query_diag_begin => 425
        case DiagKindRefactor.parse_query_expected_position_compare_operator => 426
        case DiagKindRefactor.parse_query_expected_hash_id_compare_operator => 427
        case DiagKindRefactor.parse_query_invalid_query_value => 428
        case DiagKindRefactor.parse_query_expected_query_symbol => 429
        case DiagKindRefactor.parse_query_expected_logic_symbol => 430
        case DiagKindRefactor.parse_query_position_illegal_file_id => 431
        case DiagKindRefactor.parse_query_position_illegal_line_num => 432
        case DiagKindRefactor.parse_query_position_illegal_column_num => 433
        case DiagKindRefactor.parse_query_position_comma_required => 434
        case DiagKindRefactor.parse_query_hashid_illegal_file_hash => 435
        case DiagKindRefactor.parse_query_hashid_illegal_fieldid => 436
        case DiagKindRefactor.searcher_past_the_end_of_array => 437
        case DiagKindRefactor.searcher_empty_number => 438
        case DiagKindRefactor.searcher_invalid_number => 439
        case DiagKindRefactor.searcher_invalid_scope_name => 440
        case DiagKindRefactor.parse_query_diag_end => 441
        case DiagKindRefactor.sema_diag_begin => 442
        case DiagKindRefactor.sema_invalid_node_after_check => 443
        case DiagKindRefactor.sema_unable_to_infer_decl => 444
        case DiagKindRefactor.sema_mismatched_types => 445
        case DiagKindRefactor.sema_mismatched_types_multiple_assign => 446
        case DiagKindRefactor.sema_mismatched_types_because => 447
        case DiagKindRefactor.sema_ambiguous_use => 448
        case DiagKindRefactor.sema_undeclared_identifier => 449
        case DiagKindRefactor.sema_undefined_variable => 450
        case DiagKindRefactor.sema_redefinition => 451
        case DiagKindRefactor.sema_conflict_with_sub_package => 452
        case DiagKindRefactor.sema_core_object_not_found_when_no_prelude => 453
        case DiagKindRefactor.sema_accessibility_with_main_hint => 454
        case DiagKindRefactor.sema_accessibility => 455
        case DiagKindRefactor.sema_param_miss_match => 456
        case DiagKindRefactor.sema_unable_to_infer_return_type => 457
        case DiagKindRefactor.sema_unable_to_infer_generic_func => 458
        case DiagKindRefactor.sema_invalid_called_object => 459
        case DiagKindRefactor.sema_invalid_return => 460
        case DiagKindRefactor.sema_invalid_return_in_static_init => 461
        case DiagKindRefactor.sema_wrong_number_of_arguments => 462
        case DiagKindRefactor.sema_unordered_arguments => 463
        case DiagKindRefactor.sema_param_named_mismatched => 464
        case DiagKindRefactor.sema_need_named_argument => 465
        case DiagKindRefactor.sema_invalid_subscript_assign_parameter => 466
        case DiagKindRefactor.sema_invalid_subscript_assign_parameter_num => 467
        case DiagKindRefactor.sema_invalid_subscript_assign_return => 468
        case DiagKindRefactor.sema_overload_conflicts => 469
        case DiagKindRefactor.sema_static_function_overload_conflicts => 470
        case DiagKindRefactor.sema_use_mutable_func_alone => 471
        case DiagKindRefactor.sema_unsafe_func_can_only_be_called => 472
        case DiagKindRefactor.sema_ambiguous_match_primitive_extend => 473
        case DiagKindRefactor.sema_immutable_access_mutable_func => 474
        case DiagKindRefactor.sema_recursive_constructor_call => 475
        case DiagKindRefactor.sema_cannot_have_default_param => 476
        case DiagKindRefactor.sema_trailing_lambda_cannot_used_for_non_function => 477
        case DiagKindRefactor.sema_unable_to_infer_expr => 478
        case DiagKindRefactor.sema_exceed_num_value_range => 479
        case DiagKindRefactor.sema_exceed_float_literal_range => 480
        case DiagKindRefactor.sema_float_literal_too_large => 481
        case DiagKindRefactor.sema_float_literal_too_small => 482
        case DiagKindRefactor.sema_invalid_unary_expr => 483
        case DiagKindRefactor.sema_invalid_unary_expr_with_target => 484
        case DiagKindRefactor.sema_invalid_binary_expr => 485
        case DiagKindRefactor.sema_invalid_subscript_expr => 486
        case DiagKindRefactor.sema_cannot_assign_to_subscript => 487
        case DiagKindRefactor.sema_not_member_of => 488
        case DiagKindRefactor.sema_member_not_imported => 489
        case DiagKindRefactor.sema_cannot_assign_to_immutable => 490
        case DiagKindRefactor.sema_unqualified_left_value_assigned => 491
        case DiagKindRefactor.sema_not_found_from_generic_upper_bounds => 492
        case DiagKindRefactor.sema_different_or_pattern => 493
        case DiagKindRefactor.sema_var_in_or_pattern => 494
        case DiagKindRefactor.sema_var_in_or_condition => 495
        case DiagKindRefactor.sema_nonexhuastive_patterns => 496
        case DiagKindRefactor.sema_unreachable_pattern => 497
        case DiagKindRefactor.sema_lambdaExpr_must_have_type_annotation => 498
        case DiagKindRefactor.sema_use_func_capture_var_alone => 499
        case DiagKindRefactor.sema_enum_constructor_with_param_must_have_args => 500
        case DiagKindRefactor.sema_optional_chain_non_optional => 501
        case DiagKindRefactor.sema_capture_before_initialization => 502
        case DiagKindRefactor.sema_interpolation_in_const_pattern => 503
        case DiagKindRefactor.sema_cannot_ref_to_pkg_name => 504
        case DiagKindRefactor.sema_use_expr_without_import => 505
        case DiagKindRefactor.sema_generic_func_without_type_arg => 506
        case DiagKindRefactor.sema_generic_type_inconsistent => 507
        case DiagKindRefactor.sema_generic_argument_no_match => 508
        case DiagKindRefactor.sema_generic_constraint_not_looser => 509
        case DiagKindRefactor.sema_generic_instantiation_causes_ambiguous_functions => 510
        case DiagKindRefactor.sema_multiple_class_upperbounds => 511
        case DiagKindRefactor.sema_generic_param_exist_in_class_irrelevant_upperbound_recursively => 512
        case DiagKindRefactor.sema_generic_param_directly_recursive => 513
        case DiagKindRefactor.sema_upper_bound_must_be_class_or_interface => 514
        case DiagKindRefactor.sema_inherit_member_kind_inconsistent => 515
        case DiagKindRefactor.sema_inherit_super_member_kind_inconsistent => 516
        case DiagKindRefactor.sema_inherit_member_type_inconsistent => 517
        case DiagKindRefactor.sema_inherit_abstract_class_static_unimplement_func => 518
        case DiagKindRefactor.sema_cannot_override => 519
        case DiagKindRefactor.sema_invalid_member_visibility_in_class => 520
        case DiagKindRefactor.sema_weak_visibility => 521
        case DiagKindRefactor.sema_cannot_inherit_sealed => 522
        case DiagKindRefactor.sema_inherit_thread_context_invalid => 523
        case DiagKindRefactor.sema_inherit_thread_context_not_open => 524
        case DiagKindRefactor.sema_inherit_not_return_this => 525
        case DiagKindRefactor.sema_return_type_incompatible => 526
        case DiagKindRefactor.sema_spawn_arg_invalid => 527
        case DiagKindRefactor.sema_spawn_arg_no_effect => 528
        case DiagKindRefactor.sema_spawn_capture_var => 529
        case DiagKindRefactor.sema_interface_call_with_unimplemented_call => 530
        case DiagKindRefactor.sema_type_uninitialized_static_field => 531
        case DiagKindRefactor.sema_instance_func_cannot_be_used_in_finalizer => 532
        case DiagKindRefactor.sema_no_non_param_constructor_in_super_class => 533
        case DiagKindRefactor.sema_non_abstract_class_cannot_be_sealed => 534
        case DiagKindRefactor.sema_static_variable_use_generic_parameter => 535
        case DiagKindRefactor.sema_cstruct_cannot_impl_interfaces => 536
        case DiagKindRefactor.sema_class_need_abstract_modifier_or_func_need_impl => 537
        case DiagKindRefactor.sema_need_member_implementation => 538
        case DiagKindRefactor.sema_export_same_private_decl => 539
        case DiagKindRefactor.sema_extend_function_cannot_overridden => 540
        case DiagKindRefactor.sema_extend_member_cannot_shadow => 541
        case DiagKindRefactor.sema_illegal_extended_type => 542
        case DiagKindRefactor.sema_extend_generic_must_be_used => 543
        case DiagKindRefactor.sema_extend_duplicate_interface => 544
        case DiagKindRefactor.sema_extend_not_interface => 545
        case DiagKindRefactor.sema_extend_illegal_member => 546
        case DiagKindRefactor.sema_extend_use_super => 547
        case DiagKindRefactor.sema_type_cannot_extend_imported_interface => 548
        case DiagKindRefactor.sema_c_type_cannot_extend_interface => 549
        case DiagKindRefactor.sema_immutable_type_extend_assignment_index_operator => 550
        case DiagKindRefactor.sema_immutable_type_illegal_property => 551
        case DiagKindRefactor.sema_interface_is_not_extendable => 552
        case DiagKindRefactor.sema_invalid_mut_modifier_extend_of_struct => 553
        case DiagKindRefactor.sema_extend_check_sequence_cannot_decide => 554
        case DiagKindRefactor.sema_export_extend_depend_non_export_extend => 555
        case DiagKindRefactor.sema_property_must_have_accessors => 556
        case DiagKindRefactor.sema_immutable_property_with_setter => 557
        case DiagKindRefactor.sema_property_have_same_declaration_in_inherit_mut => 558
        case DiagKindRefactor.sema_property_have_same_declaration_in_inherit_immut => 559
        case DiagKindRefactor.sema_property_must_implement_both => 560
        case DiagKindRefactor.sema_expect_const => 561
        case DiagKindRefactor.sema_cannot_define_var_in_const_funciton => 562
        case DiagKindRefactor.sema_no_const_init => 563
        case DiagKindRefactor.sema_class_const_init_with_var => 564
        case DiagKindRefactor.sema_annotation_no_const_init => 565
        case DiagKindRefactor.sema_annotation_arg_target => 566
        case DiagKindRefactor.sema_annotation_arg_target_array_lit => 567
        case DiagKindRefactor.sema_annotation_non_public => 568
        case DiagKindRefactor.sema_annotation_custom_place => 569
        case DiagKindRefactor.sema_inout_modify_cstring_or_zerosized => 570
        case DiagKindRefactor.sema_inout_modify_non_ctype => 571
        case DiagKindRefactor.sema_inout_must_be_var_variable => 572
        case DiagKindRefactor.sema_inout_modify_heap_variable => 573
        case DiagKindRefactor.sema_inout_can_only_used_in_cfunc_calling => 574
        case DiagKindRefactor.sema_inout_mismatch => 575
        case DiagKindRefactor.sema_annotation_error_arg_num => 576
        case DiagKindRefactor.sema_annotation_error_arg_range => 577
        case DiagKindRefactor.sema_annotation_error_object => 578
        case DiagKindRefactor.sema_java_incorrect_use_between_types => 579
        case DiagKindRefactor.sema_java_non_jtype => 580
        case DiagKindRefactor.sema_java_invalid_unit => 581
        case DiagKindRefactor.sema_java_app_inherit_ext => 582
        case DiagKindRefactor.sema_java_unsupported_decl => 583
        case DiagKindRefactor.sema_missing_java_interop_annotation => 584
        case DiagKindRefactor.sema_generic_static_access => 585
        case DiagKindRefactor.sema_primitive_type_as_generics_arg => 586
        case DiagKindRefactor.sema_meet_constraint_indirectly => 587
        case DiagKindRefactor.sema_static_member_in_interface_must_has_body => 588
        case DiagKindRefactor.sema_extend_a_java_type => 589
        case DiagKindRefactor.sema_generic_upper_bounds_must_be_java_in_java => 590
        case DiagKindRefactor.sema_define_java_annotation => 591
        case DiagKindRefactor.sema_invalid_use_of_java_annotation => 592
        case DiagKindRefactor.sema_invalid_use_of_annotation_jffi => 593
        case DiagKindRefactor.sema_annotation_not_applicable_jffi => 594
        case DiagKindRefactor.sema_cannot_use_annotation_jffi => 595
        case DiagKindRefactor.sema_shadow_cannot_in_type_args => 596
        case DiagKindRefactor.sema_unsupported_type_argument_in_java_interop => 597
        case DiagKindRefactor.sema_cjmapping_struct_generic_not_supported => 598
        case DiagKindRefactor.sema_cjmapping_struct_inheritance_interface_not_supported => 599
        case DiagKindRefactor.sema_cjmapping_decl_not_supported => 600
        case DiagKindRefactor.sema_cjmapping_method_arg_not_supported => 601
        case DiagKindRefactor.sema_cjmapping_method_ret_unsupported => 602
        case DiagKindRefactor.sema_cj_mapping_generic_method_not_get_instance_config => 603
        case DiagKindRefactor.sema_varray_size_match => 604
        case DiagKindRefactor.sema_varray_args_number_mismatch => 605
        case DiagKindRefactor.sema_varray_subscript_num => 606
        case DiagKindRefactor.sema_varray_in_cfunc => 607
        case DiagKindRefactor.sema_varray_arg_type_with_reftype => 608
        case DiagKindRefactor.sema_only_cfunc_can_use_annotation => 609
        case DiagKindRefactor.sema_annotation_calling_conv_not_support => 610
        case DiagKindRefactor.sema_annotation_invalid_args_type => 611
        case DiagKindRefactor.sema_illegal_scope_use_of_annotation => 612
        case DiagKindRefactor.sema_invalid_cfunc_return_type => 613
        case DiagKindRefactor.sema_mock_disabled => 614
        case DiagKindRefactor.sema_mock_not_in_test_mode => 615
        case DiagKindRefactor.sema_mock_unsupported_type => 616
        case DiagKindRefactor.sema_mock_wrong_static_decl => 617
        case DiagKindRefactor.sema_mock_doesnt_support_mocking => 618
        case DiagKindRefactor.sema_mock_frozen_unsupported => 619
        case DiagKindRefactor.sema_mock_frozen_required => 620
        case DiagKindRefactor.sema_command_handle_type_error => 621
        case DiagKindRefactor.sema_resumption_handle_type_error => 622
        case DiagKindRefactor.sema_resumption_incorrect_return_type => 623
        case DiagKindRefactor.sema_command_resumption_mismatch => 624
        case DiagKindRefactor.sema_implicit_resume_outside_handler => 625
        case DiagKindRefactor.sema_resume_no_with => 626
        case DiagKindRefactor.sema_resume_wrong_resumption_type => 627
        case DiagKindRefactor.sema_mismatching_handle_block => 628
        case DiagKindRefactor.sema_return_in_try_handle_block => 629
        case DiagKindRefactor.sema_try_handle_capture_var => 630
        case DiagKindRefactor.sema_command_incompatible_type => 631
        case DiagKindRefactor.sema_resume_throwing_mismatch_type => 632
        case DiagKindRefactor.sema_useless_command_type => 633
        case DiagKindRefactor.sema_deprecated_error => 634
        case DiagKindRefactor.sema_deprecated_warning => 635
        case DiagKindRefactor.sema_deprecation_weakening => 636
        case DiagKindRefactor.sema_deprecation_override_error => 637
        case DiagKindRefactor.sema_deprecation_override_warning => 638
        case DiagKindRefactor.sema_deprecation_redef_error => 639
        case DiagKindRefactor.sema_deprecation_redef_warning => 640
        case DiagKindRefactor.sema_common_open_class_no_init => 641
        case DiagKindRefactor.sema_multiple_common_implementations => 642
        case DiagKindRefactor.sema_common_direct_extension_has_duplicate_private_members => 643
        case DiagKindRefactor.sema_common_direct_extension_has_common_private_members => 644
        case DiagKindRefactor.sema_not_matched => 645
        case DiagKindRefactor.sema_specific_var_not_match_let => 646
        case DiagKindRefactor.sema_specific_init_common_primary_constructor => 647
        case DiagKindRefactor.specific_has_different_kind => 648
        case DiagKindRefactor.sema_specific_primary_unmatched_var_decl => 649
        case DiagKindRefactor.common_non_exaustive_platfrom_exaustive_mismatch => 650
        case DiagKindRefactor.sema_specific_has_different_type => 651
        case DiagKindRefactor.sema_specific_member_must_have_implementation => 652
        case DiagKindRefactor.sema_specific_has_different_modifier => 653
        case DiagKindRefactor.sema_specific_has_different_annotation => 654
        case DiagKindRefactor.sema_specific_has_deprecated_annotation => 655
        case DiagKindRefactor.sema_cjmp_parameter_default_value_both_sides => 656
        case DiagKindRefactor.sema_specific_has_different_parameter => 657
        case DiagKindRefactor.sema_specific_has_different_super_type => 658
        case DiagKindRefactor.sema_specific_has_duplicate_extensions => 659
        case DiagKindRefactor.sema_common_package_has_main => 660
        case DiagKindRefactor.sema_common_static_let_cant_be_initialized_in_static_init => 661
        case DiagKindRefactor.sema_common_assign_to_common_immutable_in_ctor => 662
        case DiagKindRefactor.sema_cjmp_abstract_class_member_has_no_explicit_modifier => 663
        case DiagKindRefactor.sema_explicitly_abstract_can_not_have_body => 664
        case DiagKindRefactor.sema_explicitly_abstract_only_for_cjmp_abstract_class => 665
        case DiagKindRefactor.sema_open_abstract_specific_can_not_replace_open_common => 666
        case DiagKindRefactor.sema_cjmp_non_specific_abstract_member_in_specific_class => 667
        case DiagKindRefactor.sema_common_generic_frozen_not_supported => 668
        case DiagKindRefactor.sema_common_generic_rename_not_supported => 669
        case DiagKindRefactor.sema_common_specific_annotation_not_allowed => 670
        case DiagKindRefactor.sema_java_mirror_ctor_arg_must_be_java_mirror => 671
        case DiagKindRefactor.sema_java_mirror_method_arg_must_be_java_mirror => 672
        case DiagKindRefactor.sema_java_mirror_method_ret_unsupported => 673
        case DiagKindRefactor.sema_java_mirror_prop_must_be_java_mirror => 674
        case DiagKindRefactor.sema_java_mirror_subtype_must_be_annotated => 675
        case DiagKindRefactor.sema_java_mirror_cannot_inherit_pure_cangjie_type => 676
        case DiagKindRefactor.sema_java_impl_cannot_inherit_pure_cangjie_type => 677
        case DiagKindRefactor.sema_java_mirror_subtype_anno_must_inherit_mirror => 678
        case DiagKindRefactor.sema_java_mirror_cannot_be_extended_with_interface => 679
        case DiagKindRefactor.sema_java_impl_cannot_be_extended_with_interface => 680
        case DiagKindRefactor.sema_java_impl_redefinition => 681
        case DiagKindRefactor.sema_java_mirror_interoplib_must_be_imported => 682
        case DiagKindRefactor.sema_java_interop_not_supported => 683
        case DiagKindRefactor.sema_extend_ref_target_cannot_be_java_impl => 684
        case DiagKindRefactor.sema_generic_parameter_of_java_type => 685
        case DiagKindRefactor.sema_java_interoplib_version_too_old => 686
        case DiagKindRefactor.sema_java_interoplib_version_mismatch => 687
        case DiagKindRefactor.sema_java_has_default_annotation_args => 688
        case DiagKindRefactor.sema_java_has_default_annotation_is_in_wrong_place => 689
        case DiagKindRefactor.sema_java_has_default_conflict_with_static => 690
        case DiagKindRefactor.sema_objc_interop_ctor_param_must_be_objc_compatible => 691
        case DiagKindRefactor.sema_objc_interop_method_param_must_be_objc_compatible => 692
        case DiagKindRefactor.sema_objc_interop_method_ret_must_be_objc_compatible => 693
        case DiagKindRefactor.sema_objc_interop_prop_must_be_objc_compatible => 694
        case DiagKindRefactor.sema_objc_interop_field_must_be_objc_compatible => 695
        case DiagKindRefactor.sema_objc_mirror_decl_cannot_inherit => 696
        case DiagKindRefactor.sema_objc_mirror_subtype_cannot_multiple_inherit => 697
        case DiagKindRefactor.sema_objc_mirror_subtype_must_be_annotated => 698
        case DiagKindRefactor.sema_objc_mirror_subtype_must_inherit_mirror => 699
        case DiagKindRefactor.sema_objc_mirror_must_inherit_mirror => 700
        case DiagKindRefactor.sema_objc_mirror_interoplib_must_be_imported => 701
        case DiagKindRefactor.sema_objc_interop_not_supported => 702
        case DiagKindRefactor.sema_objc_pointer_argument_must_be_objc_compatible => 703
        case DiagKindRefactor.sema_objc_interop_toplevel_param_must_be_objc_compatible => 704
        case DiagKindRefactor.sema_objc_interop_toplevel_ret_must_be_objc_compatible => 705
        case DiagKindRefactor.sema_objc_method_must_have_foreign_name => 706
        case DiagKindRefactor.sema_objc_ctor_must_have_foreign_name => 707
        case DiagKindRefactor.sema_objc_func_argument_must_be_objc_compatible => 708
        case DiagKindRefactor.sema_objc_func_call_property_can_only_be_called => 709
        case DiagKindRefactor.sema_objc_impl_must_have_objc_mirror_super_class => 710
        case DiagKindRefactor.sema_objc_setter_name_on_immutable_prop => 711
        case DiagKindRefactor.sema_objc_cjmapping_inheritance_interface_not_supported => 712
        case DiagKindRefactor.sema_objc_cjmapping_generic_not_supported => 713
        case DiagKindRefactor.sema_foreign_name_appeared_in_child => 714
        case DiagKindRefactor.sema_foreign_name_conflicting_annotation => 715
        case DiagKindRefactor.sema_foreign_name_conflicting_derived_annotation => 716
        case DiagKindRefactor.sema_ifavailable_arg_no_name => 717
        case DiagKindRefactor.sema_ifavailable_arg_not_literal => 718
        case DiagKindRefactor.sema_ifavailable_unknow_arg_name => 719
        case DiagKindRefactor.sema_apilevel_multi_anno => 720
        case DiagKindRefactor.sema_apilevel_missing_arg => 721
        case DiagKindRefactor.sema_apilevel_invalid_version_format => 722
        case DiagKindRefactor.sema_only_literal_support => 723
        case DiagKindRefactor.sema_apilevel_ref_higher => 724
        case DiagKindRefactor.sema_apilevel_syscap_warning => 725
        case DiagKindRefactor.sema_apilevel_syscap_error => 726
        case DiagKindRefactor.sema_apilevel_multi_diff_syscap => 727
        case DiagKindRefactor.sema_apilevel_integer_form_unsupported => 728
        case DiagKindRefactor.sema_ifavailable_level_limit => 729
        case DiagKindRefactor.sema_hide_multi_annotation => 730
        case DiagKindRefactor.sema_hide_at_func_param => 731
        case DiagKindRefactor.sema_hide_missing_hide => 732
        case DiagKindRefactor.sema_hide_compile_time_invisible => 733
        case DiagKindRefactor.sema_hide_diff_param => 734
        case DiagKindRefactor.sema_hide_must_at_end => 735
        case DiagKindRefactor.sema_unused_import => 736
        case DiagKindRefactor.sema_diag_end => 737
    }
}

public func WarnGroupIndex(kind: WarnGroup): Int64 {
    return match (kind) {
        case WarnGroup.UNUSED => 0
        case WarnGroup.UNUSED_MAIN => 1
        case WarnGroup.DRIVER_ARG => 2
        case WarnGroup.DEPRECATED => 3
        case WarnGroup.UNSUPPORT_COMPILE_SOURCE => 4
        case WarnGroup.PACKAGE_IMPORT => 5
        case WarnGroup.PARSER => 6
        case WarnGroup.SEMANTICS => 7
        case WarnGroup.INTERPRETER => 8
        case WarnGroup.APILEVEL_CHECK => 9
        case WarnGroup.UNGROUPED => 10
        case WarnGroup.NONE => 11
    }
}

public func DiagKindName(kind: DiagKind): String {
    return DIAG_KIND_STR[DiagKindIndex(kind)]
}

public func DiagKindRefactorName(kind: DiagKindRefactor): String {
    return RE_DIAG_KIND_STR[DiagKindRefactorIndex(kind)]
}

public func GetDiagnoseCategory(diagKind: DiagKind): DiagCategory {
    let idx = DiagKindIndex(diagKind)
    if (idx > 16 && idx <= 57) { return DiagCategory.MACRO_EXPAND }
    if (idx > 58 && idx <= 287) { return DiagCategory.SEMA }
    return DiagCategory.OTHER
}

public func GetDiagnoseCategory(diagKind: DiagKindRefactor): DiagCategory {
    let idx = DiagKindRefactorIndex(diagKind)
    if (idx > DiagKindRefactorIndex(DiagKindRefactor.lex_diag_begin) &&
        idx < DiagKindRefactorIndex(DiagKindRefactor.lex_diag_end)) { return DiagCategory.LEX }
    if (idx > DiagKindRefactorIndex(DiagKindRefactor.parse_diag_begin) &&
        idx < DiagKindRefactorIndex(DiagKindRefactor.parse_diag_end)) { return DiagCategory.PARSE }
    if (idx > DiagKindRefactorIndex(DiagKindRefactor.sema_diag_begin) &&
        idx < DiagKindRefactorIndex(DiagKindRefactor.sema_diag_end)) { return DiagCategory.SEMA }
    if (idx > DiagKindRefactorIndex(DiagKindRefactor.chir_diag_begin) &&
        idx < DiagKindRefactorIndex(DiagKindRefactor.chir_diag_end)) { return DiagCategory.CHIR }
    if (idx > DiagKindRefactorIndex(DiagKindRefactor.import_package_diag_begin) &&
        idx < DiagKindRefactorIndex(DiagKindRefactor.import_package_diag_end)) { return DiagCategory.IMPORT_PACKAGE }
    if (idx > DiagKindRefactorIndex(DiagKindRefactor.module_diag_begin) &&
        idx < DiagKindRefactorIndex(DiagKindRefactor.module_diag_end)) { return DiagCategory.MODULE }
    if (idx > DiagKindRefactorIndex(DiagKindRefactor.parse_query_diag_begin) &&
        idx < DiagKindRefactorIndex(DiagKindRefactor.parse_query_diag_end)) { return DiagCategory.PARSE_QUERY }
    if (idx > DiagKindRefactorIndex(DiagKindRefactor.conditional_compilation_diag_begin) &&
        idx < DiagKindRefactorIndex(DiagKindRefactor.conditional_compilation_diag_end)) {
        return DiagCategory.CONDITIONAL_COMPILATION
    }
    return DiagCategory.OTHER
}

public func DiagSeverityIndex(severity: DiagSeverity): Int64 {
    return match (severity) {
        case DiagSeverity.DS_ERROR => 0
        case DiagSeverity.DS_WARNING => 1
        case DiagSeverity.DS_NOTE => 2
        case DiagSeverity.DS_HINT => 3
    }
}

extend WarnGroup <: Equatable<WarnGroup> {
    public operator func ==(right: WarnGroup): Bool {
        return WarnGroupIndex(this) == WarnGroupIndex(right)
    }

    public operator func !=(right: WarnGroup): Bool {
        return !(this == right)
    }
}

extend DiagFormat <: Equatable<DiagFormat> {
    public operator func ==(right: DiagFormat): Bool {
        return match (this) {
            case DiagFormat.JSON => match (right) { case DiagFormat.JSON => true case _ => false }
            case DiagFormat.NO_COLOR => match (right) { case DiagFormat.NO_COLOR => true case _ => false }
            case DiagFormat.DEFAULT => match (right) { case DiagFormat.DEFAULT => true case _ => false }
        }
    }

    public operator func !=(right: DiagFormat): Bool {
        return !(this == right)
    }
}

extend DiagSeverity <: Equatable<DiagSeverity> {
    public operator func ==(right: DiagSeverity): Bool {
        return DiagSeverityIndex(this) == DiagSeverityIndex(right)
    }

    public operator func !=(right: DiagSeverity): Bool {
        return !(this == right)
    }
}

extend DiagCategory <: Equatable<DiagCategory> {
    public operator func ==(right: DiagCategory): Bool {
        return DiagCategoryIndex(this) == DiagCategoryIndex(right)
    }

    public operator func !=(right: DiagCategory): Bool {
        return !(this == right)
    }
}

extend DiagKind <: Equatable<DiagKind> {
    public operator func ==(right: DiagKind): Bool {
        return DiagKindIndex(this) == DiagKindIndex(right)
    }

    public operator func !=(right: DiagKind): Bool {
        return !(this == right)
    }
}

extend DiagKindRefactor <: Equatable<DiagKindRefactor> {
    public operator func ==(right: DiagKindRefactor): Bool {
        return DiagKindRefactorIndex(this) == DiagKindRefactorIndex(right)
    }

    public operator func !=(right: DiagKindRefactor): Bool {
        return !(this == right)
    }
}
