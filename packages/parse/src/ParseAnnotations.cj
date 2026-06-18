package cangjie_compiler::parse

import cangjie_compiler::utils.{StringToOverflowStrategy, StrToLower}
import std.collection.*

extend ParserImpl {
    public func SeeingBuiltinAnnotation(): Bool {
        if (!Seeing(TokenKind.AT)) {
            return false
        }
        let ahead = lexer.LookAheadSkipNL(1)
        if (ahead.isEmpty()) {
            return false
        }
        return ahead[0].kind == TokenKind.IDENTIFIER && IsBuiltinAnnotation(moduleName, ahead[0].Value())
    }

    public func SeeingAnnotationLambdaExpr(): Bool {
        return Seeing([TokenKind.AT, TokenKind.IDENTIFIER, TokenKind.LCURL]) && SeeingBuiltinAnnotation()
    }

    public func ParseAnnotations(annos: ArrayList<Annotation>): Unit {
        while (SeeingBuiltinAnnotation() || (enableCustomAnno && SeeingMacroCallDecl())) {
            let annotation = ParseAnnotation()
            for (anno in annos) {
                if (anno.kind != AnnotationKind.CUSTOM && anno.identifier.Val() == annotation.identifier.Val()) {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.INVALID_ANNOTATION,
                        annotation.begin,
                        "duplicated annotation '${annotation.identifier.Val()}'")
                    annotation.isBroken = true
                    break
                }
            }
            annos.add(annotation)
            SkipNLOrSemi()
        }
    }

    public func ParseAnnotation(): Annotation {
        if (enableCustomAnno && SeeingMacroCallDecl()) {
            return ParseCustomAnnotation()
        }
        let anno = Annotation()
        let atToken = Peek()
        if (!Skip(TokenKind.AT)) {
            diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, atToken.Begin(), "expected annotation")
            anno.isBroken = true
            return anno
        }
        anno.begin = atToken.Begin()
        anno.identifier = ExpectIdentifierWithPos(anno)
        anno.kind = NameToAnnotationKind(anno.identifier.Val())
        if (anno.kind == AnnotationKind.ATTRIBUTE) {
            ParseAttributeAnnotation(anno)
        } else if (anno.kind == AnnotationKind.NUMERIC_OVERFLOW) {
            ParseOverflowAnnotation(anno)
        } else if (anno.kind == AnnotationKind.WHEN) {
            ParseWhenAnnotation(anno)
        } else {
            ParseAnnotationArguments(anno)
            if (anno.kind == AnnotationKind.DEPRECATED) {
                CheckDeprecatedAnnotation(anno)
            }
        }
        anno.end = if (!anno.rsquarePos.IsZero()) { anno.rsquarePos + 1 } else { anno.identifier.End() }
        return anno
    }

    public func ParseCustomAnnotation(): Annotation {
        let anno = Annotation()
        let atToken = Peek()
        if (!Skip(TokenKind.AT)) {
            if (Skip(TokenKind.AT_EXCL)) {
                anno.isCompileTimeVisible = true
            } else {
                diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, atToken.Begin(), "expected annotation")
                anno.isBroken = true
                return anno
            }
        }
        anno.begin = atToken.Begin()
        var baseExpr: Expr = RefExpr(ExpectIdentifierWithPos(anno))
        while (Skip(TokenKind.DOT)) {
            let member = MemberAccess()
            member.baseExpr = baseExpr
            member.dotPos = lastToken.Begin()
            member.field = ExpectIdentifierWithPos(member)
            member.begin = baseExpr.begin
            member.end = member.field.End()
            baseExpr = member
        }
        anno.baseExpr = baseExpr
        let annotationName = baseExpr.ToString()
        anno.identifier = SrcIdentifier(annotationName, annotationName, baseExpr.begin, baseExpr.end, false)
        anno.kind = AnnotationKind.CUSTOM
        ParseAnnotationArguments(anno)
        anno.end = if (!anno.rsquarePos.IsZero()) { anno.rsquarePos + 1 } else { anno.identifier.End() }
        return anno
    }

    public func ParseAnnotationArguments(anno: Annotation): Unit {
        if (!Skip(TokenKind.LSQUARE)) {
            return
        }
        let pos = lastToken.Begin()
        anno.lsquarePos = pos
        while (true) {
            if (Seeing(TokenKind.END)) {
                diag.DiagnoseRefactor(DiagKindRefactor.UNTERMINATED_DELIMITER, pos, "expected ']' after annotation arguments")
                anno.isBroken = true
                break
            }
            if (Skip(TokenKind.RSQUARE)) {
                anno.rsquarePos = lastToken.Begin()
                break
            }
            let arg = ParseAnnotationArgument()
            if (Skip(TokenKind.COMMA)) {
                arg.commaPos = lastToken.Begin()
                if (Seeing(TokenKind.RSQUARE)) {
                    diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_IDENTIFIER, lastToken.Begin(), "expected annotation argument")
                }
            } else if (!Seeing(TokenKind.RSQUARE)) {
                diag.DiagnoseRefactor(DiagKindRefactor.UNTERMINATED_DELIMITER, pos, "expected ']' after annotation arguments")
                anno.isBroken = true
            }
            anno.args.add(arg)
        }
    }

    public func ParseAnnotationArgument(): FuncArg {
        let arg = FuncArg()
        let start = Peek()
        if (Seeing(TokenKind.IDENTIFIER) && lexer.LookAheadSkipNL(1).size > 0 && lexer.LookAheadSkipNL(1)[0].kind == TokenKind.COLON) {
            arg.name = ParseIdentifierFromToken(start)
            Next()
            arg.colonPos = Expect(TokenKind.COLON, "expected ':' after annotation argument name").Begin()
        }
        arg.expr = ParseExpr(ExprKind.EXPR_IN_ANNOTATION)
        arg.begin = start.Begin()
        MarkEndFromLast(arg)
        return arg
    }

    public func ParseAttributeAnnotation(anno: Annotation): Unit {
        if (!Skip(TokenKind.LSQUARE)) {
            return
        }
        let pos = lastToken.Begin()
        anno.lsquarePos = pos
        while (true) {
            if (Seeing(TokenKind.IDENTIFIER) || Seeing(TokenKind.STRING_LITERAL) || IsContextualKeyword(Peek().Value())) {
                anno.attrs.add(Peek())
                Next()
            }
            if (Skip(TokenKind.COMMA)) {
                anno.attrCommas.add(lastToken.Begin())
                continue
            }
            break
        }
        if (!Skip(TokenKind.RSQUARE)) {
            diag.DiagnoseRefactor(DiagKindRefactor.UNTERMINATED_DELIMITER, pos, "expected ']' after @Attribute")
            ConsumeUntil(TokenKind.NL)
            anno.isBroken = true
        } else {
            anno.rsquarePos = lastToken.Begin()
        }
    }

    public func ParseOverflowAnnotation(anno: Annotation): Unit {
        if (Skip(TokenKind.LSQUARE)) {
            let pos = lastToken.Begin()
            anno.lsquarePos = pos
            if (Seeing(TokenKind.IDENTIFIER)) {
                anno.overflowStrategy = StringToOverflowStrategy(StrToLower(Peek().Value()))
                Next()
            }
            if (!Skip(TokenKind.RSQUARE)) {
                diag.DiagnoseRefactor(DiagKindRefactor.UNTERMINATED_DELIMITER, pos, "expected ']' after overflow annotation")
                ConsumeUntil(TokenKind.NL)
                anno.isBroken = true
            } else {
                anno.rsquarePos = lastToken.Begin()
            }
            return
        }
        let name = anno.identifier.Val()
        let prefix = "Overflow"
        if (name.size > prefix.size) {
            anno.overflowStrategy = StringToOverflowStrategy(StrToLower(name[prefix.size..]))
        }
    }

    public func ParseWhenAnnotation(anno: Annotation): Unit {
        if (!Skip(TokenKind.LSQUARE)) {
            anno.isBroken = true
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, anno.begin, "when annotation must have condition")
            return
        }
        let pos = lastToken.Begin()
        anno.lsquarePos = pos
        anno.condExpr = ParseExpr()
        if (!Skip(TokenKind.RSQUARE)) {
            diag.DiagnoseRefactor(DiagKindRefactor.UNTERMINATED_DELIMITER, pos, "expected ']' after @When condition")
            ConsumeUntil(TokenKind.NL)
            anno.isBroken = true
        } else {
            anno.rsquarePos = lastToken.Begin()
        }
    }

    public func CheckDeprecatedAnnotation(anno: Annotation): Unit {
        var messageFound = false
        var sinceFound = false
        var strictFound = false
        for (arg in anno.args) {
            if (let Some(expr) <- arg.expr) {
                if (let Some(lit) <- (expr as LitConstExpr)) {
                    let name = arg.name.Val()
                    if (name.isEmpty() || name == "message") {
                        ValidateDeprecatedAnnotationArgument(anno, lit, "message", LitConstKind.STRING, messageFound)
                        messageFound = true
                    } else if (name == "since") {
                        ValidateDeprecatedAnnotationArgument(anno, lit, "since", LitConstKind.STRING, sinceFound)
                        sinceFound = true
                    } else if (name == "strict") {
                        ValidateDeprecatedAnnotationArgument(anno, lit, "strict", LitConstKind.BOOL, strictFound)
                        strictFound = true
                    } else {
                        diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, arg.begin, "unknown @Deprecated argument '${name}'")
                        anno.isBroken = true
                    }
                } else {
                    diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, arg.begin, "@Deprecated argument must be a literal")
                    anno.isBroken = true
                }
            }
        }
    }

    private func ValidateDeprecatedAnnotationArgument(
        anno: Annotation,
        lit: LitConstExpr,
        name: String,
        expectedKind: LitConstKind,
        alreadyFound: Bool
    ): Unit {
        if (alreadyFound) {
            diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, lit.begin, "duplicated @Deprecated argument '${name}'")
            anno.isBroken = true
        }
        if (lit.stringValue.isEmpty()) {
            diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, lit.begin, "@Deprecated argument '${name}' cannot be empty")
            anno.isBroken = true
        } else if (lit.kind != expectedKind) {
            let expected = if (expectedKind == LitConstKind.STRING) { "String" } else { "Bool" }
            diag.DiagnoseRefactor(
                DiagKindRefactor.INVALID_ANNOTATION,
                lit.begin,
                "@Deprecated argument '${name}' must be ${expected}")
            anno.isBroken = true
        }
    }
}
