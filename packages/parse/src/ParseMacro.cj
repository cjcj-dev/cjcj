package cjcj::parse

import std.collection.*
import cjcj::ast.AddMacroAttr
import cjcj::ast.Identifier as AstIdentifier
import cjcj::ast.ScopeKind as AstScopeKind
import cjcj::ast.SortModifierByPos
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK}

private let G_EXPRS_CONNECTED_BY_COMMA_LIST: Array<ASTKind> = [
    ASTKind.ARRAY_LIT, ASTKind.TUPLE_LIT, ASTKind.FUNC_ARG
]

extend ParserImpl {
    private func IsMacroIdentifierStart(kind: TokenKind): Bool {
        let idx = TokenKindIndex(kind)
        return kind == TokenKind.IDENTIFIER ||
            (idx >= TokenKindIndex(TokenKind.PUBLIC) && idx <= TokenKindIndex(TokenKind.OPEN))
    }

    private func IsBuiltinMacro(identifier: String): Bool {
        return identifier == "sourcePackage" || identifier == "sourceFile" || identifier == "sourceLine"
    }

    public func SeeingParamInMacroCallExpr(): Bool {
        if (SeeingContextualKeyword() || Seeing(TokenKind.IDENTIFIER) || Seeing(TokenKind.WILDCARD)) {
            let tokens = lexer.LookAheadSkipNL(1)
            if (tokens[0].kind == TokenKind.COLON || tokens[0].kind == TokenKind.NOT) {
                return true
            }
        }
        return false
    }

    public func SeeingMacroCall(): Bool {
        if (!Seeing(TokenKind.AT)) {
            return false
        }
        return SeeingMacroCallIdentifier()
    }

    public func SeeingMacroCallDecl(): Bool {
        if (!Seeing(TokenKind.AT) && !Seeing(TokenKind.AT_EXCL)) {
            return false
        }
        return SeeingMacroCallIdentifier()
    }

    private func SeeingMacroCallIdentifier(): Bool {
        let ahead = lexer.LookAheadSkipNL(1)
        if (ahead.isEmpty()) {
            return false
        }
        let kind = ahead[0].kind
        if (!IsMacroIdentifierStart(kind)) {
            return false
        }
        if (Seeing(TokenKind.AT) && kind == TokenKind.IDENTIFIER && IsBuiltinAnnotation(moduleName, ahead[0].Value())) {
            return false
        }
        return true
    }

    public func ParseAnnotationLambdaExpr(): LambdaExpr {
        return ParseAnnotationLambdaExpr(false)
    }

    public func ParseAnnotationLambdaExpr(isTailClosure: Bool): LambdaExpr {
        let annos = ArrayList<Annotation>()
        ParseAnnotations(annos)
        // C++ ParseAtom.cpp:1427-1432 ParseAnnotationLambdaExpr.
        Next()
        let expr = if (isTailClosure) { ParseLambdaExprWithTrailingClosure() } else { ParseLambdaExpr() }
        for (anno in annos) {
            if (anno.kind == AnnotationKind.NUMERIC_OVERFLOW) {
                expr.EnableAttr(Attribute.NUMERIC_OVERFLOW)
                expr.overflowStrategy = anno.overflowStrategy
            } else if (anno.kind == AnnotationKind.ENSURE_PREPARED_TO_MOCK) {
                expr.EnableAttr(Attribute.MOCK_SUPPORTED)
            } else {
                DiagExpectedDeclaration(expr.begin, "lambda expression")
            }
        }
        SetBeginToAnnotationsBegin(expr, annos)
        return expr
    }

    public func ParseMacroExprOrLambdaExpr(): Expr {
        if (SeeingAnnotationLambdaExpr()) {
            return ParseAnnotationLambdaExpr()
        }
        if (SeeingBuiltinAnnotation()) {
            DiagExpectedExpression()
            return InvalidExpr(lastToken.End())
        }
        CJC_ASSERT(SeeingMacroCall())
        let expr = MacroExpandExpr()
        try (cs = ChainScope(this, expr)) {
            if (let Some(file) <- currentFile) {
                expr.curFile = file
                file.hasMacro = true
            }
            expr.begin = Peek().Begin()
            if (!ParseMacroCallIdentifier(expr.invocation, expr)) {
                expr.EnableAttr(Attribute.IS_BROKEN)
                expr.end = lastToken.End()
                return expr
            }
            expr.identifier = AstIdentifier(
                expr.invocation.macroCallDiagInfo.identifier,
                expr.invocation.macroCallDiagInfo.identifierPos,
                expr.invocation.macroCallDiagInfo.identifierPos + expr.invocation.macroCallDiagInfo.identifier.size)
            ParseMacroInvocation(ScopeKind.UNKNOWN_SCOPE, ArrayList<Modifier>(), expr.invocation)
            expr.end = if (let Some(inputDecl) <- expr.invocation.decl) { inputDecl.end } else { lastToken.End() }
        }
        return expr
    }

    public func ParseMacroCall(scopeKind: ScopeKind): MacroExpandParam {
        CJC_ASSERT(SeeingMacroCallDecl())
        let macroCall = MacroExpandParam()
        try (cs = ChainScope(this, macroCall)) {
            if (let Some(file) <- currentFile) {
                macroCall.curFile = file
                file.hasMacro = true
            }
            macroCall.begin = Peek().Begin()
            if (!ParseMacroCallIdentifier(macroCall.invocation, macroCall)) {
                macroCall.EnableAttr(Attribute.IS_BROKEN)
                macroCall.end = lastToken.End()
                return macroCall
            }
            macroCall.identifier = SrcIdentifier(
                macroCall.invocation.macroCallDiagInfo.identifier,
                macroCall.invocation.macroCallDiagInfo.identifier,
                macroCall.invocation.macroCallDiagInfo.identifierPos,
                macroCall.invocation.macroCallDiagInfo.identifierPos + macroCall.invocation.macroCallDiagInfo.identifier.size,
                false)
            ParseMacroInvocation(scopeKind, ArrayList<Modifier>(), macroCall.invocation)
            macroCall.end = if (let Some(inputDecl) <- macroCall.invocation.decl) { inputDecl.end } else { lastToken.End() }
            let inputIsEnumConstructor = if (let Some(inputDecl) <- macroCall.invocation.decl) {
                inputDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)
            } else {
                false
            }
            if (ScopeKindEquals(scopeKind, ScopeKind.ENUM_CONSTRUCTOR) &&
                (macroCall.invocation.hasParenthesis || inputIsEnumConstructor)) {
                macroCall.EnableAttr(Attribute.ENUM_CONSTRUCTOR)
            }
        }
        return macroCall
    }

    private func ToAstScopeKind(kind: ScopeKind): AstScopeKind {
        return match (kind) {
            case ScopeKind.TOPLEVEL => AstScopeKind.TOPLEVEL
            case ScopeKind.CLASS_BODY => AstScopeKind.CLASS_BODY
            case ScopeKind.INTERFACE_BODY => AstScopeKind.INTERFACE_BODY
            case ScopeKind.STRUCT_BODY => AstScopeKind.STRUCT_BODY
            case ScopeKind.EXTEND_BODY => AstScopeKind.EXTEND_BODY
            case ScopeKind.FUNC_BODY => AstScopeKind.FUNC_BODY
            case ScopeKind.MACRO_BODY => AstScopeKind.MACRO_BODY
            case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS => AstScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS
            case ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT => AstScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT
            case ScopeKind.PROP_MEMBER_SETTER_BODY => AstScopeKind.PROP_MEMBER_SETTER_BODY
            case ScopeKind.PROP_MEMBER_GETTER_BODY => AstScopeKind.PROP_MEMBER_GETTER_BODY
            case ScopeKind.ENUM_BODY => AstScopeKind.ENUM_BODY
            case ScopeKind.ENUM_CONSTRUCTOR => AstScopeKind.ENUM_CONSTRUCTOR
            case ScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM => AstScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM
            case ScopeKind.MAIN_BODY => AstScopeKind.MAIN_BODY
            case ScopeKind.UNKNOWN_SCOPE => AstScopeKind.UNKNOWN_SCOPE
        }
    }

    public func ParseMacroCall(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): MacroExpandDecl {
        let decl = MacroExpandDecl()
        try (cs = ChainScope(this, decl)) {
            if (let Some(file) <- currentFile) {
                decl.curFile = file
                file.hasMacro = true
            }
            decl.begin = Peek().Begin()
            if (!modifiers.isEmpty()) {
                let firstModifier = SortModifierByPos(modifiers)[0]
                DiagExpectNoModifierBefore(firstModifier, "macro call")
                decl.begin = firstModifier.begin
            }
            if (!ParseMacroCallIdentifier(decl.invocation, decl)) {
                decl.EnableAttr(Attribute.IS_BROKEN)
                decl.end = lastToken.End()
                return decl
            }
            decl.identifier = SrcIdentifier(
                decl.invocation.macroCallDiagInfo.identifier,
                decl.invocation.macroCallDiagInfo.identifier,
                decl.invocation.macroCallDiagInfo.identifierPos,
                decl.invocation.macroCallDiagInfo.identifierPos + decl.invocation.macroCallDiagInfo.identifier.size,
                false)
            if (!annos.isEmpty()) {
                for (anno in annos) {
                    decl.annotations.add(anno)
                }
                SetBeginToAnnotationsBegin(decl, decl.annotations)
            }
            ParseMacroInvocation(scopeKind, modifiers, decl.invocation)
            if (!decl.invocation.hasParenthesis && decl.invocation.decl.isNone() &&
                (SeeingDeclInScope(scopeKind) || SeeingMacroCallDecl())) {
                ParseMacroCallArgsWithoutParen(scopeKind, modifiers, decl.invocation)
            }
            if (let Some(innerDecl) <- decl.invocation.decl) {
                CheckAnnotationAnno(decl.annotations, innerDecl)
            }
            decl.end = if (let Some(inputDecl) <- decl.invocation.decl) { inputDecl.end } else { lastToken.End() }
            let inputIsEnumConstructor = if (let Some(inputDecl) <- decl.invocation.decl) {
                inputDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)
            } else {
                false
            }
            if (ScopeKindEquals(scopeKind, ScopeKind.ENUM_CONSTRUCTOR) &&
                (decl.invocation.hasParenthesis || inputIsEnumConstructor)) {
                decl.EnableAttr(Attribute.ENUM_CONSTRUCTOR)
            }
        }
        return decl
    }

    public func ParseMacroInvocation(
        scopeKind: ScopeKind,
        modifiers: ArrayList<Modifier>,
        invocation: MacroInvocation
    ): Unit {
        if (Skip(TokenKind.LSQUARE)) {
            if (IsBuiltinMacro(invocation.macroCallDiagInfo.identifier)) {
                ParseDiagnoseRefactor(
                    DiagKindRefactor.parse_macro_call_illegal_with_builtin,
                    lookahead,
                    invocation.macroCallDiagInfo.identifier).Emit()
            }
            invocation.hasAttr = true
            ParseMacroCallAttr(invocation)
        }

        invocation.scopeKind = Some(ToAstScopeKind(scopeKind))
        invocation.exprKind = None
        ParseMacroCallArg(scopeKind, modifiers, invocation)
        if (!curPrimaryDeclIdent.isEmpty()) {
            invocation.outerDeclIdent = curPrimaryDeclIdent
        }
        PopulateMacroOriginPositions(invocation)
        invocation.macroCallDiagInfo.macroCallEnd = lastToken.End()
    }

    private func ParseMacroCallArg(
        scopeKind: ScopeKind,
        modifiers: ArrayList<Modifier>,
        invocation: MacroInvocation
    ): Unit {
        if (Skip(TokenKind.LPAREN)) {
            ParseMacroCallArgsWithParen(invocation)
        } else {
            ParseMacroCallArgsWithoutParen(scopeKind, modifiers, invocation)
        }
    }

    private func ParseMacroCallArgsWithoutParen(
        scopeKind: ScopeKind,
        modifiers: ArrayList<Modifier>,
        invocation: MacroInvocation
    ): Unit {
        ParseMacroCallDeclInput(scopeKind, modifiers, invocation)
        invocation.hasParenthesis = false
    }

    private func ParseMacroCallDeclInput(
        scopeKind: ScopeKind,
        modifiers: ArrayList<Modifier>,
        invocation: MacroInvocation
    ): Unit {
        let beginToken = Peek()
        let collectStarted = lexer.StartCollectTokens()
        var parsedDecl: Decl = InvalidDecl(beginToken.Begin())
        if (invocation.isFuncParam || SeeingParamInMacroCallExpr() ||
            ScopeKindEquals(scopeKind, ScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM)) {
            let scope = if (ScopeKindEquals(scopeKind, ScopeKind.PRIMARY_CONSTRUCTOR_FUNC_PARAM)) {
                ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS
            } else {
                scopeKind
            }
            let parsedParam = ParseParamInParamList(scope, None, None)
            parsedDecl = parsedParam[0]
        } else {
            parsedDecl = ParseDecl(scopeKind, modifiers, ArrayList<Annotation>())
        }
        if (parsedDecl.TestAttr(Attribute.IS_BROKEN)) {
            chainedAST[chainedAST.size - 1].EnableAttr(Attribute.HAS_BROKEN)
        }
        lexer.StopCollectTokens(collectStarted)
        if (IsValidMacroInputDeclKind(parsedDecl.astKind) && parsedDecl.astKind != ASTKind.MACRO_DECL) {
            ParseNodeToTokens(parsedDecl, beginToken, invocation.args)
        } else {
            ParseDiagnoseRefactor(
                DiagKindRefactor.parse_illegal_macro_expand_input_args_without_paren, parsedDecl.begin).Emit()
        }
        invocation.decl = parsedDecl
    }

    private func IsValidMacroInputDeclKind(kind: ASTKind): Bool {
        return kind == ASTKind.FUNC_DECL || kind == ASTKind.STRUCT_DECL || kind == ASTKind.CLASS_DECL ||
            kind == ASTKind.MAIN_DECL || kind == ASTKind.VAR_DECL || kind == ASTKind.ENUM_DECL ||
            kind == ASTKind.INTERFACE_DECL || kind == ASTKind.EXTEND_DECL || kind == ASTKind.PROP_DECL ||
            kind == ASTKind.PRIMARY_CTOR_DECL || kind == ASTKind.VAR_WITH_PATTERN_DECL ||
            kind == ASTKind.MACRO_EXPAND_DECL || kind == ASTKind.FUNC_PARAM || kind == ASTKind.MACRO_EXPAND_PARAM
    }

    private func ParseNodeToTokens(node: Node, beginToken: Token, tokens: ArrayList<Token>): Unit {
        tokens.add(beginToken)
        let collectedTokens = lexer.GetCollectTokens()
        if (collectedTokens.isEmpty() || beginToken.End() == node.end) {
            return
        }
        var startIndex: Int64 = 0
        var endIndex: Int64 = collectedTokens.size
        var index: Int64 = 0
        while (index < collectedTokens.size) {
            let token = collectedTokens[index]
            if (token.Begin() == beginToken.Begin()) {
                startIndex = index
            }
            if (token.Begin() == node.end) {
                endIndex = index
                break
            }
            if (token.End() == node.end) {
                endIndex = index + 1
                break
            }
            index++
        }
        if (collectedTokens[startIndex].Begin() == beginToken.Begin()) {
            startIndex++
        }
        tokens.add(all: collectedTokens[startIndex..endIndex])
        if (tokens[tokens.size - 1].kind == TokenKind.NL || tokens[tokens.size - 1].kind == TokenKind.END) {
            tokens.remove(at: tokens.size - 1)
        }
    }

    public func ParseMacroCallTokens(left: TokenKind, right: TokenKind, tokens: ArrayList<Token>, isAttr: Bool): Bool {
        let oldSkipNL = skipNL
        skipNL = false
        var leftDepth: Int64 = 1
        while (!Seeing(TokenKind.END)) {
            if (Seeing(right)) {
                leftDepth--
                if (leftDepth == 0) {
                    break
                }
            }
            let token = Peek()
            if (token.kind == left) {
                leftDepth++
            }
            if (Seeing(TokenKind.ILLEGAL) && token.Value() == "\\") {
                if (!ParseMacroCallEscapeTokens(left, tokens, isAttr)) {
                    skipNL = oldSkipNL
                    return false
                }
            } else {
                tokens.add(token)
            }
            Next()
        }
        skipNL = oldSkipNL
        return true
    }

    public func ParseMacroCallIdentifier(invocation: MacroInvocation, node: Node): Bool {
        let atToken = Peek()
        if (!Skip(TokenKind.AT)) {
            Skip(TokenKind.AT_EXCL)
            invocation.isCompileTimeVisible = true
        }
        invocation.macroCallDiagInfo.fullName = Peek().Value()
        invocation.atPos = atToken.Begin()
        if (newlineSkipped) {
            ParseDiagnoseRefactor(
                DiagKindRefactor.parse_unexpected_newline_between_at_and_mc,
                atToken.Begin(),
                Peek().Value()).Emit()
        }
        var item = ParseIdentifierFromName(invocation.macroCallDiagInfo.fullName, lookahead.Begin(), lookahead.End(),
            invocation.macroCallDiagInfo.fullName.size)
        invocation.macroCallDiagInfo.identifierPos = item.Begin()
        Next()
        while (Skip(TokenKind.DOT)) {
            invocation.macroCallDiagInfo.fullName += "."
            invocation.fullNameDotPos.add(lastToken.Begin())
            item = ExpectIdentifierWithPos(node)
            if (item.Val() == INVALID_IDENTIFIER) {
                if (node.astKind == ASTKind.MACRO_EXPAND_EXPR) {
                    ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI])
                } else {
                    ConsumeUntilDecl()
                }
                return false
            }
            invocation.macroCallDiagInfo.fullName += item.Val()
        }
        invocation.macroNamePos = lastToken.Begin()
        invocation.macroCallDiagInfo.identifier = item.Val()
        return true
    }

    private func ParseMacroCallAttr(invocation: MacroInvocation): Unit {
        invocation.leftSquarePos = lastToken.Begin()
        if (ParseMacroCallTokens(TokenKind.LSQUARE, TokenKind.RSQUARE, invocation.attrs, true)) {
            invocation.rightSquarePos = Expect(TokenKind.RSQUARE, "expected ']' after macro call attributes").Begin()
        }
    }

    private func ParseMacroCallArgsWithParen(invocation: MacroInvocation): Unit {
        invocation.leftParenPos = lastToken.Begin()
        if (ParseMacroCallTokens(TokenKind.LPAREN, TokenKind.RPAREN, invocation.args, false)) {
            invocation.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after macro call input").Begin()
        }
        invocation.hasParenthesis = true
        SyncMacroArgTokens(invocation)
    }

    private func ParseMacroCallEscapeTokens(left: TokenKind, tokens: ArrayList<Token>, isAttr: Bool): Bool {
        let slashToken = Peek()
        Next()
        if ((Seeing(TokenKind.LSQUARE, TokenKind.RSQUARE) && left == TokenKind.LSQUARE) ||
            (Seeing(TokenKind.LPAREN, TokenKind.RPAREN) && left == TokenKind.LPAREN)) {
            let bracketToken = Peek()
            tokens.add(Token(bracketToken.kind, bracketToken.Value(), bracketToken.Begin(), bracketToken.End()))
            return true
        }
        if (Seeing(TokenKind.AT) && (left == TokenKind.LPAREN || left == TokenKind.LSQUARE)) {
            let atToken = Peek()
            tokens.add(Token(slashToken.kind, slashToken.Value(), slashToken.Begin(), slashToken.End()))
            tokens.add(Token(atToken.kind, atToken.Value(), atToken.Begin(), atToken.End()))
            return true
        }
        let token = Peek()
        while (SeeingAny([TokenKind.LSQUARE, TokenKind.LPAREN, TokenKind.DOT])) {
            Next()
        }
        let diagKind = if (isAttr) {
            DiagKindRefactor.parse_illegal_macro_expand_attr_args
        } else {
            DiagKindRefactor.parse_illegal_macro_expand_input_args
        }
        ParseDiagnoseRefactor(diagKind, token).Emit()
        return false
    }

    private func SyncMacroArgTokens(invocation: MacroInvocation): Unit {
        let _ = invocation
    }

    private func PopulateMacroOriginPositions(invocation: MacroInvocation): Unit {
        for (attrToken in invocation.attrs) {
            invocation.macroCallDiagInfo.originPosMap.put(attrToken.Begin().Hash32(), attrToken.Begin())
        }
        for (argToken in invocation.args) {
            invocation.macroCallDiagInfo.originPosMap.put(argToken.Begin().Hash32(), argToken.Begin())
            if (argToken.kind == TokenKind.STRING_LITERAL || argToken.kind == TokenKind.MULTILINE_STRING) {
                ParseInterplationString2OriginPosMap(argToken, invocation)
            }
        }
    }

    private func ParseInterplationString2OriginPosMap(strToken: Token, invocation: MacroInvocation): Unit {
        let basicDiag = BasicDiagnosticEngine()
        basicDiag.SetSourceManager(sourceManager)
        let lexerForString = Lexer([strToken], basicDiag, sourceManager)
        let strParts = lexerForString.GetStrParts(strToken)
        for (strPart in strParts) {
            if (strPart.strKind != StringPartKind.EXPR) {
                continue
            }
            CJC_ASSERT(strPart.begin != INVALID_POSITION)
            let lexerForExpr = Lexer(strPart.begin.fileID, strPart.value, basicDiag, sourceManager, strPart.begin)
            let tokens = lexerForExpr.GetTokens()
            CJC_ASSERT(!tokens.isEmpty())
            var index: Int64 = 2
            while (index < tokens.size - 1) {
                var token = tokens[index]
                if (token.kind != TokenKind.COMMENT) {
                    var begin = token.Begin()
                    begin.isCurFile = strToken.Begin().isCurFile
                    token.SetValuePos(token.Value(), begin, token.End())
                    invocation.macroCallDiagInfo.originPosMap.put(token.Begin().Hash32(), begin)
                }
                index++
            }
        }
    }

    public func ParseNodes(
        scope: ScopeKind,
        currentMacroCall: Node,
        modifiers!: ArrayList<Modifier> = ArrayList<Modifier>(),
        annos!: ArrayList<Annotation> = ArrayList<Annotation>()
    ): ArrayList<Node> {
        return ParseNodesImpl(Some(scope), None, currentMacroCall, modifiers, annos)
    }

    public func ParseNodes(
        scope: ExprKind,
        currentMacroCall: Node,
        modifiers!: ArrayList<Modifier> = ArrayList<Modifier>(),
        annos!: ArrayList<Annotation> = ArrayList<Annotation>()
    ): ArrayList<Node> {
        return ParseNodesImpl(None, Some(scope), currentMacroCall, modifiers, annos)
    }

    // Mirrors ParseMacro.cpp:57-125; split only to represent C++'s std::variant<ScopeKind, ExprKind>.
    private func ParseNodesImpl(
        scopeKind: Option<ScopeKind>,
        exprKind: Option<ExprKind>,
        currentMacroCall: Node,
        modifiers: ArrayList<Modifier>,
        annos: ArrayList<Annotation>
    ): ArrayList<Node> {
        currentFile = currentMacroCall.curFile
        curMacroCall = currentMacroCall
        let invocationOption = currentMacroCall.GetConstInvocation()
        CJC_NULLPTR_CHECK(invocationOption)
        let invocation = invocationOption.getOrThrow()
        var isConnectedByComma = false
        var isParamMacro = false
        var namedParameter: Option<FuncParam> = None
        var memberParam: Option<FuncParam> = None
        if (let Some(parent) <- invocation.parent) {
            if (G_EXPRS_CONNECTED_BY_COMMA_LIST.contains(parent.astKind)) {
                isConnectedByComma = true
            }
            if (parent.astKind == ASTKind.FUNC_PARAM_LIST) {
                isParamMacro = true
            }
        }
        let nodes = ArrayList<Node>()
        while (!Seeing(TokenKind.END) && !DetectPrematureEnd()) {
            let hasNode = !nodes.isEmpty()
            if (hasNode && isConnectedByComma && !Skip(TokenKind.COMMA)) {
                DiagExpectCharacter("','")
                break
            }
            if (isParamMacro) {
                isConnectedByComma = Skip(TokenKind.COMMA)
            }
            if (scopeKind.isSome() || hasNode) {
                let hasNLorSEMI = SkipNLOrSemi()
                if (hasNode && !isConnectedByComma && !hasNLorSEMI) {
                    DiagExpectSemiOrNewline()
                    break
                }
            }
            if (Seeing(TokenKind.END)) {
                break
            }
            var node: Node
            if (let Some(scope) <- scopeKind) {
                if (isParamMacro) {
                    let (param, nextNamedParameter, nextMemberParam) =
                        ParseParamInParamList(scope, namedParameter, memberParam)
                    node = param
                    namedParameter = nextNamedParameter
                    memberParam = nextMemberParam
                } else if (CheckIfSeeingDecl(scope)) {
                    node = if (nodes.isEmpty()) {
                        ParseDecl(scope, modifiers, annos)
                    } else {
                        ParseDecl(scope)
                    }
                } else {
                    node = ParseExpr()
                }
                if (let Some(ctor) <- (node as FuncDecl)) {
                    if (ctor.TestAttr(Attribute.CONSTRUCTOR)) {
                        CheckConstructorBody(ctor, scope, inMacro: true)
                    }
                }
            } else {
                if (let Some(parent) <- invocation.parent) {
                    if (let Some(funcArg) <- (parent as FuncArg)) {
                        if (Seeing(TokenKind.INOUT)) {
                            funcArg.withInout = true
                            Next()
                        }
                    }
                }
                node = ParseExpr(exprKind.getOrThrow())
            }
            node.curFile = currentFile
            node.curMacroCall = curMacroCall
            AddMacroAttr(node)
            nodes.add(node)
        }
        AttachCommentToNodes(nodes)
        return nodes
    }
}
