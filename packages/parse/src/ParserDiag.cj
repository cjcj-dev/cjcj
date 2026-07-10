package cjcj::parse

import cjcj::basic.{DiagHelp, SubDiagnostic}
import cjcj::basic.Range as BasicRange
import cjcj::option.BackendToString as OptionBackendToString
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_ASSERT_WITH_MSG, InternalError}
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
    CJC_ABORT()
    return (MakeRange(DEFAULT_POSITION, node.begin + DEFAULT_POSITION), "declaration")
}

private func TraceBackNode(chainAST: ArrayList<Node>, kinds: Array<ASTKind>): Option<Node> {
    var idx = chainAST.size - 1
    while (idx >= 0) {
        for (kind in kinds) {
            if (chainAST[idx].astKind == kind) {
                return chainAST[idx]
            }
        }
        idx--
    }
    return None
}

private func IsOnlyBlockNode(chain: ArrayList<Node>): (Bool, Option<Node>) {
    if (chain.size <= 1) {
        return (false, None)
    }
    let targetNodes = ArrayList<Node>()
    var idx = chain.size - 2
    while (idx >= 0) {
        let node = chain[idx]
        if (!KIND_TO_STR(node.astKind)[0].isEmpty() || node.astKind == ASTKind.PRIMARY_CTOR_DECL ||
            node.astKind == ASTKind.BLOCK) {
            targetNodes.add(node)
        }
        idx--
    }
    if (targetNodes.isEmpty()) {
        return (false, None)
    }
    if (targetNodes[0].astKind == ASTKind.BLOCK && targetNodes.size > 1) {
        let nextKind = targetNodes[1].astKind
        if (nextKind != ASTKind.FUNC_DECL && nextKind != ASTKind.PRIMARY_CTOR_DECL &&
            nextKind != ASTKind.MAIN_DECL && nextKind != ASTKind.MACRO_DECL &&
            nextKind != ASTKind.INTERPOLATION_EXPR) {
            return (true, targetNodes[0])
        }
        return (false, targetNodes[1])
    }
    return (false, targetNodes[0])
}

private func TraceScopeInChain(chain: ArrayList<Node>): (BasicRange, (String, String)) {
    let nodePair = IsOnlyBlockNode(chain)
    if (let None <- nodePair[1]) {
        return (MakeRange(DEFAULT_POSITION, DEFAULT_POSITION), ("'top-level' scope", "'top-level' scope"))
    }
    let node = nodePair[1].getOrThrow()
    if (nodePair[0] || node.astKind == ASTKind.BLOCK) {
        let block = (node as Block).getOrThrow()
        return (MakeRange(block.leftCurlPos, block.leftCurlPos + "{".size), ("block", "block"))
    }
    if (node.astKind == ASTKind.PRIMARY_CTOR_DECL) {
        let pcd = (node as PrimaryCtorDecl).getOrThrow()
        return (MakeRange(pcd.identifier.Begin(), pcd.identifier.End()), ("primary constructor", "primary constructor"))
    }
    if (node.astKind == ASTKind.INTERPOLATION_EXPR) {
        return (MakeRange(node.begin, "$" + "{"), ("string interpolation", "string interpolation"))
    }
    if (node.astKind == ASTKind.FUNC_DECL) {
        let fd = (node as FuncDecl).getOrThrow()
        if (fd.isGetter) {
            return (MakeRange(node.begin, node.begin + "get".size), ("getter", "getter body"))
        }
        if (fd.isSetter) {
            return (MakeRange(node.begin, node.begin + "set".size), ("setter", "setter body"))
        }
    }
    let kindToStr = KIND_TO_STR(node.astKind)
    if (!kindToStr[0].isEmpty()) {
        let keyword = kindToStr[0]
        let end = node.begin + keyword.size
        var name = keyword
        if (name == "func") {
            name = "function"
        } else if (name == "main") {
            name = "main function"
        }
        return (MakeRange(node.begin, end), (name, name + " body"))
    }
    return (MakeRange(DEFAULT_POSITION, DEFAULT_POSITION), ("'top-level' scope", "'top-level' scope"))
}

