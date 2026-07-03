package cangjie_compiler::parse

import std.collection.*
import cangjie_compiler::ast.OverloadableExpr as AstOverloadableExpr
import cangjie_compiler::ast.VisitAction
import cangjie_compiler::ast.Walker
import cangjie_compiler::option.IsUnsafeBackend as OptionIsUnsafeBackend

extend ParserImpl {
    public func SeeingCombinator(kinds: Array<TokenKind>): Bool {
        if (kinds.isEmpty() || !Seeing(kinds, skipNewline: false)) {
            return false
        }
        let ahead = lexer.LookAhead(kinds.size - 1)
        if (ahead.size + 1 < kinds.size) {
            return false
        }
        var previous = Peek()
        var index: Int64 = 1
        while (index < kinds.size) {
            let token = ahead[index - 1]
            if (token.kind != kinds[index]) {
                return false
            }
            if (token.Begin().line != previous.Begin().line || token.Begin().column != previous.Begin().column + 1) {
                return false
            }
            previous = token
            index++
        }
        return true
    }

    public func SeeingTokenAndCombinator(kind: TokenKind, cmb: Array<TokenKind>): Bool {
        if (!Seeing(kind) || cmb.isEmpty()) {
            return false
        }
        let ahead = lexer.LookAhead(cmb.size)
        if (ahead.size < cmb.size) {
            return false
        }
        var index: Int64 = 0
        while (index < cmb.size) {
            if (ahead[index].kind != cmb[index]) {
                return false
            }
            index++
        }
        index = 1
        while (index < cmb.size) {
            if (ahead[index].Begin().line != ahead[index - 1].Begin().line ||
                ahead[index].Begin().column != ahead[index - 1].Begin().column + 1) {
                return false
            }
            index++
        }
        return true
    }

    public func SkipCombinator(kinds: Array<TokenKind>): Bool {
        if (!SeeingCombinator(kinds)) {
            return false
        }
        var index: Int64 = 0
        while (index < kinds.size) {
            Next()
            index++
        }
        return true
    }

    public func SkipCombinedDoubleArrow(): Bool {
        if (!SeeingCombinator([TokenKind.ASSIGN, TokenKind.GT])) {
            return false
        }
        let begin = Peek().Begin()
        SkipCombinator([TokenKind.ASSIGN, TokenKind.GT])
        lastToken = Token(TokenKind.DOUBLE_ARROW, "=>", begin, begin + 2)
        return true
    }

    public func SkipCombinedBackarrow(): Bool {
        if (!SeeingCombinator([TokenKind.LT, TokenKind.SUB])) {
            return false
        }
        let begin = Peek().Begin()
        SkipCombinator([TokenKind.LT, TokenKind.SUB])
        lastToken = Token(TokenKind.BACKARROW, "<-", begin, begin + 2)
        return true
    }

    public func SeeingDoubleArrow(): Bool {
        return Seeing(TokenKind.DOUBLE_ARROW) || SeeingCombinator([TokenKind.ASSIGN, TokenKind.GT])
    }

    public func SeeingContextualKeyword(): Bool {
        for (kind in GetContextualKeyword()) {
            if (Seeing(kind)) {
                return true
            }
        }
        return false
    }

    public func SeeingKeywordAndOperater(): Bool {
        if (SeeingContextualKeyword()) {
            let ahead = lexer.LookAheadSkipNL(1)
            if (ahead.isEmpty()) {
                return false
            }
            let kind = ahead[0].kind
            if (kind == TokenKind.BITNOT || kind == TokenKind.AT) {
                return false
            }
            if (TokenKindIndex(kind) < TokenKindIndex(TokenKind.WILDCARD)) {
                return true
            }
        }
        return false
    }

    public func SeeingBackarrow(): Bool {
        return Seeing(TokenKind.BACKARROW) || SeeingCombinator([TokenKind.LT, TokenKind.SUB])
    }

    public func SkipDoubleArrow(): Bool {
        return Skip(TokenKind.DOUBLE_ARROW) || SkipCombinedDoubleArrow()
    }

    public func SkipBackarrow(): Bool {
        return Skip(TokenKind.BACKARROW) || SkipCombinedBackarrow()
    }

    public func LookupSeenCombinator(): Option<Token> {
        if (SeeingCombinator([TokenKind.GT, TokenKind.GT, TokenKind.ASSIGN])) {
            let begin = Peek().Begin()
            return Token(TokenKind.RSHIFT_ASSIGN, ">>=", begin, begin + 3)
        }
        if (SeeingCombinator([TokenKind.GT, TokenKind.GT])) {
            let begin = Peek().Begin()
            return Token(TokenKind.RSHIFT, ">>", begin, begin + 2)
        }
        if (SeeingCombinator([TokenKind.GT, TokenKind.ASSIGN])) {
            let begin = Peek().Begin()
            return Token(TokenKind.GE, ">=", begin, begin + 2)
        }
        if (SeeingCombinator([TokenKind.QUEST, TokenKind.QUEST])) {
            let begin = Peek().Begin()
            return Token(TokenKind.COALESCING, "??", begin, begin + 2)
        }
        return None
    }

    public func SkipAmbiguousToken(): Bool {
        if (let Some(token) <- LookupSeenCombinator()) {
            let consumed = match (token.kind) {
                case TokenKind.RSHIFT_ASSIGN => 3
                case _ => 2
            }
            var index: Int64 = 0
            while (index < consumed) {
                Next()
                index++
            }
            lastToken = token
            return true
        }
        return false
    }

    public func IsIdentifierOrContextualKeyword(kind: TokenKind): Bool {
        if (kind == TokenKind.IDENTIFIER) {
            return true
        }
        for (contextual in GetContextualKeyword()) {
            if (kind == contextual) {
                return true
            }
        }
        return false
    }

    public func IsPackageIdentifierOrContextualKeyword(kind: TokenKind): Bool {
        return kind == TokenKind.PACKAGE_IDENTIFIER || IsIdentifierOrContextualKeyword(kind)
    }

    public func SeeingIdentifierLike(): Bool {
        return IsIdentifierOrContextualKeyword(Peek().kind) ||
            Seeing(TokenKind.INIT) || Seeing(TokenKind.THIS) || Seeing(TokenKind.SUPER)
    }

    public func SeeingIdentifierAndTargetOp(tokenKinds: Array<TokenKind>): Bool {
        if (!IsIdentifierOrContextualKeyword(Peek().kind)) {
            return false
        }
        let ahead = lexer.LookAheadSkipNL(1)
        if (ahead.isEmpty()) {
            return false
        }
        for (kind in tokenKinds) {
            if (ahead[0].kind == kind) {
                return true
            }
        }
        return false
    }

    public func SeeingPrimaryIdentifier(): Bool {
        if (curPrimaryDeclIdent.isEmpty() || !SeeingIdentifierLike()) {
            return false
        }
        let distance = LevenshteinDistance(Peek().Value(), GetPrimaryDeclIdentRawValue())
        if (distance > 1u64) {
            return false
        }
        let ahead = lexer.LookAheadSkipNL(1)
        if (ahead.isEmpty()) {
            return false
        }
        let nextKind = ahead[0].kind
        return nextKind == TokenKind.LT || nextKind == TokenKind.LPAREN ||
            nextKind == TokenKind.LSQUARE || nextKind == TokenKind.LCURL
    }

    public func SeeingPrimaryConstructor(scopeKind: ScopeKind): Bool {
        return (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) || ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY)) &&
            SeeingPrimaryIdentifier()
    }

    public func SeeingFinalizer(): Bool {
        return Seeing([TokenKind.BITNOT, TokenKind.INIT], skipNewline: false)
    }

    public func IsConditionExprKind(ek: ExprKind): Bool {
        return ExprKindEquals(ek, ExprKind.IF_COND_EXPR) || ExprKindEquals(ek, ExprKind.WHILE_COND_EXPR) ||
            ExprKindEquals(ek, ExprKind.EXPR_IN_IF_COND_TUPLE) ||
            ExprKindEquals(ek, ExprKind.EXPR_IN_WHILE_COND_TUPLE)
    }

    public func SeeingInvalidParamListInLambdaExpr(): Bool {
        if (SeeingIdentifierLike() || Seeing(TokenKind.WILDCARD)) {
            let ahead = lexer.LookAheadSkipNL(2)
            if (ahead.isEmpty()) {
                return true
            }
            let firstKind = ahead[0].kind
            if (firstKind == TokenKind.COMMA || firstKind == TokenKind.COLON || firstKind == TokenKind.DOUBLE_ARROW) {
                return false
            }
            if (ahead.size == 2 && firstKind == TokenKind.ASSIGN && ahead[1].kind == TokenKind.GT &&
                ahead[1].Begin().line == ahead[0].Begin().line &&
                ahead[1].Begin().column == ahead[0].Begin().column + 1) {
                return false
            }
        }
        return true
    }

    public func SeeingPrimitiveTypeToken(kind: TokenKind): Bool {
        let idx = TokenKindIndex(kind)
        return idx >= TokenKindIndex(TokenKind.INT8) && idx <= TokenKindIndex(TokenKind.UNIT)
    }

    public func SeeingOperator(): Bool {
        return Seeing(TokenKind.DOT, TokenKind.WILDCARD)
    }

    public func SeeingTypeConvertiblePrimitiveToken(kind: TokenKind): Bool {
        let idx = TokenKindIndex(kind)
        return idx >= TokenKindIndex(TokenKind.INT8) && idx <= TokenKindIndex(TokenKind.RUNE)
    }

    public func SeeingPrimitiveTypeAndLParen(): Bool {
        return SeeingTypeConvertiblePrimitiveToken(Peek().kind) &&
            lexer.LookAhead(1).size > 0 && lexer.LookAhead(1)[0].kind == TokenKind.LPAREN
    }

    public func SeeingPrimitiveTypeAndDot(): Bool {
        return SeeingPrimitiveTypeToken(Peek().kind) &&
            lexer.LookAhead(1).size > 0 && lexer.LookAhead(1)[0].kind == TokenKind.DOT
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
        var pos = INVALID_POSITION
        if (!node.isBroken) {
            pos = lastToken.Begin()
            DiagExpectedIdentifierWithNode(node)
        }
        node.isBroken = true
        return SrcIdentifier("", "", pos, pos, false)
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
        if (!Skip(TokenKind.WHERE)) {
            return out
        }
        while (true) {
            let constraint = GenericConstraint()
            if (lastToken.kind == TokenKind.COMMA && !out.isEmpty()) {
                out[out.size - 1].commaPos = lastToken.Begin()
            } else if (lastToken.kind == TokenKind.WHERE) {
                constraint.wherePos = lastToken.Begin()
            }
            let refTy = ParseRefType(true)
            constraint.refType = refTy
            if (!Skip(TokenKind.UPPERBOUND)) {
                DiagExpectCharacter("'<:'")
            } else {
                constraint.operatorPos = lastToken.Begin()
            }
            constraint.upperBounds.add(ParseType())
            while (Skip(TokenKind.BITAND)) {
                constraint.bitAndPos.add(lastToken.Begin())
                constraint.upperBounds.add(ParseType())
            }
            constraint.begin = if (constraint.wherePos.IsZero()) { refTy.begin } else { constraint.wherePos }
            constraint.end = if (!constraint.upperBounds.isEmpty()) {
                constraint.upperBounds[constraint.upperBounds.size - 1].end
            } else {
                refTy.end
            }
            out.add(constraint)
            if (!Skip(TokenKind.COMMA)) {
                break
            }
        }
        let posRecord = HashMap<String, Position>()
        for (constraint in out) {
            if (let Some(refTy) <- constraint.refType) {
                let typeName = refTy.ref.identifier.Val()
                if (let Some(prePos) <- posRecord.get(typeName)) {
                    DiagDuplicatedItem("type name", typeName, refTy.begin, prePos, " in generic constrain")
                } else {
                    posRecord.add(typeName, refTy.begin)
                }
            }
        }
        return out
    }

    public func ApplyModifiersAndAnnotations(decl: Decl, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Unit {
        for (modifier in modifiers) {
            decl.modifiers.add(modifier)
            if (let Some(attr) <- GetAttributeByModifier(modifier.modifier)) {
                decl.EnableAttr(attr)
            }
        }
        for (anno in annos) {
            decl.annotations.add(anno)
            if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (anno.kind == AnnotationKind.INTRINSIC) {
                    funcDecl.EnableAttr(Attribute.INTRINSIC)
                }
                if (anno.kind == AnnotationKind.FASTNATIVE) {
                    funcDecl.isFastNative = true
                }
                if (anno.kind == AnnotationKind.FROZEN) {
                    funcDecl.isFrozen = true
                }
            } else if (let Some(mainDecl) <- (decl as MainDecl)) {
                if (anno.kind == AnnotationKind.INTRINSIC) {
                    mainDecl.EnableAttr(Attribute.INTRINSIC)
                }
                if (anno.kind == AnnotationKind.FASTNATIVE) {
                    mainDecl.isFastNative = true
                }
            } else if (let Some(primaryCtor) <- (decl as PrimaryCtorDecl)) {
                if (anno.kind == AnnotationKind.INTRINSIC) {
                    primaryCtor.EnableAttr(Attribute.INTRINSIC)
                }
                if (anno.kind == AnnotationKind.FASTNATIVE) {
                    primaryCtor.isFastNative = true
                }
            }
        }
        if (!modifiers.isEmpty()) {
            var index: Int64 = 0
            if (inForeignBlock) {
                while (index < modifiers.size && modifiers[index].modifier != TokenKind.FOREIGN) {
                    index++
                }
                if (index < modifiers.size) {
                    index++
                }
            }
            if (index < modifiers.size) {
                decl.begin = modifiers[index].begin
            }
        }
        if (!annos.isEmpty() && (decl.begin.IsZero() || annos[0].begin < decl.begin)) {
            decl.begin = annos[0].begin
        }
    }

    func SetUnsafe(node: Node, modifiers!: ArrayList<Modifier> = ArrayList<Modifier>()): Unit {
        var unsafeModifier: Option<Modifier> = None
        for (modifier in modifiers) {
            if (modifier.modifier == TokenKind.UNSAFE) {
                unsafeModifier = modifier
                break
            }
        }
        if (!OptionIsUnsafeBackend(compileOptions.backend)) {
            if (let Some(modifierValue) <- unsafeModifier) {
                DiagUnsafeWillBeIgnored(modifierValue)
                return
            }
        }
        let walker = Walker(node, visitPre: { current: Node =>
            if (let Some(_) <- (current as CallExpr)) {
                current.EnableAttr(Attribute.UNSAFE)
            }
            if (let Some(expr) <- (current as AstOverloadableExpr)) {
                expr.EnableAttr(Attribute.UNSAFE)
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
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
