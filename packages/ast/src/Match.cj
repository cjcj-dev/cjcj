package cjcj::ast

import cjcj::utils.{DynamicCast, StaticCast}

public func As(kind: ASTKind, node: Option<Node>): Option<Node> {
    if (let Some(value) <- node) {
        return match (kind) {
            case ASTKind.ANNOTATION =>
                if (let Some(casted) <- DynamicCast<Annotation>(value)) { casted } else { None }
            case ASTKind.MODIFIER =>
                if (let Some(casted) <- DynamicCast<Modifier>(value)) { casted } else { None }
            case ASTKind.DECL =>
                if (let Some(casted) <- DynamicCast<Decl>(value)) { casted } else { None }
            case ASTKind.MAIN_DECL =>
                if (let Some(casted) <- DynamicCast<MainDecl>(value)) { casted } else { None }
            case ASTKind.FUNC_DECL =>
                if (let Some(casted) <- DynamicCast<FuncDecl>(value)) { casted } else { None }
            case ASTKind.MACRO_DECL =>
                if (let Some(casted) <- DynamicCast<MacroDecl>(value)) { casted } else { None }
            case ASTKind.CLASS_LIKE_DECL =>
                if (let Some(casted) <- DynamicCast<ClassLikeDecl>(value)) { casted } else { None }
            case ASTKind.CLASS_DECL =>
                if (let Some(casted) <- DynamicCast<ClassDecl>(value)) { casted } else { None }
            case ASTKind.INTERFACE_DECL =>
                if (let Some(casted) <- DynamicCast<InterfaceDecl>(value)) { casted } else { None }
            case ASTKind.EXTEND_DECL =>
                if (let Some(casted) <- DynamicCast<ExtendDecl>(value)) { casted } else { None }
            case ASTKind.ENUM_DECL =>
                if (let Some(casted) <- DynamicCast<EnumDecl>(value)) { casted } else { None }
            case ASTKind.STRUCT_DECL =>
                if (let Some(casted) <- DynamicCast<StructDecl>(value)) { casted } else { None }
            case ASTKind.TYPE_ALIAS_DECL =>
                if (let Some(casted) <- DynamicCast<TypeAliasDecl>(value)) { casted } else { None }
            case ASTKind.PRIMARY_CTOR_DECL =>
                if (let Some(casted) <- DynamicCast<PrimaryCtorDecl>(value)) { casted } else { None }
            case ASTKind.BUILTIN_DECL =>
                if (let Some(casted) <- DynamicCast<BuiltInDecl>(value)) { casted } else { None }
            case ASTKind.VAR_DECL =>
                if (let Some(casted) <- DynamicCast<VarDecl>(value)) { casted } else { None }
            case ASTKind.PROP_DECL =>
                if (let Some(casted) <- DynamicCast<PropDecl>(value)) { casted } else { None }
            case ASTKind.MACRO_EXPAND_PARAM =>
                if (let Some(casted) <- DynamicCast<MacroExpandParam>(value)) { casted } else { None }
            case ASTKind.FUNC_PARAM =>
                if (let Some(casted) <- DynamicCast<FuncParam>(value)) { casted } else { None }
            case ASTKind.VAR_WITH_PATTERN_DECL =>
                if (let Some(casted) <- DynamicCast<VarWithPatternDecl>(value)) { casted } else { None }
            case ASTKind.GENERIC_PARAM_DECL =>
                if (let Some(casted) <- DynamicCast<GenericParamDecl>(value)) { casted } else { None }
            case ASTKind.PACKAGE_DECL =>
                if (let Some(casted) <- DynamicCast<PackageDecl>(value)) { casted } else { None }
            case ASTKind.MACRO_EXPAND_DECL =>
                if (let Some(casted) <- DynamicCast<MacroExpandDecl>(value)) { casted } else { None }
            case ASTKind.INVALID_DECL =>
                if (let Some(casted) <- DynamicCast<InvalidDecl>(value)) { casted } else { None }
            case ASTKind.PATTERN =>
                if (let Some(casted) <- DynamicCast<Pattern>(value)) { casted } else { None }
            case ASTKind.VAR_PATTERN =>
                if (let Some(casted) <- DynamicCast<VarPattern>(value)) { casted } else { None }
            case ASTKind.CONST_PATTERN =>
                if (let Some(casted) <- DynamicCast<ConstPattern>(value)) { casted } else { None }
            case ASTKind.TUPLE_PATTERN =>
                if (let Some(casted) <- DynamicCast<TuplePattern>(value)) { casted } else { None }
            case ASTKind.ENUM_PATTERN =>
                if (let Some(casted) <- DynamicCast<EnumPattern>(value)) { casted } else { None }
            case ASTKind.VAR_OR_ENUM_PATTERN =>
                if (let Some(casted) <- DynamicCast<VarOrEnumPattern>(value)) { casted } else { None }
            case ASTKind.TYPE_PATTERN =>
                if (let Some(casted) <- DynamicCast<TypePattern>(value)) { casted } else { None }
            case ASTKind.EXCEPT_TYPE_PATTERN =>
                if (let Some(casted) <- DynamicCast<ExceptTypePattern>(value)) { casted } else { None }
            case ASTKind.COMMAND_TYPE_PATTERN =>
                if (let Some(casted) <- DynamicCast<CommandTypePattern>(value)) { casted } else { None }
            case ASTKind.WILDCARD_PATTERN =>
                if (let Some(casted) <- DynamicCast<WildcardPattern>(value)) { casted } else { None }
            case ASTKind.INVALID_PATTERN =>
                if (let Some(casted) <- DynamicCast<InvalidPattern>(value)) { casted } else { None }
            case ASTKind.TYPE =>
                if (let Some(casted) <- DynamicCast<Type>(value)) { casted } else { None }
            case ASTKind.REF_TYPE =>
                if (let Some(casted) <- DynamicCast<RefType>(value)) { casted } else { None }
            case ASTKind.QUALIFIED_TYPE =>
                if (let Some(casted) <- DynamicCast<QualifiedType>(value)) { casted } else { None }
            case ASTKind.OPTION_TYPE =>
                if (let Some(casted) <- DynamicCast<OptionType>(value)) { casted } else { None }
            case ASTKind.CONSTANT_TYPE =>
                if (let Some(casted) <- DynamicCast<ConstantType>(value)) { casted } else { None }
            case ASTKind.VARRAY_TYPE =>
                if (let Some(casted) <- DynamicCast<VArrayType>(value)) { casted } else { None }
            case ASTKind.PRIMITIVE_TYPE =>
                if (let Some(casted) <- DynamicCast<PrimitiveType>(value)) { casted } else { None }
            case ASTKind.PAREN_TYPE =>
                if (let Some(casted) <- DynamicCast<ParenType>(value)) { casted } else { None }
            case ASTKind.FUNC_TYPE =>
                if (let Some(casted) <- DynamicCast<FuncType>(value)) { casted } else { None }
            case ASTKind.TUPLE_TYPE =>
                if (let Some(casted) <- DynamicCast<TupleType>(value)) { casted } else { None }
            case ASTKind.THIS_TYPE =>
                if (let Some(casted) <- DynamicCast<ThisType>(value)) { casted } else { None }
            case ASTKind.INVALID_TYPE =>
                if (let Some(casted) <- DynamicCast<InvalidType>(value)) { casted } else { None }
            case ASTKind.EXPR =>
                if (let Some(casted) <- DynamicCast<Expr>(value)) { casted } else { None }
            case ASTKind.WILDCARD_EXPR =>
                if (let Some(casted) <- DynamicCast<WildcardExpr>(value)) { casted } else { None }
            case ASTKind.CALL_EXPR =>
                if (let Some(casted) <- DynamicCast<CallExpr>(value)) { casted } else { None }
            case ASTKind.PAREN_EXPR =>
                if (let Some(casted) <- DynamicCast<ParenExpr>(value)) { casted } else { None }
            case ASTKind.MEMBER_ACCESS =>
                if (let Some(casted) <- DynamicCast<MemberAccess>(value)) { casted } else { None }
            case ASTKind.REF_EXPR =>
                if (let Some(casted) <- DynamicCast<RefExpr>(value)) { casted } else { None }
            case ASTKind.OPTIONAL_EXPR =>
                if (let Some(casted) <- DynamicCast<OptionalExpr>(value)) { casted } else { None }
            case ASTKind.OPTIONAL_CHAIN_EXPR =>
                if (let Some(casted) <- DynamicCast<OptionalChainExpr>(value)) { casted } else { None }
            case ASTKind.PRIMITIVE_TYPE_EXPR =>
                if (let Some(casted) <- DynamicCast<PrimitiveTypeExpr>(value)) { casted } else { None }
            case ASTKind.RETURN_EXPR =>
                if (let Some(casted) <- DynamicCast<ReturnExpr>(value)) { casted } else { None }
            case ASTKind.LIT_CONST_EXPR =>
                if (let Some(casted) <- DynamicCast<LitConstExpr>(value)) { casted } else { None }
            case ASTKind.INTERPOLATION_EXPR =>
                if (let Some(casted) <- DynamicCast<InterpolationExpr>(value)) { casted } else { None }
            case ASTKind.STR_INTERPOLATION_EXPR =>
                if (let Some(casted) <- DynamicCast<StrInterpolationExpr>(value)) { casted } else { None }
            case ASTKind.ASSIGN_EXPR =>
                if (let Some(casted) <- DynamicCast<AssignExpr>(value)) { casted } else { None }
            case ASTKind.UNARY_EXPR =>
                if (let Some(casted) <- DynamicCast<UnaryExpr>(value)) { casted } else { None }
            case ASTKind.BINARY_EXPR =>
                if (let Some(casted) <- DynamicCast<BinaryExpr>(value)) { casted } else { None }
            case ASTKind.INC_OR_DEC_EXPR =>
                if (let Some(casted) <- DynamicCast<IncOrDecExpr>(value)) { casted } else { None }
            case ASTKind.SUBSCRIPT_EXPR =>
                if (let Some(casted) <- DynamicCast<SubscriptExpr>(value)) { casted } else { None }
            case ASTKind.IS_EXPR =>
                if (let Some(casted) <- DynamicCast<IsExpr>(value)) { casted } else { None }
            case ASTKind.AS_EXPR =>
                if (let Some(casted) <- DynamicCast<AsExpr>(value)) { casted } else { None }
            case ASTKind.RANGE_EXPR =>
                if (let Some(casted) <- DynamicCast<RangeExpr>(value)) { casted } else { None }
            case ASTKind.ARRAY_LIT =>
                if (let Some(casted) <- DynamicCast<ArrayLit>(value)) { casted } else { None }
            case ASTKind.ARRAY_EXPR =>
                if (let Some(casted) <- DynamicCast<ArrayExpr>(value)) { casted } else { None }
            case ASTKind.POINTER_EXPR =>
                if (let Some(casted) <- DynamicCast<PointerExpr>(value)) { casted } else { None }
            case ASTKind.TUPLE_LIT =>
                if (let Some(casted) <- DynamicCast<TupleLit>(value)) { casted } else { None }
            case ASTKind.MATCH_EXPR =>
                if (let Some(casted) <- DynamicCast<MatchExpr>(value)) { casted } else { None }
            case ASTKind.BLOCK =>
                if (let Some(casted) <- DynamicCast<Block>(value)) { casted } else { None }
            case ASTKind.IF_EXPR =>
                if (let Some(casted) <- DynamicCast<IfExpr>(value)) { casted } else { None }
            case ASTKind.LET_PATTERN_DESTRUCTOR =>
                if (let Some(casted) <- DynamicCast<LetPatternDestructor>(value)) { casted } else { None }
            case ASTKind.TOKEN_PART =>
                if (let Some(casted) <- DynamicCast<TokenPart>(value)) { casted } else { None }
            case ASTKind.QUOTE_EXPR =>
                if (let Some(casted) <- DynamicCast<QuoteExpr>(value)) { casted } else { None }
            case ASTKind.TRY_EXPR =>
                if (let Some(casted) <- DynamicCast<TryExpr>(value)) { casted } else { None }
            case ASTKind.WHILE_EXPR =>
                if (let Some(casted) <- DynamicCast<WhileExpr>(value)) { casted } else { None }
            case ASTKind.JUMP_EXPR =>
                if (let Some(casted) <- DynamicCast<JumpExpr>(value)) { casted } else { None }
            case ASTKind.LAMBDA_EXPR =>
                if (let Some(casted) <- DynamicCast<LambdaExpr>(value)) { casted } else { None }
            case ASTKind.TRAIL_CLOSURE_EXPR =>
                if (let Some(casted) <- DynamicCast<TrailingClosureExpr>(value)) { casted } else { None }
            case ASTKind.FOR_IN_EXPR =>
                if (let Some(casted) <- DynamicCast<ForInExpr>(value)) { casted } else { None }
            case ASTKind.DO_WHILE_EXPR =>
                if (let Some(casted) <- DynamicCast<DoWhileExpr>(value)) { casted } else { None }
            case ASTKind.TYPE_CONV_EXPR =>
                if (let Some(casted) <- DynamicCast<TypeConvExpr>(value)) { casted } else { None }
            case ASTKind.THROW_EXPR =>
                if (let Some(casted) <- DynamicCast<ThrowExpr>(value)) { casted } else { None }
            case ASTKind.PERFORM_EXPR =>
                if (let Some(casted) <- DynamicCast<PerformExpr>(value)) { casted } else { None }
            case ASTKind.RESUME_EXPR =>
                if (let Some(casted) <- DynamicCast<ResumeExpr>(value)) { casted } else { None }
            case ASTKind.SPAWN_EXPR =>
                if (let Some(casted) <- DynamicCast<SpawnExpr>(value)) { casted } else { None }
            case ASTKind.SYNCHRONIZED_EXPR =>
                if (let Some(casted) <- DynamicCast<SynchronizedExpr>(value)) { casted } else { None }
            case ASTKind.MACRO_EXPAND_EXPR =>
                if (let Some(casted) <- DynamicCast<MacroExpandExpr>(value)) { casted } else { None }
            case ASTKind.IF_AVAILABLE_EXPR =>
                if (let Some(casted) <- DynamicCast<IfAvailableExpr>(value)) { casted } else { None }
            case ASTKind.INVALID_EXPR =>
                if (let Some(casted) <- DynamicCast<InvalidExpr>(value)) { casted } else { None }
            case ASTKind.GENERIC =>
                if (let Some(casted) <- DynamicCast<Generic>(value)) { casted } else { None }
            case ASTKind.GENERIC_CONSTRAINT =>
                if (let Some(casted) <- DynamicCast<GenericConstraint>(value)) { casted } else { None }
            case ASTKind.MATCH_CASE =>
                if (let Some(casted) <- DynamicCast<MatchCase>(value)) { casted } else { None }
            case ASTKind.MATCH_CASE_OTHER =>
                if (let Some(casted) <- DynamicCast<MatchCaseOther>(value)) { casted } else { None }
            case ASTKind.FUNC_ARG =>
                if (let Some(casted) <- DynamicCast<FuncArg>(value)) { casted } else { None }
            case ASTKind.FUNC_PARAM_LIST =>
                if (let Some(casted) <- DynamicCast<FuncParamList>(value)) { casted } else { None }
            case ASTKind.FUNC_BODY =>
                if (let Some(casted) <- DynamicCast<FuncBody>(value)) { casted } else { None }
            case ASTKind.STRUCT_BODY =>
                if (let Some(casted) <- DynamicCast<StructBody>(value)) { casted } else { None }
            case ASTKind.CLASS_BODY =>
                if (let Some(casted) <- DynamicCast<ClassBody>(value)) { casted } else { None }
            case ASTKind.INTERFACE_BODY =>
                if (let Some(casted) <- DynamicCast<InterfaceBody>(value)) { casted } else { None }
            case ASTKind.DUMMY_BODY =>
                if (let Some(casted) <- DynamicCast<DummyBody>(value)) { casted } else { None }
            case ASTKind.IMPORT_CONTENT =>
                if (let Some(casted) <- DynamicCast<ImportContent>(value)) { casted } else { None }
            case ASTKind.IMPORT_SPEC =>
                if (let Some(casted) <- DynamicCast<ImportSpec>(value)) { casted } else { None }
            case ASTKind.PACKAGE_SPEC =>
                if (let Some(casted) <- DynamicCast<PackageSpec>(value)) { casted } else { None }
            case ASTKind.PACKAGE =>
                if (let Some(casted) <- DynamicCast<Package>(value)) { casted } else { None }
            case ASTKind.FEATURE_ID =>
                if (let Some(casted) <- DynamicCast<FeatureId>(value)) { casted } else { None }
            case ASTKind.FEATURES_SET =>
                if (let Some(casted) <- DynamicCast<FeaturesSet>(value)) { casted } else { None }
            case ASTKind.FEATURES_DIRECTIVE =>
                if (let Some(casted) <- DynamicCast<FeaturesDirective>(value)) { casted } else { None }
            case ASTKind.FILE =>
                if (let Some(casted) <- DynamicCast<File>(value)) { casted } else { None }
            case ASTKind.NODE =>
                if (let Some(casted) <- DynamicCast<Node>(value)) { casted } else { None }
        }
    }
    return None
}

