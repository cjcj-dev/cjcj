package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func SeeingBuiltinAnnotation(): Bool {
        if (!Seeing(TokenKind.AT) && !Seeing(TokenKind.AT_EXCL)) {
            return false
        }
        let ahead = lexer.LookAheadSkipNL(1)
        if (ahead.isEmpty()) {
            return false
        }
        return ahead[0].kind == TokenKind.IDENTIFIER && NameToAnnotationKind(ahead[0].Value()) != AnnotationKind.CUSTOM
    }

    public func SeeingAnnotationLambdaExpr(): Bool {
        return (Seeing([TokenKind.AT, TokenKind.IDENTIFIER, TokenKind.LCURL]) ||
            Seeing([TokenKind.AT_EXCL, TokenKind.IDENTIFIER, TokenKind.LCURL])) && SeeingBuiltinAnnotation()
    }

    public func ParseAnnotations(annos: ArrayList<Annotation>): Unit {
        while (Seeing(TokenKind.AT) || Seeing(TokenKind.AT_EXCL)) {
            annos.add(ParseAnnotation())
            SkipNLOrSemi()
        }
    }

    public func ParseAnnotation(): Annotation {
        let anno = Annotation()
        let atToken = Peek()
        if (!Skip(TokenKind.AT) && !Skip(TokenKind.AT_EXCL)) {
            diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, atToken.Begin(), "expected annotation")
            anno.isBroken = true
            return anno
        }
        anno.atPos = atToken.Begin()
        anno.begin = atToken.Begin()
        anno.identifier = ExpectIdentifierWithPos(anno)
        anno.kind = NameToAnnotationKind(anno.identifier.Val())
        if (Skip(TokenKind.LPAREN)) {
            anno.leftParenPos = lastToken.Begin()
            ParseAnnotationArguments(anno)
            anno.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after annotation arguments").Begin()
        }
        anno.end = if (!anno.rightParenPos.IsZero()) { anno.rightParenPos + 1 } else { anno.identifier.End() }
        return anno
    }

    public func ParseCustomAnnotation(): Annotation {
        let anno = ParseAnnotation()
        anno.kind = AnnotationKind.CUSTOM
        return anno
    }

    public func ParseAnnotationArguments(anno: Annotation): Unit {
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
            let arg = ParseAnnotationArgument()
            anno.args.add(arg)
            if (!Skip(TokenKind.COMMA)) {
                break
            }
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
}
