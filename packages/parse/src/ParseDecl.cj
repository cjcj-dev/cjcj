package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func ParseTopLevel(): File {
        let file = File()
        currentFile = file
        file.begin = Peek().Begin()
        SkipNLOrSemi()
        var pendingAnnos = ArrayList<Annotation>()
        ParseTopLevelPreamble(file, pendingAnnos)
        ParseTopLevelDecls(file, pendingAnnos)
        file.end = Peek().End()
        if (enableAttachComment) {
            AttachCommentToFile(file)
        }
        return file
    }

    private func ParseTopLevelPreamble(file: File, annos: ArrayList<Annotation>): Unit {
        if (SeeingBuiltinAnnotation()) {
            ParseAnnotations(annos)
        }
        if (Seeing(TokenKind.FEATURES)) {
            file.feature = ParseTopLvlFeatures(annos)
            annos.clear()
        } else {
            CheckAndHandleUnexpectedTopLevelDeclAfterFeatures()
        }
        if (SeeingBuiltinAnnotation()) {
            ParseAnnotations(annos)
        }
        if (SeeingPackageHeaderAfterModifiers()) {
            let modifiers = ArrayList<Modifier>()
            ParseModifiers(modifiers)
            file.packageSpec = ParsePackageHeader(modifiers)
            if (!annos.isEmpty()) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.INVALID_ANNOTATION,
                    annos[0].begin,
                    "unexpected annotation '${annos[0].identifier.Val()}' on package")
                annos.clear()
            }
            SkipBlank(TokenKind.SEMI)
        } else {
            CheckExpectedTopLevelDeclWhenNoPackage(annos)
        }
        ParseImportSpecInTop(file.imports, annos)
    }

    private func ParseTopLevelDecls(file: File, annos: ArrayList<Annotation>): Unit {
        var topLevelCount: Int64 = 0
        while (!Seeing(TokenKind.END)) {
            if (topLevelCount > 0 && !newlineSkipped && !Skip(TokenKind.SEMI)) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.EXPECTED_TOKEN,
                    Peek().Begin(),
                    "expected ';' or newline between top-level declarations")
                ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI], targetTokenConsumed: false)
            }
            SkipBlank(TokenKind.SEMI)
            if (Seeing(TokenKind.END)) {
                break
            }
            ParseAnnotations(annos)
            ParseTopLevelDecl(file, annos)
            annos.clear()
            topLevelCount++
        }
    }

    private func ParseTopLevelDecl(file: File, annos: ArrayList<Annotation>): Unit {
        let modifiers = ArrayList<Modifier>()
        ParseModifiers(modifiers)
        if (SeeingPackageHeader()) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.UNEXPECTED_TOKEN,
                Peek().Begin(),
                "package declaration is only allowed in the preamble")
            ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI], targetTokenConsumed: false)
            return
        }
        if (SeeingImport()) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.UNEXPECTED_TOKEN,
                Peek().Begin(),
                "import declaration is only allowed before top-level declarations")
            ParseImportSpec(file.imports, annos)
            return
        }
        if (Seeing(TokenKind.FEATURES)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.UNEXPECTED_TOKEN,
                Peek().Begin(),
                "features directive is only allowed before the package header")
            file.feature = ParseTopLvlFeatures(annos)
            return
        }
        if (SeeingDecl() || Seeing(TokenKind.AT) || Seeing(TokenKind.AT_EXCL)) {
            let decl = ParseDecl(ScopeKind.TOPLEVEL, modifiers, annos)
            decl.EnableAttr(Attribute.GLOBAL)
            FinalizeDeclTree(decl)
            CheckMacroPackageTopLevelDecl(file, decl)
            file.decls.add(decl)
            return
        }
        diag.DiagnoseRefactor(DiagKindRefactor.UNEXPECTED_TOKEN, Peek().Begin(), "unexpected token at top level")
        Next()
    }

    private func SeeingPackageHeader(): Bool {
        return Seeing(TokenKind.PACKAGE) || Seeing([TokenKind.MACRO, TokenKind.PACKAGE])
    }

    private func SeeingPackageHeaderAfterModifiers(): Bool {
        if (SeeingPackageHeader()) {
            return true
        }
        if (!SeeingModifier()) {
            return false
        }
        let ahead = lexer.LookAheadSkipNL(32)
        var kind = Peek().kind
        var index: Int64 = 0
        while (ModifierKindFromToken(kind).isSome()) {
            if (index >= ahead.size) {
                return false
            }
            kind = ahead[index].kind
            index++
        }
        if (kind == TokenKind.PACKAGE) {
            return true
        }
        if (kind == TokenKind.MACRO && index < ahead.size && ahead[index].kind == TokenKind.PACKAGE) {
            return true
        }
        return false
    }

    private func CheckMacroPackageTopLevelDecl(file: File, decl: Decl): Unit {
        if (let Some(pkg) <- file.packageSpec) {
            if (pkg.hasMacro && decl.TestAttr(Attribute.PUBLIC) && decl.astKind != ASTKind.MACRO_DECL) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.INVALID_MODIFIER,
                    decl.begin,
                    "public declaration in a macro package must be a macro declaration")
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
        }
    }

    private func CheckAndHandleUnexpectedTopLevelDeclAfterFeatures(): Unit {
        if (SeeingExpectedAfterFeatures(true)) {
            return
        }
        diag.DiagnoseRefactor(
            DiagKindRefactor.UNEXPECTED_TOKEN,
            Peek().Begin(),
            "expected features, package, import, or top-level declaration")
        while (!Seeing(TokenKind.END) && !SeeingExpectedAfterFeatures(true)) {
            Next()
        }
    }

    private func CheckExpectedTopLevelDeclWhenNoPackage(annos: ArrayList<Annotation>): Unit {
        if (!annos.isEmpty()) {
            return
        }
        if (!SeeingExpectedAfterFeatures(false)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.UNEXPECTED_TOKEN,
                Peek().Begin(),
                "expected package, import, or top-level declaration")
        }
    }

    private func SeeingExpectedAfterFeatures(allowPackageKeyword: Bool): Bool {
        if (Seeing(TokenKind.SEMI) || SeeingImport() || SeeingDecl() || SeeingMacroCallDecl() ||
            SeeingBuiltinAnnotation() || Seeing(TokenKind.END)) {
            return true
        }
        return allowPackageKeyword && SeeingPackageHeader()
    }

    public func SeeingDecl(): Bool {
        return SeeingDeclInScope(ScopeKind.UNKNOWN_SCOPE)
    }

    public func SeeingDeclInScope(scopeKind: ScopeKind): Bool {
        let seeingScopedSpecial = (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) && SeeingFinalizer()) ||
            SeeingPrimaryConstructor(scopeKind)
        return seeingScopedSpecial || (SeeingModifier() && !Seeing([TokenKind.UNSAFE, TokenKind.LCURL])) ||
            SeeingAny([TokenKind.FUNC, TokenKind.MACRO, TokenKind.LET, TokenKind.VAR,
            TokenKind.CONST, TokenKind.ENUM, TokenKind.TYPE, TokenKind.STRUCT, TokenKind.CLASS,
            TokenKind.INTERFACE, TokenKind.MAIN, TokenKind.EXTEND, TokenKind.PROP, TokenKind.INIT])
    }

    public func ParseDecl(scopeKind: ScopeKind): Decl {
        let annos = ArrayList<Annotation>()
        let modifiers = ArrayList<Modifier>()
        ParseAnnotations(annos)
        ParseModifiers(modifiers)
        return ParseDecl(scopeKind, modifiers, annos)
    }

    public func ParseDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Decl {
        if (SeeingBuiltinAnnotation() && !modifiers.isEmpty() && annos.isEmpty()) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.INVALID_MODIFIER,
                modifiers[0].begin,
                "modifier cannot appear before annotation")
        }
        ParseAnnotations(annos)
        ParseModifiers(modifiers)
        CheckOverflowAnnotation(annos, scopeKind)
        CheckAnnotationAnnotation(annos, modifiers)
        if (Seeing(TokenKind.AT) || Seeing(TokenKind.AT_EXCL)) {
            return ParseMacroCallDeclInput(scopeKind, modifiers, annos)
        }
        if (SeeingFinalizer()) { return ParseFinalizer(scopeKind, modifiers, annos) }
        if (SeeingPrimaryConstructor(scopeKind)) { return ParsePrimaryConstructor(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.FUNC)) { return ParseFuncDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.MACRO)) { return ParseMacroDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.MAIN)) { return ParseMainDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.LET) || Seeing(TokenKind.VAR) || Seeing(TokenKind.CONST)) { return ParseVarOrLet(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.CLASS)) { return ParseClassDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.INTERFACE)) { return ParseInterfaceDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.STRUCT)) { return ParseStructDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.ENUM)) { return ParseEnumDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.EXTEND)) { return ParseExtendDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.TYPE)) { return ParseTypeAlias(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.PROP)) { return ParsePropDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.INIT)) { return ParseConstructor(scopeKind, modifiers, annos) }
        let token = Peek()
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, token.Begin(), "expected declaration")
        ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RCURL], targetTokenConsumed: false)
        return InvalidDecl(token.Begin())
    }

    private func CheckOverflowAnnotation(annos: ArrayList<Annotation>, scopeKind: ScopeKind): Unit {
        if (annos.isEmpty()) {
            return
        }
        if (SeeingAny([TokenKind.FUNC, TokenKind.MAIN, TokenKind.INIT, TokenKind.AT_EXCL]) || SeeingMacroCall()) {
            return
        }
        if (SeeingPrimaryConstructor(scopeKind)) {
            return
        }
        for (anno in annos) {
            if (anno.kind == AnnotationKind.NUMERIC_OVERFLOW) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.INVALID_ANNOTATION,
                    anno.begin,
                    "unexpected annotation '${anno.identifier.Val()}' on '${Peek().Value()}'")
                anno.isBroken = true
                break
            }
        }
    }

    private func CheckAnnotationAnnotation(annos: ArrayList<Annotation>, modifiers: ArrayList<Modifier>): Unit {
        for (anno in annos) {
            if (anno.kind != AnnotationKind.ANNOTATION) {
                continue
            }
            if (!Seeing(TokenKind.CLASS) && !Seeing(TokenKind.AT)) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.INVALID_ANNOTATION,
                    anno.begin,
                    "@Annotation can only be applied to class declarations")
                anno.isBroken = true
                return
            }
            for (modifier in modifiers) {
                if (modifier.modifier == TokenKind.ABSTRACT || modifier.modifier == TokenKind.OPEN ||
                    modifier.modifier == TokenKind.SEALED) {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.INVALID_ANNOTATION,
                        modifier.begin,
                        "@Annotation cannot be combined with '${TokenKindName(modifier.modifier)}'")
                    anno.isBroken = true
                    return
                }
            }
        }
    }

    public func ParseFuncDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): FuncDecl {
        let ret = FuncDecl()
        ParseFuncLikeHeader(ret, TokenKind.FUNC, scopeKind, modifiers, annos)
        return ret
    }

    public func ParseMacroDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): MacroDecl {
        let ret = MacroDecl()
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.MACRO))
        let keywordToken = Expect(TokenKind.MACRO, "expected 'macro'")
        ret.keywordPos = keywordToken.Begin()
        if (ret.begin.IsZero()) {
            ret.begin = keywordToken.Begin()
        }
        ret.EnableAttr(Attribute.MACRO_FUNC)
        ret.identifier = ExpectIdentifierWithPos(ret)
        if (IsBuiltinAnnotation(moduleName, ret.identifier.Val()) || IsBuiltinMacroDeclName(ret.identifier.Val())) {
            let builtinKind = if (IsBuiltinMacroDeclName(ret.identifier.Val())) { "macro" } else { "annotation" }
            diag.DiagnoseRefactor(
                DiagKindRefactor.PARSE_ERROR,
                ret.identifier.Begin(),
                "macro declaration '${ret.identifier.Val()}' conflicts with builtin ${builtinKind}")
            ret.EnableAttr(Attribute.IS_BROKEN)
        }
        let body = ParseMacroBody(ret)
        ret.funcBody = body
        ret.end = body.end
        if (!ret.TestAttr(Attribute.PUBLIC) && !ret.TestAttr(Attribute.IS_BROKEN)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.INVALID_MODIFIER,
                ret.begin,
                "macro declaration must be public")
            ret.EnableAttr(Attribute.IS_BROKEN)
        }
        CheckMacroDeclPackage(ret)
        return ret
    }

    private func ParseMacroBody(macroDecl: MacroDecl): FuncBody {
        let body = FuncBody()
        body.begin = Peek().Begin()
        body.paramLists.add(ParseMacroParameterList(macroDecl))
        if (Skip(TokenKind.COLON)) {
            body.colonPos = lastToken.Begin()
            body.retType = ParseType()
            if (let Some(retType) <- body.retType) {
                CheckMacroParamType(macroDecl, retType, true)
                body.end = retType.end
            }
        }
        if (body.retType.isNone()) {
            let retPos = if (lastToken.Begin() == INVALID_POSITION) { Peek().Begin() } else { lastToken.Begin() }
            body.retType = MakeTokensRefType(retPos)
        }
        if (Seeing(TokenKind.LCURL)) {
            body.body = ParseBlock(ScopeKind.MACRO_BODY)
            if (let Some(block) <- body.body) {
                body.end = block.end
            }
        } else {
            let invalidBlock = Block()
            invalidBlock.begin = lastToken.End()
            invalidBlock.end = lastToken.End()
            invalidBlock.isBroken = true
            body.body = invalidBlock
            body.end = invalidBlock.end
            diag.DiagnoseRefactor(
                DiagKindRefactor.EXPECTED_TOKEN,
                Peek().Begin(),
                "expected macro body for '${macroDecl.identifier.Val()}'")
            macroDecl.EnableAttr(Attribute.IS_BROKEN)
        }
        return body
    }

    private func ParseMacroParameterList(macroDecl: MacroDecl): FuncParamList {
        let paramList = ParseParameterList(ScopeKind.MACRO_BODY)
        if (paramList.params.isEmpty() || paramList.params.size > 2) {
            let pos = if (paramList.params.isEmpty()) { paramList.begin } else { paramList.params[0].begin }
            diag.DiagnoseRefactor(
                DiagKindRefactor.PARSE_ERROR,
                pos,
                "macro declaration expects one or two Tokens parameters")
            macroDecl.EnableAttr(Attribute.IS_BROKEN)
        } else {
            for (param in paramList.params) {
                if (let Some(paramType) <- param.typeNode) {
                    CheckMacroParamType(macroDecl, paramType, false)
                } else {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.PARSE_ERROR,
                        param.begin,
                        "macro parameter type must be Tokens")
                    macroDecl.EnableAttr(Attribute.IS_BROKEN)
                }
                if (param.isNamedParam) {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.PARSE_ERROR,
                        param.begin,
                        "macro parameters cannot be named parameters")
                    macroDecl.EnableAttr(Attribute.IS_BROKEN)
                }
            }
        }
        return paramList
    }

    private func CheckMacroParamType(macroDecl: MacroDecl, typeNode: Type, isReturnTy: Bool): Unit {
        if (IsTokensRefType(typeNode)) {
            return
        }
        let subject = if (isReturnTy) { "return type" } else { "parameter type" }
        diag.DiagnoseRefactor(
            DiagKindRefactor.PARSE_ERROR,
            typeNode.begin,
            "macro ${subject} must be Tokens")
        macroDecl.EnableAttr(Attribute.IS_BROKEN)
    }

    private func IsTokensRefType(typeNode: Type): Bool {
        if (let Some(refType) <- (typeNode as RefType)) {
            return refType.ref.identifier.Val() == "Tokens" && refType.typeArguments.isEmpty()
        }
        return false
    }

    private func MakeTokensRefType(pos: Position): RefType {
        let typeNode = RefType()
        typeNode.begin = pos
        typeNode.end = pos
        typeNode.ref.identifier = SrcIdentifier("Tokens", "Tokens", pos, pos, false)
        return typeNode
    }

    private func CheckMacroDeclPackage(macroDecl: MacroDecl): Unit {
        if (let Some(file) <- currentFile) {
            var inMacroPackage = false
            if (let Some(pkg) <- file.packageSpec) {
                inMacroPackage = pkg.hasMacro
            }
            if (!inMacroPackage) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    macroDecl.identifier.Begin(),
                    "macro declaration must be defined in a macro package")
                macroDecl.EnableAttr(Attribute.IS_BROKEN)
            }
        }
    }

    private func IsBuiltinMacroDeclName(identifier: String): Bool {
        return identifier == "sourcePackage" || identifier == "sourceFile" || identifier == "sourceLine"
    }

    public func ParseMainDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): MainDecl {
        let ret = MainDecl()
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.MAIN))
        let keywordToken = Expect(TokenKind.MAIN, "expected function keyword")
        ret.keywordPos = keywordToken.Begin()
        if (ret.begin.IsZero()) { ret.begin = keywordToken.Begin() }
        let body = ParseFuncBody(scopeKind)
        ret.funcBody = body
        ret.end = body.end
        ret.identifier = SrcIdentifier("main", "main", ret.keywordPos, ret.keywordPos + 4, false)
        return ret
    }

    public func ParseFuncLikeHeader(ret: FuncDecl, keyword: TokenKind, scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Unit {
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.FUNC))
        if (HasModifierToken(modifiers, TokenKind.CONST)) {
            ret.isConst = true
        }
        let keywordToken = Expect(keyword, "expected function keyword")
        ret.keywordPos = keywordToken.Begin()
        if (ret.begin.IsZero()) { ret.begin = keywordToken.Begin() }
        if (keyword != TokenKind.MAIN) {
            if (ret.TestAttr(Attribute.OPERATOR)) {
                ret.identifier = ExpectOperatorIdentifier(ret)
            } else if (Skip(TokenKind.OPERATOR)) {
                ret.EnableAttr(Attribute.OPERATOR)
                ret.identifier = ExpectOperatorIdentifier(ret)
            } else {
                ret.identifier = ExpectIdentifierWithPos(ret)
            }
        }
        let body = ParseFuncBody(scopeKind)
        ret.funcBody = body
        if (let Some(_) <- body.generic) {
            ret.EnableAttr(Attribute.GENERIC)
        }
        ret.end = body.end
    }

    public func ExpectOperatorIdentifier(ret: FuncDecl): SrcIdentifier {
        let operatorToken = SkipAndReturnOverloadingOperator()
        if (operatorToken.kind == TokenKind.ILLEGAL) {
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_IDENTIFIER, Peek().Begin(), "expected overloadable operator")
            Next()
            return SrcIdentifier("", "", Peek().Begin(), Peek().Begin(), false)
        }
        if (!Seeing(TokenKind.LPAREN) && !Seeing(TokenKind.LT)) {
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected '(' after operator name")
            Next()
        }
        ret.op = operatorToken.kind
        return SrcIdentifier(operatorToken.Value(), operatorToken.Value(), operatorToken.Begin(), operatorToken.End(), false)
    }

    public func SkipAndReturnOverloadingOperator(): Token {
        if (Skip(TokenKind.RSHIFT)) {
            return lastToken
        }
        if (Skip(TokenKind.GE)) {
            return lastToken
        }
        if (SeeingCombinator([TokenKind.GT, TokenKind.GT])) {
            let start = Peek().Begin()
            SkipCombinator([TokenKind.GT, TokenKind.GT])
            return Token(TokenKind.RSHIFT, ">>", start, lastToken.End())
        }
        if (SeeingCombinator([TokenKind.GT, TokenKind.ASSIGN])) {
            let start = Peek().Begin()
            SkipCombinator([TokenKind.GT, TokenKind.ASSIGN])
            return Token(TokenKind.GE, ">=", start, lastToken.End())
        }
        if (Seeing([TokenKind.LSQUARE, TokenKind.RSQUARE])) {
            let start = Peek().Begin()
            Skip(TokenKind.LSQUARE)
            Skip(TokenKind.RSQUARE)
            return Token(TokenKind.LSQUARE, "[]", start, lastToken.End())
        }
        if (Seeing([TokenKind.LPAREN, TokenKind.RPAREN])) {
            let start = Peek().Begin()
            Skip(TokenKind.LPAREN)
            Skip(TokenKind.RPAREN)
            return Token(TokenKind.LPAREN, "()", start, lastToken.End())
        }
        if (SkipOperator()) {
            return lastToken
        }
        return Token(TokenKind.ILLEGAL)
    }

    public func SkipOperator(): Bool {
        return Skip(TokenKind.NOT) || Skip(TokenKind.ADD) || Skip(TokenKind.SUB) || Skip(TokenKind.EXP) ||
            Skip(TokenKind.MUL) || Skip(TokenKind.DIV) || Skip(TokenKind.MOD) || Skip(TokenKind.LSHIFT) ||
            Skip(TokenKind.LT) || Skip(TokenKind.LE) || Skip(TokenKind.GT) || Skip(TokenKind.EQUAL) ||
            Skip(TokenKind.NOTEQ) || Skip(TokenKind.BITAND) || Skip(TokenKind.BITXOR) || Skip(TokenKind.BITOR)
    }

    public func ParseFuncBody(scopeKind: ScopeKind): FuncBody {
        let body = FuncBody()
        body.begin = Peek().Begin()
        if (let Some(generic) <- ParseOptionalGeneric()) {
            body.generic = generic
        }
        body.paramLists.add(ParseParameterList(scopeKind))
        let paramsEnd = lastToken.End()
        if (Skip(TokenKind.COLON)) {
            body.colonPos = lastToken.Begin()
            body.retType = ParseType()
        }
        var constraintsEnd = INVALID_POSITION
        for (constraint in ParseGenericConstraints()) {
            EnsureFuncBodyGeneric(body).genericConstraints.add(constraint)
            constraintsEnd = constraint.end
        }
        if (Seeing(TokenKind.LCURL)) {
            body.body = ParseBlock(ScopeKind.FUNC_BODY)
            if (let Some(block) <- body.body) { body.end = block.end }
        } else if (!constraintsEnd.IsZero()) {
            body.end = constraintsEnd
        } else if (let Some(retType) <- body.retType) {
            body.end = retType.end
        } else {
            body.end = paramsEnd
        }
        return body
    }

    private func EnsureFuncBodyGeneric(body: FuncBody): Generic {
        if (let Some(generic) <- body.generic) {
            return generic
        }
        let generic = Generic()
        body.generic = generic
        return generic
    }

    public func ParseParameterList(scopeKind: ScopeKind): FuncParamList {
        let list = FuncParamList()
        list.leftParenPos = Expect(TokenKind.LPAREN, "expected '(' for parameter list").Begin()
        list.begin = list.leftParenPos
        var namedParameter: Option<FuncParam> = None
        var memberParameter: Option<FuncParam> = None
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
            let param = ParseFuncParam(scopeKind)
            if (let Some(firstNamed) <- namedParameter) {
                if (!param.isNamedParam) {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.PARSE_ERROR,
                        param.begin,
                        "unnamed parameter cannot appear after named parameter '${firstNamed.identifier.Val()}'")
                    param.EnableAttr(Attribute.IS_BROKEN)
                }
            }
            if (let Some(firstMember) <- memberParameter) {
                if (!param.isMemberParam) {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.PARSE_ERROR,
                        param.begin,
                        "regular parameter cannot appear after member parameter '${firstMember.identifier.Val()}'")
                    param.EnableAttr(Attribute.IS_BROKEN)
                }
            }
            if (param.isNamedParam && namedParameter.isNone()) {
                namedParameter = param
            }
            if (param.isMemberParam && memberParameter.isNone()) {
                memberParameter = param
            }
            if (param.identifier.Val() == "...") {
                list.hasVariableLenArg = true
                list.variadicArgIndex = UInt64(list.params.size)
            }
            list.params.add(param)
            if (Skip(TokenKind.COMMA)) {
                param.commaPos = lastToken.Begin()
            } else {
                break
            }
        }
        list.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after parameters").Begin()
        list.end = list.rightParenPos + 1
        if (ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_SETTER_BODY)) {
            if (list.params.isEmpty()) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    list.begin,
                    "setter must contain one parameter")
            } else if (list.params.size > 1) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    list.params[1].begin,
                    "setter can only accept one parameter")
            }
        }
        return list
    }

    public func ParseFuncParam(): FuncParam {
        return ParseFuncParam(ScopeKind.UNKNOWN_SCOPE)
    }

    public func ParseFuncParam(scopeKind: ScopeKind): FuncParam {
        let param = FuncParam()
        ParseAnnotations(param.annotations)
        let mods = ArrayList<Modifier>()
        ParseModifiers(mods)
        for (modifier in mods) { param.modifiers.add(modifier) }
        let isPrimaryConstructor = ScopeKindEquals(scopeKind, ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS) ||
            ScopeKindEquals(scopeKind, ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT)
        var memberStart = INVALID_POSITION
        if (Skip(TokenKind.LET) || Skip(TokenKind.VAR)) {
            param.hasLetOrVar = true
            param.keywordPos = lastToken.Begin()
            if (isPrimaryConstructor) {
                param.isMemberParam = true
                param.isVar = lastToken.kind == TokenKind.VAR
                memberStart = lastToken.Begin()
            } else {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    lastToken.Begin(),
                    "'${lastToken.Value()}' is only allowed in primary constructor parameter lists")
                param.EnableAttr(Attribute.IS_BROKEN)
            }
        }
        if (Skip(TokenKind.ELLIPSIS)) {
            param.identifier = SrcIdentifier("...", "...", lastToken.Begin(), lastToken.End(), false)
            param.begin = if (!param.modifiers.isEmpty()) { param.modifiers[0].begin } else { param.identifier.Begin() }
            param.end = param.identifier.End()
            return param
        }
        if (Skip(TokenKind.WILDCARD)) {
            if (param.hasLetOrVar) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    lastToken.Begin(),
                    "wildcard cannot be used as member parameter name")
                param.EnableAttr(Attribute.IS_BROKEN)
            }
            param.identifier = SrcIdentifier("_", "_", lastToken.Begin(), lastToken.End(), false)
        } else {
            param.identifier = ExpectIdentifierWithPos(param)
        }
        param.begin = if (!param.modifiers.isEmpty()) { param.modifiers[0].begin } else { param.identifier.Begin() }
        if (param.isMemberParam) {
            param.begin = memberStart
        }
        if (!ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_SETTER_BODY) &&
            !ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_GETTER_BODY) && Skip(TokenKind.NOT)) {
            if (param.identifier.Val() == "_") {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.EXPECTED_TOKEN,
                    lastToken.Begin(),
                    "expected ':' after wildcard parameter")
                param.EnableAttr(Attribute.IS_BROKEN)
            }
            param.notMarkPos = lastToken.Begin()
            param.isNamedParam = true
        }
        if (ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_SETTER_BODY) ||
            ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_GETTER_BODY)) {
            param.end = param.identifier.End()
            return param
        }
        if (!Skip(TokenKind.COLON)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.EXPECTED_TOKEN,
                Peek().Begin(),
                "expected ':' in parameter declaration")
            let invalidType = InvalidType(Peek().Begin())
            invalidType.isBroken = true
            param.typeNode = invalidType
            param.end = invalidType.end
            param.EnableAttr(Attribute.IS_BROKEN)
            return param
        } else {
            param.colonPos = lastToken.Begin()
            param.typeNode = ParseType()
        }
        if (Skip(TokenKind.ASSIGN)) {
            if (!param.isNamedParam) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.EXPECTED_TOKEN,
                    lastToken.Begin(),
                    "default parameter value requires a named parameter marker '!'")
                param.EnableAttr(Attribute.IS_BROKEN)
            }
            param.assignPos = lastToken.Begin()
            param.assignment = ParseExpr()
        }
        if (Skip(TokenKind.ELLIPSIS)) {
            param.identifier = SrcIdentifier("...", "...", lastToken.Begin(), lastToken.End(), false)
        }
        param.end = if (let Some(expr) <- param.assignment) {
            expr.end
        } else if (let Some(ty) <- param.typeNode) {
            ty.end
        } else {
            param.identifier.End()
        }
        return param
    }

    public func ParseVarOrLet(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Decl {
        let key = Peek()
        let isVar = key.kind == TokenKind.VAR
        let isConst = key.kind == TokenKind.CONST
        Next()
        if (SeeingVarWithPatternStart()) {
            return ParseVarWithPatternDecl(scopeKind, modifiers, annos, key, isVar, isConst)
        }
        if (SeeingIdentifierLike()) {
            return ParseVarDecl(scopeKind, modifiers, annos, key, isVar, isConst)
        }
        diag.DiagnoseRefactor(
            DiagKindRefactor.EXPECTED_IDENTIFIER,
            Peek().Begin(),
            "expected identifier or irrefutable pattern after '${key.Value()}'")
        ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RCURL], targetTokenConsumed: false)
        return InvalidDecl(key.Begin())
    }

    private func SeeingVarWithPatternStart(): Bool {
        return Seeing(TokenKind.WILDCARD) || Seeing(TokenKind.LPAREN) ||
            SeeingIdentifierAndTargetOp([TokenKind.LPAREN, TokenKind.DOT, TokenKind.LT])
    }

    private func ParseVarDecl(
        scopeKind: ScopeKind,
        modifiers: ArrayList<Modifier>,
        annos: ArrayList<Annotation>,
        key: Token,
        isVar: Bool,
        isConst: Bool
    ): VarDecl {
        let decl = VarDecl()
        ApplyModifiersAndAnnotations(decl, modifiers, annos)
        decl.keywordPos = key.Begin()
        decl.identifier = ExpectIdentifierWithPos(decl)
        decl.isVar = isVar
        decl.isConst = isConst
        decl.begin = if (decl.begin.IsZero()) { key.Begin() } else { decl.begin }
        ParseTypeAndExpr(decl)
        CheckVarDeclShape(decl, modifiers, scopeKind, key)
        return decl
    }

    private func ParseVarWithPatternDecl(
        scopeKind: ScopeKind,
        modifiers: ArrayList<Modifier>,
        annos: ArrayList<Annotation>,
        key: Token,
        isVar: Bool,
        isConst: Bool
    ): VarWithPatternDecl {
        let pattern = ParsePattern(ArrayList<Attribute>(), isVar, true)
        let decl = VarWithPatternDecl()
        ApplyModifiersAndAnnotations(decl, modifiers, annos)
        decl.keywordPos = key.Begin()
        decl.irrefutablePattern = pattern
        decl.isVar = isVar
        decl.isConst = isConst
        decl.begin = if (decl.begin.IsZero()) { key.Begin() } else { decl.begin }
        ParseTypeAndExpr(decl)
        if (decl.end.IsZero()) {
            decl.end = pattern.end
        }
        if ((pattern.astKind == ASTKind.TUPLE_PATTERN || pattern.astKind == ASTKind.ENUM_PATTERN ||
                pattern.astKind == ASTKind.WILDCARD_PATTERN) &&
            (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) || ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY))) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.PARSE_ERROR,
                pattern.begin,
                "declaration patterns are not allowed in class or struct body")
            decl.EnableAttr(Attribute.IS_BROKEN)
        }
        CheckVarDeclShape(decl, modifiers, scopeKind, key)
        return decl
    }

    public func ParseTypeAndExpr(ret: VarDeclAbstract): Unit {
        if (Skip(TokenKind.COLON)) {
            ret.colonPos = lastToken.Begin()
            ret.typeNode = ParseType()
        }
        if (Skip(TokenKind.ASSIGN)) {
            ret.assignPos = lastToken.Begin()
            ret.initializer = ParseExpr(ExprKind.VAR_INIT)
        }
        ret.end = if (let Some(expr) <- ret.initializer) {
            expr.end
        } else if (let Some(ty) <- ret.typeNode) {
            ty.end
        } else if (!ret.identifier.Empty()) {
            ret.identifier.End()
        } else {
            ret.end
        }
    }

    private func CheckVarDeclShape(
        decl: VarDeclAbstract,
        modifiers: ArrayList<Modifier>,
        scopeKind: ScopeKind,
        key: Token
    ): Unit {
        EnableModifierAttrs(decl, CheckDeclModifiers(modifiers, scopeKind, DefKind.VARIABLE))
        if (!decl.isConst && HasModifierToken(modifiers, TokenKind.CONST)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.INVALID_MODIFIER,
                key.Begin(),
                "modifier 'const' cannot be used on '${key.Value()}' declaration")
            decl.EnableAttr(Attribute.IS_BROKEN)
        }
        if (decl.isConst && (let None <- decl.initializer)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.EXPECTED_TOKEN,
                key.Begin(),
                "const variable declaration requires an initializer")
            decl.EnableAttr(Attribute.IS_BROKEN)
        } else if (!decl.isConst && !ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL) &&
            (let None <- decl.typeNode) && (let None <- decl.initializer)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.EXPECTED_TOKEN,
                key.Begin(),
                "local variable declaration requires a type annotation or initializer")
            decl.EnableAttr(Attribute.IS_BROKEN)
        } else if (!decl.isConst && ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL) && (let None <- decl.initializer) &&
            !HasModifierToken(modifiers, TokenKind.FOREIGN) &&
            ((let None <- decl.typeNode) || !HasModifierToken(modifiers, TokenKind.COMMON))) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.EXPECTED_TOKEN,
                key.Begin(),
                "top-level variable declaration requires an initializer unless it is foreign")
            decl.EnableAttr(Attribute.IS_BROKEN)
        }
    }

    private func HasModifierToken(modifiers: ArrayList<Modifier>, tokenKind: TokenKind): Bool {
        for (modifier in modifiers) {
            if (modifier.modifier == tokenKind) {
                return true
            }
        }
        return false
    }

    public func ParseClassDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): ClassDecl {
        let ret = ClassDecl()
        ParseInheritableHeader(ret, TokenKind.CLASS, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.CLASS))
        SetPrimaryDecl(ret.identifier.Val())
        ParseClassLikeBody(ret, ScopeKind.CLASS_BODY)
        RevertPrimaryDecl()
        return ret
    }

    public func ParseInterfaceDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): InterfaceDecl {
        let ret = InterfaceDecl()
        ParseInheritableHeader(ret, TokenKind.INTERFACE, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.INTERFACE))
        ParseClassLikeBody(ret, ScopeKind.INTERFACE_BODY)
        return ret
    }

    public func ParseStructDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): StructDecl {
        let ret = StructDecl()
        ParseInheritableHeader(ret, TokenKind.STRUCT, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.STRUCT))
        SetPrimaryDecl(ret.identifier.Val())
        ParseClassLikeBody(ret, ScopeKind.STRUCT_BODY)
        RevertPrimaryDecl()
        return ret
    }

    public func ParseEnumDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): EnumDecl {
        let ret = EnumDecl()
        ParseInheritableHeader(ret, TokenKind.ENUM, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.ENUM))
        if (Skip(TokenKind.LCURL)) {
            ret.leftCurlPos = lastToken.Begin()
            ret.bodyScope = DummyBody()
            if (let Some(bodyScope) <- ret.bodyScope) {
                bodyScope.begin = ret.leftCurlPos
            }
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RCURL)) {
                if (Skip(TokenKind.BITOR)) {
                    ret.bitOrPosVector.add(lastToken.Begin())
                    continue
                }
                let localAnnos = ArrayList<Annotation>()
                ParseAnnotations(localAnnos)
                if (SeeingIdentifierLike()) {
                    let ctor = ParseEnumConstructor(ArrayList<Modifier>(), localAnnos)
                    ctor.outerDecl = ret
                    if (ctor.astKind == ASTKind.FUNC_DECL) {
                        ret.hasArguments = true
                    }
                    ret.constructors.add(ctor)
                } else if (SeeingDeclInScope(ScopeKind.ENUM_BODY)) {
                    let member = ParseDecl(ScopeKind.ENUM_BODY)
                    member.outerDecl = ret
                    ret.members.add(member)
                } else {
                    Next()
                }
                SkipNLOrSemi()
            }
            ret.rightCurlPos = Expect(TokenKind.RCURL, "expected '}' after enum body").Begin()
            ret.end = ret.rightCurlPos + 1
        }
        return ret
    }

    public func ParseEnumConstructor(modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Decl {
        let identifier = ExpectIdentifierWithPos(Node())
        if (Skip(TokenKind.LPAREN)) {
            let decl = FuncDecl()
            ApplyModifiersAndAnnotations(decl, modifiers, annos)
            decl.EnableAttr(Attribute.ENUM_CONSTRUCTOR)
            decl.identifier = identifier
            decl.begin = if (decl.begin.IsZero()) { identifier.Begin() } else { decl.begin }
            let paramList = FuncParamList()
            paramList.leftParenPos = lastToken.Begin()
            paramList.begin = paramList.leftParenPos
            var index: Int64 = 1
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
                let param = FuncParam()
                let ty = ParseType()
                param.identifier = SrcIdentifier("p${index}", "p${index}", ty.begin, ty.begin, false)
                param.isIdentifierCompilerAdd = true
                param.typeNode = ty
                param.begin = ty.begin
                param.end = ty.end
                paramList.params.add(param)
                index++
                if (!Skip(TokenKind.COMMA)) { break }
            }
            paramList.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after enum constructor").Begin()
            paramList.end = paramList.rightParenPos + 1
            let body = FuncBody()
            body.begin = paramList.begin
            body.paramLists.add(paramList)
            body.end = paramList.end
            decl.funcBody = body
            decl.end = body.end
            return decl
        }
        let decl = VarDecl()
        ApplyModifiersAndAnnotations(decl, modifiers, annos)
        decl.EnableAttr(Attribute.ENUM_CONSTRUCTOR)
        decl.identifier = identifier
        decl.begin = if (decl.begin.IsZero()) { decl.identifier.Begin() } else { decl.begin }
        decl.end = decl.identifier.End()
        return decl
    }

    public func ParseInheritableHeader(ret: InheritableDecl, keyword: TokenKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Unit {
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        let key = Expect(keyword, "expected declaration keyword")
        ret.keywordPos = key.Begin()
        ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
        ret.identifier = ExpectIdentifierWithPos(ret)
        if (let Some(generic) <- ParseOptionalGeneric()) {
            ret.generic = generic
            ret.EnableAttr(Attribute.GENERIC)
        }
        // The supertype clause is introduced by `<:` (the subtype operator, lexed as UPPERBOUND), e.g.
        // `class Sub <: Base & I`. (A bare `:` is accepted too for leniency.)
        if (Skip(TokenKind.UPPERBOUND) || Skip(TokenKind.COLON)) {
            ret.inheritedTypes.add(ParseType())
            while (Skip(TokenKind.BITAND)) {
                ret.inheritedTypes.add(ParseType())
            }
        }
        for (constraint in ParseGenericConstraints()) {
            EnsureDeclGeneric(ret).genericConstraints.add(constraint)
        }
        ret.end = ret.identifier.End()
    }

    private func EnsureDeclGeneric(decl: Decl): Generic {
        if (let Some(generic) <- decl.generic) {
            return generic
        }
        let generic = Generic()
        decl.generic = generic
        return generic
    }

    public func ParseClassLikeBody(ret: InheritableDecl, scopeKind: ScopeKind): Unit {
        if (!Skip(TokenKind.LCURL)) {
            return
        }
        let leftCurl = lastToken.Begin()
        SetDeclBodyLeftCurl(ret, leftCurl)
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RCURL)) {
            if (SeeingDeclInScope(scopeKind) || Seeing(TokenKind.AT) || Seeing(TokenKind.AT_EXCL)) {
                let member = ParseDecl(scopeKind)
                member.outerDecl = ret
                AddBodyMember(ret, member)
            } else {
                Next()
            }
            SkipNLOrSemi()
        }
        let rightCurl = Expect(TokenKind.RCURL, "expected '}' after declaration body").Begin()
        SetDeclBodyRightCurl(ret, rightCurl)
        ret.end = rightCurl + 1
    }

    private func SetDeclBodyLeftCurl(ret: InheritableDecl, pos: Position): Unit {
        if (let Some(classDecl) <- (ret as ClassDecl)) {
            let body = ClassBody()
            body.leftCurlPos = pos
            body.begin = pos
            classDecl.body = body
        } else if (let Some(interfaceDecl) <- (ret as InterfaceDecl)) {
            let body = InterfaceBody()
            body.leftCurlPos = pos
            body.begin = pos
            interfaceDecl.body = body
        } else if (let Some(structDecl) <- (ret as StructDecl)) {
            let body = StructBody()
            body.leftCurlPos = pos
            body.begin = pos
            structDecl.body = body
        } else if (let Some(extendDecl) <- (ret as ExtendDecl)) {
            extendDecl.leftCurlPos = pos
        }
    }

    private func SetDeclBodyRightCurl(ret: InheritableDecl, pos: Position): Unit {
        if (let Some(classDecl) <- (ret as ClassDecl)) {
            if (let Some(body) <- classDecl.body) {
                body.rightCurlPos = pos
                body.end = pos + 1
            }
        } else if (let Some(interfaceDecl) <- (ret as InterfaceDecl)) {
            if (let Some(body) <- interfaceDecl.body) {
                body.rightCurlPos = pos
                body.end = pos + 1
            }
        } else if (let Some(structDecl) <- (ret as StructDecl)) {
            if (let Some(body) <- structDecl.body) {
                body.rightCurlPos = pos
                body.end = pos + 1
            }
        } else if (let Some(extendDecl) <- (ret as ExtendDecl)) {
            extendDecl.rightCurlPos = pos
        }
    }

    private func AddBodyMember(ret: InheritableDecl, member: Decl): Unit {
        if (let Some(classDecl) <- (ret as ClassDecl)) {
            if (let Some(body) <- classDecl.body) {
                body.decls.add(member)
            }
        } else if (let Some(interfaceDecl) <- (ret as InterfaceDecl)) {
            if (let Some(body) <- interfaceDecl.body) {
                body.decls.add(member)
            }
        } else if (let Some(structDecl) <- (ret as StructDecl)) {
            if (let Some(body) <- structDecl.body) {
                body.decls.add(member)
            }
        } else if (let Some(extendDecl) <- (ret as ExtendDecl)) {
            extendDecl.members.add(member)
        }
    }

    public func ParseExtendDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): ExtendDecl {
        let ret = ExtendDecl()
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.EXTEND))
        let key = Expect(TokenKind.EXTEND, "expected 'extend'")
        ret.keywordPos = key.Begin()
        ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
        ret.extendedType = ParseType()
        ParseClassLikeBody(ret, ScopeKind.EXTEND_BODY)
        return ret
    }

    public func ParseTypeAlias(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): TypeAliasDecl {
        let ret = TypeAliasDecl()
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.TYPE))
        let key = Expect(TokenKind.TYPE, "expected 'type'")
        ret.keywordPos = key.Begin()
        ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
        ret.identifier = ExpectIdentifierWithPos(ret)
        if (let Some(generic) <- ParseOptionalGeneric()) { ret.generic = generic }
        ret.assignPos = Expect(TokenKind.ASSIGN, "expected '=' in type alias").Begin()
        ret.typeNode = ParseType()
        ret.end = if (let Some(ty) <- ret.typeNode) { ty.end } else { ret.identifier.End() }
        return ret
    }

    public func ParsePropDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): PropDecl {
        let ret = PropDecl()
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.PROPERTY))
        let key = Expect(TokenKind.PROP, "expected 'prop'")
        ret.keywordPos = key.Begin()
        ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
        ret.identifier = ExpectIdentifierWithPos(ret)
        if (Skip(TokenKind.COLON)) {
            ret.colonPos = lastToken.Begin()
            ret.typeNode = ParseType()
        }
        if (Skip(TokenKind.ASSIGN)) {
            ret.assignPos = lastToken.Begin()
            ret.initializer = ParseExpr(ExprKind.VAR_INIT)
        }
        if (Skip(TokenKind.LCURL)) {
            ret.leftCurlPos = lastToken.Begin()
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RCURL)) {
                if (Seeing(TokenKind.IDENTIFIER) && (Peek().Value() == "get" || Peek().Value() == "set")) {
                    let accessorName = Peek().Value()
                    let accessor = FuncDecl()
                    accessor.identifier = ParseIdentifierFromToken(Peek())
                    Next()
                    accessor.funcBody = ParseFuncBody(if (accessorName == "get") { ScopeKind.PROP_MEMBER_GETTER_BODY } else { ScopeKind.PROP_MEMBER_SETTER_BODY })
                    accessor.propDecl = ret
                    if (accessorName == "get") {
                        accessor.isGetter = true
                        ret.getters.add(accessor)
                    } else {
                        accessor.isSetter = true
                        ret.setters.add(accessor)
                    }
                } else {
                    Next()
                }
                SkipNLOrSemi()
            }
            ret.rightCurlPos = Expect(TokenKind.RCURL, "expected '}' after property body").Begin()
            ret.end = ret.rightCurlPos + 1
        } else {
            ret.end = if (let Some(expr) <- ret.initializer) {
                expr.end
            } else if (let Some(ty) <- ret.typeNode) {
                ty.end
            } else {
                ret.identifier.End()
            }
        }
        return ret
    }

    public func ParseConstructor(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): FuncDecl {
        let ret = FuncDecl()
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.CONSTRUCTOR))
        let key = Expect(TokenKind.INIT, "expected 'init'")
        ret.keywordPos = key.Begin()
        ret.identifier = SrcIdentifier("init", "init", key.Begin(), key.End(), false)
        ret.EnableAttr(Attribute.CONSTRUCTOR)
        if (HasModifierToken(modifiers, TokenKind.CONST)) {
            ret.isConst = true
        }
        ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
        ret.funcBody = ParseFuncBody(scopeKind)
        if (let Some(body) <- ret.funcBody) { ret.end = body.end }
        return ret
    }

    public func ParseFinalizer(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): FuncDecl {
        let ret = FuncDecl()
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.FINALIZER))
        let tilde = Expect(TokenKind.BITNOT, "expected '~' before finalizer")
        let initTok = Expect(TokenKind.INIT, "expected 'init' after '~'")
        ret.keywordPos = initTok.Begin()
        ret.identifier = SrcIdentifier("~init", "~init", tilde.Begin(), initTok.End(), false)
        ret.EnableAttr(Attribute.FINALIZER)
        ret.begin = if (ret.begin.IsZero()) { tilde.Begin() } else { ret.begin }
        ret.funcBody = ParseFuncBody(scopeKind)
        if (let Some(body) <- ret.funcBody) {
            if (!body.paramLists.isEmpty() && !body.paramLists[0].params.isEmpty()) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    body.paramLists[0].begin,
                    "finalizer cannot accept parameters")
                ret.EnableAttr(Attribute.IS_BROKEN)
            }
            if (let Some(retType) <- body.retType) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    retType.begin,
                    "finalizer cannot declare a return type")
                ret.EnableAttr(Attribute.IS_BROKEN)
            }
            ret.end = body.end
        }
        return ret
    }

    public func ParsePrimaryConstructor(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): PrimaryCtorDecl {
        let ret = PrimaryCtorDecl()
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.PRIMARY_CONSTRUCTOR))
        let id = ExpectIdentifierWithPos(ret)
        ret.identifier = id
        ret.keywordPos = id.Begin()
        ret.begin = if (ret.begin.IsZero()) { id.Begin() } else { ret.begin }
        if (!curPrimaryDeclIdent.isEmpty() && id.Val() != curPrimaryDeclIdent) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.EXPECTED_IDENTIFIER,
                id.Begin(),
                "expected primary constructor name '${curPrimaryDeclIdent}'")
            ret.EnableAttr(Attribute.IS_BROKEN)
        }
        let bodyScope = if (ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY)) {
            ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT
        } else {
            ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS
        }
        ret.funcBody = ParseFuncBody(bodyScope)
        ret.EnableAttr(Attribute.CONSTRUCTOR)
        ret.EnableAttr(Attribute.PRIMARY_CONSTRUCTOR)
        if (ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY)) {
            ret.EnableAttr(Attribute.IN_STRUCT)
        } else {
            ret.EnableAttr(Attribute.IN_CLASSLIKE)
        }
        if (HasModifierToken(modifiers, TokenKind.CONST)) {
            ret.isConst = true
        }
        if (let Some(body) <- ret.funcBody) {
            if (let Some(retType) <- body.retType) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    retType.begin,
                    "primary constructor cannot declare a return type")
                ret.EnableAttr(Attribute.IS_BROKEN)
            }
            ret.end = body.end
        }
        return ret
    }

    private func EnableModifierAttrs(decl: Decl, attrs: ArrayList<Attribute>): Unit {
        for (attr in attrs) {
            decl.EnableAttr(attr)
        }
    }
}
