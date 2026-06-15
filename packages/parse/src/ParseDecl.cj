package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func ParseTopLevel(): File {
        let file = File()
        currentFile = file
        file.fileID = lexer.GetFileID()
        file.begin = Peek().Begin()
        SkipNLOrSemi()
        var pendingAnnos = ArrayList<Annotation>()
        while (!Seeing(TokenKind.END)) {
            ParseAnnotations(pendingAnnos)
            let modifiers = ArrayList<Modifier>()
            ParseModifiers(modifiers)
            if (Seeing(TokenKind.PACKAGE)) {
                file.packageSpec = ParsePackageHeader(modifiers)
            } else if (Seeing(TokenKind.FEATURES)) {
                file.features.add(ParseTopLvlFeatures(pendingAnnos))
            } else if (SeeingImport()) {
                file.imports.add(ParseImportSpec(pendingAnnos))
            } else if (SeeingDecl() || Seeing(TokenKind.AT) || Seeing(TokenKind.AT_EXCL)) {
                let decl = ParseDecl(ScopeKind.TOPLEVEL, modifiers, pendingAnnos)
                FinalizeDeclTree(decl)
                file.decls.add(decl)
            } else {
                diag.DiagnoseRefactor(DiagKindRefactor.UNEXPECTED_TOKEN, Peek().Begin(), "unexpected token at top level")
                Next()
            }
            pendingAnnos = ArrayList<Annotation>()
            SkipNLOrSemi()
        }
        file.end = Peek().End()
        if (enableAttachComment) {
            AttachCommentToFile(file)
        }
        return file
    }

    public func SeeingDecl(): Bool {
        return SeeingModifier() || SeeingAny([TokenKind.FUNC, TokenKind.MACRO, TokenKind.LET, TokenKind.VAR,
            TokenKind.CONST, TokenKind.ENUM, TokenKind.TYPE, TokenKind.STRUCT, TokenKind.CLASS,
            TokenKind.INTERFACE, TokenKind.MAIN, TokenKind.EXTEND, TokenKind.PROP, TokenKind.INIT])
    }

    public func ParseDecl(scopeKind: ScopeKind): Decl {
        let annos = ArrayList<Annotation>()
        let modifiers = ArrayList<Modifier>()
        ParseAnnotations(annos)
        ParseModifiers(modifiers)
        return ParseDecl(scopeKind, modifiers, annos)
    }

    public func ParseDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Decl {
        if (Seeing(TokenKind.AT) || Seeing(TokenKind.AT_EXCL)) {
            return ParseMacroCallDeclInput(scopeKind, modifiers, annos)
        }
        if (Seeing(TokenKind.FUNC)) { return ParseFuncDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.MACRO)) { return ParseMacroDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.MAIN)) { return ParseMainDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.LET) || Seeing(TokenKind.VAR) || Seeing(TokenKind.CONST)) { return ParseVarOrLet(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.CLASS)) { return ParseClassDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.INTERFACE)) { return ParseInterfaceDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.STRUCT)) { return ParseStructDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.ENUM)) { return ParseEnumDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.EXTEND)) { return ParseExtendDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.TYPE)) { return ParseTypeAlias(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.PROP)) { return ParsePropDecl(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.INIT)) { return ParseConstructor(scopeKind, modifiers, annos) }
        let token = Peek()
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, token.Begin(), "expected declaration")
        ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RCURL], targetTokenConsumed: false)
        return InvalidDecl(token.Begin())
    }

    public func ParseFuncDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): FuncDecl {
        let ret = FuncDecl()
        ParseFuncLikeHeader(ret, TokenKind.FUNC, scopeKind, modifiers, annos)
        return ret
    }

    public func ParseMacroDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): MacroDecl {
        let ret = MacroDecl()
        ParseFuncLikeHeader(ret, TokenKind.MACRO, scopeKind, modifiers, annos)
        return ret
    }

    public func ParseMainDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): MainDecl {
        let ret = MainDecl()
        ParseFuncLikeHeader(ret, TokenKind.MAIN, scopeKind, modifiers, annos)
        ret.identifier = SrcIdentifier("main", "main", ret.keywordPos, ret.keywordPos + 4, false)
        return ret
    }

    public func ParseFuncLikeHeader(ret: FuncDecl, keyword: TokenKind, scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Unit {
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        let keywordToken = Expect(keyword, "expected function keyword")
        ret.keywordPos = keywordToken.Begin()
        if (ret.begin.IsZero()) { ret.begin = keywordToken.Begin() }
        if (keyword != TokenKind.MAIN) {
            if (Skip(TokenKind.OPERATOR)) {
                ret.isOperator = true
                ret.identifier = SrcIdentifier(lastToken.Value(), lastToken.Value(), lastToken.Begin(), lastToken.End(), false)
            } else {
                ret.identifier = ExpectIdentifierWithPos(ret)
            }
        }
        let body = ParseFuncBody(scopeKind)
        ret.funcBody = body
        if (let Some(_) <- body.generic) {
            ret.EnableAttr(Attribute.GENERIC)
        }
        ret.end = body.end
    }

    public func ParseFuncBody(scopeKind: ScopeKind): FuncBody {
        let body = FuncBody()
        if (let Some(generic) <- ParseOptionalGeneric()) {
            body.generic = generic
        }
        body.paramLists.add(ParseParameterList(scopeKind))
        if (Skip(TokenKind.COLON)) {
            body.colonPos = lastToken.Begin()
            body.retType = ParseType()
        }
        for (constraint in ParseGenericConstraints()) {
            body.genericConstraints.add(constraint)
        }
        if (Seeing(TokenKind.LCURL)) {
            body.body = ParseBlock(ScopeKind.FUNC_BODY)
            if (let Some(block) <- body.body) { body.end = block.end }
        } else if (Skip(TokenKind.SEMI)) {
            body.end = lastToken.End()
        } else if (parseDeclFile) {
            body.end = lastToken.End()
        } else {
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected function body")
            body.end = Peek().Begin()
        }
        return body
    }

    public func ParseParameterList(scopeKind: ScopeKind): FuncParamList {
        let list = FuncParamList()
        list.leftParenPos = Expect(TokenKind.LPAREN, "expected '(' for parameter list").Begin()
        list.begin = list.leftParenPos
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
            list.params.add(ParseFuncParam())
            if (!Skip(TokenKind.COMMA)) { break }
        }
        list.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after parameters").Begin()
        list.end = list.rightParenPos + 1
        return list
    }

    public func ParseFuncParam(): FuncParam {
        let param = FuncParam()
        let mods = ArrayList<Modifier>()
        ParseModifiers(mods)
        for (modifier in mods) { param.modifiers.add(modifier) }
        if (Skip(TokenKind.LET) || Skip(TokenKind.VAR)) {
            param.isMemberParam = true
        }
        param.identifier = ExpectIdentifierWithPos(param)
        param.begin = if (!param.modifiers.isEmpty()) { param.modifiers[0].begin } else { param.identifier.Begin() }
        if (Skip(TokenKind.COLON)) {
            param.colonPos = lastToken.Begin()
            param.typeNode = ParseType()
        }
        if (Skip(TokenKind.ASSIGN)) {
            param.assignPos = lastToken.Begin()
            param.assignment = ParseExpr()
        }
        if (Skip(TokenKind.ELLIPSIS)) {
            param.isVariadic = true
        }
        param.end = if (let Some(expr) <- param.assignment) {
            expr.end
        } else if (let Some(ty) <- param.typeNode) {
            ty.end
        } else {
            param.identifier.End()
        }
        return param
    }

    public func ParseVarOrLet(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Decl {
        let key = Peek()
        let isVar = key.kind == TokenKind.VAR
        let isConst = key.kind == TokenKind.CONST
        Next()
        let pattern = ParsePattern(ArrayList<Attribute>(), isVar, true)
        if (let Some(varPat) <- (pattern as VarPattern)) {
            let decl = VarDecl()
            ApplyModifiersAndAnnotations(decl, modifiers, annos)
            decl.keywordPos = key.Begin()
            decl.identifier = varPat.identifier
            decl.isVar = isVar
            decl.isConst = isConst
            decl.begin = if (decl.begin.IsZero()) { key.Begin() } else { decl.begin }
            ParseTypeAndExpr(decl)
            return decl
        }
        let decl = VarWithPatternDecl()
        ApplyModifiersAndAnnotations(decl, modifiers, annos)
        decl.keywordPos = key.Begin()
        decl.pattern = pattern
        decl.isVar = isVar
        decl.isConst = isConst
        decl.begin = if (decl.begin.IsZero()) { key.Begin() } else { decl.begin }
        if (Skip(TokenKind.COLON)) {
            decl.typeNode = ParseType()
        }
        if (Skip(TokenKind.ASSIGN)) {
            decl.initializer = ParseExpr(ExprKind.VAR_INIT)
        }
        decl.end = if (let Some(expr) <- decl.initializer) {
            expr.end
        } else if (let Some(ty) <- decl.typeNode) {
            ty.end
        } else {
            pattern.end
        }
        return decl
    }

    public func ParseTypeAndExpr(ret: VarDeclAbstract): Unit {
        if (Skip(TokenKind.COLON)) {
            ret.colonPos = lastToken.Begin()
            ret.typeNode = ParseType()
        }
        if (Skip(TokenKind.ASSIGN)) {
            ret.assignPos = lastToken.Begin()
            ret.initializer = ParseExpr(ExprKind.VAR_INIT)
        }
        ret.end = if (let Some(expr) <- ret.initializer) {
            expr.end
        } else if (let Some(ty) <- ret.typeNode) {
            ty.end
        } else {
            ret.identifier.End()
        }
    }

    public func ParseClassDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): ClassDecl {
        let ret = ClassDecl()
        ParseInheritableHeader(ret, TokenKind.CLASS, modifiers, annos)
        ParseClassLikeBody(ret, ScopeKind.CLASS_BODY)
        return ret
    }

    public func ParseInterfaceDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): InterfaceDecl {
        let ret = InterfaceDecl()
        ParseInheritableHeader(ret, TokenKind.INTERFACE, modifiers, annos)
        ParseClassLikeBody(ret, ScopeKind.INTERFACE_BODY)
        return ret
    }

    public func ParseStructDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): StructDecl {
        let ret = StructDecl()
        ParseInheritableHeader(ret, TokenKind.STRUCT, modifiers, annos)
        ParseClassLikeBody(ret, ScopeKind.STRUCT_BODY)
        return ret
    }

    public func ParseEnumDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): EnumDecl {
        let ret = EnumDecl()
        ParseInheritableHeader(ret, TokenKind.ENUM, modifiers, annos)
        if (Skip(TokenKind.LCURL)) {
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RCURL)) {
                let localAnnos = ArrayList<Annotation>()
                ParseAnnotations(localAnnos)
                if (SeeingIdentifierLike()) {
                    let ctor = ParseEnumConstructor(ArrayList<Modifier>(), localAnnos)
                    ctor.outerDecl = ret
                    ret.constructors.add(ctor)
                } else if (SeeingDecl()) {
                    let member = ParseDecl(ScopeKind.ENUM_BODY)
                    member.outerDecl = ret
                    ret.bodyDecls.add(member)
                } else {
                    Next()
                }
                SkipNLOrSemi()
            }
            ret.end = Expect(TokenKind.RCURL, "expected '}' after enum body").End()
        }
        return ret
    }

    public func ParseEnumConstructor(modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Decl {
        let decl = VarDecl()
        ApplyModifiersAndAnnotations(decl, modifiers, annos)
        decl.EnableAttr(Attribute.ENUM_CONSTRUCTOR)
        decl.identifier = ExpectIdentifierWithPos(decl)
        decl.begin = if (decl.begin.IsZero()) { decl.identifier.Begin() } else { decl.begin }
        if (Skip(TokenKind.LPAREN)) {
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
                ParseFuncParam()
                if (!Skip(TokenKind.COMMA)) { break }
            }
            decl.end = Expect(TokenKind.RPAREN, "expected ')' after enum constructor").End()
        } else {
            decl.end = decl.identifier.End()
        }
        return decl
    }

    public func ParseInheritableHeader(ret: InheritableDecl, keyword: TokenKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Unit {
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        let key = Expect(keyword, "expected declaration keyword")
        ret.keywordPos = key.Begin()
        ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
        ret.identifier = ExpectIdentifierWithPos(ret)
        if (let Some(generic) <- ParseOptionalGeneric()) {
            ret.generic = generic
            ret.EnableAttr(Attribute.GENERIC)
        }
        if (Skip(TokenKind.COLON)) {
            ret.inheritedTypes.add(ParseType())
            while (Skip(TokenKind.BITAND)) {
                ret.inheritedTypes.add(ParseType())
            }
        }
        for (constraint in ParseGenericConstraints()) {
            ret.genericConstraints.add(constraint)
        }
        ret.end = ret.identifier.End()
    }

    public func ParseClassLikeBody(ret: InheritableDecl, scopeKind: ScopeKind): Unit {
        if (!Skip(TokenKind.LCURL)) {
            return
        }
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RCURL)) {
            if (SeeingDecl() || Seeing(TokenKind.AT) || Seeing(TokenKind.AT_EXCL)) {
                let member = ParseDecl(scopeKind)
                member.outerDecl = ret
                ret.bodyDecls.add(member)
            } else {
                Next()
            }
            SkipNLOrSemi()
        }
        ret.end = Expect(TokenKind.RCURL, "expected '}' after declaration body").End()
    }

    public func ParseExtendDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): ExtendDecl {
        let ret = ExtendDecl()
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        let key = Expect(TokenKind.EXTEND, "expected 'extend'")
        ret.keywordPos = key.Begin()
        ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
        ret.extendedType = ParseType()
        ParseClassLikeBody(ret, ScopeKind.EXTEND_BODY)
        return ret
    }

    public func ParseTypeAlias(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): TypeAliasDecl {
        let ret = TypeAliasDecl()
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        let key = Expect(TokenKind.TYPE, "expected 'type'")
        ret.keywordPos = key.Begin()
        ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
        ret.identifier = ExpectIdentifierWithPos(ret)
        if (let Some(generic) <- ParseOptionalGeneric()) { ret.generic = generic }
        ret.assignPos = Expect(TokenKind.ASSIGN, "expected '=' in type alias").Begin()
        ret.typeNode = ParseType()
        ret.end = if (let Some(ty) <- ret.typeNode) { ty.end } else { ret.identifier.End() }
        return ret
    }

    public func ParsePropDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): PropDecl {
        let ret = PropDecl()
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        let key = Expect(TokenKind.PROP, "expected 'prop'")
        ret.keywordPos = key.Begin()
        ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
        ret.identifier = ExpectIdentifierWithPos(ret)
        if (Skip(TokenKind.COLON)) {
            ret.typeNode = ParseType()
        }
        if (Skip(TokenKind.ASSIGN)) {
            ret.initializer = ParseExpr(ExprKind.VAR_INIT)
        }
        if (Skip(TokenKind.LCURL)) {
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RCURL)) {
                if (Seeing(TokenKind.IDENTIFIER) && (Peek().Value() == "get" || Peek().Value() == "set")) {
                    let accessorName = Peek().Value()
                    let accessor = FuncDecl()
                    accessor.identifier = ParseIdentifierFromToken(Peek())
                    Next()
                    accessor.funcBody = ParseFuncBody(if (accessorName == "get") { ScopeKind.PROP_MEMBER_GETTER_BODY } else { ScopeKind.PROP_MEMBER_SETTER_BODY })
                    if (accessorName == "get") { ret.getter = accessor } else { ret.setter = accessor }
                } else {
                    Next()
                }
                SkipNLOrSemi()
            }
            ret.end = Expect(TokenKind.RCURL, "expected '}' after property body").End()
        } else {
            ret.end = if (let Some(expr) <- ret.initializer) {
                expr.end
            } else if (let Some(ty) <- ret.typeNode) {
                ty.end
            } else {
                ret.identifier.End()
            }
        }
        return ret
    }

    public func ParseConstructor(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): FuncDecl {
        let ret = FuncDecl()
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        let key = Expect(TokenKind.INIT, "expected 'init'")
        ret.keywordPos = key.Begin()
        ret.identifier = SrcIdentifier("init", "init", key.Begin(), key.End(), false)
        ret.EnableAttr(Attribute.CONSTRUCTOR)
        ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
        ret.funcBody = ParseFuncBody(scopeKind)
        if (let Some(body) <- ret.funcBody) { ret.end = body.end }
        return ret
    }
}
