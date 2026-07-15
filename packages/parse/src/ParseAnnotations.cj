package cjcj::parse

import cjcj::utils.{StringToOverflowStrategy, StrToLower}
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

    public func SeeingAtWhen(): Bool {
        if (!SeeingCombinator([TokenKind.AT, TokenKind.IDENTIFIER])) {
            return false
        }
        let tokens = lexer.LookAheadSkipNL(1)
        var token = tokens[0]
        token.SetValue("When")
        tokens[0] = token
        return true
    }

    public func SeeingAnnotationLambdaExpr(): Bool {
        return Seeing([TokenKind.AT, TokenKind.IDENTIFIER, TokenKind.LCURL]) && SeeingBuiltinAnnotation()
    }

    public func ParseAnnotations(annos: ArrayList<Annotation>): Unit {
        while (SeeingBuiltinAnnotation() || (enableCustomAnno && SeeingMacroCallDecl())) {
            let annotation = ParseAnnotation()
            for (anno in annos) {
                if (anno.kind != AnnotationKind.CUSTOM && anno.identifier.Val() == annotation.identifier.Val()) {
                    DiagDuplicatedAnno(annotation, anno)
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
            DiagExpectCharacter("'@'")
            anno.isBroken = true
            return anno
        }
        anno.begin = atToken.Begin()
        anno.identifier = ExpectIdentifierWithPos(anno)
        anno.kind = NameToAnnotationKind(anno.identifier.Val())
        try (cs = ChainScope(this, anno)) {
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
        }
        return anno
    }

    public func ParseCustomAnnotation(): Annotation {
        let anno = Annotation()
        let atToken = Peek()
        if (!Skip(TokenKind.AT)) {
            if (Skip(TokenKind.AT_EXCL)) {
                anno.isCompileTimeVisible = true
            } else {
                DiagExpectCharacter("'@'")
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
        var backArgsIsInvalid = false
        while (true) {
            if (Seeing(TokenKind.END)) {
                DiagExpectedRightDelimiter("[", pos)
                anno.isBroken = true
                break
            }
            if (Skip(TokenKind.RSQUARE)) {
                anno.rsquarePos = lastToken.Begin()
                break
            }
            let arg = ParseAnnotationArgument()
            backArgsIsInvalid = false
            if (let Some(expr) <- arg.expr) {
                backArgsIsInvalid = expr.astKind == ASTKind.INVALID_EXPR
            }
            if (Skip(TokenKind.COMMA)) {
                arg.commaPos = lastToken.Begin()
                if (Seeing(TokenKind.RSQUARE)) {
                    DiagExpectCharacter("identifier")
                }
            } else if (!Seeing(TokenKind.RSQUARE)) {
                if (backArgsIsInvalid) {
                    break
                }
                let builder = if (lookahead.kind == TokenKind.NL) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_right_delimiter, lastToken, "[")
                } else {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_right_delimiter, lastToken.End(), "[")
                }
                builder.AddMainHintArguments("]")
                builder.AddHint(pos, arguments: ["["])
                if (anno.kind == AnnotationKind.CUSTOM) {
                    builder.AddNote("Argument syntax error. May be caused by missing macro definitions. If not, verify the annotation arguments are valid.")
                }
                builder.Emit()
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
            DiagExpectedRightDelimiter("[", pos)
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
                DiagExpectedRightDelimiter("[", pos)
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
            DiagExpectedLsquareAfter(anno, "@When", "when annotation must have condition")
            return
        }
        let pos = lastToken.Begin()
        anno.lsquarePos = pos
        anno.condExpr = ParseExpr()
        if (let Some(expr) <- anno.condExpr) {
            if (expr.astKind != ASTKind.UNARY_EXPR && expr.astKind != ASTKind.BINARY_EXPR &&
                expr.astKind != ASTKind.REF_EXPR && !expr.isBroken) {
                DiagUnrecognizedExprInWhen(expr, anno)
                anno.isBroken = true
            }
        }
        if (!Skip(TokenKind.RSQUARE)) {
            DiagExpectedRightDelimiter("[", pos)
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
                        DiagDeprecatedUnknownArgument(arg, name)
                        anno.isBroken = true
                    }
                } else {
                    DiagDeprecatedArgumentNotLitConst(arg)
                    anno.isBroken = true
                    return
                }
            } else {
                DiagDeprecatedArgumentNotLitConst(arg)
                anno.isBroken = true
                return
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
            DiagDeprecatedArgumentDuplicated(lit, name)
            anno.isBroken = true
        }
        if (lit.stringValue.isEmpty()) {
            DiagDeprecatedEmptyStringArgument(lit, name)
            anno.isBroken = true
        } else if (lit.kind != expectedKind) {
            let expected = if (expectedKind == LitConstKind.STRING) { "String" } else { "Bool" }
            DiagDeprecatedWrongArgumentType(lit, name, expected)
            anno.isBroken = true
        }
    }
}
