package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
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
        let canStart = kind == TokenKind.IDENTIFIER || kind == TokenKind.PUBLIC || kind == TokenKind.PROTECTED ||
            kind == TokenKind.INTERNAL || kind == TokenKind.PRIVATE || kind == TokenKind.STATIC ||
            kind == TokenKind.ABSTRACT || kind == TokenKind.OPEN
        if (!canStart) {
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
        expr.end = lastToken.End()
        return expr
    }

    public func ParseMacroCallDeclInput(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Decl {
        let decl = MacroExpandDecl()
        ApplyModifiersAndAnnotations(decl, modifiers, annos)
        decl.begin = if (decl.begin.IsZero()) { Peek().Begin() } else { decl.begin }
        ParseMacroInvocation(scopeKind, modifiers, decl.invocation)
        decl.end = lastToken.End()
        return decl
    }

    public func ParseMacroInvocation(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, invocation: MacroInvocation): Unit {
        if (Skip(TokenKind.AT) || Skip(TokenKind.AT_EXCL)) {
            invocation.attrs.add(lastToken)
        }
        let id = ExpectIdentifierWithPos(Node())
        invocation.identifier = id
        if (Skip(TokenKind.LSQUARE)) {
            ParseMacroCallTokens(TokenKind.LSQUARE, TokenKind.RSQUARE, invocation.tokens, true)
        } else if (Skip(TokenKind.LPAREN)) {
            ParseMacroCallTokens(TokenKind.LPAREN, TokenKind.RPAREN, invocation.tokens, false)
        } else if (Seeing(TokenKind.LCURL)) {
            ParseMacroCallTokens(TokenKind.LCURL, TokenKind.RCURL, invocation.tokens, false)
        }
    }

    public func ParseMacroCallTokens(left: TokenKind, right: TokenKind, tokens: ArrayList<Token>, isAttr: Bool): Bool {
        var depth: Int64 = 1
        while (!Seeing(TokenKind.END) && depth > 0) {
            let token = Peek()
            Next()
            if (token.kind == left) { depth++ }
            if (token.kind == right) {
                depth--
                if (depth == 0) { break }
            }
            tokens.add(token)
        }
        return depth == 0
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