public func StaticAs(kind: ASTKind, node: Any): Node {
    return match (kind) {
        case ASTKind.ANNOTATION => StaticCast<Annotation>(node)
        case ASTKind.MODIFIER => StaticCast<Modifier>(node)
        case ASTKind.DECL => StaticCast<Decl>(node)
        case ASTKind.MAIN_DECL => StaticCast<MainDecl>(node)
        case ASTKind.FUNC_DECL => StaticCast<FuncDecl>(node)
        case ASTKind.MACRO_DECL => StaticCast<MacroDecl>(node)
        case ASTKind.CLASS_LIKE_DECL => StaticCast<ClassLikeDecl>(node)
        case ASTKind.CLASS_DECL => StaticCast<ClassDecl>(node)
        case ASTKind.INTERFACE_DECL => StaticCast<InterfaceDecl>(node)
        case ASTKind.EXTEND_DECL => StaticCast<ExtendDecl>(node)
        case ASTKind.ENUM_DECL => StaticCast<EnumDecl>(node)
        case ASTKind.STRUCT_DECL => StaticCast<StructDecl>(node)
        case ASTKind.TYPE_ALIAS_DECL => StaticCast<TypeAliasDecl>(node)
        case ASTKind.PRIMARY_CTOR_DECL => StaticCast<PrimaryCtorDecl>(node)
        case ASTKind.BUILTIN_DECL => StaticCast<BuiltInDecl>(node)
        case ASTKind.VAR_DECL => StaticCast<VarDecl>(node)
        case ASTKind.PROP_DECL => StaticCast<PropDecl>(node)
        case ASTKind.MACRO_EXPAND_PARAM => StaticCast<MacroExpandParam>(node)
        case ASTKind.FUNC_PARAM => StaticCast<FuncParam>(node)
        case ASTKind.VAR_WITH_PATTERN_DECL => StaticCast<VarWithPatternDecl>(node)
        case ASTKind.GENERIC_PARAM_DECL => StaticCast<GenericParamDecl>(node)
        case ASTKind.PACKAGE_DECL => StaticCast<PackageDecl>(node)
        case ASTKind.MACRO_EXPAND_DECL => StaticCast<MacroExpandDecl>(node)
        case ASTKind.INVALID_DECL => StaticCast<InvalidDecl>(node)
        case ASTKind.PATTERN => StaticCast<Pattern>(node)
        case ASTKind.VAR_PATTERN => StaticCast<VarPattern>(node)
        case ASTKind.CONST_PATTERN => StaticCast<ConstPattern>(node)
        case ASTKind.TUPLE_PATTERN => StaticCast<TuplePattern>(node)
        case ASTKind.ENUM_PATTERN => StaticCast<EnumPattern>(node)
        case ASTKind.VAR_OR_ENUM_PATTERN => StaticCast<VarOrEnumPattern>(node)
        case ASTKind.TYPE_PATTERN => StaticCast<TypePattern>(node)
        case ASTKind.EXCEPT_TYPE_PATTERN => StaticCast<ExceptTypePattern>(node)
        case ASTKind.COMMAND_TYPE_PATTERN => StaticCast<CommandTypePattern>(node)
        case ASTKind.WILDCARD_PATTERN => StaticCast<WildcardPattern>(node)
        case ASTKind.INVALID_PATTERN => StaticCast<InvalidPattern>(node)
        case ASTKind.TYPE => StaticCast<Type>(node)
        case ASTKind.REF_TYPE => StaticCast<RefType>(node)
        case ASTKind.QUALIFIED_TYPE => StaticCast<QualifiedType>(node)
        case ASTKind.OPTION_TYPE => StaticCast<OptionType>(node)
        case ASTKind.CONSTANT_TYPE => StaticCast<ConstantType>(node)
        case ASTKind.VARRAY_TYPE => StaticCast<VArrayType>(node)
        case ASTKind.PRIMITIVE_TYPE => StaticCast<PrimitiveType>(node)
        case ASTKind.PAREN_TYPE => StaticCast<ParenType>(node)
        case ASTKind.FUNC_TYPE => StaticCast<FuncType>(node)
        case ASTKind.TUPLE_TYPE => StaticCast<TupleType>(node)
        case ASTKind.THIS_TYPE => StaticCast<ThisType>(node)
        case ASTKind.INVALID_TYPE => StaticCast<InvalidType>(node)
        case ASTKind.EXPR => StaticCast<Expr>(node)
        case ASTKind.WILDCARD_EXPR => StaticCast<WildcardExpr>(node)
        case ASTKind.CALL_EXPR => StaticCast<CallExpr>(node)
        case ASTKind.PAREN_EXPR => StaticCast<ParenExpr>(node)
        case ASTKind.MEMBER_ACCESS => StaticCast<MemberAccess>(node)
        case ASTKind.REF_EXPR => StaticCast<RefExpr>(node)
        case ASTKind.OPTIONAL_EXPR => StaticCast<OptionalExpr>(node)
        case ASTKind.OPTIONAL_CHAIN_EXPR => StaticCast<OptionalChainExpr>(node)
        case ASTKind.PRIMITIVE_TYPE_EXPR => StaticCast<PrimitiveTypeExpr>(node)
        case ASTKind.RETURN_EXPR => StaticCast<ReturnExpr>(node)
        case ASTKind.LIT_CONST_EXPR => StaticCast<LitConstExpr>(node)
        case ASTKind.INTERPOLATION_EXPR => StaticCast<InterpolationExpr>(node)
        case ASTKind.STR_INTERPOLATION_EXPR => StaticCast<StrInterpolationExpr>(node)
        case ASTKind.ASSIGN_EXPR => StaticCast<AssignExpr>(node)
        case ASTKind.UNARY_EXPR => StaticCast<UnaryExpr>(node)
        case ASTKind.BINARY_EXPR => StaticCast<BinaryExpr>(node)
        case ASTKind.INC_OR_DEC_EXPR => StaticCast<IncOrDecExpr>(node)
        case ASTKind.SUBSCRIPT_EXPR => StaticCast<SubscriptExpr>(node)
        case ASTKind.IS_EXPR => StaticCast<IsExpr>(node)
        case ASTKind.AS_EXPR => StaticCast<AsExpr>(node)
        case ASTKind.RANGE_EXPR => StaticCast<RangeExpr>(node)
        case ASTKind.ARRAY_LIT => StaticCast<ArrayLit>(node)
        case ASTKind.ARRAY_EXPR => StaticCast<ArrayExpr>(node)
        case ASTKind.POINTER_EXPR => StaticCast<PointerExpr>(node)
        case ASTKind.TUPLE_LIT => StaticCast<TupleLit>(node)
        case ASTKind.MATCH_EXPR => StaticCast<MatchExpr>(node)
        case ASTKind.BLOCK => StaticCast<Block>(node)
        case ASTKind.IF_EXPR => StaticCast<IfExpr>(node)
        case ASTKind.LET_PATTERN_DESTRUCTOR => StaticCast<LetPatternDestructor>(node)
        case ASTKind.TOKEN_PART => StaticCast<TokenPart>(node)
        case ASTKind.QUOTE_EXPR => StaticCast<QuoteExpr>(node)
        case ASTKind.TRY_EXPR => StaticCast<TryExpr>(node)
        case ASTKind.WHILE_EXPR => StaticCast<WhileExpr>(node)
        case ASTKind.JUMP_EXPR => StaticCast<JumpExpr>(node)
        case ASTKind.LAMBDA_EXPR => StaticCast<LambdaExpr>(node)
        case ASTKind.TRAIL_CLOSURE_EXPR => StaticCast<TrailingClosureExpr>(node)
        case ASTKind.FOR_IN_EXPR => StaticCast<ForInExpr>(node)
        case ASTKind.DO_WHILE_EXPR => StaticCast<DoWhileExpr>(node)
        case ASTKind.TYPE_CONV_EXPR => StaticCast<TypeConvExpr>(node)
        case ASTKind.THROW_EXPR => StaticCast<ThrowExpr>(node)
        case ASTKind.PERFORM_EXPR => StaticCast<PerformExpr>(node)
        case ASTKind.RESUME_EXPR => StaticCast<ResumeExpr>(node)
        case ASTKind.SPAWN_EXPR => StaticCast<SpawnExpr>(node)
        case ASTKind.SYNCHRONIZED_EXPR => StaticCast<SynchronizedExpr>(node)
        case ASTKind.MACRO_EXPAND_EXPR => StaticCast<MacroExpandExpr>(node)
        case ASTKind.IF_AVAILABLE_EXPR => StaticCast<IfAvailableExpr>(node)
        case ASTKind.INVALID_EXPR => StaticCast<InvalidExpr>(node)
        case ASTKind.GENERIC => StaticCast<Generic>(node)
        case ASTKind.GENERIC_CONSTRAINT => StaticCast<GenericConstraint>(node)
        case ASTKind.MATCH_CASE => StaticCast<MatchCase>(node)
        case ASTKind.MATCH_CASE_OTHER => StaticCast<MatchCaseOther>(node)
        case ASTKind.FUNC_ARG => StaticCast<FuncArg>(node)
        case ASTKind.FUNC_PARAM_LIST => StaticCast<FuncParamList>(node)
        case ASTKind.FUNC_BODY => StaticCast<FuncBody>(node)
        case ASTKind.STRUCT_BODY => StaticCast<StructBody>(node)
        case ASTKind.CLASS_BODY => StaticCast<ClassBody>(node)
        case ASTKind.INTERFACE_BODY => StaticCast<InterfaceBody>(node)
        case ASTKind.DUMMY_BODY => StaticCast<DummyBody>(node)
        case ASTKind.IMPORT_CONTENT => StaticCast<ImportContent>(node)
        case ASTKind.IMPORT_SPEC => StaticCast<ImportSpec>(node)
        case ASTKind.PACKAGE_SPEC => StaticCast<PackageSpec>(node)
        case ASTKind.PACKAGE => StaticCast<Package>(node)
        case ASTKind.FEATURE_ID => StaticCast<FeatureId>(node)
        case ASTKind.FEATURES_SET => StaticCast<FeaturesSet>(node)
        case ASTKind.FEATURES_DIRECTIVE => StaticCast<FeaturesDirective>(node)
        case ASTKind.FILE => StaticCast<File>(node)
        case ASTKind.NODE => StaticCast<Node>(node)
    }
}
