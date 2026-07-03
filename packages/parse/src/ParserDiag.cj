package cangjie_compiler::parse

import cangjie_compiler::basic.{DiagHelp, SubDiagnostic}
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::option.BackendToString as OptionBackendToString
import std.collection.*

private func LookupDiagExpectedIdentifierHandler(kind: ASTKind): String {
    return match (kind) {
        case ASTKind.ENUM_DECL => "DiagExpectedIdentifierEnumDecl"
        case ASTKind.GENERIC => "DiagExpectedIdentifierGeneric"
        case ASTKind.GENERIC_CONSTRAINT => "DiagExpectedIdentifierGenericConstraint"
        case ASTKind.IMPORT_CONTENT => "DiagExpectedIdentifierImportContent"
        case ASTKind.IMPORT_SPEC => "DiagExpectedIdentifierImportSpec"
        case ASTKind.PACKAGE_SPEC => "DiagExpectedIdentifierPackageSpec"
        case ASTKind.PROP_DECL => "DiagExpectedIdentifierPropDecl"
        case ASTKind.REF_TYPE => "DiagExpectedIdentifierRefType"
        case ASTKind.FUNC_PARAM => "DiagExpectedIdentifierFuncParam"
        case ASTKind.QUALIFIED_TYPE => "DiagExpectedIdentifierQualifiedType"
        case ASTKind.MEMBER_ACCESS => "DiagExpectedIdentifierMemberAccess"
        case ASTKind.MACRO_DECL => "DiagExpectedIdentifierMacroDecl"
        case ASTKind.FUNC_BODY => "DiagExpectedIdentifierFuncBody"
        case ASTKind.FUNC_DECL => "DiagExpectedIdentifierFuncDecl"
        case ASTKind.CLASS_DECL => "DiagExpectedIdentifierClassDecl"
        case ASTKind.INTERFACE_DECL => "DiagExpectedIdentifierInterfaceDecl"
        case ASTKind.STRUCT_DECL => "DiagExpectedIdentifierStructDecl"
        case ASTKind.TYPE_ALIAS_DECL => "DiagExpectedIdentifierTypeAliasDecl"
        case ASTKind.MACRO_EXPAND_DECL => "DiagExpectedIdentifierMacroExpandDecl"
        case ASTKind.MACRO_EXPAND_EXPR => "DiagExpectedIdentifierMacroExpandExpr"
        case _ => ""
    }
}

private func KIND_TO_STR(kind: ASTKind): (String, String) {
    return match (kind) {
        case ASTKind.VAR_DECL => ("var", "variable declaration")
        case ASTKind.VAR_WITH_PATTERN_DECL => ("var", "variable declaration")
        case ASTKind.FUNC_DECL => ("func", "function declaration")
        case ASTKind.MAIN_DECL => ("main", "main function")
        case ASTKind.MACRO_DECL => ("macro", "macro declaration")
        case ASTKind.CLASS_DECL => ("class", "class declaration")
        case ASTKind.EXTEND_DECL => ("extend", "extend declaration")
        case ASTKind.INTERFACE_DECL => ("interface", "interface declaration")
        case ASTKind.STRUCT_DECL => ("struct", "struct declaration")
        case ASTKind.ENUM_DECL => ("enum", "enum declaration")
        case ASTKind.TYPE_ALIAS_DECL => ("type", "type alias declaration")
        case ASTKind.PROP_DECL => ("prop", "property declaration")
        case ASTKind.INTERPOLATION_EXPR => ("interpolation", "string interpolation")
        case ASTKind.PACKAGE_SPEC => ("package", "package declaration")
        case ASTKind.FEATURES_DIRECTIVE => ("features", "features declarations")
        case _ => ("", "declaration")
    }
}

private func SCOPE_TO_DECL(scopeKind: ScopeKind): (String, String) {
    return match (scopeKind) {
        case ScopeKind.TOPLEVEL => ("", "'top-level' scope")
        case ScopeKind.MACRO_BODY => ("macro", "macro body")
        case ScopeKind.CLASS_BODY => ("class", "class body")
        case ScopeKind.EXTEND_BODY => ("extend", "extend body")
        case ScopeKind.INTERFACE_BODY => ("interface", "interface body")
        case ScopeKind.STRUCT_BODY => ("struct", "struct body")
        case ScopeKind.ENUM_BODY => ("enum", "enum body")
        case ScopeKind.ENUM_CONSTRUCTOR => ("enum", "enum body")
        case ScopeKind.FUNC_BODY => ("func", "function body")
        case ScopeKind.PROP_MEMBER_SETTER_BODY => ("setter", "setter body")
        case ScopeKind.PROP_MEMBER_GETTER_BODY => ("getter", "getter body")
        case _ => ("", "scope")
    }
}

