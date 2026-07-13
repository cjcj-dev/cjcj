package cjcj::parse

import std.collection.*

extend ParserImpl {
    public func ParseType(): Type {
        let ty = ParsePrefixType()
        if (Seeing(TokenKind.ARROW)) {
            if (ty.astKind == ASTKind.FUNC_TYPE) {
                DiagRedundantArrowAfterFunc(ty)
                ConsumeUntilAny([TokenKind.RCURL, TokenKind.NL], targetTokenConsumed: false)
            } else {
                DiagParseExpectedParenthis(ty)
                ty.isBroken = true
            }
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
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_newline_not_allowed_between_quest_and_type,
                        Peek().End()).Emit()
                    SkipBlank(TokenKind.NL)
                }
            }
            let baseType = ParseBaseType()
            skipNL = true
            while (oldSkipNL && Skip(TokenKind.NL)) {}
            opt.componentType = baseType
            opt.end = baseType.end
            return opt
        }
        return ParseBaseType()
    }

    public func ParseBaseType(): Type {
        let token = Peek()
        if (SeeingPrimitiveType()) {
            Next()
            return PrimitiveType(token.Value(), token.Begin(), token.End())
        }
        if (Skip(TokenKind.THISTYPE)) {
            if (enableThis) {
                return ThisType(token.Begin())
            } else {
                DiagThisTypeNotAllow()
                return InvalidType(token.Begin())
            }
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
        DiagExpectedTypeName()
        return InvalidType(token.Begin())
    }

    public func SeeingPrimitiveType(): Bool {
        let idx = TokenKindIndex(Peek().kind)
        return idx >= TokenKindIndex(TokenKind.INT8) && idx <= TokenKindIndex(TokenKind.UNIT)
    }

    public func ParseRefType(onlyRef: Bool): RefType {
        let ref = RefType()
        try (cs = ChainScope(this, ref)) {
            ref.ref.identifier = ExpectIdentifierWithPos(ref)
            ref.begin = ref.ref.identifier.Begin()
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
                ref.end = ref.ref.identifier.End()
            }
        }
        return ref
    }

    public func ParseQualifiedType(): Type {
        var current: Type = ParseRefType(false)
        while (Skip(TokenKind.DOT)) {
            let q = QualifiedType()
            try (cs = ChainScope(this, q)) {
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
        }
        return current
    }

    public func ParseVarrayType(): Type {
        let ret = VArrayType()
        let token = Expect(TokenKind.VARRAY, "expected 'VArray'")
        ret.varrayPos = token.Begin()
        ret.begin = token.Begin()
        try (cs = ChainScope(this, ret)) {
            if (!Skip(TokenKind.LT)) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_varray_type_parameter, token.End()).Emit()
                return InvalidType(Peek().Begin())
            }
            ret.leftAnglePos = lastToken.Begin()
            let typeArgument = ParseType()
            ret.typeArgument = typeArgument
            if (typeArgument.IsInvalid()) {
                return InvalidType(Peek().Begin())
            }
            if (!Skip(TokenKind.COMMA)) {
                DiagVArrayTypeArgMismatch(MakeRange(ret.leftAnglePos, Peek().End()), "a type argument and size literal")
                ConsumeUntilAny([TokenKind.NL])
                return InvalidType(Peek().Begin())
            } else {
                typeArgument.commaPos = lastToken.Begin()
                skipNL = false
                if (!Skip(TokenKind.DOLLAR)) {
                    DiagVArrayTypeArgMismatch(MakeRange(Peek().Begin(), Peek().End()),
                        "a '$' follows an integer literal as the second generic argument")
                    ConsumeUntilAny([TokenKind.NL])
                    return InvalidType(Peek().Begin())
                } else {
                    let constType = ConstantType()
                    constType.dollarPos = lastToken.Begin()
                    constType.begin = constType.dollarPos
                    if (!Seeing(TokenKind.INTEGER_LITERAL)) {
                        ParseDiagnoseRefactor(DiagKindRefactor.parse_expect_integer_literal_varray,
                            constType.dollarPos).Emit()
                        ConsumeUntilAny([TokenKind.NL])
                        return InvalidType(Peek().Begin())
                    }
                    skipNL = true
                    constType.constantExpr = ParseLitConst()
                    constType.end = Peek().End()
                    ret.constantType = constType
                }
            }
            if (!Skip(TokenKind.GT)) {
                DiagExpectedRightDelimiter("<", ret.leftAnglePos)
                return InvalidType(Peek().Begin())
            }
            ret.rightAnglePos = lastToken.Begin()
            ret.end = lastToken.End()
        }
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
                let builder = diag.DiagnoseRefactor(DiagKindRefactor.parse_duplicate_type_parameter_name,
                    MakeRange(parameterName.Begin(), parameterName.End()), parameterName.Val())
                if (let Some(pos) <- typeNameMap.get(parameterName.Val())) {
                    builder.AddHint(MakeRange(pos, parameterName.Val()))
                }
                builder.Emit()
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
        arrowPos: Position
    ): FuncType {
        let funcTy = FuncType()
        funcTy.leftParenPos = leftParenPos
        funcTy.rightParenPos = rightParenPos
        funcTy.arrowPos = arrowPos
        funcTy.begin = leftParenPos
        for (typeNode in types) {
            funcTy.paramTypes.add(typeNode)
        }
        funcTy.retType = ParseType()
        if (let Some(ret) <- funcTy.retType) {
            funcTy.end = ret.end
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
        if (HasNamedTypeParameters(types) && HasUnnamedTypeParameters(types)) {
            if (!types.isEmpty()) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_all_parameters_must_be_named,
                    MakeRange(types[0].begin, types[types.size - 1].end)).Emit()
            }
        }
        if (!Skip(TokenKind.RPAREN)) {
            DiagExpectedRightDelimiter("(", left.Begin())
            return InvalidType(Peek().Begin())
        }
        let right = lastToken.Begin()
        if (Skip(TokenKind.ARROW)) {
            return MakeFuncType(types, left.Begin(), right, lastToken.Begin())
        }
        if (types.size == 1) {
            let first = types[0]
            if (!first.typeParameterName.isEmpty()) {
                let builder = ParseDiagnoseRefactor(
                    DiagKindRefactor.parse_only_tuple_and_func_type_allow_type_parameter_name,
                    MakeRange(first.begin, first.begin + first.typeParameterName.size), first.typeParameterName)
                builder.AddNote("only tuple type and function type support type parameter name")
                builder.Emit()
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
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_arrow_in_func_type, Peek().Begin()).Emit()
        return MakeFuncType(types, left.Begin(), right, right)
    }
}
