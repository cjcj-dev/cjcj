package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func ParseTopLvlFeatures(annos: ArrayList<Annotation>): FeaturesDirective {
        let directive = FeaturesDirective()
        let token = Expect(TokenKind.FEATURES, "expected 'features'")
        directive.featuresPos = token.Begin()
        directive.begin = token.Begin()
        ParseFeatureDirective(directive)
        directive.end = lastToken.End()
        SkipNLOrSemi()
        return directive
    }

    public func ParseFeatureDirective(features: FeaturesDirective): Unit {
        let set = FeaturesSet()
        if (Skip(TokenKind.LPAREN)) {
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
                ParseFeatureId(set)
                if (!Skip(TokenKind.COMMA)) { break }
            }
            Expect(TokenKind.RPAREN, "expected ')' after features")
        } else {
            ParseFeatureId(set)
        }
        features.featureSets.add(set)
    }

    public func ParseFeatureId(features: FeaturesSet): Unit {
        let id = ExpectIdentifierWithPos(features)
        features.features.add(FeatureId(id))
    }
}