private func GetSignature(node: Node): (BasicRange, String) {
    if (node.astKind == ASTKind.FUNC_DECL && node.TestAttr(Attribute.CONSTRUCTOR)) {
        return (MakeRange(node.begin, node.begin + "init".size), "constructor")
    }
    if (node.astKind == ASTKind.FUNC_DECL && node.TestAttr(Attribute.FINALIZER)) {
        return (MakeRange(node.begin, node.begin + "~init".size), "finalizer")
    }
    if (node.astKind == ASTKind.VAR_DECL) {
        if (let Some(vd) <- (node as VarDecl)) {
            if (vd.isConst) {
                return (MakeRange(node.begin, node.begin + "const".size), KIND_TO_STR(node.astKind)[1])
            }
        }
    }
    let kindToStr = KIND_TO_STR(node.astKind)
    let keyword = kindToStr[0]
    if (!keyword.isEmpty()) {
        return (MakeRange(node.begin, node.begin + keyword.size), kindToStr[1])
    }
    if (node.astKind == ASTKind.PRIMARY_CTOR_DECL) {
        if (let Some(pcd) <- (node as PrimaryCtorDecl)) {
            return (MakeRange(node.begin, node.begin + pcd.identifier.Length()), "primary constructor")
        }
    }
    return (MakeRange(DEFAULT_POSITION, DEFAULT_POSITION), "declaration")
}