private func PrepareExpectNoModifierArg(node: Node, arg: ArrayList<String>, range: ArrayList<BasicRange>): Unit {
    match (node.astKind) {
        case ASTKind.EXTEND_DECL =>
            arg.add("extend declaration")
            range.add(MakeRange(node.begin, node.begin + "extend".size))
        case ASTKind.FUNC_DECL =>
            let fd = (node as FuncDecl).getOrThrow()
            if (fd.isGetter) {
                arg.add("getter function")
                range.add(MakeRange(node.begin, node.begin + "get".size))
            } else if (fd.isSetter) {
                arg.add("setter function")
                range.add(MakeRange(node.begin, node.begin + "set".size))
            } else if (fd.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                arg.add("enum constructor")
                range.add(MakeRange(fd.identifier.Begin(), fd.identifier.End()))
            } else {
                CJC_ABORT()
            }
        case ASTKind.FUNC_PARAM =>
            arg.add("non-member variable parameter")
            range.add(MakeRange(node.begin, node.end))
        case ASTKind.VAR_DECL =>
            let vd = (node as VarDecl).getOrThrow()
            if (vd.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                arg.add("enum constructor")
                range.add(MakeRange(vd.identifier.Begin(), vd.identifier.End()))
            } else {
                CJC_ABORT()
            }
        case _ =>
            return
    }
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
        builder.Emit()
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
        let med = (node as MacroExpandDecl).getOrThrow()
        let dotPos = med.invocation.fullNameDotPos[med.invocation.fullNameDotPos.size - 1]
        DiagExpectedIdentifier(MakeRange(dotPos, dotPos + ".".size), "a type name", "after '.' in qualified name")
    }

    public func DiagExpectedIdentifierMacroExpandExpr(node: Node): Unit {
        let mee = (node as MacroExpandExpr).getOrThrow()
        let dotPos = mee.invocation.fullNameDotPos[mee.invocation.fullNameDotPos.size - 1]
        DiagExpectedIdentifier(MakeRange(dotPos, dotPos + ".".size), "a type name", "after '.' in qualified name")
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
        ParseDiagnoseRefactor(DiagKindRefactor.parse_not_allowed_raw_identifier, lastToken, str).Emit()
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
                    db.Emit()
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
        builder.Emit()
    }

    public func DiagExpectedExpression(): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_expression, lookahead, ConvertToken(lastToken),
            ConvertToken(lookahead)).Emit()
    }

    public func DiagExpectedDeclaration(scopeKind: ScopeKind): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_decl, lookahead, ConvertToken(lookahead))
        if (scopeKind == ScopeKind.TOPLEVEL) {
            builder.AddNote("only declarations or macro expressions can be used in the top-level")
        }
        builder.Emit()
    }

    public func DiagExpectedDeclaration(pos: Position, str: String): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_decl, pos, str).Emit()
    }

    public func DiagUnsafeWillBeIgnored(mod: Modifier): Unit {
        let backend = OptionBackendToString(compileOptions.backend)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unsafe_will_be_ignored, mod, backend)
        builder.AddMainHintArguments(backend)
        builder.Emit()
    }

    public func DiagMissingBody(str: String, name: String, pos: Position): Unit {
        if (parseDeclFile) {
            return
        }
        let bodyName = if (name.isEmpty()) { str } else { str + name }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_missing_body, pos, bodyName)
        builder.AddMainHintArguments(str)
        builder.Emit()
    }

    public func DiagNamedParameterAfterUnnamed(param: FuncParam, pre: FuncParam): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_named_parameter_after_unnamed, param)
        builder.AddHint(MakeRange(pre.begin, pre.end))
        builder.Emit()
    }

    public func DiagMemberParameterAfterRegular(param: FuncParam, pre: FuncParam): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_member_parameter_after_regular, param)
        builder.AddHint(MakeRange(pre.begin, pre.end))
        builder.Emit()
    }

    public func DiagExpectNoModifier(mod: Modifier): Unit {
        CJC_ASSERT(!chainedAST.isEmpty())
        let node = chainedAST[chainedAST.size - 1]
        let args = ArrayList<String>()
        let ranges = ArrayList<BasicRange>()
        PrepareExpectNoModifierArg(node, args, ranges)
        let arg = if (args.isEmpty()) { "" } else { args[0] }
        let range = if (ranges.isEmpty()) { MakeRange(DEFAULT_POSITION, DEFAULT_POSITION) } else { ranges[0] }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_no_modifier,
            MakeRange(mod.begin, mod.begin + mod.ToString().size), arg, mod.ToString())
        builder.AddHint(range, arguments: [arg])
        if (let Some(_) <- (node as FuncParam)) {
            let content = GetSingleLineContent(node.begin, node.end)
            var help = DiagHelp("if you want an immutable member variable, use 'let'")
            help.AddSubstitution(MakeRange(node.begin, node.end), "let " + content)
            builder.AddHelp(help)
            help = DiagHelp("or 'var' to get a mutable member variable")
            help.AddSubstitution(MakeRange(node.begin, node.end), "var " + content)
            builder.AddHelp(help)
        }
        builder.Emit()
    }

    public func DiagUnexpectedAnnoOn(anno: Annotation, onPos: Position, annoStr: String, onStr: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_anno_on, anno, "@" + annoStr, onStr)
        builder.AddHint(MakeRange(onPos, onStr), arguments: [onStr])
        builder.Emit()
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
                builder.Emit()
                return
            }
        }
        ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_const_modifier_on_variable, decl).Emit()
    }

    public func DiagDeprecatedInvalidTarget(node: Node, invalidTarget: String): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_deprecated_invalid_target, node, invalidTarget).Emit()
    }

    public func DiagAnnotationExpectsOneArgument(node: Annotation, annotationName: String): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_annotation_one_argument, node, annotationName, "").Emit()
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
        builder.Emit()
    }

    public func DiagAnnotationMoreThanOneArgs(node: Annotation, annotationName: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_annotation_max_one_argument, node, annotationName, "")
        builder.AddMainHintArguments("single argument for " + annotationName)
        builder.Emit()
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
        builder.Emit()
    }

    public func DiagAnnotationShouldNotHaveArgs(node: Annotation, annotationName: String): Unit {
        var diagNode: Node = node
        if (!node.args.isEmpty()) {
            diagNode = node.args[0]
        }
        ParseDiagnoseRefactor(DiagKindRefactor.parse_annotation_no_arguments, diagNode, annotationName).Emit()
    }

    public func DiagIllegalModifierInScope(mod: Modifier): Unit {
        CJC_ASSERT(!chainedAST.isEmpty())
        let node = chainedAST[chainedAST.size - 1]
        let scopeInfo = TraceScopeInChain(chainedAST)
        var hintFirst = DEFAULT_POSITION
        var hintSecond = DEFAULT_POSITION
        var hintMes = ""
        var needSecondHint = false
        if (node.astKind == ASTKind.FUNC_PARAM || node.astKind == ASTKind.VAR_DECL ||
            node.astKind == ASTKind.FUNC_DECL || node.astKind == ASTKind.PROP_DECL) {
            needSecondHint = true
        }
        let kindToStr = KIND_TO_STR(node.astKind)
        if (!kindToStr[0].isEmpty()) {
            hintFirst = node.begin
            if (node.astKind == ASTKind.PACKAGE_SPEC) {
                hintFirst = (node as PackageSpec).getOrThrow().packagePos
            }
            hintSecond = hintFirst + kindToStr[0].size
            if (node.TestAttr(Attribute.CONSTRUCTOR)) {
                hintMes = "constructor"
            } else if (node.TestAttr(Attribute.FINALIZER)) {
                hintMes = "finalizer"
            } else {
                hintMes = kindToStr[1]
            }
        } else if (node.astKind == ASTKind.FUNC_PARAM) {
            hintFirst = node.begin
            hintSecond = node.begin + "var".size
            hintMes = "variable declaration"
        } else if (node.astKind == ASTKind.PRIMARY_CTOR_DECL) {
            let pcd = (node as PrimaryCtorDecl).getOrThrow()
            hintFirst = pcd.identifier.Begin()
            hintSecond = pcd.identifier.End()
            hintMes = "primary constructor"
        } else {
            CJC_ABORT()
        }
        let modStr = TokenKindLiteral(mod.modifier)
        let secondArg = if (needSecondHint) { " in " + scopeInfo[1][1] } else { "" }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_illegal_modifier_in_scope, mod, modStr,
            hintMes, secondArg)
        if (scopeInfo[0].IsDefault() && needSecondHint) {
            hintMes += " in " + scopeInfo[1][0]
        }
        builder.AddHint(MakeRange(hintFirst, hintSecond), arguments: [hintMes])
        if (!scopeInfo[0].IsDefault()) {
            builder.AddHint(scopeInfo[0], arguments: [scopeInfo[1][0]])
        }
        builder.Emit()
    }

    public func DiagConflictedModifier(resMod: Modifier, tarMod: Modifier): Unit {
        if (chainedAST.isEmpty()) {
            InternalError("The chainAST is empty in DiagConflictedModifier")
            return
        }
        let node = chainedAST[chainedAST.size - 1]
        let resStr = TokenKindLiteral(resMod.modifier)
        let tarStr = TokenKindLiteral(tarMod.modifier)
        let tarRange = MakeRange(tarMod.begin, tarMod.begin + tarStr.size)
        var hintN1 = ""
        var hintN2 = ""
        let kindToStr = KIND_TO_STR(node.astKind)
        if (!kindToStr[0].isEmpty()) {
            hintN1 = kindToStr[0]
            hintN2 = kindToStr[1]
        } else if (node.astKind == ASTKind.PRIMARY_CTOR_DECL) {
            let pcd = (node as PrimaryCtorDecl).getOrThrow()
            hintN1 = pcd.identifier.Val()
            hintN2 = "constructor"
        } else if (node.astKind == ASTKind.FUNC_PARAM) {
            hintN1 = "var"
            hintN2 = "variable declaration"
        } else {
            CJC_ABORT()
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_conflict_modifier, tarRange, tarStr, resStr,
            hintN2)
        builder.AddHint(MakeRange(resMod.begin, resMod.begin + resStr.size))
        if (node.IsDecl()) {
            let decl = (node as Decl).getOrThrow()
            if (decl.astKind == ASTKind.VAR_DECL && decl.IsConst()) {
                builder.AddHint(MakeRange(decl.identifier.Begin(), decl.identifier.End()), arguments: [hintN2])
            } else {
                builder.AddHint(MakeRange(decl.keywordPos, decl.keywordPos + hintN1.size), arguments: [hintN2])
            }
        } else if (node.astKind == ASTKind.PACKAGE_SPEC) {
            let pkgPos = (node as PackageSpec).getOrThrow().packagePos
            builder.AddHint(MakeRange(pkgPos, pkgPos + hintN1.size), arguments: [hintN2])
        } else {
            builder.AddHint(MakeRange(node.begin, node.begin + hintN1.size), arguments: [hintN2])
        }
        builder.Emit()
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
        builder.Emit()
    }

    public func DiagUnexpectedWhenON(annos: ArrayList<Annotation>): Unit {
        for (anno in annos) {
            if (anno.kind == AnnotationKind.WHEN) {
                DiagUnexpectedAnnoOn(anno, lookahead.Begin(), anno.identifier.Val(), lookahead.Value())
                return
            }
        }
        CJC_ASSERT(false)
    }

    public func DiagUnexpectedDeclInScope(sk: ScopeKind): Unit {
        CJC_ASSERT_WITH_MSG(!chainedAST.isEmpty(), "The chainAST is empty in DiagUnexpectedDeclInScope")
        let node = chainedAST[chainedAST.size - 1]
        let target = GetSignature(node)
        let res = TraceScopeInChain(chainedAST)
        let arg = if (res[0].IsDefault() && sk != ScopeKind.TOPLEVEL) {
            SCOPE_TO_DECL(sk)
        } else {
            res[1]
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_declaration_in_scope, target[0],
            target[1], arg[1])
        if (!res[0].IsDefault()) {
            builder.AddHint(res[0], arguments: [arg[0]])
            builder.AddMainHintArguments(target[1])
        } else {
            builder.AddMainHintArguments(target[1] + " in " + arg[1])
        }
        node.EnableAttr(Attribute.IS_BROKEN)
        builder.Emit()
    }

    public func DiagExpectedMoreFieldInTuplePattern(): Unit {
        if (chainedAST.isEmpty() || chainedAST[chainedAST.size - 1].astKind != ASTKind.TUPLE_PATTERN) {
            InternalError("The chainAST is empty in DiagExpectedMoreFieldInTuplePattern")
            return
        }
        let tp = (chainedAST[chainedAST.size - 1] as TuplePattern).getOrThrow()
        ParseDiagnoseRefactor(DiagKindRefactor.parse_tuple_pattern_expected_more_field,
            MakeRange(tp.leftBracePos, tp.rightBracePos + 1)).Emit()
    }

    public func DiagExpectedTypeNameAfterAs(tok: Token): Unit {
        if (tok.kind != TokenKind.AS && tok.kind != TokenKind.IS) {
            return
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_type, lookahead, ConvertToken(tok),
            ConvertToken(lookahead))
        builder.AddHint(MakeRange(tok.Begin(), tok.End()), arguments: [ConvertToken(tok)])
        builder.Emit()
    }

    public func DiagExpectedTypeName(): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_type, lookahead, ConvertToken(lastToken),
            ConvertToken(lookahead))
        builder.AddHint(MakeRange(lastToken.Begin(), lastToken.End()), arguments: [ConvertToken(lastToken)])
        builder.Emit()
    }

    public func DiagInvalidLeftHandExpr(expr: Expr, tok: Token): Unit {
        if (expr.TestAttr(Attribute.IS_BROKEN)) {
            return
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_invalid_left_hand_expr, tok, tok.Value())
        builder.AddHint(MakeRange(expr.begin, expr.end))
        builder.Emit()
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
            builder.Emit()
        }
    }

    public func DiagInvalidInheritType(ty: Type): Unit {
        let typeName = sourceManager.GetContentBetween(ty.begin.fileID, ty.begin, ty.end)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_invalid_super_declaration, ty, typeName)
        builder.AddNote("only class types and interface types can be subtyped")
        builder.Emit()
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
        builder.Emit()
    }

    public func DiagInvalidIncreExpr(expr: Expr): Unit {
        let name = if (lookahead.kind == TokenKind.INCR) { "increment" } else { "decrement" }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_invalid_incre_expr, lookahead, name)
        builder.AddHint(MakeRange(expr.begin, expr.end))
        builder.Emit()
    }

    public func DiagInvalidMacroExpandExpr(tok: Token, expr: MacroExpandExpr): Unit {
        let decl = expr.invocation.decl.getOrThrow()
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_expression, decl, ConvertToken(tok),
            "a declaration")
        builder.AddHint(MakeRange(tok.Begin(), tok.End()))
        builder.Emit()
    }

    public func DiagUnrecognizedNodeAfterMacro(tok: Token, expr: MacroExpandExpr): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unrecognized_token_after_macro_node, tok,
            ConvertToken(tok))
        let decl = expr.invocation.decl.getOrThrow()
        builder.AddHint(MakeRange(decl.begin, decl.end))
        builder.Emit()
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
        builder.Emit()
    }

    public func DiagExpecetedOpeOrEnd(): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_operator_or_end, lookahead, ConvertToken(lookahead)).Emit()
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
        builder.Emit()
    }

    public func DiagCannotHaveAssignmentInInit(expr: Expr): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_cannot_have_assi_in_init, expr).Emit()
    }

    public func DiagOrPattern(): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_illegal_or_pattern, lookahead.Begin()).Emit()
    }

    public func DiagDeclarationInMacroPackage(decl: Decl): Unit {
        let typeKeyword = KIND_TO_STR(decl.astKind)[0]
        var publicRange = MakeRange(DEFAULT_POSITION, DEFAULT_POSITION)
        for (modifier in decl.modifiers) {
            if (modifier.modifier == TokenKind.PUBLIC) {
                publicRange = MakeRange(modifier.begin, modifier.begin + "public".size)
                break
            }
        }
        CJC_ASSERT(!publicRange.IsDefault())
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_macro_decl_in_macro_package,
            publicRange, typeKeyword)
        let file = currentFile.getOrThrow()
        let pkg = file.packageSpec.getOrThrow()
        builder.AddHint(MakeRange(pkg.macroPos, pkg.packagePos + "package".size))
        let note = SubDiagnostic(
            "Declarations in 'macro package' cannot be accessed in other packages, except macro declarations.")
        builder.AddNote(note)
        builder.Emit()
    }

    public func DiagExpectPublicBeforeMacroCall(md: MacroDecl): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_public_before_macro_decl,
            MakeRange(md.keywordPos, md.keywordPos + "macro".size)).Emit()
    }

    public func DiagExpectMacroParamType(ty: Type): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_macro_illegal_ret_type, ty)
        builder.AddMainHintArguments(ConvertToken(lastToken))
        builder.Emit()
    }

    public func DiagMacroUnexpectNamedParam(param: FuncParam): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_macro_illegal_named_param,
            MakeRange(param.notMarkPos, param.notMarkPos + 1))
        builder.AddHint(MakeRange(param.begin, param.identifier.Begin()), arguments: [param.identifier.Val()])
        builder.Emit()
    }

    public func DiagIllegalFunc(funcDecl: FuncDecl): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_illegal_function_name,
            MakeRange(funcDecl.identifier.Begin(), funcDecl.identifier.End()))
        builder.AddHint(MakeRange(funcDecl.keywordPos, funcDecl.keywordPos + "func".size))
        builder.Emit()
    }

    public func DiagParseExpectedParenthis(postType: Type): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_parentheses, lastToken)
        let help = DiagHelp("should be surrounded by '(' and ')'")
        help.AddSubstitution(MakeRange(postType.begin, postType.end), "(" + lastToken.Value() + ")")
        builder.AddHelp(help)
        builder.Emit()
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
            if (let Some(pNode) <- TraceBackNode(chainedAST, [ASTKind.CLASS_DECL, ASTKind.STRUCT_DECL])) {
                let node = (pNode as Decl).getOrThrow()
                if (scopeKind == ScopeKind.CLASS_BODY) {
                    builder.AddHint(MakeRange(node.keywordPos, node.keywordPos + "class".size), arguments: ["class"])
                } else if (scopeKind == ScopeKind.STRUCT_BODY) {
                    builder.AddHint(MakeRange(node.keywordPos, node.keywordPos + "struct".size), arguments: ["struct"])
                }
            }
            builder.Emit()
        }
    }

    public func DiagThisTypeNotAllow(): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_this_type_not_allow, lookahead)
        let note = SubDiagnostic("'This' type can only be used as the return type of an instance member function in class")
        builder.AddNote(note)
        builder.Emit()
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
        builder.Emit()
    }

    public func DiagExpectedLiteral(subPos: Position): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_literal, lookahead, ConvertToken(lookahead))
        builder.AddHint(subPos)
        builder.Emit()
    }

    public func DiagTypePatternInLetCondExpr(pat: Pattern, ek: ExprKind): Unit {
        let exprName = if (ek == ExprKind.WHILE_COND_EXPR) { "while-let" } else { "if-let" }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_type_pattern_in_let_cond, pat, exprName)
        let note = SubDiagnostic(
            exprName + " expression can only accept constant, wildcard, binding, tuple and enum pattern")
        builder.AddNote(note)
        builder.Emit()
    }

    public func DiagExpectedLeftParenAfter(pos: Position, str: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_paren_after, lookahead, str,
            ConvertToken(lookahead))
        builder.AddHint(MakeRange(pos, str))
        builder.Emit()
    }

    public func DiagMatchCaseExpectedExprOrDecl(): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_expr_or_decl_in, lookahead,
            ConvertToken(lookahead))
        DiagMatchCase(builder)
        builder.Emit()
    }

    public func DiagMatchCaseBodyCannotBeEmpty(pos: Position): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_case_body_cannot_be_empty, pos)
        DiagMatchCase(builder)
        builder.Emit()
    }

    public func DiagMatchCase(builder: DiagnosticBuilder): Unit {
        if (let Some(node) <- TraceBackNode(chainedAST, [ASTKind.MATCH_CASE_OTHER, ASTKind.MATCH_CASE])) {
            if (node.astKind == ASTKind.MATCH_CASE) {
                let mc = (node as MatchCase).getOrThrow()
                builder.AddHint(MakeRange(mc.begin, "case"))
            } else if (node.astKind == ASTKind.MATCH_CASE_OTHER) {
                let mco = (node as MatchCaseOther).getOrThrow()
                builder.AddHint(MakeRange(mco.begin, "case"))
            } else {
                CJC_ABORT()
            }
        }
    }

    public func DiagExpectedCatchOrHandleOrFinallyAfterTry(te: TryExpr): Unit {
        let diagKind = if (enableEH) {
            DiagKindRefactor.parse_expected_catch_or_handle_or_finally_in_try
        } else {
            DiagKindRefactor.parse_expected_catch_or_finally_in_try
        }
        let builder = ParseDiagnoseRefactor(diagKind, lookahead, ConvertToken(lookahead))
        let tryBlock = te.tryBlock.getOrThrow()
        builder.AddHint(MakeRange(te.begin, tryBlock.end))
        builder.Emit()
    }

    public func DiagExpectedSelectorOrMatchExprBody(pos: Position): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_selector_or_match_expression_body, lookahead,
            ConvertToken(lookahead))
        builder.AddHint(MakeRange(pos, "match"))
        builder.Emit()
    }

    public func DiagRedefinedResourceName(cur: (String, Position), pre: (String, Position)): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_redefined_resource_name,
            MakeRange(cur[1], cur[0]), cur[0])
        builder.AddHint(MakeRange(pre[1], pre[0]))
        builder.Emit()
    }

    public func DiagExpectedNoArgumentsInSpawn(params: ArrayList<FuncParam>, pos: Position): Unit {
        let arg = if (params.size == 1) { "argument" } else { "arguments" }
        let diagRange = MakeRange(params[0].begin, params[params.size - 1].end)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_no_arguments_in_spawn, diagRange, arg)
        builder.AddMainHintArguments(arg)
        builder.AddHint(MakeRange(pos, "spawn"))
        builder.Emit()
    }

    public func DiagExpectCharacter(expectStr: String, noteStr!: String = ""): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character, lookahead, expectStr,
            ConvertToken(lookahead))
        builder.AddMainHintArguments(expectStr)
        if (!noteStr.isEmpty()) {
            builder.AddNote(noteStr)
        }
        builder.Emit()
    }

    public func DiagExpectCharacter(pos: Position, expectStr: String, noteStr!: String = ""): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character, pos, expectStr,
            ConvertToken(lookahead))
        builder.AddMainHintArguments(expectStr)
        if (!noteStr.isEmpty()) {
            builder.AddNote(noteStr)
        }
        builder.Emit()
    }

    public func DiagExpectSemiOrNewline(): Unit {
        DiagExpectCharacter("';' or '<NL>'")
    }

    public func DiagRedundantArrowAfterFunc(ty: Type): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_redundant_arrow_after_func_type, lookahead)
        builder.AddHint(MakeRange(ty.begin, ty.end), arguments: ["function type"])
        builder.Emit()
    }

    public func DiagInvalidOverloadedOperator(): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_invalid_overloaded_operator, lookahead,
            ConvertToken(lookahead))
        let note = SubDiagnostic("only operator '+', '-', ... can be overloaded")
        builder.AddNote(note)
        builder.Emit()
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
        builder.Emit()
    }

    public func DiagConstVariableExpectedInitializer(vd: Decl): Unit {
        if (parseDeclFile) {
            return
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_const_expected_initializer, vd.end)
        builder.AddHint(MakeRange(vd.begin, vd.end))
        builder.Emit()
    }

    public func DiagConstVariableExpectedStatic(key: Token): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_static_for_const_member_var, key).Emit()
    }

    public func DiagExpectedOneOfTypeOrInitializer(vd: Decl, str: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_one_of_type_or_initializer, vd.end, str)
        builder.AddHint(MakeRange(vd.begin, vd.end))
        builder.Emit()
    }

    public func DiagExpectedTypeOrInitializerInPattern(vd: Decl): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_type_or_init_in_pattern, vd.end)
        builder.AddHint(MakeRange(vd.begin, vd.end))
        builder.Emit()
    }

    public func DiagExpectedInitializerForToplevelVar(vd: Decl): Unit {
        if (parseDeclFile) {
            return
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_var_must_be_initialized, vd.end)
        builder.AddHint(MakeRange(vd.begin, vd.end))
        builder.Emit()
    }

    public func DiagExpectedIdentifierOrPattern(isVar: Bool, pos: Position, isConst: Bool): Unit {
        if (isConst) {
            let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_one_of_identifier_or_pattern,
                lookahead, "const", ConvertToken(lookahead))
            builder.AddHint(MakeRange(pos, "const"))
            builder.Emit()
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
        builder.Emit()
    }

    public func DiagExpectedGetOrSetInProp(pos: Position): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_get_or_set_in_prop, lookahead,
            ConvertToken(lookahead))
        builder.AddHint(MakeRange(pos, "prop"))
        builder.Emit()
    }

    public func DiagDuplicatedGetOrSet(node: Node, pd: PropDecl): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_duplicated_get_or_set, lookahead,
            lookahead.Value())
        builder.AddMainHintArguments(lookahead.Value())
        builder.AddHint(MakeRange(node.begin, node.end))
        builder.AddHint(MakeRange(pd.begin, "prop"))
        builder.Emit()
    }

    public func DiagUnknownPrimaryConstructor(str: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_decl, lookahead, ConvertToken(lookahead))
        builder.AddHelp(DiagHelp("probably you want a primary constructor name: '" + str + "'"))
        builder.Emit()
    }

    public func DiagExpectedName(str: String, afterName: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_name, lookahead, str + " name",
            afterName, ConvertToken(lookahead))
        builder.AddMainHintArguments(str + " name")
        builder.Emit()
    }

    public func DiagGetOrSetCannotBeGeneric(str: String, ge: Generic): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_getter_setter_cannot_be_generic, ge, str)
        var idx = chainedAST.size - 1
        while (idx >= 0) {
            let node = chainedAST[idx]
            if (node.astKind == ASTKind.FUNC_DECL) {
                let fd = (node as FuncDecl).getOrThrow()
                if (fd.isSetter || fd.isGetter) {
                    builder.AddHint(MakeRange(fd.begin, "get"), arguments: [str])
                    builder.Emit()
                    return
                }
            }
            idx--
        }
        CJC_ASSERT_WITH_MSG(false, "cannot find getter or setter")
        builder.Emit()
    }

    public func DiagUnexpectedWhere(token: Token): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_where, token)
        var idx = chainedAST.size - 1
        while (idx >= 0) {
            let node = chainedAST[idx]
            if (node.astKind == ASTKind.FUNC_DECL || node.astKind == ASTKind.CLASS_DECL ||
                node.astKind == ASTKind.INTERFACE_DECL || node.astKind == ASTKind.ENUM_DECL ||
                node.astKind == ASTKind.STRUCT_DECL || node.astKind == ASTKind.MAIN_DECL ||
                node.astKind == ASTKind.EXTEND_DECL) {
                let decl = (node as Decl).getOrThrow()
                let hintRange = if (decl.astKind == ASTKind.EXTEND_DECL) {
                    MakeRange(decl.keywordPos, "extend")
                } else {
                    MakeRange(decl.identifier.Begin(), decl.identifier.End())
                }
                builder.AddHint(hintRange)
                builder.Emit()
                return
            }
            idx--
        }
        CJC_ASSERT_WITH_MSG(false, "cannot find declaration")
        builder.Emit()
    }

    public func DiagDuplicatedIntrinsicFunc(decl: Decl, prev: Decl): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_duplicated_intrinsic_function, decl,
            decl.identifier.Val())
        builder.AddHint(MakeRange(prev.begin, prev.end))
        builder.Emit()
    }

    public func DiagDeclCannotInheritTheirSelf(decl: InheritableDecl, rt: RefType): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_decl_cannot_inherit_their_self, rt,
            rt.ref.identifier.Val())
        builder.AddHint(MakeRange(decl.identifier.Begin(), decl.identifier.End()), arguments: [rt.ref.identifier.Val()])
        builder.Emit()
    }

    public func DiagDuplicatedModifier(mod: Modifier, pre: Modifier): Unit {
        let modStr = TokenKindLiteral(mod.modifier)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_duplicate_modifier, mod, modStr)
        builder.AddHint(MakeRange(pre.begin, pre.end))
        builder.Emit()
    }

    public func DiagUnexpectedColonInRange(re: RangeExpr): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_colon_in_range, lookahead)
        builder.AddHint(MakeRange(re.begin, re.end))
        builder.AddNote("range expression in index access cannot have step if it is without start or end")
        builder.Emit()
    }

    public func DiagDuplicatedAttiValue(attr: String, pos: Position, pre: Position): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_duplicated_attr_value, MakeRange(pos, attr), attr)
        builder.AddHint(MakeRange(pre, attr))
        builder.Emit()
    }

    public func DiagDuplicatedItem(
        name: String,
        sourceName: String,
        errPos: Position,
        prePos: Position,
        attachment: String
    ): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_duplicated_item, MakeRange(errPos, sourceName),
            name, sourceName, attachment)
        builder.AddMainHintArguments(name)
        builder.AddHint(MakeRange(prePos, sourceName))
        builder.Emit()
    }

    public func DiagUnrecognizedAttrInAnno(
        anno: Annotation,
        attrName: String,
        pos: Position,
        acs: ArrayList<String>
    ): Unit {
        var str = ""
        if (!acs.isEmpty()) {
            str = "'" + acs[0] + "'"
            var idx: Int64 = 1
            while (idx < acs.size) {
                let temp = if (idx == acs.size - 1) { " or " } else { ", " }
                str += temp + "'" + acs[idx] + "'"
                idx++
            }
        }
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unrecognized_attr_in_anno,
            MakeRange(pos, attrName), attrName, anno.identifier.Val())
        builder.AddHint(MakeRange(anno.begin, anno.end))
        CJC_ASSERT_WITH_MSG(!acs.isEmpty(), "accepted attributes cannot be empty")
        builder.AddNote("annotation '@" + anno.identifier.Val() + "' only accept " + str + " as attribute")
        builder.Emit()
    }

    public func DiagDuplicatedAnno(anno: Annotation, pre: Annotation): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_duplicated_annotation, anno,
            "@" + anno.identifier.Val())
        builder.AddHint(MakeRange(pre.begin, pre.end))
        builder.Emit()
    }

    public func DiagExpectedLsquareAfter(node: Node, aName: String, note: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_lsquare_after, lookahead, aName,
            ConvertToken(lookahead))
        builder.AddNote(note)
        builder.AddHint(MakeRange(node.begin, node.end))
        builder.Emit()
    }

    public func DiagUnrecognizedExprInWhen(expr: Expr, when: Annotation): Unit {
        let str = sourceManager.GetContentBetween(expr.begin.fileID, expr.begin, expr.end)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unrecognized_expression_in_when, expr, str)
        builder.AddHint(MakeRange(when.begin, when.end))
        builder.AddNote("annotation '@When' can only support unary, binary and ref expression")
        builder.Emit()
    }

    public func DiagDeprecatedArgumentNotLitConst(node: Node): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_deprecated_arguments_must_be_lit_const_expr, node).Emit()
    }

    public func DiagDeprecatedArgumentDuplicated(node: Node, parameterName: String): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_deprecated_argument_duplication, node, parameterName).Emit()
    }

    public func DiagDeprecatedWrongArgumentType(node: Node, paramName: String, expectedType: String): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_deprecated_wrong_argument, node, paramName, expectedType).Emit()
    }

    public func DiagDeprecatedUnknownArgument(arg: Node, name: String): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_deprecated_unknown_argument, arg, name).Emit()
    }

    public func DiagDeprecatedEmptyStringArgument(node: Node, paramName: String): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_deprecated_empty_string_argument, node, paramName).Emit()
    }

    public func DiagUnexpectedTypeIn(ty: Type, inPos: Position, inStr: String, noteStr: String): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_type_in, ty, inStr)
        builder.AddHint(MakeRange(inPos, inStr), arguments: [inStr])
        builder.AddNote(noteStr)
        builder.Emit()
    }

    public func DiagImportingByPackageNameIsNotSupported(expectPos: Position): Unit {
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_importing_by_package_name_is_not_supported,
            expectPos)
        builder.AddNote("importing by package name is not supported.")
        builder.Emit()
    }

    public func DiagVArrayTypeArgMismatch(range: BasicRange, note: String): Unit {
        ParseDiagnoseRefactor(DiagKindRefactor.parse_varray_type_args_mismatch, range, note).Emit()
        ConsumeUntil(TokenKind.NL)
    }

    public func DiagRedundantModifiers(modifier: Modifier): Unit {
        CJC_ASSERT(!chainedAST.isEmpty())
        if (let None <- TraceBackNode(chainedAST, [ASTKind.INTERFACE_DECL])) {
            return
        }
        let node = TraceBackNode(chainedAST, [ASTKind.INTERFACE_DECL]).getOrThrow()
        let kindStr = KIND_TO_STR(node.astKind)
        CJC_ASSERT(!kindStr[0].isEmpty())
        let scopeRange = MakeRange(node.begin, node.begin + kindStr[0].size)
        let modStr = TokenKindLiteral(modifier.modifier)
        let modRange = MakeRange(modifier.begin, modifier.begin + modStr.size)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_redundant_modifier, modRange, modStr)
        builder.AddMainHintArguments("interface member", modStr)
        builder.AddHint(scopeRange)
        builder.Emit()
    }

    public func DiagRedundantModifiers(lowerModifier: Modifier, higherModifier: Modifier): Unit {
        let resStr = TokenKindLiteral(lowerModifier.modifier)
        let tarStr = TokenKindLiteral(higherModifier.modifier)
        let resRange = MakeRange(lowerModifier.begin, lowerModifier.begin + resStr.size)
        let tarRange = MakeRange(higherModifier.begin, higherModifier.begin + tarStr.size)
        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_redundant_modifier, resRange, resStr)
        builder.AddMainHintArguments("'" + tarStr + "'", resStr)
        builder.AddHint(tarRange)
        builder.Emit()
    }
}
