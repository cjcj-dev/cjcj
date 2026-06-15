package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func IsIdentifierOrContextualKeyword(kind: TokenKind): Bool {
        return kind == TokenKind.IDENTIFIER || kind == TokenKind.PACKAGE_IDENTIFIER
    }

    public func SeeingIdentifierLike(): Bool {
        return Seeing(TokenKind.IDENTIFIER) || Seeing(TokenKind.PACKAGE_IDENTIFIER) ||
            Seeing(TokenKind.INIT) || Seeing(TokenKind.THIS) || Seeing(TokenKind.SUPER)
    }

    public func ParseIdentifierFromToken(token: Token): SrcIdentifier {
        let raw = token.Value()
        var value = raw
        var isRaw = false
        if (raw.size >= 2 && raw[0] == b'`' && raw[raw.size - 1] == b'`') {
            value = raw[1..(raw.size - 1)]
            isRaw = true
        }
        return SrcIdentifier(value, raw, token.Begin(), token.End(), isRaw)
    }

    public func ExpectIdentifierWithPos(node: Node): SrcIdentifier {
        let token = Peek()
        if (SeeingIdentifierLike()) {
            Next()
            return ParseIdentifierFromToken(token)
        }
        node.isBroken = true
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_IDENTIFIER, token.Begin(), "expected identifier")
        return SrcIdentifier("", "", token.Begin(), token.Begin(), false)
    }

    public func ParseOptionalGeneric(): Option<Generic> {
        if (!Seeing(TokenKind.LT)) {
            return None
        }
        let generic = Generic()
        generic.leftAnglePos = Peek().Begin()
        Next()
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.GT)) {
            let param = GenericParamDecl()
            param.identifier = ExpectIdentifierWithPos(param)
            param.begin = param.identifier.Begin()
            param.end = param.identifier.End()
            generic.typeParameters.add(param)
            if (!Skip(TokenKind.COMMA)) {
                break
            }
        }
        generic.rightAnglePos = Expect(TokenKind.GT, "expected '>' after generic parameters").Begin()
        generic.begin = generic.leftAnglePos
        generic.end = generic.rightAnglePos + 1
        return generic
    }

    public func ParseGenericConstraints(): ArrayList<GenericConstraint> {
        let out = ArrayList<GenericConstraint>()
        while (Skip(TokenKind.WHERE)) {
            let constraint = GenericConstraint()
            constraint.wherePos = lastToken.Begin()
            let refTy = ParseRefType(true)
            constraint.refType = refTy
            if (Skip(TokenKind.UPPERBOUND) || Skip(TokenKind.COLON)) {
                constraint.upperBounds.add(ParseType())
                while (Skip(TokenKind.BITAND)) {
                    constraint.upperBounds.add(ParseType())
                }
            }
            constraint.begin = constraint.wherePos
            constraint.end = if (!constraint.upperBounds.isEmpty()) { constraint.upperBounds[constraint.upperBounds.size - 1].end } else { refTy.end }
            out.add(constraint)
        }
        return out
    }

    public func ApplyModifiersAndAnnotations(decl: Decl, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Unit {
        decl.AddCommon(modifiers, annos)
        if (!modifiers.isEmpty()) {
            decl.begin = modifiers[0].begin
        }
        if (!annos.isEmpty() && (decl.begin.IsZero() || annos[0].begin < decl.begin)) {
            decl.begin = annos[0].begin
        }
    }

    public func AtTerminator(): Bool {
        return Seeing(TokenKind.END) || Seeing(TokenKind.RCURL) || Seeing(TokenKind.RPAREN) ||
            Seeing(TokenKind.RSQUARE) || Seeing(TokenKind.COMMA) || Seeing(TokenKind.SEMI) || Seeing(TokenKind.NL)
    }

    public func MarkEndFromLast(node: Node): Unit {
        if (!lastToken.End().IsZero()) {
            node.end = lastToken.End()
        } else {
            node.end = node.begin
        }
    }

    public func FinalizeDeclTree(decl: Decl): Unit {
        FFIParserImpl(this).CheckInteropDecl(decl)
        MPParserImpl(this).CheckCJMPDecl(decl)
    }
}

public func LevenshteinDistance(source: String, target: String): UInt64 {
    let s = source.toArray()
    let t = target.toArray()
    var prev = ArrayList<UInt64>()
    var cur = ArrayList<UInt64>()
    var j: Int64 = 0
    while (j <= t.size) {
        prev.add(UInt64(j))
        cur.add(0)
        j++
    }
    var i: Int64 = 1
    while (i <= s.size) {
        cur[0] = UInt64(i)
        j = 1
        while (j <= t.size) {
            let cost: UInt64 = if (s[i - 1] == t[j - 1]) { 0 } else { 1 }
            let del = prev[j] + 1
            let ins = cur[j - 1] + 1
            let sub = prev[j - 1] + cost
            var best = if (del < ins) { del } else { ins }
            if (sub < best) { best = sub }
            cur[j] = best
            j++
        }
        j = 0
        while (j <= t.size) {
            prev[j] = cur[j]
            j++
        }
        i++
    }
    return prev[t.size]
}
