package cangjie_compiler::parse

import std.collection.*
import cangjie_compiler::ast.AddMacroAttr
import cangjie_compiler::ast.Identifier as AstIdentifier
import cangjie_compiler::ast.ScopeKind as AstScopeKind
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK}

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
        let expr = if (isTailClosure) { ParseLambdaExprWithTrailingClosure() } else { ParseLambdaExpr() }
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
        expr.identifier = AstIdentifier(
            expr.invocation.macroCallDiagInfo.identifier,
            expr.invocation.macroNamePos,
            expr.invocation.macroNamePos + expr.invocation.macroCallDiagInfo.identifier.size)
        expr.end = lastToken.End()
        return expr
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

    public func ParseMacroCallDeclInput(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Decl {
        let decl = MacroExpandDecl()
        ApplyModifiersAndAnnotations(decl, modifiers, annos)
        decl.begin = if (decl.begin.IsZero()) { Peek().Begin() } else { decl.begin }
        ParseMacroInvocation(scopeKind, modifiers, decl.invocation)
        if (!decl.invocation.hasParenthesis && decl.invocation.decl.isNone() &&
            (SeeingDeclInScope(scopeKind) || SeeingMacroCallDecl())) {
            ParseMacroCallArgsWithoutParen(scopeKind, modifiers, decl.invocation)
        }
        decl.identifier = SrcIdentifier(
            decl.invocation.macroCallDiagInfo.identifier,
            decl.invocation.macroCallDiagInfo.identifier,
            decl.invocation.macroNamePos,
            decl.invocation.macroNamePos + decl.invocation.macroCallDiagInfo.identifier.size,
            false)
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

        invocation.scopeKind = ToAstScopeKind(scopeKind)
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
            kind == ASTKind.MACRO_EXPAND_DECL || kind == ASTKind.FUNC_PARAM || kind == ASTKind.MACRO_EXPAND_PARAM
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

    public func ParseNodes(scope: ScopeKind, currentMacroCall: Node): ArrayList<Node> {
        currentFile = currentMacroCall.curFile
        curMacroCall = currentMacroCall
        let invocation = currentMacroCall.GetConstInvocation()
        CJC_NULLPTR_CHECK(invocation)
        let out = ArrayList<Node>()
        while (!Seeing(TokenKind.END)) {
            let node = if (ScopeKindEquals(scope, ScopeKind.FUNC_BODY)) {
                ParseExprOrDecl(scope)
            } else {
                ParseDecl(scope)
            }
            node.curFile = currentFile
            node.curMacroCall = curMacroCall
            AddMacroAttr(node)
            out.add(node)
            SkipNLOrSemi()
        }
        AttachCommentToNodes(out)
        return out
    }
}