extend ParserImpl {
    public func DiagExpectedIdentifier(pos: Position): Unit {
        DiagExpectedIdentifier(MakeRange(pos, pos + 1))
    }

    public func DiagExpectedIdentifier(range: BasicRange): Unit {
        DiagExpectedIdentifier(range, "a name", "after this", true)
    }

    public func DiagExpectedIdentifier(range: BasicRange, expectedName: String, afterName: String): Unit {
        DiagExpectedIdentifier(range, expectedName, afterName, true)
    }

    public func DiagExpectedIdentifier(range: BasicRange, expectedName: String, afterName: String, callHelp: Bool): Unit {
        let foundName = ConvertToken(lookahead)
        var expectedMsg = expectedName
        var otherHintMsg = afterName
        var otherHintRange = range
        if (lookahead.kind == TokenKind.WILDCARD) {
            let ahead = lexer.LookAheadSkipNL(1)
            if (!ahead.isEmpty()) {
                if (lookahead.Begin().line == ahead[0].Begin().line &&
                    lookahead.Begin().column + 1 == ahead[0].Begin().column) {
                    expectedMsg = "identifier"
                    otherHintMsg = "expected a Unicode XID_Continue after '_'"
                    otherHintRange = MakeRange(ahead[0].Begin(), ahead[0].Begin() + 1)
                }
            }
        }
        let builder = ParseDiagnoseRefactor(
            DiagKindRefactor.parse_expected_name, lookahead, expectedMsg, afterName, foundName)
        builder.AddMainHintArguments(expectedMsg)
        builder.AddHint(otherHintRange, arguments: [otherHintMsg])
        if (IsKeyWord(lookahead) && callHelp) {
            let help = DiagHelp("you could escape keyword as " + expectedName + " using '`'")
            help.AddSubstitution(MakeRange(lookahead.Begin(), lookahead.End()), "`" + lookahead.Value() + "`")
            builder.AddHelp(help)
        }
    }

    public func DiagExpectedIdentifierClassDecl(node: Node): Unit {
        DiagExpectedIdentifier(MakeRange(node.begin, node.begin + "class".size), "a class name", "after keyword 'class'")
    }

    public func DiagExpectedIdentifierInterfaceDecl(node: Node): Unit {
        DiagExpectedIdentifier(
            MakeRange(node.begin, node.begin + "interface".size), "a interface name", "after keyword 'interface'")
    }

    public func DiagExpectedIdentifierStructDecl(node: Node): Unit {
        DiagExpectedIdentifier(
            MakeRange(node.begin, node.begin + "struct".size), "a struct name", "after keyword 'struct'")
    }

    public func DiagExpectedIdentifierTypeAliasDecl(node: Node): Unit {
        DiagExpectedIdentifier(
            MakeRange(node.begin, node.begin + "type".size), "a type name", "after keyword 'type'")
    }

    public func DiagExpectedIdentifierMacroExpandDecl(node: Node): Unit {
        if (let Some(med) <- (node as MacroExpandDecl)) {
            if (!med.invocation.fullNameDotPos.isEmpty()) {
                let dotPos = med.invocation.fullNameDotPos[med.invocation.fullNameDotPos.size - 1]
                DiagExpectedIdentifier(MakeRange(dotPos, dotPos + ".".size), "a type name", "after '.' in qualified name")
                return
            }
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_name, lookahead, "a type name",
            "after '.' in qualified name", ConvertToken(lookahead))
        builder.AddMainHintArguments("a type name")
        builder.AddNote("GAP_TODO: requires faithful port of ParserDiag.cpp:133 DiagExpectedIdentifierMacroExpandDecl fullNameDotPos")
    }

    public func DiagExpectedIdentifierMacroExpandExpr(node: Node): Unit {
        if (let Some(mee) <- (node as MacroExpandExpr)) {
            if (!mee.invocation.fullNameDotPos.isEmpty()) {
                let dotPos = mee.invocation.fullNameDotPos[mee.invocation.fullNameDotPos.size - 1]
                DiagExpectedIdentifier(MakeRange(dotPos, dotPos + ".".size), "a type name", "after '.' in qualified name")
                return
            }
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_name, lookahead, "a type name",
            "after '.' in qualified name", ConvertToken(lookahead))
        builder.AddMainHintArguments("a type name")
        builder.AddNote("GAP_TODO: requires faithful port of ParserDiag.cpp:141 DiagExpectedIdentifierMacroExpandExpr fullNameDotPos")
    }

    public func DiagExpectedIdentifierFuncDecl(node: Node): Unit {
        DiagExpectedIdentifier(MakeRange(node.begin, node.begin + "func".size), "a func name", "after keyword 'func'")
    }

    public func DiagExpectedIdentifierFuncBody(node: Node): Unit {
        if (let Some(fb) <- (node as FuncBody)) {
            DiagExpectedIdentifier(MakeRange(fb.colonPos, fb.colonPos + ":".size), "a type name",
                "after ':' in function declaration")
        }
    }

    public func DiagExpectedIdentifierMacroDecl(node: Node): Unit {
        DiagExpectedIdentifier(MakeRange(node.begin, node.begin + "macro".size), "a macro name",
            "after keyword 'macro'")
    }

    public func DiagExpectedIdentifierMemberAccess(node: Node): Unit {
        if (let Some(ma) <- (node as MemberAccess)) {
            DiagExpectedIdentifier(MakeRange(ma.dotPos, ma.dotPos + ".".size), "a member name",
                "after '.' in qualified name")
        }
    }

    public func DiagExpectedIdentifierQualifiedType(node: Node): Unit {
        if (let Some(qt) <- (node as QualifiedType)) {
            DiagExpectedIdentifier(MakeRange(qt.dotPos, qt.dotPos + ".".size), "a type name",
                "after '.' in qualified name")
        }
    }

    public func DiagExpectedIdentifierFuncParam(_: Node): Unit {
        DiagExpectedIdentifier(MakeRange(lastToken.Begin(), lastToken.End()))
    }

    public func DiagExpectedIdentifierRefType(_: Node): Unit {
        DiagExpectedIdentifier(MakeRange(lastToken.Begin(), lastToken.End()))
    }

    public func DiagExpectedIdentifierPropDecl(node: Node): Unit {
        if (let Some(pd) <- (node as PropDecl)) {
            DiagExpectedIdentifier(MakeRange(pd.keywordPos, pd.keywordPos + "prop".size), "a property name",
                "after keyword 'prop' in property definition")
        }
    }

    public func DiagExpectedIdentifierPackageSpec(node: Node): Unit {
        if (let Some(ps) <- (node as PackageSpec)) {
            if (ps.prefixDotPoses.isEmpty()) {
                DiagExpectedIdentifier(MakeRange(ps.packagePos, ps.packagePos + "package".size), "a package name",
                    "after keyword 'package'")
            } else {
                let dotPos = ps.prefixDotPoses[ps.prefixDotPoses.size - 1]
                DiagExpectedIdentifier(MakeRange(dotPos, dotPos + lastToken.Value().size), "a package name",
                    "after '" + lastToken.Value() + "' in qualified name")
            }
        }
    }

    public func DiagExpectedIdentifierImportContent(node: Node): Unit {
        if (let Some(ic) <- (node as ImportContent)) {
            if (lastToken.kind == TokenKind.IMPORT) {
                DiagExpectedIdentifier(MakeRange(lastToken.Begin(), lastToken.End()), "a package name",
                    "after keyword 'import'")
            } else if (!ic.prefixDotPoses.isEmpty()) {
                let expectedName = if (lastToken.Value() == ".") { "a '*' or identifier" } else { "an identifier" }
                let dotPos = ic.prefixDotPoses[ic.prefixDotPoses.size - 1]
                DiagExpectedIdentifier(MakeRange(dotPos, dotPos + lastToken.Value().size), expectedName,
                    "after '" + lastToken.Value() + "' in qualified name")
            } else {
                DiagExpectedIdentifier(MakeRange(lastToken.Begin(), lastToken.End()))
            }
        }
    }

    public func DiagExpectedIdentifierImportSpec(node: Node): Unit {
        if (let Some(importSpec) <- (node as ImportSpec)) {
            DiagExpectedIdentifier(MakeRange(importSpec.importPos, importSpec.importPos + "import".size),
                "a package name", "after keyword 'import'")
        }
    }

    public func DiagRawIdentifierNotAllowed(str: String): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_not_allowed_raw_identifier, lastToken, str)
    }

    public func DiagExpectedIdentifierGenericConstraint(node: Node): Unit {
        if (let Some(gc) <- (node as GenericConstraint)) {
            if (gc.bitAndPos.isEmpty()) {
                DiagExpectedIdentifier(MakeRange(gc.operatorPos, gc.operatorPos + "<:".size), "a type name",
                    "after '<:' in generic constraint")
            } else {
                let bitAndPos = gc.bitAndPos[gc.bitAndPos.size - 1]
                DiagExpectedIdentifier(MakeRange(bitAndPos, bitAndPos + "&".size), "a type name",
                    "after '&' in generic constraint")
            }
        }
    }

    public func DiagExpectedIdentifierGeneric(node: Node): Unit {
        if (let Some(generic) <- (node as Generic)) {
            if (generic.typeParameters.isEmpty()) {
                DiagExpectedIdentifier(MakeRange(generic.leftAnglePos, generic.leftAnglePos + "<".size),
                    "a generic type name", "after '<' in generic")
            } else {
                let commaPos = generic.typeParameters[generic.typeParameters.size - 1].commaPos
                DiagExpectedIdentifier(MakeRange(commaPos, commaPos + ",".size), "a generic type name",
                    "after ',' in generic")
            }
        }
    }

    public func DiagExpectedIdentifierEnumDecl(node: Node): Unit {
        if (let Some(enumDecl) <- (node as EnumDecl)) {
            if (enumDecl.identifier.ZeroPos()) {
                DiagExpectedIdentifier(MakeRange(enumDecl.begin, enumDecl.begin + "enum".size), "a enum name",
                    "after keyword 'enum'")
            } else if (enumDecl.constructors.isEmpty()) {
                if (lastToken.kind == TokenKind.ELLIPSIS) {
                    let db = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_name, lastToken, "an enum name",
                        "at beginning of enum body", ConvertToken(lastToken))
                    db.AddMainHintArguments("an enum constructor name")
                    db.AddNote("ellipse cannot be the only constructor of an enum decl")
                    return
                }
                DiagExpectedIdentifier(MakeRange(enumDecl.leftCurlPos, enumDecl.leftCurlPos + "{".size),
                    "a enum value name", "at beginning of enum body")
            } else if (!enumDecl.bitOrPosVector.isEmpty()) {
                let bitOrPos = enumDecl.bitOrPosVector[enumDecl.bitOrPosVector.size - 1]
                DiagExpectedIdentifier(MakeRange(bitOrPos, bitOrPos + "|".size), "a enum value name",
                    "after '|' in enum body")
            }
        }
    }

    public func DiagExpectedIdentifierWithNode(node: Node): Unit {
        let handlerName = LookupDiagExpectedIdentifierHandler(node.astKind)
        if (handlerName == "DiagExpectedIdentifierEnumDecl") { DiagExpectedIdentifierEnumDecl(node); return }
        if (handlerName == "DiagExpectedIdentifierGeneric") { DiagExpectedIdentifierGeneric(node); return }
        if (handlerName == "DiagExpectedIdentifierGenericConstraint") { DiagExpectedIdentifierGenericConstraint(node); return }
        if (handlerName == "DiagExpectedIdentifierImportContent") { DiagExpectedIdentifierImportContent(node); return }
        if (handlerName == "DiagExpectedIdentifierImportSpec") { DiagExpectedIdentifierImportSpec(node); return }
        if (handlerName == "DiagExpectedIdentifierPackageSpec") { DiagExpectedIdentifierPackageSpec(node); return }
        if (handlerName == "DiagExpectedIdentifierPropDecl") { DiagExpectedIdentifierPropDecl(node); return }
        if (handlerName == "DiagExpectedIdentifierRefType") { DiagExpectedIdentifierRefType(node); return }
        if (handlerName == "DiagExpectedIdentifierFuncParam") { DiagExpectedIdentifierFuncParam(node); return }
        if (handlerName == "DiagExpectedIdentifierQualifiedType") { DiagExpectedIdentifierQualifiedType(node); return }
        if (handlerName == "DiagExpectedIdentifierMemberAccess") { DiagExpectedIdentifierMemberAccess(node); return }
        if (handlerName == "DiagExpectedIdentifierMacroDecl") { DiagExpectedIdentifierMacroDecl(node); return }
        if (handlerName == "DiagExpectedIdentifierFuncBody") { DiagExpectedIdentifierFuncBody(node); return }
        if (handlerName == "DiagExpectedIdentifierFuncDecl") { DiagExpectedIdentifierFuncDecl(node); return }
        if (handlerName == "DiagExpectedIdentifierClassDecl") { DiagExpectedIdentifierClassDecl(node); return }
        if (handlerName == "DiagExpectedIdentifierInterfaceDecl") { DiagExpectedIdentifierInterfaceDecl(node); return }
        if (handlerName == "DiagExpectedIdentifierStructDecl") { DiagExpectedIdentifierStructDecl(node); return }
        if (handlerName == "DiagExpectedIdentifierTypeAliasDecl") { DiagExpectedIdentifierTypeAliasDecl(node); return }
        if (handlerName == "DiagExpectedIdentifierMacroExpandDecl") { DiagExpectedIdentifierMacroExpandDecl(node); return }
        if (handlerName == "DiagExpectedIdentifierMacroExpandExpr") { DiagExpectedIdentifierMacroExpandExpr(node); return }
        DiagExpectedIdentifier(MakeRange(node.begin, node.end))
    }

    public func DiagNameLengthOverflow(range: BasicRange, target: String, maxLength: Int64, realLength: Int64): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_package_name_length_overflow, range, target)
        let note = SubDiagnostic(
            "the maximum length is " + maxLength.toString() + ", the real length is " + realLength.toString())
        builder.AddNote(note)
    }

    public func DiagExpectedExpression(): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_expression, lookahead, ConvertToken(lastToken),
            ConvertToken(lookahead))
    }

    public func DiagExpectedDeclaration(scopeKind: ScopeKind): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_decl, lookahead, ConvertToken(lookahead))
        if (scopeKind == ScopeKind.TOPLEVEL) {
            builder.AddNote("only declarations or macro expressions can be used in the top-level")
        }
    }

    public func DiagExpectedDeclaration(pos: Position, str: String): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_decl, pos, str)
    }

    public func DiagUnsafeWillBeIgnored(mod: Modifier): Unit {
        let backend = OptionBackendToString(compileOptions.backend)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unsafe_will_be_ignored, mod, backend)
        builder.AddMainHintArguments(backend)
    }

    public func DiagMissingBody(str: String, name: String, pos: Position): Unit {
        if (parseDeclFile) {
            return
        }
        let bodyName = if (name.isEmpty()) { str } else { str + name }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_missing_body, pos, bodyName)
        builder.AddMainHintArguments(str)
    }

    public func DiagNamedParameterAfterUnnamed(param: FuncParam, pre: FuncParam): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_named_parameter_after_unnamed, param)
        builder.AddHint(MakeRange(pre.begin, pre.end))
    }

    public func DiagMemberParameterAfterRegular(param: FuncParam, pre: FuncParam): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_member_parameter_after_regular, param)
        builder.AddHint(MakeRange(pre.begin, pre.end))
    }

    public func DiagExpectNoModifier(mod: Modifier): Unit {
        let args = PrepareExpectNoModifierArg(mod)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_no_modifier,
            MakeRange(mod.begin, mod.end), args[0], args[1])
        builder.AddHint(MakeRange(mod.begin, mod.end), arguments: [args[0]])
        builder.AddNote("GAP_TODO: requires faithful port of ParserDiag.cpp:649 PrepareExpectNoModifierArg chainedAST context")
    }

    public func DiagUnexpectedAnnoOn(anno: Annotation, onPos: Position, annoStr: String, onStr: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_anno_on, anno, "@" + annoStr, onStr)
        builder.AddHint(MakeRange(onPos, onStr), arguments: [onStr])
    }

    public func DiagUnexpectedAnnoOnKind(anno: Annotation, onPos: Position, annoStr: String, kind: ASTKind): Unit {
        let keyword = KIND_TO_STR(kind)[0]
        DiagUnexpectedAnnoOn(anno, onPos, annoStr, keyword)
    }

    public func DiagUnExpectedModifierOnDeclaration(decl: Decl): Unit {
        for (modifier in decl.modifiers) {
            if (modifier.modifier == TokenKind.CONST) {
                let builder = ParseDiagnoseRefactor(
                    DiagKindRefactor.parse_unexpected_const_modifier_on_variable,
                    MakeRange(modifier.begin, modifier.end))
                builder.AddHint(MakeRange(decl.keywordPos, decl.keywordPos + 3))
                return
            }
        }
        ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_const_modifier_on_variable, decl)
    }

    public func DiagDeprecatedInvalidTarget(node: Node, invalidTarget: String): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_deprecated_invalid_target, node, invalidTarget)
    }

    public func DiagAnnotationExpectsOneArgument(node: Annotation, annotationName: String): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_annotation_one_argument, node, annotationName, "")
    }

    public func DiagAnnotationExpectsOneArgument(node: Annotation, annotationName: String, argInfo: String): Unit {
        var diagNode: Node = node
        if (node.args.size == 1) {
            diagNode = node.args[0]
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_annotation_one_argument, diagNode,
            annotationName, " " + argInfo)
        if (node.args.size == 1) {
            builder.AddMainHintArguments(argInfo)
        } else {
            builder.AddMainHintArguments("single " + argInfo + " for " + annotationName)
        }
    }

    public func DiagAnnotationMoreThanOneArgs(node: Annotation, annotationName: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_annotation_max_one_argument, node, annotationName, "")
        builder.AddMainHintArguments("single argument for " + annotationName)
    }

    public func DiagAnnotationMoreThanOneArgs(node: Annotation, annotationName: String, argInfo: String): Unit {
        var diagNode: Node = node
        if (node.args.size == 1) {
            diagNode = node.args[0]
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_annotation_max_one_argument, diagNode,
            annotationName, " " + argInfo)
        if (node.args.size == 1) {
            builder.AddMainHintArguments(argInfo)
        } else {
            builder.AddMainHintArguments("single " + argInfo + " for " + annotationName)
        }
    }

    public func DiagAnnotationShouldNotHaveArgs(node: Annotation, annotationName: String): Unit {
        var diagNode: Node = node
        if (!node.args.isEmpty()) {
            diagNode = node.args[0]
        }
        ParseDiagnoseRefactor(DiagKindRefactor.parse_annotation_no_arguments, diagNode, annotationName)
    }
}

private func PrepareExpectNoModifierArg(mod: Modifier): Array<String> {
    return ["no modifier", TokenKindLiteral(mod.modifier)]
}
