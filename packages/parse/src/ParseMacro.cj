package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    private func IsMacroIdentifierStart(kind: TokenKind): Bool {
        let idx = TokenKindIndex(kind)
        return kind == TokenKind.IDENTIFIER ||
            (idx >= TokenKindIndex(TokenKind.PUBLIC) && idx <= TokenKindIndex(TokenKind.OPEN))
    }

    private func IsBuiltinMacro(identifier: String): Bool {
        return identifier == "sourcePackage" || identifier == "sourceFile" || identifier == "sourceLine"
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
        let expr = if (isTailClosure) { ParseLambdaExprWithTrailingClosure() } else { ParseLambdaExpr() }
        for (anno in annos) { expr.annotations.add(anno) }
        if (!annos.isEmpty()) {
            expr.begin = annos[0].begin
        }
        return expr
    }

    public func ParseMacroExprOrLambdaExpr(): Expr {
        if (SeeingAnnotationLambdaExpr()) {
            return ParseAnnotationLambdaExpr()
        }
        if (SeeingBuiltinAnnotation()) {
            let token = Peek()
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, token.Begin(), "expected lambda expression after builtin annotation")
            Next()
            return InvalidExpr(token.Begin())
        }
        if (!SeeingMacroCall()) {
            let token = Peek()
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, token.Begin(), "expected macro call")
            Next()
            return InvalidExpr(token.Begin())
        }
        let expr = MacroExpandExpr()
        expr.begin = Peek().Begin()
        ParseMacroInvocation(ScopeKind.FUNC_BODY, ArrayList<Modifier>(), expr.invocation)
        expr.identifier = expr.invocation.identifier
        expr.end = lastToken.End()
        return expr
    }

    public func ParseMacroCallDeclInput(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Decl {
        let decl = MacroExpandDecl()
        ApplyModifiersAndAnnotations(decl, modifiers, annos)
        decl.begin = if (decl.begin.IsZero()) { Peek().Begin() } else { decl.begin }
        ParseMacroInvocation(scopeKind, modifiers, decl.invocation)
        if (!decl.invocation.hasParenthesis && decl.invocation.decl.isNone() &&
            (SeeingDeclInScope(scopeKind) || SeeingMacroCallDecl())) {
            ParseMacroCallArgsWithoutParen(scopeKind, modifiers, decl.invocation)
        }
        decl.identifier = decl.invocation.identifier
        decl.end = if (let Some(inputDecl) <- decl.invocation.decl) { inputDecl.end } else { lastToken.End() }
        return decl
    }

    public func ParseMacroInvocation(scopeKind: ScopeKind, _: ArrayList<Modifier>, invocation: MacroInvocation): Unit {
        if (!ParseMacroCallIdentifier(invocation, Node())) {
            invocation.macroCallDiagInfo.macroCallEnd = lastToken.End()
            return
        }

        if (Skip(TokenKind.LSQUARE)) {
            if (IsBuiltinMacro(invocation.macroCallDiagInfo.identifier)) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.INVALID_ANNOTATION,
                    lastToken.Begin(),
                    "builtin macro call cannot have attribute arguments")
            }
            invocation.hasAttr = true
            ParseMacroCallAttr(invocation)
        }

        invocation.scopeKind = scopeKind
        if (Skip(TokenKind.LPAREN)) {
            ParseMacroCallArgsWithParen(invocation)
        } else if (Seeing(TokenKind.LCURL)) {
            Skip(TokenKind.LCURL)
            invocation.leftParenPos = lastToken.Begin()
            ParseMacroCallTokens(TokenKind.LCURL, TokenKind.RCURL, invocation.args, false)
            invocation.rightParenPos = Expect(TokenKind.RCURL, "expected '}' after macro call input").Begin()
            invocation.hasParenthesis = true
            SyncMacroArgTokens(invocation)
        } else {
            invocation.hasParenthesis = false
        }
        if (!curPrimaryDeclIdent.isEmpty()) {
            invocation.outerDeclIdent = curPrimaryDeclIdent
        }
        PopulateMacroOriginPositions(invocation)
        invocation.macroCallDiagInfo.macroCallEnd = lastToken.End()
    }

    private func ParseMacroCallArgsWithoutParen(
        scopeKind: ScopeKind,
        modifiers: ArrayList<Modifier>,
        invocation: MacroInvocation
    ): Unit {
        let beginToken = Peek()
        let collectStarted = lexer.StartCollectTokens()
        let parsedDecl = ParseDecl(scopeKind, modifiers, ArrayList<Annotation>())
        lexer.StopCollectTokens(collectStarted)
        if (IsValidMacroInputDeclKind(parsedDecl.astKind)) {
            ParseNodeToTokens(parsedDecl, beginToken, invocation.args)
            SyncMacroArgTokens(invocation)
            invocation.decl = parsedDecl
            invocation.hasParenthesis = false
            invocation.macroCallDiagInfo.macroCallEnd = parsedDecl.end
            PopulateMacroOriginPositions(invocation)
            return
        }
        diag.DiagnoseRefactor(
            DiagKindRefactor.EXPECTED_TOKEN,
            parsedDecl.begin,
            "illegal macro input without parentheses")
    }

    private func IsValidMacroInputDeclKind(kind: ASTKind): Bool {
        return kind == ASTKind.FUNC_DECL || kind == ASTKind.STRUCT_DECL || kind == ASTKind.CLASS_DECL ||
            kind == ASTKind.MAIN_DECL || kind == ASTKind.VAR_DECL || kind == ASTKind.ENUM_DECL ||
            kind == ASTKind.INTERFACE_DECL || kind == ASTKind.EXTEND_DECL || kind == ASTKind.PROP_DECL ||
            kind == ASTKind.PRIMARY_CTOR_DECL || kind == ASTKind.VAR_WITH_PATTERN_DECL ||
            kind == ASTKind.MACRO_EXPAND_DECL || kind == ASTKind.FUNC_PARAM
    }

    private func ParseNodeToTokens(node: Node, beginToken: Token, tokens: ArrayList<Token>): Unit {
        tokens.add(beginToken)
        let collectedTokens = lexer.GetCollectTokens()
        for (token in collectedTokens) {
            if (token.Begin() == beginToken.Begin()) {
                continue
            }
            if (!node.end.IsZero() && (node.end < token.Begin() || token.Begin() == node.end)) {
                break
            }
            tokens.add(token)
            if (!node.end.IsZero() && token.End() == node.end) {
                break
            }
        }
        while (!tokens.isEmpty() &&
            (tokens[tokens.size - 1].kind == TokenKind.NL || tokens[tokens.size - 1].kind == TokenKind.END)) {
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

    private func ParseMacroCallIdentifier(invocation: MacroInvocation, node: Node): Bool {
        let atToken = Peek()
        if (!Skip(TokenKind.AT)) {
            if (Skip(TokenKind.AT_EXCL)) {
                invocation.isCompileTimeVisible = true
            } else {
                diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, atToken.Begin(), "expected '@' before macro call")
                node.isBroken = true
                return false
            }
        }
        invocation.atPos = atToken.Begin()
        invocation.macroCallDiagInfo.macroCallBegin = atToken.Begin()
        if (newlineSkipped) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.UNEXPECTED_TOKEN,
                atToken.Begin(),
                "unexpected newline between '@' and macro call name")
        }
        var currentPart = ExpectMacroIdentifierPart(node)
        if (currentPart.Empty()) {
            return false
        }
        invocation.macroCallDiagInfo.fullName = currentPart.Val()
        while (Skip(TokenKind.DOT)) {
            invocation.fullNameDotPos.add(lastToken.Begin())
            let nextPart = ExpectMacroIdentifierPart(node)
            if (nextPart.Empty()) {
                ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI], targetTokenConsumed: false)
                return false
            }
            invocation.macroCallDiagInfo.fullName += "." + nextPart.Val()
            currentPart = nextPart
        }
        invocation.identifier = currentPart
        invocation.macroNamePos = currentPart.Begin()
        invocation.macroCallDiagInfo.identifier = currentPart.Val()
        invocation.macroCallDiagInfo.identifierPos = currentPart.Begin()
        return true
    }

    private func ExpectMacroIdentifierPart(node: Node): SrcIdentifier {
        let token = Peek()
        if (IsMacroIdentifierStart(token.kind)) {
            Next()
            return ParseIdentifierFromToken(token)
        }
        node.isBroken = true
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_IDENTIFIER, token.Begin(), "expected macro call identifier")
        return SrcIdentifier("", "", token.Begin(), token.Begin(), false)
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
        let tokenPos = Peek().Begin()
        while (SeeingAny([TokenKind.LSQUARE, TokenKind.LPAREN, TokenKind.DOT])) {
            Next()
        }
        let message = if (isAttr) {
            "illegal macro attribute arguments"
        } else {
            "illegal macro input arguments"
        }
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, tokenPos, message)
        return false
    }

    private func SyncMacroArgTokens(invocation: MacroInvocation): Unit {
        invocation.tokens.clear()
        for (argToken in invocation.args) {
            invocation.tokens.add(argToken)
        }
    }

    private func PopulateMacroOriginPositions(invocation: MacroInvocation): Unit {
        for (attrToken in invocation.attrs) {
            invocation.macroCallDiagInfo.originPosMap.put(attrToken.Begin().Hash32(), attrToken.Begin())
        }
        for (argToken in invocation.args) {
            invocation.macroCallDiagInfo.originPosMap.put(argToken.Begin().Hash32(), argToken.Begin())
        }
    }

    public func ParseNodes(scope: ScopeKind, currentMacroCall: Node): ArrayList<Node> {
        let old = curMacroCall
        curMacroCall = currentMacroCall
        let out = ArrayList<Node>()
        while (!Seeing(TokenKind.END)) {
            if (scope == ScopeKind.FUNC_BODY) {
                out.add(ParseExprOrDecl(scope))
            } else {
                out.add(ParseDecl(scope))
            }
            SkipNLOrSemi()
        }
        curMacroCall = old
        return out
    }
}
