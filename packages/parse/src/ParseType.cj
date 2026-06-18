package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func ParseType(): Type {
        var ty = ParsePrefixType()
        if (Seeing(TokenKind.ARROW)) {
            if (ty.astKind == ASTKind.FUNC_TYPE) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.EXPECTED_TOKEN,
                    Peek().Begin(),
                    "unexpected extra '->' after function type")
                ConsumeUntilAny([TokenKind.RCURL, TokenKind.NL], targetTokenConsumed: false)
            } else {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.EXPECTED_TOKEN,
                    Peek().Begin(),
                    "function type parameters must be parenthesized before '->'")
                ty.isBroken = true
            }
        }
        while (Skip(TokenKind.QUEST)) {
            let opt = OptionType()
            opt.componentType = ty
            opt.questNum = 1u64
            opt.questVector.add(lastToken.Begin())
            opt.begin = ty.begin
            opt.end = lastToken.End()
            ty = opt
        }
        return ty
    }

    public func ParsePrefixType(): Type {
        if (Seeing(TokenKind.QUEST)) {
            let opt = OptionType()
            opt.begin = Peek().Begin()
            let oldSkipNL = skipNL
            skipNL = false
            while (Skip(TokenKind.QUEST)) {
                opt.questNum++
                opt.questVector.add(lastToken.Begin())
                opt.end = lastToken.End()
                if (Seeing(TokenKind.NL)) {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.UNEXPECTED_TOKEN,
                        Peek().Begin(),
                        "newline is not allowed between '?' and type")
                    SkipBlank(TokenKind.NL)
                }
            }
            let baseType = ParseBaseType()
            skipNL = oldSkipNL
            while (oldSkipNL && Skip(TokenKind.NL)) {}
            opt.componentType = baseType
            opt.end = baseType.end
            return opt
        }
        if (Skip(TokenKind.DOLLAR)) {
            let ct = ConstantType()
            ct.dollarPos = lastToken.Begin()
            ct.begin = ct.dollarPos
            ct.constantExpr = ParseExpr()
            if (let Some(expr) <- ct.constantExpr) { ct.end = expr.end }
            return ct
        }
        return ParseBaseType()
    }

    public func ParseBaseType(): Type {
        let token = Peek()
        if (SeeingPrimitiveType()) {
            Next()
            return PrimitiveType(token.Value(), token.kind, token.Begin(), token.End())
        }
        if (Skip(TokenKind.THISTYPE)) {
            return ThisType(token.Begin())
        }
        if (Seeing(TokenKind.VARRAY)) {
            return ParseVarrayType()
        }
        if (Seeing(TokenKind.LPAREN)) {
            return ParseTypeWithParen()
        }
        if (SeeingIdentifierLike()) {
            return ParseQualifiedType()
        }
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, token.Begin(), "expected type")
        Next()
        return InvalidType(token.Begin())
    }

    public func SeeingPrimitiveType(): Bool {
        let idx = TokenKindIndex(Peek().kind)
        return idx >= TokenKindIndex(TokenKind.INT8) && idx <= TokenKindIndex(TokenKind.UNIT)
    }

    public func ParseRefType(onlyRef: Bool): RefType {
        let ref = RefType()
        ref.identifier = ExpectIdentifierWithPos(ref)
        ref.begin = ref.identifier.Begin()
        if (!onlyRef && Skip(TokenKind.LT)) {
            ref.leftAnglePos = lastToken.Begin()
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.GT)) {
                ref.typeArguments.add(ParseType())
                if (!Skip(TokenKind.COMMA)) {
                    break
                }
            }
            ref.rightAnglePos = Expect(TokenKind.GT, "expected '>' after type arguments").Begin()
            ref.end = ref.rightAnglePos + 1
        } else {
            ref.end = ref.identifier.End()
        }
        return ref
    }

    public func ParseQualifiedType(): Type {
        var current: Type = ParseRefType(false)
        while (Skip(TokenKind.DOT)) {
            let q = QualifiedType()
            q.baseType = current
            q.dotPos = lastToken.Begin()
            q.field = ExpectIdentifierWithPos(q)
            if (Skip(TokenKind.LT)) {
                q.leftAnglePos = lastToken.Begin()
                while (!Seeing(TokenKind.END) && !Seeing(TokenKind.GT)) {
                    q.typeArguments.add(ParseType())
                    if (!Skip(TokenKind.COMMA)) { break }
                }
                q.rightAnglePos = Expect(TokenKind.GT, "expected '>' after type arguments").Begin()
                q.end = q.rightAnglePos + 1
            } else {
                q.end = q.field.End()
            }
            q.begin = current.begin
            current = q
        }
        return current
    }

    public func ParseVarrayType(): VArrayType {
        let ret = VArrayType()
        let token = Expect(TokenKind.VARRAY, "expected 'VArray'")
        ret.varrayPos = token.Begin()
        ret.begin = token.Begin()
        ret.leftAnglePos = Expect(TokenKind.LT, "expected '<' after VArray").Begin()
        ret.typeArgument = ParseType()
        if (!Skip(TokenKind.COMMA)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.EXPECTED_TOKEN,
                Peek().Begin(),
                "expected ',' and '$' size argument in VArray type")
            ret.isBroken = true
        } else {
            if (let Some(argType) <- ret.typeArgument) {
                argType.commaPos = lastToken.Begin()
            }
            let oldSkipNL = skipNL
            skipNL = false
            if (!Skip(TokenKind.DOLLAR)) {
                skipNL = oldSkipNL
                diag.DiagnoseRefactor(
                    DiagKindRefactor.EXPECTED_TOKEN,
                    Peek().Begin(),
                    "expected '$' before VArray size literal")
                ret.isBroken = true
                ret.constantType = ParseType()
            } else {
                skipNL = oldSkipNL
                let constType = ConstantType()
                constType.dollarPos = lastToken.Begin()
                constType.begin = constType.dollarPos
                if (Seeing(TokenKind.INTEGER_LITERAL)) {
                    constType.constantExpr = ParseLitConst()
                    if (let Some(expr) <- constType.constantExpr) { constType.end = expr.end }
                } else {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.EXPECTED_TOKEN,
                        Peek().Begin(),
                        "expected integer literal after '$' in VArray type")
                    constType.constantExpr = ParseExpr()
                    constType.isBroken = true
                    if (let Some(expr) <- constType.constantExpr) { constType.end = expr.end }
                }
                ret.constantType = constType
            }
        }
        ret.rightAnglePos = Expect(TokenKind.GT, "expected '>' after VArray type").Begin()
        ret.end = ret.rightAnglePos + 1
        return ret
    }

    private func ParseTypeParameterInTupleType(typeNameMap: HashMap<String, Position>): Type {
        SkipBlank(TokenKind.NL)
        var parameterName = SrcIdentifier()
        var parameterColonPos = INVALID_POSITION
        if (SeeingTypeParameterNameColon()) {
            let nameToken = Peek()
            Next()
            parameterName = ParseIdentifierFromToken(nameToken)
            if (typeNameMap.contains(parameterName.Val())) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    parameterName.Begin(),
                    "duplicate type parameter name '${parameterName.Val()}'")
            } else {
                typeNameMap.add(parameterName.Val(), parameterName.Begin())
            }
            SkipBlank(TokenKind.NL)
            parameterColonPos = Expect(TokenKind.COLON, "expected ':' after type parameter name").Begin()
        }
        let parsedType = ParseType()
        parsedType.typeParameterName = parameterName.Val()
        parsedType.typeParameterNameIsRawId = parameterName.IsRaw()
        parsedType.colonPos = parameterColonPos
        parsedType.typePos = parsedType.begin
        if (!parameterName.Empty()) {
            parsedType.begin = parameterName.Begin()
        }
        return parsedType
    }

    private func SeeingTypeParameterNameColon(): Bool {
        if (!SeeingIdentifierLike()) {
            return false
        }
        let ahead = lexer.LookAheadSkipNL(1)
        return !ahead.isEmpty() && ahead[0].kind == TokenKind.COLON
    }

    private func HasNamedTypeParameters(types: ArrayList<Type>): Bool {
        for (typeNode in types) {
            if (!typeNode.typeParameterName.isEmpty()) {
                return true
            }
        }
        return false
    }

    private func HasUnnamedTypeParameters(types: ArrayList<Type>): Bool {
        for (typeNode in types) {
            if (typeNode.typeParameterName.isEmpty()) {
                return true
            }
        }
        return false
    }

    private func MakeTupleType(types: ArrayList<Type>, leftParenPos: Position, rightParenPos: Position): TupleType {
        let tuple = TupleType()
        tuple.leftParenPos = leftParenPos
        tuple.rightParenPos = rightParenPos
        tuple.begin = leftParenPos
        tuple.end = rightParenPos + 1
        for (typeNode in types) {
            tuple.fieldTypes.add(typeNode)
            tuple.commaPosVector.add(typeNode.commaPos)
        }
        return tuple
    }

    private func MakeFuncType(
        types: ArrayList<Type>,
        leftParenPos: Position,
        rightParenPos: Position,
        arrowPos: Position,
        parseReturnType: Bool
    ): FuncType {
        let funcTy = FuncType()
        funcTy.leftParenPos = leftParenPos
        funcTy.rightParenPos = rightParenPos
        funcTy.arrowPos = arrowPos
        funcTy.begin = leftParenPos
        for (typeNode in types) {
            funcTy.paramTypes.add(typeNode)
        }
        if (parseReturnType) {
            funcTy.retType = ParseType()
            if (let Some(ret) <- funcTy.retType) {
                funcTy.end = ret.end
            }
        } else {
            funcTy.end = rightParenPos + 1
            funcTy.isBroken = true
        }
        return funcTy
    }

    public func ParseTypeWithParen(): Type {
        let left = Expect(TokenKind.LPAREN, "expected '('")
        let types = ArrayList<Type>()
        let typeNameMap = HashMap<String, Position>()
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
            types.add(ParseTypeParameterInTupleType(typeNameMap))
            if (Skip(TokenKind.COMMA)) {
                types[types.size - 1].commaPos = lastToken.Begin()
            } else {
                break
            }
        }
        let right = Expect(TokenKind.RPAREN, "expected ')' after type").Begin()
        if (HasNamedTypeParameters(types) && HasUnnamedTypeParameters(types)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.PARSE_ERROR,
                left.Begin(),
                "all function or tuple type parameters must either be named or unnamed")
        }
        if (Skip(TokenKind.ARROW)) {
            return MakeFuncType(types, left.Begin(), right, lastToken.Begin(), true)
        }
        if (types.size == 1) {
            let first = types[0]
            if (!first.typeParameterName.isEmpty()) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    first.begin,
                    "only tuple and function types can use type parameter names")
            }
            let paren = ParenType()
            paren.leftParenPos = left.Begin()
            paren.innerType = first
            paren.rightParenPos = right
            paren.begin = left.Begin()
            paren.end = right + 1
            return paren
        }
        if (types.size >= 2) {
            return MakeTupleType(types, left.Begin(), right)
        }
        diag.DiagnoseRefactor(
            DiagKindRefactor.EXPECTED_TOKEN,
            right,
            "expected '->' in empty function type")
        return MakeFuncType(types, left.Begin(), right, right, false)
    }
}
