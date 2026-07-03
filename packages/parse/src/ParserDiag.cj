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

    public func DiagIllegalModifierInScope(mod: Modifier): Unit {
        let modStr = TokenKindLiteral(mod.modifier)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_illegal_modifier_in_scope, mod, modStr,
            "declaration", "")
        builder.AddHint(MakeRange(mod.begin, mod.end), arguments: ["unexpected modifier"])
        builder.AddNote("GAP_TODO: requires faithful port of ParserDiag.cpp:504 DiagIllegalModifierInScope chainedAST")
    }

    public func DiagConflictedModifier(resMod: Modifier, tarMod: Modifier): Unit {
        let resStr = TokenKindLiteral(resMod.modifier)
        let tarStr = TokenKindLiteral(tarMod.modifier)
        let tarRange = MakeRange(tarMod.begin, tarMod.begin + tarStr.size)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_conflict_modifier, tarRange, tarStr, resStr,
            "declaration")
        builder.AddHint(MakeRange(resMod.begin, resMod.begin + resStr.size))
        builder.AddHint(MakeRange(tarMod.begin, tarMod.end), arguments: ["declaration"])
        builder.AddNote("GAP_TODO: requires faithful port of ParserDiag.cpp:559 DiagConflictedModifier chainedAST")
    }

    public func GetSingleLineContent(begin: Position, end: Position): String {
        if (begin.line == end.line) {
            return sourceManager.GetContentBetween(begin.fileID, begin, end)
        }
        return sourceManager.GetContentBetween(begin.fileID, begin, Position(begin.fileID, begin.line, Int64.Max))
    }

    public func DiagExpectNoModifierBefore(mod: Modifier, str: String): Unit {
        let modStr = TokenKindLiteral(mod.modifier)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_no_modifier,
            MakeRange(mod.begin, mod.end), str, modStr)
        let tokens = lexer.LookAheadSkipNL(1)
        let endPos = if (tokens.isEmpty()) { lookahead.End() } else { tokens[0].End() }
        builder.AddHint(MakeRange(lookahead.Begin(), endPos), arguments: [str])
    }

    public func DiagUnexpectedWhenON(annos: ArrayList<Annotation>): Unit {
        for (anno in annos) {
            if (anno.kind == AnnotationKind.WHEN) {
                DiagUnexpectedAnnoOn(anno, lookahead.Begin(), anno.identifier.Val(), lookahead.Value())
                return
            }
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_anno_on, lookahead, "@When",
            lookahead.Value())
        builder.AddNote("GAP_TODO: requires faithful port of ParserDiag.cpp:642 DiagUnexpectedWhenON annotation lookup")
    }

    public func DiagUnexpectedDeclInScope(sk: ScopeKind): Unit {
        let scopeInfo = SCOPE_TO_DECL(sk)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_declaration_in_scope, lookahead,
            "declaration", scopeInfo[1])
        builder.AddMainHintArguments("declaration in " + scopeInfo[1])
        builder.AddNote("GAP_TODO: requires faithful port of ParserDiag.cpp:717 DiagUnexpectedDeclInScope chainedAST")
    }

    public func DiagExpectedMoreFieldInTuplePattern(): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_tuple_pattern_expected_more_field, lookahead)
        builder.AddNote(
            "GAP_TODO: requires faithful port of ParserDiag.cpp:748 DiagExpectedMoreFieldInTuplePattern chainedAST")
    }

    public func DiagExpectedTypeNameAfterAs(tok: Token): Unit {
        if (tok.kind != TokenKind.AS && tok.kind != TokenKind.IS) {
            return
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_type, lookahead, ConvertToken(tok),
            ConvertToken(lookahead))
        builder.AddHint(MakeRange(tok.Begin(), tok.End()), arguments: [ConvertToken(tok)])
    }

    public func DiagExpectedTypeName(): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_type, lookahead, ConvertToken(lastToken),
            ConvertToken(lookahead))
        builder.AddHint(MakeRange(lastToken.Begin(), lastToken.End()), arguments: [ConvertToken(lastToken)])
    }

    public func DiagInvalidLeftHandExpr(expr: Expr, tok: Token): Unit {
        if (expr.TestAttr(Attribute.IS_BROKEN)) {
            return
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_invalid_left_hand_expr, tok, tok.Value())
        builder.AddHint(MakeRange(expr.begin, expr.end))
    }

    public func IsNoneAssociative(tok: Token): Bool {
        let prec = Precedence(tok.kind)
        return prec == Precedence(TokenKind.ASSIGN) || prec == Precedence(TokenKind.RANGEOP) ||
            prec == Precedence(TokenKind.EQUAL) || prec == Precedence(TokenKind.LT)
    }

    public func DiagNoneAssociativeOp(preT: Token, tok: Token): Unit {
        let prec = Precedence(tok.kind)
        var name = ""
        if (prec == Precedence(TokenKind.ASSIGN)) {
            name = "assignment"
        } else if (prec == Precedence(TokenKind.RANGEOP)) {
            name = "range"
        } else if (prec == Precedence(TokenKind.EQUAL)) {
            name = "equality"
        } else if (prec == Precedence(TokenKind.LT)) {
            name = "comparison"
        }
        if (!name.isEmpty()) {
            let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_chained_none_associative, tok, name)
            builder.AddHint(MakeRange(preT.Begin(), preT.End()))
        }
    }

    public func DiagInvalidInheritType(ty: Type): Unit {
        let typeName = sourceManager.GetContentBetween(ty.begin.fileID, ty.begin, ty.end)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_invalid_super_declaration, ty, typeName)
        builder.AddNote("only class types and interface types can be subtyped")
    }

    public func DiagExpectedRightDelimiter(del: String, pos: Position): Unit {
        let builder = if (lookahead.kind == TokenKind.NL) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_right_delimiter, lastToken, del)
        } else {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_right_delimiter, lastToken.End(), del)
        }
        let expected = match (del) {
            case "{" => "}"
            case "(" => ")"
            case "[" => "]"
            case "<" => ">"
            case _ => del
        }
        builder.AddMainHintArguments(expected)
        builder.AddHint(pos, arguments: [del])
    }

    public func DiagInvalidIncreExpr(expr: Expr): Unit {
        let name = if (lookahead.kind == TokenKind.INCR) { "increment" } else { "decrement" }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_invalid_incre_expr, lookahead, name)
        builder.AddHint(MakeRange(expr.begin, expr.end))
    }

    public func DiagInvalidMacroExpandExpr(tok: Token, expr: MacroExpandExpr): Unit {
        if (let Some(decl) <- expr.invocation.decl) {
            let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_expression, decl, ConvertToken(tok),
                "a declaration")
            builder.AddHint(MakeRange(tok.Begin(), tok.End()))
            return
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_expression, expr, ConvertToken(tok),
            "a declaration")
        builder.AddHint(MakeRange(tok.Begin(), tok.End()))
        builder.AddNote(
            "GAP_TODO: requires faithful port of ParserDiag.cpp:855 DiagInvalidMacroExpandExpr invocation.decl")
    }

    public func DiagUnrecognizedNodeAfterMacro(tok: Token, expr: MacroExpandExpr): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unrecognized_token_after_macro_node, tok,
            ConvertToken(tok))
        if (let Some(decl) <- expr.invocation.decl) {
            builder.AddHint(MakeRange(decl.begin, decl.end))
            return
        }
        builder.AddNote(
            "GAP_TODO: requires faithful port of ParserDiag.cpp:862 DiagUnrecognizedNodeAfterMacro invocation.decl")
    }

    public func DiagChainedAsExpr(expr: Expr, tok: Token): Unit {
        var pos = DEFAULT_POSITION
        if (let Some(asExpr) <- (expr as AsExpr)) {
            pos = asExpr.asPos
        }
        if (let Some(isExpr) <- (expr as IsExpr)) {
            pos = isExpr.isPos
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_chained_none_associative, tok, "`is` and `as`")
        builder.AddHint(MakeRange(pos, pos + "is".size))
    }

    public func DiagExpecetedOpeOrEnd(): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_operator_or_end, lookahead, ConvertToken(lookahead))
    }

    public func DiagExpectedNoNewLine(): Unit {
        let old = skipNL
        skipNL = false
        Next()
        let newline = Peek()
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_no_newline_after, newline,
            ConvertToken(lastToken))
        builder.AddHint(MakeRange(lastToken.Begin(), lastToken.End()), arguments: [ConvertToken(lastToken)])
        skipNL = old
    }

    public func DiagCannotHaveAssignmentInInit(expr: Expr): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_cannot_have_assi_in_init, expr)
    }

    public func DiagOrPattern(): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_illegal_or_pattern, lookahead.Begin())
    }

    public func DiagDeclarationInMacroPackage(decl: Decl): Unit {
        let typeKeyword = KIND_TO_STR(decl.astKind)[0]
        var publicRange = MakeRange(decl.begin, decl.begin)
        var foundPublic = false
        for (modifier in decl.modifiers) {
            if (modifier.modifier == TokenKind.PUBLIC) {
                publicRange = MakeRange(modifier.begin, modifier.begin + "public".size)
                foundPublic = true
                break
            }
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_macro_decl_in_macro_package,
            publicRange, typeKeyword)
        if (let Some(file) <- currentFile) {
            if (let Some(pkg) <- file.packageSpec) {
                builder.AddHint(MakeRange(pkg.macroPos, pkg.packagePos + "package".size))
            } else {
                builder.AddNote(
                    "GAP_TODO: requires faithful port of ParserDiag.cpp:912 DiagDeclarationInMacroPackage package")
            }
        } else {
            builder.AddNote(
                "GAP_TODO: requires faithful port of ParserDiag.cpp:912 DiagDeclarationInMacroPackage currentFile")
        }
        if (!foundPublic) {
            builder.AddNote(
                "GAP_TODO: requires faithful port of ParserDiag.cpp:912 DiagDeclarationInMacroPackage public modifier")
        }
        let note = SubDiagnostic(
            "Declarations in 'macro package' cannot be accessed in other packages, except macro declarations.")
        builder.AddNote(note)
    }

    public func DiagExpectPublicBeforeMacroCall(md: MacroDecl): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_public_before_macro_decl,
            MakeRange(md.keywordPos, md.keywordPos + "macro".size))
    }

    public func DiagExpectMacroParamType(ty: Type): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_macro_illegal_ret_type, ty)
        builder.AddMainHintArguments(ConvertToken(lastToken))
    }

    public func DiagMacroUnexpectNamedParam(param: FuncParam): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_macro_illegal_named_param,
            MakeRange(param.notMarkPos, param.notMarkPos + 1))
        builder.AddHint(MakeRange(param.begin, param.identifier.Begin()), arguments: [param.identifier.Val()])
    }

    public func DiagIllegalFunc(funcDecl: FuncDecl): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_illegal_function_name,
            MakeRange(funcDecl.identifier.Begin(), funcDecl.identifier.End()))
        builder.AddHint(MakeRange(funcDecl.keywordPos, funcDecl.keywordPos + "func".size))
    }

    public func DiagParseExpectedParenthis(postType: Type): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_parentheses, lastToken)
        let help = DiagHelp("should be surrounded by '(' and ')'")
        help.AddSubstitution(MakeRange(postType.begin, postType.end), "(" + lastToken.Value() + ")")
        builder.AddHelp(help)
    }

    public func DiagParseIllegalDeclarationPattern(decl: VarWithPatternDecl, scopeKind: ScopeKind): Unit {
        var patternTypeStr = ""
        if (let Some(pattern) <- decl.irrefutablePattern) {
            if (pattern.astKind == ASTKind.ENUM_PATTERN) {
                patternTypeStr = "enum"
            } else if (pattern.astKind == ASTKind.TUPLE_PATTERN) {
                patternTypeStr = "tuple"
            } else if (pattern.astKind == ASTKind.WILDCARD_PATTERN) {
                patternTypeStr = "wildcard"
            }
            let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_illegal_declaration_pattern, pattern,
                patternTypeStr)
            if (scopeKind == ScopeKind.CLASS_BODY) {
                builder.AddNote(
                    "GAP_TODO: requires faithful port of ParserDiag.cpp:963 DiagParseIllegalDeclarationPattern class chainedAST")
            } else if (scopeKind == ScopeKind.STRUCT_BODY) {
                builder.AddNote(
                    "GAP_TODO: requires faithful port of ParserDiag.cpp:963 DiagParseIllegalDeclarationPattern struct chainedAST")
            }
        }
    }

    public func DiagThisTypeNotAllow(): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_this_type_not_allow, lookahead)
        let note = SubDiagnostic("'This' type can only be used as the return type of an instance member function in class")
        builder.AddNote(note)
    }

    public func DiagInvalidUnicodeScalar(startPos: Position, str: String): Unit {
        let prefixSize = "\\u{".size
        let pos = startPos + prefixSize + 1
        let endPos = startPos + str.size
        let args = "0x" + str[prefixSize..(str.size - 1)]
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_invalid_unicode_scalar, MakeRange(pos, endPos), args)
        builder.AddHint(MakeRange(startPos + 1, startPos + prefixSize + 1))
        builder.AddHint(MakeRange(startPos + str.size, startPos + str.size + 1))
        let note = SubDiagnostic("the valid range of code point is '0x0 ~ 0x7fffffff'")
        builder.AddNote(note)
    }

    public func DiagExpectedLiteral(subPos: Position): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_literal, lookahead, ConvertToken(lookahead))
        builder.AddHint(subPos)
    }

    public func DiagTypePatternInLetCondExpr(pat: Pattern, ek: ExprKind): Unit {
        let exprName = if (ek == ExprKind.WHILE_COND_EXPR) { "while-let" } else { "if-let" }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_type_pattern_in_let_cond, pat, exprName)
        let note = SubDiagnostic(
            exprName + " expression can only accept constant, wildcard, binding, tuple and enum pattern")
        builder.AddNote(note)
    }

    public func DiagExpectedLeftParenAfter(pos: Position, str: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_paren_after, lookahead, str,
            ConvertToken(lookahead))
        builder.AddHint(MakeRange(pos, str))
    }

    public func DiagMatchCaseExpectedExprOrDecl(): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_expr_or_decl_in, lookahead,
            ConvertToken(lookahead))
        DiagMatchCase(builder)
    }

    public func DiagMatchCaseBodyCannotBeEmpty(pos: Position): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_case_body_cannot_be_empty, pos)
        DiagMatchCase(builder)
    }

    public func DiagMatchCase(builder: DiagnosticBuilder): Unit {
        builder.AddNote("GAP_TODO: requires faithful port of ParserDiag.cpp:1045 DiagMatchCase chainedAST")
    }

    public func DiagExpectedCatchOrHandleOrFinallyAfterTry(te: TryExpr): Unit {
        let diagKind = if (enableEH) {
            DiagKindRefactor.parse_expected_catch_or_handle_or_finally_in_try
        } else {
            DiagKindRefactor.parse_expected_catch_or_finally_in_try
        }
        let builder = ParseDiagnoseRefactor(diagKind, lookahead, ConvertToken(lookahead))
        if (let Some(tryBlock) <- te.tryBlock) {
            builder.AddHint(MakeRange(te.begin, tryBlock.end))
        } else {
            builder.AddHint(MakeRange(te.begin, te.end))
            builder.AddNote(
                "GAP_TODO: requires faithful port of ParserDiag.cpp:1062 DiagExpectedCatchOrHandleOrFinallyAfterTry tryBlock")
        }
    }

    public func DiagExpectedSelectorOrMatchExprBody(pos: Position): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_selector_or_match_expression_body, lookahead,
            ConvertToken(lookahead))
        builder.AddHint(MakeRange(pos, "match"))
    }

    public func DiagRedefinedResourceName(cur: (String, Position), pre: (String, Position)): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_redefined_resource_name,
            MakeRange(cur[1], cur[0]), cur[0])
        builder.AddHint(MakeRange(pre[1], pre[0]))
    }

    public func DiagExpectedNoArgumentsInSpawn(params: ArrayList<FuncParam>, pos: Position): Unit {
        let arg = if (params.size == 1) { "argument" } else { "arguments" }
        let diagRange = if (params.isEmpty()) {
            MakeRange(pos, pos + "spawn".size)
        } else {
            MakeRange(params[0].begin, params[params.size - 1].end)
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_no_arguments_in_spawn, diagRange, arg)
        builder.AddMainHintArguments(arg)
        builder.AddHint(MakeRange(pos, "spawn"))
        if (params.isEmpty()) {
            builder.AddNote(
                "GAP_TODO: requires faithful port of ParserDiag.cpp:1085 DiagExpectedNoArgumentsInSpawn params")
        }
    }

    public func DiagExpectCharacter(expectStr: String, noteStr!: String = ""): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character, lookahead, expectStr,
            ConvertToken(lookahead))
        builder.AddMainHintArguments(expectStr)
        if (!noteStr.isEmpty()) {
            builder.AddNote(noteStr)
        }
    }

    public func DiagExpectCharacter(pos: Position, expectStr: String, noteStr!: String = ""): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character, pos, expectStr,
            ConvertToken(lookahead))
        builder.AddMainHintArguments(expectStr)
        if (!noteStr.isEmpty()) {
            builder.AddNote(noteStr)
        }
    }

    public func DiagExpectSemiOrNewline(): Unit {
        DiagExpectCharacter("';' or '<NL>'")
    }

    public func DiagRedundantArrowAfterFunc(ty: Type): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_redundant_arrow_after_func_type, lookahead)
        builder.AddHint(MakeRange(ty.begin, ty.end), arguments: ["function type"])
    }

    public func DiagInvalidOverloadedOperator(): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_invalid_overloaded_operator, lookahead,
            ConvertToken(lookahead))
        let note = SubDiagnostic("only operator '+', '-', ... can be overloaded")
        builder.AddNote(note)
    }

    public func DiagAndSuggestKeywordForExpectedDeclaration(
        keywords: ArrayList<String>,
        minLevDis: UInt64,
        scopeKind: ScopeKind
    ): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_decl, lookahead, ConvertToken(lookahead))
        if (scopeKind == ScopeKind.TOPLEVEL) {
            let note = SubDiagnostic("only declarations or macro expressions can be used in the top-level")
            builder.AddNote(note)
        }
        if (Seeing(TokenKind.IDENTIFIER)) {
            let ident = lookahead.Value()
            for (keyword in keywords) {
                if (LevenshteinDistance(ident, keyword) <= minLevDis) {
                    builder.AddHelp(DiagHelp("did you mean '" + keyword + "'?"))
                    break
                }
            }
        }
    }

    public func DiagConstVariableExpectedInitializer(vd: Decl): Unit {
        if (parseDeclFile) {
            return
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_const_expected_initializer, vd.end)
        builder.AddHint(MakeRange(vd.begin, vd.end))
    }

    public func DiagConstVariableExpectedStatic(key: Token): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_static_for_const_member_var, key)
    }

    public func DiagExpectedOneOfTypeOrInitializer(vd: Decl, str: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_one_of_type_or_initializer, vd.end, str)
        builder.AddHint(MakeRange(vd.begin, vd.end))
    }

    public func DiagExpectedTypeOrInitializerInPattern(vd: Decl): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_type_or_init_in_pattern, vd.end)
        builder.AddHint(MakeRange(vd.begin, vd.end))
    }

    public func DiagExpectedInitializerForToplevelVar(vd: Decl): Unit {
        if (parseDeclFile) {
            return
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_var_must_be_initialized, vd.end)
        builder.AddHint(MakeRange(vd.begin, vd.end))
    }

    public func DiagExpectedIdentifierOrPattern(isVar: Bool, pos: Position, isConst: Bool): Unit {
        if (isConst) {
            let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_one_of_identifier_or_pattern,
                lookahead, "const", ConvertToken(lookahead))
            builder.AddHint(MakeRange(pos, "const"))
            return
        }
        let s = if (isVar) { "var" } else { "let" }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_one_of_identifier_or_pattern,
            lookahead, s, ConvertToken(lookahead))
        builder.AddHint(MakeRange(pos, s))
        if (IsKeyWord(lookahead)) {
            let helpMes = "escape the keyword `" + lookahead.Value() + "` to use it as an identifier"
            let help = DiagHelp(helpMes)
            help.AddSubstitution(MakeRange(lookahead.Begin(), lookahead.End()), "`" + lookahead.Value() + "`")
            builder.AddHelp(help)
        }
    }

    public func DiagExpectedGetOrSetInProp(pos: Position): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_get_or_set_in_prop, lookahead,
            ConvertToken(lookahead))
        builder.AddHint(MakeRange(pos, "prop"))
    }

    public func DiagDuplicatedGetOrSet(node: Node, pd: PropDecl): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_duplicated_get_or_set, lookahead,
            lookahead.Value())
        builder.AddMainHintArguments(lookahead.Value())
        builder.AddHint(MakeRange(node.begin, node.end))
        builder.AddHint(MakeRange(pd.begin, "prop"))
    }

    public func DiagUnknownPrimaryConstructor(str: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_decl, lookahead, ConvertToken(lookahead))
        builder.AddHelp(DiagHelp("probably you want a primary constructor name: '" + str + "'"))
    }

    public func DiagExpectedName(str: String, afterName: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_name, lookahead, str + " name",
            afterName, ConvertToken(lookahead))
        builder.AddMainHintArguments(str + " name")
    }

    public func DiagGetOrSetCannotBeGeneric(str: String, ge: Generic): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_getter_setter_cannot_be_generic, ge, str)
        builder.AddNote(
            "GAP_TODO: requires faithful port of ParserDiag.cpp:1265 DiagGetOrSetCannotBeGeneric chainedAST")
    }

    public func DiagUnexpectedWhere(token: Token): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_where, token)
        builder.AddHint(MakeRange(token.Begin(), token.End()))
        builder.AddNote("GAP_TODO: requires faithful port of ParserDiag.cpp:1285 DiagUnexpectedWhere chainedAST")
    }
}

private func PrepareExpectNoModifierArg(mod: Modifier): Array<String> {
    return ["no modifier", TokenKindLiteral(mod.modifier)]
}
