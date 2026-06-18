package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func ParseTopLvlFeatures(annos: ArrayList<Annotation>): FeaturesDirective {
        let directive = FeaturesDirective()
        let token = Expect(TokenKind.FEATURES, "expected 'features'")
        directive.featuresPos = token.Begin()
        directive.begin = token.Begin()
        directive.end = token.End()
        for (anno in annos) {
            if (anno.kind != AnnotationKind.NON_PRODUCT) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.INVALID_ANNOTATION,
                    anno.begin,
                    "unexpected annotation '${anno.identifier.Val()}' on features directive")
                directive.isBroken = true
            }
            directive.annotations.add(anno)
        }
        if (!directive.annotations.isEmpty()) {
            directive.begin = directive.annotations[0].begin
        }
        ParseFeatureDirective(directive)
        if (let Some(set) <- directive.featuresSet) {
            directive.end = set.end
        }
        SkipNLOrSemi()
        return directive
    }

    public func ParseFeatureDirective(features: FeaturesDirective): Unit {
        let set = FeaturesSet()
        features.featuresSet = set
        var isBroken = false
        if (!Skip(TokenKind.LCURL)) {
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, lastToken.End(), "expected '{' after features")
            isBroken = true
        } else {
            set.lCurlPos = lastToken.Begin()
            set.begin = lastToken.Begin()
        }
        ParseFeaturesSet(set)
        if (!Skip(TokenKind.RCURL)) {
            let pos = if (!set.lCurlPos.IsZero()) { set.lCurlPos } else { lastToken.End() }
            diag.DiagnoseRefactor(DiagKindRefactor.UNTERMINATED_DELIMITER, pos, "expected '}' after features")
            isBroken = true
        } else {
            set.rCurlPos = lastToken.Begin()
            set.end = lastToken.End()
        }
        if (isBroken) {
            features.isBroken = true
            set.isBroken = true
        }
    }

    public func ParseFeaturesSet(features: FeaturesSet): Unit {
        var isBroken = false
        while (!Seeing(TokenKind.END)) {
            if (Seeing(TokenKind.RCURL) || isBroken) {
                break
            }
            if (Seeing(TokenKind.IDENTIFIER)) {
                if (lastToken.kind == TokenKind.IDENTIFIER) {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.EXPECTED_TOKEN,
                        lastToken.End(),
                        "expected '.' or ',' in features directive")
                    ConsumeUntilAny([TokenKind.NL, TokenKind.COMMA, TokenKind.RCURL], targetTokenConsumed: false)
                    isBroken = true
                } else {
                    ParseFeatureId(features)
                }
                if (Skip(TokenKind.COMMA)) {
                    features.commaPoses.add(lastToken.Begin())
                }
            } else {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.EXPECTED_IDENTIFIER,
                    Peek().Begin(),
                    "expected feature identifier")
                ConsumeUntilAny([TokenKind.NL, TokenKind.COMMA, TokenKind.RCURL], targetTokenConsumed: false)
                isBroken = true
            }
        }
        features.end = lastToken.End()
        if (isBroken) {
            features.isBroken = true
        }
    }

    public func ParseFeatureId(features: FeaturesSet): Unit {
        let content = FeatureId()
        var first = true
        var isBroken = false
        while (Skip(TokenKind.IDENTIFIER) || Skip(TokenKind.DOT)) {
            let token = lastToken
            if (first) {
                content.begin = token.Begin()
                content.end = token.End()
                first = false
            }
            if (token.kind == TokenKind.IDENTIFIER) {
                let identifier = ParseIdentifierFromToken(token)
                content.identifiers.add(identifier)
                if (identifier.IsRaw()) {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.INVALID_ANNOTATION,
                        token.Begin(),
                        "raw identifier '${token.Value()}' is not allowed in features directive")
                    isBroken = true
                }
            } else {
                content.dotPoses.add(token.Begin())
            }
            content.end = token.End()
            if (Seeing(token.kind)) {
                isBroken = true
            }
            if (isBroken) {
                break
            }
        }
        if (lastToken.kind != TokenKind.IDENTIFIER) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.EXPECTED_IDENTIFIER,
                lastToken.Begin(),
                "expected identifier in features directive")
            isBroken = true
        }
        if (isBroken) {
            content.isBroken = true
        }
        if (!content.identifiers.isEmpty()) {
            features.content.add(content)
        }
    }
}
