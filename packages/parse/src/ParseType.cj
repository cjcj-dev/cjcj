package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func ParseType(): Type {
        var ty = ParsePrefixType()
        while (Skip(TokenKind.QUEST)) {
            let opt = OptionType()
            opt.componentType = ty
            opt.questVector.add(lastToken.Begin())
            opt.begin = ty.begin
            opt.end = lastToken.End()
            ty = opt
        }
        return ty
    }

    public func ParsePrefixType(): Type {
        if (Skip(TokenKind.QUEST)) {
            let opt = OptionType()
            opt.questVector.add(lastToken.Begin())
            opt.componentType = ParsePrefixType()
            opt.begin = lastToken.Begin()
            if (let Some(child) <- opt.componentType) { opt.end = child.end }
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
        if (Skip(TokenKind.LT)) {
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
                while (!Seeing(TokenKind.END) && !Seeing(TokenKind.GT)) {
                    q.typeArguments.add(ParseType())
                    if (!Skip(TokenKind.COMMA)) { break }
                }
                Expect(TokenKind.GT, "expected '>' after type arguments")
            }
            q.begin = current.begin
            q.end = q.field.End()
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
        } else if (!Skip(TokenKind.DOLLAR)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.EXPECTED_TOKEN,
                Peek().Begin(),
                "expected '$' before VArray size literal")
            ret.isBroken = true
            ret.constantType = ParseType()
        } else {
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
        ret.rightAnglePos = Expect(TokenKind.GT, "expected '>' after VArray type").Begin()
        ret.end = ret.rightAnglePos + 1
        return ret
    }

    public func ParseTypeWithParen(): Type {
        let left = Expect(TokenKind.LPAREN, "expected '('")
        if (Skip(TokenKind.RPAREN)) {
            let tuple = TupleType()
            tuple.leftParenPos = left.Begin()
            tuple.rightParenPos = lastToken.Begin()
            tuple.begin = left.Begin()
            tuple.end = lastToken.End()
            return tuple
        }
        let first = ParseType()
        if (Skip(TokenKind.COMMA)) {
            let tuple = TupleType()
            tuple.leftParenPos = left.Begin()
            tuple.fieldTypes.add(first)
            tuple.commaPosVector.add(lastToken.Begin())
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
                tuple.fieldTypes.add(ParseType())
                if (Skip(TokenKind.COMMA)) {
                    tuple.commaPosVector.add(lastToken.Begin())
                } else {
                    break
                }
            }
            tuple.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after tuple type").Begin()
            tuple.begin = left.Begin()
            tuple.end = tuple.rightParenPos + 1
            if (Skip(TokenKind.ARROW)) {
                let funcTy = FuncType()
                funcTy.leftParenPos = tuple.leftParenPos
                funcTy.rightParenPos = tuple.rightParenPos
                for (field in tuple.fieldTypes) { funcTy.paramTypes.add(field) }
                funcTy.arrowPos = lastToken.Begin()
                funcTy.retType = ParseType()
                funcTy.begin = tuple.begin
                if (let Some(ret) <- funcTy.retType) { funcTy.end = ret.end }
                return funcTy
            }
            return tuple
        }
        let right = Expect(TokenKind.RPAREN, "expected ')' after type").Begin()
        if (Skip(TokenKind.ARROW)) {
            let funcTy = FuncType()
            funcTy.leftParenPos = left.Begin()
            funcTy.rightParenPos = right
            funcTy.paramTypes.add(first)
            funcTy.arrowPos = lastToken.Begin()
            funcTy.retType = ParseType()
            funcTy.begin = left.Begin()
            if (let Some(ret) <- funcTy.retType) { funcTy.end = ret.end }
            return funcTy
        }
        let paren = ParenType()
        paren.leftParenPos = left.Begin()
        paren.innerType = first
        paren.rightParenPos = right
        paren.begin = left.Begin()
        paren.end = right + 1
        return paren
    }
}
