package cjcj::parse

import cjcj::ast.ASTCloner
import cjcj::ast.Node
import cjcj::ast.SortModifierByPos
import cjcj::ast.VisitAction
import cjcj::ast.Walker
import cjcj::utils.{CJC_ASSERT, FileUtil}
import std.collection.*

extend ParserImpl {
    // C++ anchor: cangjie_compiler/src/Parse/ParseDecl.cpp:1926-1947
    private func ParseForImportToGetContentBetween(
        fileID: UInt64,
        beginLine: Int64,
        beginColumn: Int64,
        endLine: Int64,
        endColumn: Int64
    ): String {
        let posBase = lexer.GetPosBase()
        var newBeginLine: Int64
        var newBeginColumn: Int64
        var newEndLine: Int64
        var newEndColumn: Int64
        if (beginLine == posBase.line && beginColumn == posBase.column) {
            newBeginLine = 1
            newBeginColumn = 1
            newEndLine = (endLine - beginLine) + 1
            newEndColumn = endColumn
        } else {
            newBeginLine = (beginLine - posBase.line) + 1
            newBeginColumn = beginColumn
            newEndLine = (endLine - posBase.line) + 1
            newEndColumn = endColumn
        }
        return sourceManager.GetContentBetween(fileID, Position(newBeginLine, newBeginColumn),
            Position(newEndLine, newEndColumn), importGenericContent: inputString)
    }

    public func ParseTopLevel(): File {
        let file = File()
        currentFile = file
        Peek()
        file.begin = Position(lexer.GetFileID(), 1, 1)
        let source = sourceManager.GetSource(file.begin.fileID)
        file.fileName = FileUtil.GetFileName(source.path)
        file.filePath = source.path
        file.fileHash = source.fileHash
        SkipBlank(TokenKind.NL)
        var annos = ArrayList<Annotation>()
        if (SeeingBuiltinAnnotation()) {
            ParseAnnotations(annos)
        }
        if (SeeingFeatures()) {
            file.feature = ParseTopLvlFeatures(annos)
            annos.clear()
        } else {
            CheckAndHandleUnexpectedTopLevelDeclAfterFeatures()
        }
        if (SeeingBuiltinAnnotation()) {
            ParseAnnotations(annos)
        }
        let scope = ParserScope(this)
        let modifiers = ArrayList<Modifier>()
        ParseModifiers(modifiers)
        if (SeeingPackage() || SeeingMacroPackage()) {
            file.packageSpec = ParsePackageHeader(modifiers)
            if (ParsePackageHeaderEnd()) {
                file.end = lastToken.End()
                file.curFile = file
                return file
            }
            SkipBlank(TokenKind.SEMI)
            if (!annos.isEmpty()) {
                if (let Some(packageSpec) <- file.packageSpec) {
                    DiagUnexpectedAnnoOn(annos[0], packageSpec.packagePos, annos[0].identifier.Val(), "package")
                }
                annos.clear()
            }
        } else {
            CheckExpectedTopLevelDeclWhenNoPackage(annos, modifiers)
            scope.ResetParserScope()
        }
        ParseImportSpecInTop(file.imports, annos)
        if (!scanDepPkg) {
            ParseTopLevelDecls(file, annos)
        }
        file.end = lookahead.End()
        if (file.end.IsZero()) {
            file.end = file.begin
        }
        if (enableAttachComment) {
            AttachCommentToFile(file)
        }
        let comments = ArrayList<Token>()
        for (comment in lexer.GetComments()) {
            comments.add(comment)
        }
        commentsMap.Put(UInt32(file.begin.fileID), comments)
        AssignCurFile(file)
        return file
    }

    private func ParseTopLevelDecls(file: File, annos: ArrayList<Annotation>): Unit {
        var topLevelCount: Int64 = 0
        while (true) {
            if (!newlineSkipped) {
                if (Seeing(TokenKind.END)) {
                    break
                }
            }
            if (topLevelCount >= 1) {
                if (!newlineSkipped && !Skip(TokenKind.SEMI)) {
                    DiagExpectSemiOrNewline()
                }
                SkipBlank(TokenKind.SEMI)
            }
            if (DetectPrematureEnd()) {
                break
            }
            ParseAnnotations(annos)
            ParseTopLevelDecl(file, annos)
            annos.clear()
            bracketsStack.clear()
            topLevelCount++
        }
    }

    private func ParseTopLevelDecl(file: File, annos: ArrayList<Annotation>): Unit {
        let modifiers = ArrayList<Modifier>()
        ParseModifiers(modifiers)
        if (HasModifierToken(modifiers, TokenKind.FOREIGN)) {
            let decls = ParseForeignDecls(modifiers, annos)
            if (!decls.isEmpty()) {
                for (decl in decls) {
                    FinalizeDeclTree(decl)
                    file.decls.add(decl)
                }
            }
            return
        }
        let decl = ParseDecl(ScopeKind.TOPLEVEL, modifiers, annos)
        FinalizeDeclTree(decl)
        if (let Some(current) <- currentFile) {
            if (let Some(pkg) <- current.packageSpec) {
                if (HasModifierToken(decl.modifiers, TokenKind.PUBLIC) && pkg.hasMacro &&
                    decl.astKind != ASTKind.MACRO_DECL) {
                    DiagDeclarationInMacroPackage(decl)
                }
            }
        }
        file.decls.add(decl)
    }

    private func AssignCurFile(file: File): Unit {
        file.curFile = file
        let visitPre = { curNode: Node =>
            curNode.curFile = file
            VisitAction.WALK_CHILDREN
        }
        Walker(file, visitPre: visitPre).Walk()
    }

    private func ParseForeignDecls(modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): ArrayList<Decl> {
        let ret = ArrayList<Decl>()
        if (!Skip(TokenKind.LCURL)) {
            ret.add(ParseDecl(ScopeKind.TOPLEVEL, modifiers, annos))
            return ret
        }
        CheckNoDeprecatedAnnotation(annos, "foreign block")
        let leftCurlPos = lastToken.Begin()
        SkipBlank(TokenKind.SEMI)
        inForeignBlock = true
        while (true) {
            if (Skip(TokenKind.RCURL)) {
                break
            }
            if (DetectPrematureEnd()) {
                DiagExpectedRightDelimiter("{", leftCurlPos)
                break
            }
            let clonedModifiers = CloneModifiers(modifiers)
            let clonedAnnos = CloneAnnotations(annos)
            ParseAnnotations(clonedAnnos)
            ret.add(ParseDecl(ScopeKind.TOPLEVEL, clonedModifiers, clonedAnnos))
            SkipBlank(TokenKind.SEMI)
        }
        inForeignBlock = false
        return ret
    }

    private func CloneModifiers(modifiers: ArrayList<Modifier>): ArrayList<Modifier> {
        let ret = ArrayList<Modifier>()
        for (modifier in modifiers) {
            if (let Some(cloned) <- (ASTCloner.Clone(modifier) as Modifier)) {
                ret.add(cloned)
            }
        }
        return ret
    }

    private func CloneAnnotations(annos: ArrayList<Annotation>): ArrayList<Annotation> {
        let ret = ArrayList<Annotation>()
        for (anno in annos) {
            if (let Some(cloned) <- (ASTCloner.Clone(anno) as Annotation)) {
                ret.add(cloned)
            }
        }
        return ret
    }

    private func CheckNoDeprecatedAnnotation(annos: ArrayList<Annotation>, invalidTarget: String): Unit {
        for (anno in annos) {
            if (anno.kind == AnnotationKind.DEPRECATED) {
                DiagDeprecatedInvalidTarget(anno, invalidTarget)
            }
        }
    }

    private func ParsePackageHeaderEnd(): Bool {
        var seeingFileEnd = false
        if (newlineSkipped) {
            return seeingFileEnd
        }
        if (Seeing(TokenKind.END)) {
            seeingFileEnd = true
        } else if (!Skip(TokenKind.SEMI)) {
            DiagExpectSemiOrNewline()
        }
        return seeingFileEnd
    }

    private func SeeingPackage(): Bool {
        return Seeing(TokenKind.PACKAGE)
    }

    private func SeeingFeatures(): Bool {
        return Seeing(TokenKind.FEATURES)
    }

    private func SeeingMacroPackage(): Bool {
        return Seeing([TokenKind.MACRO, TokenKind.PACKAGE])
    }

    private func CheckAndHandleUnexpectedTopLevelDeclAfterFeatures(): Unit {
        if (!IsExpectedTokenAfterFeaturesOrPackage(true)) {
            let keywords = ArrayList<String>()
            keywords.add("features")
            keywords.add("macro")
            keywords.add("package")
            keywords.add("import")
            keywords.add("func")
            keywords.add("let")
            keywords.add("var")
            keywords.add("const")
            keywords.add("enum")
            keywords.add("type")
            keywords.add("struct")
            keywords.add("class")
            keywords.add("interface")
            keywords.add("extend")
            keywords.add("main")
            DiagAndSuggestKeywordForExpectedDeclaration(keywords, 1, ScopeKind.TOPLEVEL)
            let consumeTarget = { => IsExpectedTokenAfterFeaturesOrPackage(true) }
            ConsumeUntilAny(consumeTarget, targetTokenConsumed: false)
        }
    }

    private func CheckExpectedTopLevelDeclWhenNoPackage(
        annos: ArrayList<Annotation>,
        modifiers: ArrayList<Modifier>
    ): Unit {
        if (!annos.isEmpty() || !modifiers.isEmpty()) {
            return
        }
        if (!IsExpectedTokenAfterFeaturesOrPackage(false)) {
            let keywords = ArrayList<String>()
            keywords.add("macro")
            keywords.add("package")
            keywords.add("import")
            keywords.add("func")
            keywords.add("let")
            keywords.add("var")
            keywords.add("const")
            keywords.add("enum")
            keywords.add("type")
            keywords.add("struct")
            keywords.add("class")
            keywords.add("interface")
            keywords.add("extend")
            keywords.add("main")
            DiagAndSuggestKeywordForExpectedDeclaration(keywords, 1, ScopeKind.TOPLEVEL)
        }
    }

    private func IsExpectedTokenAfterFeaturesOrPackage(allowPackageKeyword: Bool): Bool {
        if (Seeing(TokenKind.SEMI) || SeeingImport() || SeeingDecl() || SeeingMacroCallDecl() ||
            SeeingInitializer() || SeeingFinalizer() || SeeingBuiltinAnnotation() || Seeing(TokenKind.END)) {
            return true
        }
        return allowPackageKeyword && (SeeingPackage() || SeeingMacroPackage())
    }

    public func SeeingDecl(): Bool {
        return SeeingDeclInScope(ScopeKind.UNKNOWN_SCOPE)
    }

    public func SeeingDeclInScope(scopeKind: ScopeKind): Bool {
        if (SeeingIfAvailable()) {
            return false
        }
        let seeingScopedSpecial = (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) && SeeingFinalizer()) ||
            SeeingPrimaryConstructor(scopeKind)
        return seeingScopedSpecial || (SeeingModifier() && !Seeing([TokenKind.UNSAFE, TokenKind.LCURL])) ||
            SeeingAny([TokenKind.FUNC, TokenKind.MACRO, TokenKind.LET, TokenKind.VAR,
            TokenKind.ENUM, TokenKind.TYPE, TokenKind.STRUCT, TokenKind.CLASS,
            TokenKind.INTERFACE, TokenKind.MAIN, TokenKind.EXTEND, TokenKind.PROP, TokenKind.INIT]) ||
            (SeeingBuiltinAnnotation() && !SeeingAnnotationLambdaExpr())
    }

    public func ParseDecl(scopeKind: ScopeKind): Decl {
        let annos = ArrayList<Annotation>()
        let modifiers = ArrayList<Modifier>()
        ParseAnnotations(annos)
        ParseModifiers(modifiers)
        return ParseDecl(scopeKind, modifiers, annos)
    }

    public func ParseDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Decl {
        if (SeeingBuiltinAnnotation() && !modifiers.isEmpty() && annos.isEmpty()) {
            DiagExpectNoModifierBefore(SortModifierByPos(modifiers)[0], "annotation")
        }
        if ((newlineSkipped && Seeing(TokenKind.NL)) || Seeing(TokenKind.SEMI)) {
            SkipNLOrSemi()
        }
        ParseAnnotations(annos)
        ParseModifiers(modifiers)
        CheckOverflowAnnotation(annos, scopeKind)
        CheckAnnotationAnnotation(annos, modifiers)
        if (SeeingEnumConstructor(scopeKind)) {
            return ParseEnumConstructor(modifiers, annos)
        }
        if (Seeing(TokenKind.AT) || Seeing(TokenKind.AT_EXCL)) {
            return ParseMacroCallDeclInput(scopeKind, modifiers, annos)
        }
        if (SeeingFinalizer()) { return ParseFinalizer(scopeKind, modifiers, annos) }
        if (SeeingPrimaryConstructor(scopeKind)) { return ParsePrimaryConstructor(scopeKind, modifiers, annos) }
        if (Seeing(TokenKind.FUNC)) {
            let decl = ParseFuncDecl(scopeKind, modifiers, annos)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                decl.EnableAttr(Attribute.GLOBAL)
            }
            if (HasModifierToken(modifiers, TokenKind.CONST)) {
                decl.isConst = true
            }
            SetDeclBeginPos(decl)
            SetBeginToAnnotationsBegin(decl, annos)
            return decl
        }
        if (Seeing(TokenKind.MACRO)) {
            let decl = ParseMacroDecl(scopeKind, modifiers, annos)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                decl.EnableAttr(Attribute.GLOBAL)
            }
            return decl
        }
        if (Seeing(TokenKind.MAIN)) {
            let decl = ParseMainDecl(scopeKind, modifiers, annos)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                decl.EnableAttr(Attribute.GLOBAL)
            }
            return decl
        }
        if (Seeing(TokenKind.LET) || Seeing(TokenKind.VAR) || Seeing(TokenKind.CONST)) {
            let decl = ParseVarOrLet(scopeKind, modifiers, annos)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                decl.EnableAttr(Attribute.GLOBAL)
            }
            return decl
        }
        if (Seeing(TokenKind.CLASS)) {
            let decl = ParseClassDecl(scopeKind, modifiers, annos)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                decl.EnableAttr(Attribute.GLOBAL)
            }
            return decl
        }
        if (Seeing(TokenKind.INTERFACE)) {
            let decl = ParseInterfaceDecl(scopeKind, modifiers, annos)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                decl.EnableAttr(Attribute.GLOBAL)
            }
            return decl
        }
        if (Seeing(TokenKind.STRUCT)) {
            let decl = ParseStructDecl(scopeKind, modifiers, annos)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                decl.EnableAttr(Attribute.GLOBAL)
            }
            return decl
        }
        if (Seeing(TokenKind.ENUM)) {
            let decl = ParseEnumDecl(scopeKind, modifiers, annos)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                decl.EnableAttr(Attribute.GLOBAL)
            }
            return decl
        }
        if (Seeing(TokenKind.EXTEND)) {
            let decl = ParseExtendDecl(scopeKind, modifiers, annos)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                decl.EnableAttr(Attribute.GLOBAL)
            }
            return decl
        }
        if (Seeing(TokenKind.TYPE)) {
            let decl = ParseTypeAlias(scopeKind, modifiers, annos)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                decl.EnableAttr(Attribute.GLOBAL)
            }
            return decl
        }
        if (Seeing(TokenKind.PROP)) {
            let decl = ParsePropDecl(scopeKind, modifiers, annos)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                decl.EnableAttr(Attribute.GLOBAL)
            }
            return decl
        }
        if (Seeing(TokenKind.INIT)) {
            let decl = ParseConstructor(scopeKind, modifiers, annos)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                decl.EnableAttr(Attribute.GLOBAL)
            }
            return decl
        }
        if (SeeingConsumedConstModifier(modifiers)) {
            let decl = ParseConstVariable(scopeKind, modifiers, annos)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                decl.EnableAttr(Attribute.GLOBAL)
            }
            return decl
        }
        let ret = InvalidDecl(lookahead.Begin())
        DiagExpectedDeclaration(scopeKind)

        ret.EnableAttr(Attribute.IS_BROKEN)
        ImplementConsumeStrategy(scopeKind)
        SetBeginToAnnotationsBegin(ret, annos)
        ret.end = lastToken.End()
        return ret
    }

    private func CheckOverflowAnnotation(annos: ArrayList<Annotation>, scopeKind: ScopeKind): Unit {
        if (annos.isEmpty()) {
            return
        }
        if (SeeingAny([TokenKind.FUNC, TokenKind.MAIN, TokenKind.INIT, TokenKind.AT_EXCL]) || SeeingMacroCall()) {
            return
        }
        if (SeeingPrimaryConstructor(scopeKind)) {
            return
        }
        for (anno in annos) {
            if (anno.kind == AnnotationKind.NUMERIC_OVERFLOW) {
                DiagUnexpectedAnnoOn(anno, Peek().Begin(), anno.identifier.Val(), Peek().Value())
                anno.isBroken = true
                break
            }
        }
    }

    private func CheckAnnotationAnnotation(annos: ArrayList<Annotation>, modifiers: ArrayList<Modifier>): Unit {
        for (anno in annos) {
            if (anno.kind != AnnotationKind.ANNOTATION) {
                continue
            }
            if (!Seeing(TokenKind.CLASS) && !Seeing(TokenKind.AT)) {
                DiagUnexpectedAnnoOn(anno, Peek().Begin(), anno.identifier.Val(), Peek().Value())
                anno.isBroken = true
                return
            }
            for (modifier in modifiers) {
                if (modifier.modifier == TokenKind.ABSTRACT || modifier.modifier == TokenKind.OPEN ||
                    modifier.modifier == TokenKind.SEALED) {
                    DiagUnexpectedAnnoOn(anno, modifier.begin, anno.identifier.Val(), modifier.ToString())
                    anno.isBroken = true
                    return
                }
            }
        }
    }

    public func ParseFuncDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): FuncDecl {
        let ret = FuncDecl()
        try (cs = ChainScope(this, ret)) {
            ret.keywordPos = Peek().Begin()
            ret.begin = Peek().Begin()
            Next()
            var funcScopeKind = scopeKind
            if (forImport && ScopeKindEquals(funcScopeKind, ScopeKind.CLASS_BODY) &&
                HasModifierToken(modifiers, TokenKind.MUT)) {
                funcScopeKind = ScopeKind.INTERFACE_BODY
            }
            EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, funcScopeKind, DefKind.FUNC))
            if (ret.TestAttr(Attribute.OPERATOR)) {
                ret.identifier = ExpectOperatorIdentifier(ret)
            } else {
                ret.identifier = ExpectIdentifierWithPos(ret)
            }
            if (ret.identifier.Begin() == INVALID_POSITION) {
                ret.identifier.SetPos(Peek().Begin(), Peek().End())
            }
            for (modifier in modifiers) {
                ret.modifiers.add(modifier)
            }
            let body = ParseFuncBody(funcScopeKind)
            ret.funcBody = body
            let hasNoBody = body.body.isNone()
            let hasNoReturnType = body.retType.isNone()
            if (ret.TestAttr(Attribute.COMMON) && hasNoReturnType && hasNoBody) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_common_function_must_have_return_type, ret).Emit()
            }
            if (ret.TestAttr(Attribute.SPECIFIC) && hasNoReturnType && hasNoBody) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_specific_function_must_have_return_type, ret).Emit()
            }
            if (HasModifierToken(modifiers, TokenKind.UNSAFE) || HasModifierToken(modifiers, TokenKind.FOREIGN)) {
                SetUnsafe(ret, modifiers: modifiers)
            }
            let ffiParser = FFIParserImpl(this)
            ffiParser.CheckFuncSignature(ret, annos)
            ParseFuncDeclAnnos(annos, ret)
            CheckFuncBody(funcScopeKind, ret)
            if (let Some(funcBody) <- ret.funcBody) {
                ret.end = funcBody.end
                if (funcBody.paramLists.size > 1) {
                    ParseDiagnoseRefactor(
                        DiagKindRefactor.parse_expected_left_brace, funcBody.paramLists[1].begin, "(").Emit()
                }
                if (ret.identifier == "main" && !ret.identifier.IsRaw()) {
                    DiagIllegalFunc(ret)
                }
            }
            SetDefaultFunc(funcScopeKind, ret)
            if (!ScopeKindEquals(funcScopeKind, ScopeKind.CLASS_BODY) &&
                !ScopeKindEquals(funcScopeKind, ScopeKind.INTERFACE_BODY)) {
                ffiParser.CheckForeignNameAnnotation(ret)
            }
            if (!ScopeKindEquals(funcScopeKind, ScopeKind.CLASS_BODY)) {
                ffiParser.ObjC().CheckInitAnnotation(ret)
            }
        }
        return ret
    }

    private func ParseFuncDeclAnnos(annos: ArrayList<Annotation>, funcDecl: FuncDecl): Unit {
        for (anno in annos) {
            funcDecl.annotations.add(anno)
            if (anno.kind == AnnotationKind.JAVA) {
                funcDecl.EnableAttr(Attribute.JAVA_APP)
            }
            if (anno.kind == AnnotationKind.INTRINSIC) {
                CheckIntrinsicFunc(funcDecl)
                funcDecl.EnableAttr(Attribute.INTRINSIC)
            }
            if (anno.kind == AnnotationKind.NUMERIC_OVERFLOW) {
                funcDecl.EnableAttr(Attribute.NUMERIC_OVERFLOW)
                funcDecl.overflowStrategy = anno.overflowStrategy
            }
            if (anno.kind == AnnotationKind.FASTNATIVE) {
                funcDecl.isFastNative = true
            }
            @When[backend == "cjnative"]
            let isFrozenAnno = anno.kind == AnnotationKind.FROZEN
            @When[backend != "cjnative"]
            let isFrozenAnno = false
            if (isFrozenAnno) {
                funcDecl.isFrozen = true
            }
        }
    }

    private func CheckIntrinsicFunc(fd: Decl): Unit {
        for (intrinsic in intrinsics) {
            if (let Some(intrinsicDecl) <- (intrinsic as Decl)) {
                if (fd.identifier == intrinsicDecl.identifier) {
                    DiagDuplicatedIntrinsicFunc(fd, intrinsicDecl)
                    return
                }
            }
        }
        intrinsics.add(fd)
    }

    public func ParseMacroDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): MacroDecl {
        let ret = MacroDecl()
        try (cs = ChainScope(this, ret)) {
            ApplyModifiersAndAnnotations(ret, modifiers, annos)
            let keywordToken = Expect(TokenKind.MACRO, "expected 'macro'")
            ret.keywordPos = keywordToken.Begin()
            if (ret.begin.IsZero()) {
                ret.begin = keywordToken.Begin()
            }
            CheckDeclarationInScope(scopeKind, DefKind.MACRO)
            EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.MACRO))
            ret.EnableAttr(Attribute.MACRO_FUNC)
            ret.identifier = ExpectIdentifierWithPos(ret)
            if (IsBuiltinAnnotation(moduleName, ret.identifier.Val()) || IsBuiltinMacroDeclName(ret.identifier.Val())) {
                let builtinKind = if (IsBuiltinMacroDeclName(ret.identifier.Val())) { "macro" } else { "annotation" }
                ParseDiagnoseRefactor(
                    DiagKindRefactor.parse_macro_define_conflicted_with_builtin,
                    MakeRange(ret.identifier.Begin(), ret.identifier.End()),
                    ret.identifier.Val(),
                    builtinKind).Emit()
                ret.EnableAttr(Attribute.IS_BROKEN)
            }
            let body = ParseMacroBody(ret)
            ret.funcBody = body
            ret.end = body.end
            if (!ret.TestAttr(Attribute.PUBLIC) && !ret.TestAttr(Attribute.IS_BROKEN)) {
                DiagExpectPublicBeforeMacroCall(ret)
                ret.EnableAttr(Attribute.IS_BROKEN)
            }
            CheckMacroDeclPackage(ret)
        }
        return ret
    }

    private func ParseMacroBody(macroDecl: MacroDecl): FuncBody {
        let body = FuncBody()
        body.begin = Peek().Begin()
        body.paramLists.add(ParseMacroParameterList(macroDecl))
        if (Skip(TokenKind.COLON)) {
            body.colonPos = lastToken.Begin()
            body.retType = ParseType()
            if (let Some(retType) <- body.retType) {
                CheckMacroParamType(macroDecl, retType, true)
                body.end = retType.end
            }
        }
        if (body.retType.isNone()) {
            let retPos = if (lastToken.Begin() == INVALID_POSITION) { Peek().Begin() } else { lastToken.Begin() }
            body.retType = MakeTokensRefType(retPos)
        }
        if (Seeing(TokenKind.LCURL)) {
            body.body = ParseBlock(ScopeKind.MACRO_BODY)
            if (let Some(block) <- body.body) {
                body.end = block.end
            }
        } else {
            let invalidBlock = Block()
            invalidBlock.begin = lastToken.End()
            invalidBlock.end = lastToken.End()
            invalidBlock.isBroken = true
            body.body = invalidBlock
            body.end = invalidBlock.end
            DiagMissingBody("macro", if (!macroDecl.identifier.Valid()) { "" } else { " '" + macroDecl.identifier.Val() + "'" },
                Peek().End())
            macroDecl.EnableAttr(Attribute.IS_BROKEN)
        }
        return body
    }

    private func ParseMacroParameterList(macroDecl: MacroDecl): FuncParamList {
        let paramList = ParseParameterList(ScopeKind.MACRO_BODY)
        if (paramList.params.isEmpty() || paramList.params.size > 2) {
            let pos = if (paramList.params.isEmpty()) { paramList.begin } else { paramList.params[0].begin }
            let diagKind = if (paramList.params.isEmpty()) {
                DiagKindRefactor.parse_macro_unexpected_empty_parameter
            } else {
                DiagKindRefactor.parse_macro_expected_right_parameter_nums
            }
            ParseDiagnoseRefactor(diagKind, pos).Emit()
            macroDecl.EnableAttr(Attribute.IS_BROKEN)
        } else {
            for (param in paramList.params) {
                if (let Some(paramType) <- param.typeNode) {
                    CheckMacroParamType(macroDecl, paramType, false)
                } else {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_macro_illegal_param_type, lookahead).Emit()
                    macroDecl.EnableAttr(Attribute.IS_BROKEN)
                }
                if (param.isNamedParam) {
                    DiagMacroUnexpectNamedParam(param)
                    macroDecl.EnableAttr(Attribute.IS_BROKEN)
                }
            }
        }
        return paramList
    }

    private func CheckMacroParamType(macroDecl: MacroDecl, typeNode: Type, isReturnTy: Bool): Unit {
        if (IsTokensRefType(typeNode)) {
            return
        }
        if (isReturnTy) {
            DiagExpectMacroParamType(typeNode)
        } else {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_macro_illegal_param_type, typeNode).Emit()
        }
        macroDecl.EnableAttr(Attribute.IS_BROKEN)
    }

    private func IsTokensRefType(typeNode: Type): Bool {
        if (let Some(refType) <- (typeNode as RefType)) {
            return refType.ref.identifier.Val() == "Tokens" && refType.typeArguments.isEmpty()
        }
        return false
    }

    private func MakeTokensRefType(pos: Position): RefType {
        let typeNode = RefType()
        typeNode.begin = pos
        typeNode.end = pos
        typeNode.ref.identifier = SrcIdentifier("Tokens", "Tokens", pos, pos, false)
        return typeNode
    }

    private func CheckMacroDeclPackage(macroDecl: MacroDecl): Unit {
        if (let Some(file) <- currentFile) {
            var inMacroPackage = false
            if (let Some(pkg) <- file.packageSpec) {
                inMacroPackage = pkg.hasMacro
            }
            if (!inMacroPackage) {
                ParseDiagnoseRefactor(
                    DiagKindRefactor.parse_expected_macro_decl_define_in_macro_package,
                    MakeRange(macroDecl.identifier.Begin(), macroDecl.identifier.End())).Emit()
                macroDecl.EnableAttr(Attribute.IS_BROKEN)
            }
        }
    }

    private func IsBuiltinMacroDeclName(identifier: String): Bool {
        return identifier == "sourcePackage" || identifier == "sourceFile" || identifier == "sourceLine"
    }

    public func ParseMainDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): MainDecl {
        let ret = MainDecl()
        try (cs = ChainScope(this, ret)) {
            ApplyModifiersAndAnnotations(ret, modifiers, annos)
            let keywordToken = Expect(TokenKind.MAIN, "expected function keyword")
            ret.keywordPos = keywordToken.Begin()
            if (ret.begin.IsZero()) { ret.begin = keywordToken.Begin() }
            CheckDeclarationInScope(scopeKind, DefKind.MAIN)
            let body = ParseFuncBody(scopeKind)
            ret.funcBody = body
            ret.end = body.end
            ret.identifier = SrcIdentifier("main", "main", ret.keywordPos, ret.keywordPos + 4, false)
            EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.MAIN))
            if (ret.TestAttr(Attribute.UNSAFE)) {
                SetUnsafe(ret, modifiers: modifiers)
            }
        }
        return ret
    }

    public func ParseFuncLikeHeader(ret: FuncDecl, keyword: TokenKind, scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Unit {
        ApplyModifiersAndAnnotations(ret, modifiers, annos)
        EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.FUNC))
        if (HasModifierToken(modifiers, TokenKind.CONST)) {
            ret.isConst = true
        }
        let keywordToken = Expect(keyword, "expected function keyword")
        ret.keywordPos = keywordToken.Begin()
        if (ret.begin.IsZero()) { ret.begin = keywordToken.Begin() }
        if (keyword != TokenKind.MAIN) {
            if (ret.TestAttr(Attribute.OPERATOR)) {
                ret.identifier = ExpectOperatorIdentifier(ret)
            } else if (Skip(TokenKind.OPERATOR)) {
                ret.EnableAttr(Attribute.OPERATOR)
                ret.identifier = ExpectOperatorIdentifier(ret)
            } else {
                ret.identifier = ExpectIdentifierWithPos(ret)
            }
        }
        let body = ParseFuncBody(scopeKind)
        ret.funcBody = body
        if (HasModifierToken(modifiers, TokenKind.UNSAFE) || HasModifierToken(modifiers, TokenKind.FOREIGN)) {
            SetUnsafe(ret, modifiers: modifiers)
        }
        CheckFuncBody(scopeKind, ret)
        ret.end = body.end
    }

    private func CheckFuncBody(scopeKind: ScopeKind, decl: FuncDecl): Unit {
        if (let Some(funcBody) <- decl.funcBody) {
            if (let Some(_) <- funcBody.generic) {
                decl.EnableAttr(Attribute.GENERIC)
            }
        }
        if (decl.TestAttr(Attribute.INTRINSIC)) {
            if (!ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL) && !ScopeKindEquals(scopeKind, ScopeKind.UNKNOWN_SCOPE)) {
                ParseDiagnoseRefactor(
                    DiagKindRefactor.parse_intrinsic_function_must_be_toplevel,
                    MakeRange(decl.begin, lastToken.End())).Emit()
            }
            if (let Some(funcBody) <- decl.funcBody) {
                if (let Some(block) <- funcBody.body) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_intrinsic_function_cannot_have_body, block).Emit()
                }
            }
        }

        let inClassLikeScope = ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) ||
            ScopeKindEquals(scopeKind, ScopeKind.INTERFACE_BODY)
        if (let Some(funcBody) <- decl.funcBody) {
            if ((let None <- funcBody.body) && !parseDeclFile &&
                !ScopeKindEquals(scopeKind, ScopeKind.UNKNOWN_SCOPE) &&
                !decl.TestAnyAttr(Attribute.FOREIGN, Attribute.INTRINSIC, Attribute.OBJ_C_MIRROR)) {
                if (CanBeAbstract(decl, scopeKind)) {
                    decl.EnableAttr(Attribute.ABSTRACT)
                } else if (!funcBody.TestAttr(Attribute.HAS_BROKEN) && !inClassLikeScope &&
                    !decl.TestAttr(Attribute.COMMON)) {
                    DiagMissingBody(
                        "function",
                        if (!decl.identifier.Valid()) { "" } else { " '${decl.identifier.Val()}'" },
                        lastToken.End())
                }
            }
        }

        if (decl.TestAnyAttr(Attribute.FOREIGN)) {
            let funcBody = decl.funcBody.getOrThrow()
            if (decl.TestAttr(Attribute.GENERIC)) {
                if (let Some(generic) <- funcBody.generic) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_foreign_func_should_not_be_generic, generic).Emit()
                } else {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_foreign_func_should_not_be_generic, decl).Emit()
                }
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
            if (let None <- funcBody.retType) {
                var foreignPos = decl.keywordPos
                for (modifier in decl.modifiers) {
                    if (modifier.modifier == TokenKind.FOREIGN) {
                        foreignPos = modifier.begin
                        break
                    }
                }
                ParseDiagnoseRefactor(
                    DiagKindRefactor.parse_foreign_func_must_declare_return_type,
                    MakeRange(foreignPos, decl.keywordPos + 4)).Emit()
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
            if (let Some(block) <- funcBody.body) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_foreign_function_with_body, block).Emit()
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
        }
        CheckVariableParams(decl)
    }

    private func CheckInitCtorDeclBody(ctor: FuncDecl): Unit {
        let missingBody = match (ctor.funcBody) {
            case Some(funcBody) => funcBody.body.isNone()
            case None => true
        }
        if (missingBody &&
            !ctor.TestAnyAttr(Attribute.COMMON, Attribute.JAVA_MIRROR, Attribute.OBJ_C_MIRROR)) {
            DiagMissingBody("constructor", "", ctor.end)
            if (!parseDeclFile) {
                ctor.EnableAttr(Attribute.HAS_BROKEN)
            }
        }
    }

    func CheckConstructorBody(ctor: FuncDecl, scopeKind: ScopeKind, inMacro!: Bool = false): Unit {
        CJC_ASSERT(ctor.TestAttr(Attribute.CONSTRUCTOR))
        if (let Some(funcBody) <- ctor.funcBody) {
            if (let Some(retType) <- funcBody.retType) {
                ParseDiagnoseRefactor(
                    DiagKindRefactor.parse_invalid_return_type, retType, "constructor").Emit()
                ctor.EnableAttr(Attribute.HAS_BROKEN)
            }
        }
        let isInClassLike = ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) ||
            ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY)
        let missingBody = match (ctor.funcBody) {
            case Some(funcBody) => funcBody.body.isNone()
            case None => true
        }
        if ((!isInClassLike || inMacro) && missingBody && !ctor.TestAttr(Attribute.COMMON)) {
            DiagMissingBody("constructor", "", ctor.end)
            ctor.EnableAttr(Attribute.HAS_BROKEN)
        }
    }

    private func CanBeAbstract(decl: Decl, scopeKind: ScopeKind): Bool {
        match (decl.astKind) {
            case ASTKind.FUNC_DECL =>
                if (let Some(funcDecl) <- (decl as FuncDecl)) {
                    if (let Some(funcBody) <- funcDecl.funcBody) {
                        if (let Some(_) <- funcBody.body) {
                            return false
                        }
                    }
                }
            case ASTKind.PROP_DECL =>
                if (let Some(propDecl) <- (decl as PropDecl)) {
                    if (!propDecl.getters.isEmpty() || !propDecl.setters.isEmpty()) {
                        return false
                    }
                }
            case ASTKind.PRIMARY_CTOR_DECL =>
                if (let Some(primaryCtor) <- (decl as PrimaryCtorDecl)) {
                    if (primaryCtor.funcBody.isNone()) {
                        let primaryCtorBody = primaryCtor.funcBody.getOrThrow()
                        if (let Some(_) <- primaryCtorBody.body) {
                            return false
                        }
                    }
                }
            case _ => ()
        }
        if (ScopeKindEquals(scopeKind, ScopeKind.INTERFACE_BODY)) {
            return true
        }
        if (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) && !decl.TestAttr(Attribute.COMMON)) {
            return true
        }
        return false
    }

    private func CheckVariableParams(decl: FuncDecl): Unit {
        if (let None <- decl.funcBody) {
            return
        }
        let body = decl.funcBody.getOrThrow()
        if (body.paramLists.size != 1) {
            return
        }
        let paramList = body.paramLists[0]
        let params = paramList.params
        let ellipsis = TokenKindLiteral(TokenKind.ELLIPSIS)
        var varargIdx: Option<Int64> = None
        var index = 0
        while (index < params.size) {
            if (params[index].identifier.Val() == ellipsis) {
                decl.hasVariableLenArg = true
                decl.variadicArgIndex = UInt64(index)
                paramList.hasVariableLenArg = true
                paramList.variadicArgIndex = UInt64(index)

                if (!decl.TestAttr(Attribute.FOREIGN)) {
                    ParseDiagnoseRefactor(
                        DiagKindRefactor.parse_variable_length_parameter_only_in_the_foreign_function,
                        MakeRange(decl.keywordPos, decl.identifier.End())).Emit()
                    decl.EnableAttr(Attribute.IS_BROKEN)
                    break
                }

                if (index == 0) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_variable_length_parameter_can_not_be_first, params[index]).Emit()
                    decl.EnableAttr(Attribute.IS_BROKEN)
                } else if (index != params.size - 1) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_variable_length_parameter_must_in_the_end, params[index]).Emit()
                    decl.EnableAttr(Attribute.IS_BROKEN)
                } else {
                    varargIdx = Some(index)
                }
            }
            index++
        }
        if (let Some(idx) <- varargIdx) {
            params.remove(at: idx)
        }
    }

    private func SetDefaultFunc(scopeKind: ScopeKind, decl: Decl): Unit {
        if (!ScopeKindEquals(scopeKind, ScopeKind.INTERFACE_BODY)) {
            return
        }
        if (decl.astKind == ASTKind.FUNC_DECL) {
            let defaultFunc = !decl.TestAttr(Attribute.FOREIGN) && !decl.TestAttr(Attribute.ABSTRACT)
            if (defaultFunc) {
                decl.EnableAttr(Attribute.DEFAULT)
            }
        } else if (decl.astKind == ASTKind.PROP_DECL) {
            if (decl.TestAttr(Attribute.ABSTRACT)) {
                return
            }
            decl.EnableAttr(Attribute.DEFAULT)
            if (let Some(propDecl) <- (decl as PropDecl)) {
                for (setter in propDecl.setters) {
                    setter.EnableAttr(Attribute.DEFAULT)
                }
                for (getter in propDecl.getters) {
                    getter.EnableAttr(Attribute.DEFAULT)
                }
            }
        }
    }

    public func ExpectOperatorIdentifier(ret: FuncDecl): SrcIdentifier {
        let operatorToken = SkipAndReturnOverloadingOperator()
        if (operatorToken.kind == TokenKind.ILLEGAL) {
            DiagInvalidOverloadedOperator()
            Next()
            return SrcIdentifier("", "", Peek().Begin(), Peek().Begin(), false)
        }
        if (!Seeing(TokenKind.LPAREN) && !Seeing(TokenKind.LT)) {
            DiagExpectCharacter("'('")
            Next()
        }
        ret.op = operatorToken.kind
        return SrcIdentifier(operatorToken.Value(), operatorToken.Value(), operatorToken.Begin(), operatorToken.End(), false)
    }

    public func SkipAndReturnOverloadingOperator(): Token {
        if (Skip(TokenKind.RSHIFT)) {
            return lastToken
        }
        if (Skip(TokenKind.GE)) {
            return lastToken
        }
        if (SeeingCombinator([TokenKind.GT, TokenKind.GT])) {
            let start = Peek().Begin()
            SkipCombinator([TokenKind.GT, TokenKind.GT])
            return Token(TokenKind.RSHIFT, ">>", start, lastToken.End())
        }
        if (SeeingCombinator([TokenKind.GT, TokenKind.ASSIGN])) {
            let start = Peek().Begin()
            SkipCombinator([TokenKind.GT, TokenKind.ASSIGN])
            return Token(TokenKind.GE, ">=", start, lastToken.End())
        }
        if (Seeing([TokenKind.LSQUARE, TokenKind.RSQUARE])) {
            let start = Peek().Begin()
            Skip(TokenKind.LSQUARE)
            Skip(TokenKind.RSQUARE)
            return Token(TokenKind.LSQUARE, "[]", start, lastToken.End())
        }
        if (Seeing([TokenKind.LPAREN, TokenKind.RPAREN])) {
            let start = Peek().Begin()
            Skip(TokenKind.LPAREN)
            Skip(TokenKind.RPAREN)
            return Token(TokenKind.LPAREN, "()", start, lastToken.End())
        }
        if (SkipOperator()) {
            return lastToken
        }
        return Token(TokenKind.ILLEGAL)
    }

    public func SkipOperator(): Bool {
        return Skip(TokenKind.NOT) || Skip(TokenKind.ADD) || Skip(TokenKind.SUB) || Skip(TokenKind.EXP) ||
            Skip(TokenKind.MUL) || Skip(TokenKind.DIV) || Skip(TokenKind.MOD) || Skip(TokenKind.LSHIFT) ||
            Skip(TokenKind.LT) || Skip(TokenKind.LE) || Skip(TokenKind.GT) || Skip(TokenKind.EQUAL) ||
            Skip(TokenKind.NOTEQ) || Skip(TokenKind.BITAND) || Skip(TokenKind.BITXOR) || Skip(TokenKind.BITOR)
    }

    public func ParseFuncBody(scopeKind: ScopeKind): FuncBody {
        let body = FuncBody()
        body.begin = Peek().Begin()
        try (cs = ChainScope(this, body)) {
            if (let Some(generic) <- ParseOptionalGeneric()) {
                body.generic = generic
            }
            ParseFuncParameters(scopeKind, body)
            let paramsEnd = lastToken.End()
            if (ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_SETTER_BODY) ||
                ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_GETTER_BODY)) {
                ParsePropMemberBody(scopeKind, body)
                return body
            }
            if (Skip(TokenKind.COLON)) {
                body.colonPos = lastToken.Begin()
                // C++ anchor: cangjie_compiler/src/Parse/ParseDecl.cpp:2327-2341
                if (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) && Seeing(TokenKind.THISTYPE)) {
                    enableThis = true
                }
                body.retType = ParseType()
                if (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY)) {
                    enableThis = false
                }
            }
            var constraintsEnd = INVALID_POSITION
            for (constraint in ParseGenericConstraints()) {
                EnsureFuncBodyGeneric(body).genericConstraints.add(constraint)
                constraintsEnd = constraint.end
            }
            if (Seeing(TokenKind.LCURL)) {
                body.body = ParseBlock(ScopeKind.FUNC_BODY)
                if (let Some(block) <- body.body) { body.end = block.end }
            } else if (!constraintsEnd.IsZero()) {
                body.end = constraintsEnd
            } else if (let Some(retType) <- body.retType) {
                body.end = retType.end
            } else {
                body.end = paramsEnd
            }
        }
        return body
    }

    public func ParseFuncParameters(scopeKind: ScopeKind, body: FuncBody): Unit {
        if (Seeing(TokenKind.LPAREN)) {
            do {
                if (ScopeKindEquals(scopeKind, ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS) ||
                    ScopeKindEquals(scopeKind, ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT) ||
                    ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_SETTER_BODY) ||
                    ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_GETTER_BODY)) {
                    body.paramLists.add(ParseParameterList(scopeKind))
                } else {
                    body.paramLists.add(ParseParameterList(ScopeKind.UNKNOWN_SCOPE))
                }
            } while (Seeing(TokenKind.LPAREN))
        } else {
            let invalid = FuncParamList()
            invalid.EnableAttr(Attribute.IS_BROKEN)
            invalid.begin = Peek().Begin()
            invalid.end = Peek().Begin()
            body.paramLists.add(invalid)
            let kind = if (ScopeKindEquals(scopeKind, ScopeKind.MAIN_BODY)) {
                DiagKindRefactor.parse_expected_left_paren
            } else {
                DiagKindRefactor.parse_expected_lt_paren
            }
            ParseDiagnoseRefactor(kind, Peek(), ConvertToken(Peek())).Emit()
            body.EnableAttr(Attribute.HAS_BROKEN)
        }
    }

    private func EnsureFuncBodyGeneric(body: FuncBody): Generic {
        if (let Some(generic) <- body.generic) {
            return generic
        }
        let generic = Generic()
        body.generic = generic
        return generic
    }

    public func ParseParameterList(scopeKind: ScopeKind): FuncParamList {
        if (!Skip(TokenKind.LPAREN)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_paren, lookahead,
                ConvertToken(lookahead)).Emit()
            let invalid = FuncParamList()
            invalid.EnableAttr(Attribute.IS_BROKEN)
            invalid.begin = lookahead.Begin()
            invalid.end = lookahead.Begin()
            return invalid
        }
        let list = FuncParamList()
        try (cs = ChainScope(this, list)) {
            list.begin = lookahead.Begin()
            list.leftParenPos = lookahead.Begin()
            var namedParameter: Option<FuncParam> = None
            var memberParameter: Option<FuncParam> = None
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
                let parsed = ParseParamInParamList(scopeKind, namedParameter, memberParameter)
                let param = parsed[0]
                namedParameter = parsed[1]
                memberParameter = parsed[2]
                if (param.identifier.Val() == "...") {
                    list.hasVariableLenArg = true
                    list.variadicArgIndex = UInt64(list.params.size)
                }
                list.params.add(param)
                if (Skip(TokenKind.COMMA)) {
                    param.commaPos = lastToken.Begin()
                } else {
                    break
                }
            }
            if (!Skip(TokenKind.RPAREN)) {
                DiagExpectedRightDelimiter("(", list.leftParenPos)
                list.end = lookahead.End()
                list.EnableAttr(Attribute.IS_BROKEN)
                return list
            }
            if (ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_SETTER_BODY)) {
                if (list.params.isEmpty()) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_setter_must_contain_one_parameter, list.begin).Emit()
                } else if (list.params.size > 1) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_setter_can_only_accept_one_parameter,
                        list.params[1].begin).Emit()
                }
            }
            list.rightParenPos = lastToken.Begin()
            list.end = lastToken.End()
        }
        return list
    }

    public func ParseFuncParam(): FuncParam {
        return ParseFuncParam(ScopeKind.UNKNOWN_SCOPE)
    }

    public func ParseFuncParam(scopeKind: ScopeKind): FuncParam {
        let param = FuncParam()
        try (cs = ChainScope(this, param)) {
            ParseAnnotations(param.annotations)
            let mods = ArrayList<Modifier>()
            ParseModifiers(mods)
            for (modifier in mods) { param.modifiers.add(modifier) }
        let isPrimaryConstructor = ScopeKindEquals(scopeKind, ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS) ||
            ScopeKindEquals(scopeKind, ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT)
        var memberStart = INVALID_POSITION
        if (Skip(TokenKind.LET) || Skip(TokenKind.VAR)) {
            param.hasLetOrVar = true
            param.keywordPos = lastToken.Begin()
            if (isPrimaryConstructor) {
                param.isMemberParam = true
                param.isVar = lastToken.kind == TokenKind.VAR
                memberStart = lastToken.Begin()
            } else {
                ParseDiagnoseRefactor(
                    DiagKindRefactor.parse_expected_parameter_rp,
                    lastToken,
                    ConvertToken(lastToken)).Emit()
                param.EnableAttr(Attribute.IS_BROKEN)
            }
        }
        if (Skip(TokenKind.ELLIPSIS)) {
            param.identifier = SrcIdentifier("...", "...", lastToken.Begin(), lastToken.End(), false)
            param.begin = if (!param.modifiers.isEmpty()) { param.modifiers[0].begin } else { param.identifier.Begin() }
            param.end = param.identifier.End()
            return param
        }
        if (Skip(TokenKind.WILDCARD)) {
            if (param.hasLetOrVar) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_wildcard_can_not_be_used_as_member_name, lastToken).Emit()
                param.EnableAttr(Attribute.IS_BROKEN)
            }
            param.identifier = SrcIdentifier("_", "_", lastToken.Begin(), lastToken.End(), false)
        } else {
            param.identifier = ExpectIdentifierWithPos(param)
        }
        param.begin = if (!param.modifiers.isEmpty()) { param.modifiers[0].begin } else { param.identifier.Begin() }
        if (param.isMemberParam) {
            param.begin = memberStart
        }
        if (!ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_SETTER_BODY) &&
            !ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_GETTER_BODY) && Skip(TokenKind.NOT)) {
            if (param.identifier.Val() == "_") {
                let builder = ParseDiagnoseRefactor(
                    DiagKindRefactor.parse_expected_character,
                    lastToken,
                    "':'",
                    lastToken.Value())
                builder.AddMainHintArguments("':'")
                param.EnableAttr(Attribute.IS_BROKEN)
                builder.Emit()
            }
            param.notMarkPos = lastToken.Begin()
            param.isNamedParam = true
        }
        if (ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_SETTER_BODY) ||
            ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_GETTER_BODY)) {
            param.end = param.identifier.End()
            return param
        }
        if (!Skip(TokenKind.COLON)) {
            DiagExpectCharacter("':'")
            let invalidType = InvalidType(Peek().Begin())
            invalidType.isBroken = true
            param.typeNode = invalidType
            param.end = invalidType.end
            param.EnableAttr(Attribute.IS_BROKEN)
            return param
        } else {
            param.colonPos = lastToken.Begin()
            param.typeNode = ParseType()
        }
        if (Skip(TokenKind.ASSIGN)) {
            if (!param.isNamedParam) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_dot_lparen, lastToken, ConvertToken(lastToken)).Emit()
                param.EnableAttr(Attribute.IS_BROKEN)
            }
            param.assignPos = lastToken.Begin()
            param.assignment = ParseExpr()
        }
        if (Skip(TokenKind.ELLIPSIS)) {
            param.identifier = SrcIdentifier("...", "...", lastToken.Begin(), lastToken.End(), false)
        }
        param.end = if (let Some(expr) <- param.assignment) {
            expr.end
        } else if (let Some(ty) <- param.typeNode) {
            ty.end
        } else {
            param.identifier.End()
        }
        }
        return param
    }

    public func ParseParamInParamList(
        scopeKind: ScopeKind,
        meetNamedParameter: Option<FuncParam>,
        meetMemberParams: Option<FuncParam>
    ): (FuncParam, Option<FuncParam>, Option<FuncParam>) {
        if (SeeingMacroCallDecl() && !enableCustomAnno) {
            return (ParseMacroCall(scopeKind), meetNamedParameter, meetMemberParams)
        }
        let param = ParseFuncParam(scopeKind)
        var namedParameter = meetNamedParameter
        var memberParameter = meetMemberParams
        try (cs = ChainScope(this, param)) {
            if (let Some(firstNamed) <- meetNamedParameter) {
                if (!param.isNamedParam) {
                    DiagNamedParameterAfterUnnamed(param, firstNamed)
                }
            }
            if (let Some(firstMember) <- meetMemberParams) {
                if (!param.isMemberParam) {
                    DiagMemberParameterAfterRegular(param, firstMember)
                }
            }
            if (param.isNamedParam && namedParameter.isNone()) {
                namedParameter = param
            }
            if (param.isMemberParam && memberParameter.isNone()) {
                memberParameter = param
            }
            CheckModifierInParamList(scopeKind, param.modifiers, param.isMemberParam, param)
            if (Seeing(TokenKind.COMMA)) {
                param.commaPos = Peek().Begin()
            }
            SetDeclBeginPos(param)
            CheckDeprecationOfFuncParam(param)
        }
        return (param, namedParameter, memberParameter)
    }

    public func ParseVarOrLet(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Decl {
        let key = Peek()
        let isVar = key.kind == TokenKind.VAR
        let isConst = key.kind == TokenKind.CONST
        Next()
        if (SeeingVarWithPatternStart()) {
            return ParseVarWithPatternDecl(scopeKind, modifiers, annos, key, isVar, isConst)
        }
        if (SeeingIdentifierLike()) {
            return ParseVarDecl(scopeKind, modifiers, annos, key, isVar, isConst)
        }
        DiagExpectedIdentifierOrPattern(isVar, key.Begin(), isConst)
        ConsumeUntil(TokenKind.NL)
        return InvalidDecl(key.Begin())
    }

    private func ParseConstVariable(
        scopeKind: ScopeKind,
        modifiers: ArrayList<Modifier>,
        annos: ArrayList<Annotation>
    ): Decl {
        let key = lastToken
        if (SeeingVarWithPatternStart()) {
            return ParseVarWithPatternDecl(scopeKind, modifiers, annos, key, false, true)
        }
        if (SeeingIdentifierLike()) {
            return ParseVarDecl(scopeKind, modifiers, annos, key, false, true)
        }
        DiagExpectedIdentifierOrPattern(false, key.Begin(), true)
        ConsumeUntil(TokenKind.NL)
        return InvalidDecl(key.Begin())
    }

    private func SeeingVarWithPatternStart(): Bool {
        return Seeing(TokenKind.WILDCARD) || Seeing(TokenKind.LPAREN) ||
            SeeingIdentifierAndTargetOp([TokenKind.LPAREN, TokenKind.DOT, TokenKind.LT])
    }

    private func CheckDeclarationInScope(sk: ScopeKind, dk: DefKind): Unit {
        if (ScopeKindEquals(sk, ScopeKind.UNKNOWN_SCOPE)) {
            return
        }
        if (!HasScopeRules(dk, sk)) {
            let node = chainedAST[chainedAST.size - 1]
            if (!node.TestAttr(Attribute.HAS_BROKEN)) {
                DiagUnexpectedDeclInScope(sk)
                node.EnableAttr(Attribute.HAS_BROKEN)
            }
        }
    }

    private func ParseVarDecl(
        scopeKind: ScopeKind,
        modifiers: ArrayList<Modifier>,
        annos: ArrayList<Annotation>,
        key: Token,
        isVar: Bool,
        isConst: Bool
    ): VarDecl {
        let decl = VarDecl()
        try (cs = ChainScope(this, decl)) {
            ApplyModifiersAndAnnotations(decl, modifiers, annos)
            decl.begin = if (decl.begin.IsZero()) { key.Begin() } else { decl.begin }
            decl.isVar = isVar
            decl.isConst = isConst
            decl.keywordPos = key.Begin()
            CheckDeclarationInScope(scopeKind, DefKind.VARIABLE)
            decl.identifier = ExpectIdentifierWithPos(decl)
            ParseTypeAndExpr(decl)
            CheckVarDeclShape(decl, modifiers, scopeKind, key)
            if (HasModifierToken(modifiers, TokenKind.UNSAFE) || HasModifierToken(modifiers, TokenKind.FOREIGN)) {
                SetUnsafe(decl, modifiers: modifiers)
            }
        }
        return decl
    }

    private func ParseVarWithPatternDecl(
        scopeKind: ScopeKind,
        modifiers: ArrayList<Modifier>,
        annos: ArrayList<Annotation>,
        key: Token,
        isVar: Bool,
        isConst: Bool
    ): VarWithPatternDecl {
        let decl = VarWithPatternDecl()
        try (cs = ChainScope(this, decl)) {
            let pattern = ParsePattern(ArrayList<Attribute>(), isVar, true)
            ApplyModifiersAndAnnotations(decl, modifiers, annos)
            decl.keywordPos = key.Begin()
            decl.irrefutablePattern = pattern
            decl.isVar = isVar
            decl.isConst = isConst
            decl.begin = if (decl.begin.IsZero()) { key.Begin() } else { decl.begin }
            ParseTypeAndExpr(decl)
            if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
                let setGlobalAttr = { node: Node =>
                    node.EnableAttr(Attribute.GLOBAL)
                    VisitAction.WALK_CHILDREN
                }
                Walker(pattern, visitPre: setGlobalAttr).Walk()
            }
            if (decl.end.IsZero()) {
                decl.end = pattern.end
            }
            if ((pattern.astKind == ASTKind.TUPLE_PATTERN || pattern.astKind == ASTKind.ENUM_PATTERN ||
                    pattern.astKind == ASTKind.WILDCARD_PATTERN) &&
                (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) ||
                    ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY))) {
                DiagParseIllegalDeclarationPattern(decl, scopeKind)
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
            CheckVarDeclShape(decl, modifiers, scopeKind, key)
            if (HasModifierToken(modifiers, TokenKind.UNSAFE) || HasModifierToken(modifiers, TokenKind.FOREIGN)) {
                SetUnsafe(decl, modifiers: modifiers)
            }
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
        } else if (!ret.identifier.Empty()) {
            ret.identifier.End()
        } else {
            ret.end
        }
    }

    private func CheckVarDeclShape(
        decl: VarDeclAbstract,
        modifiers: ArrayList<Modifier>,
        scopeKind: ScopeKind,
        key: Token
    ): Unit {
        EnableModifierAttrs(decl, CheckDeclModifiers(modifiers, scopeKind, DefKind.VARIABLE))
        if (!decl.isConst && HasModifierToken(modifiers, TokenKind.CONST)) {
            DiagUnExpectedModifierOnDeclaration(decl)
            decl.EnableAttr(Attribute.IS_BROKEN)
        } else if (decl.astKind == ASTKind.VAR_DECL && decl.isConst &&
            (ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) || ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY)) &&
            !HasModifierToken(modifiers, TokenKind.STATIC)) {
            DiagConstVariableExpectedStatic(key)
            decl.EnableAttr(Attribute.IS_BROKEN)
        } else if (decl.isConst && (let None <- decl.initializer)) {
            DiagConstVariableExpectedInitializer(decl)
            decl.EnableAttr(Attribute.IS_BROKEN)
        } else if (!decl.isConst && !ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL) &&
            (let None <- decl.typeNode) && (let None <- decl.initializer)) {
            if (decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
                DiagExpectedTypeOrInitializerInPattern(decl)
            } else {
                DiagExpectedOneOfTypeOrInitializer(decl, decl.identifier.Val())
            }
            decl.EnableAttr(Attribute.IS_BROKEN)
        } else if (!decl.isConst && ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL) && (let None <- decl.initializer) &&
            !HasModifierToken(modifiers, TokenKind.FOREIGN) &&
            ((let None <- decl.typeNode) || !HasModifierToken(modifiers, TokenKind.COMMON))) {
            DiagExpectedInitializerForToplevelVar(decl)
            decl.EnableAttr(Attribute.IS_BROKEN)
        }
    }

    private func HasModifierToken(modifiers: ArrayList<Modifier>, tokenKind: TokenKind): Bool {
        for (modifier in modifiers) {
            if (modifier.modifier == tokenKind) {
                return true
            }
        }
        return false
    }

    private func SeeingConsumedConstModifier(modifiers: ArrayList<Modifier>): Bool {
        return HasModifierToken(modifiers, TokenKind.CONST) && lastToken.kind == TokenKind.CONST
    }

    public func ParseClassDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): ClassDecl {
        let ret = ClassDecl()
        try (cs = ChainScope(this, ret)) {
            ParseInheritableHeader(ret, TokenKind.CLASS, modifiers, annos)
            CheckDeclarationInScope(scopeKind, DefKind.CLASS)
            EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.CLASS))
            SetPrimaryDecl(ret.identifier.Val(), isRawId: ret.identifier.IsRaw())
            ParseClassLikeBody(ret, ScopeKind.CLASS_BODY)
            RevertPrimaryDecl()
        }
        return ret
    }

    public func ParseInterfaceDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): InterfaceDecl {
        let ret = InterfaceDecl()
        try (cs = ChainScope(this, ret)) {
            ParseInheritableHeader(ret, TokenKind.INTERFACE, modifiers, annos)
            CheckDeclarationInScope(scopeKind, DefKind.INTERFACE)
            EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.INTERFACE))
            ParseClassLikeBody(ret, ScopeKind.INTERFACE_BODY)
        }
        return ret
    }

    public func ParseStructDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): StructDecl {
        let ret = StructDecl()
        try (cs = ChainScope(this, ret)) {
            ParseInheritableHeader(ret, TokenKind.STRUCT, modifiers, annos)
            CheckDeclarationInScope(scopeKind, DefKind.STRUCT)
            EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.STRUCT))
            SetPrimaryDecl(ret.identifier.Val(), isRawId: ret.identifier.IsRaw())
            ParseClassLikeBody(ret, ScopeKind.STRUCT_BODY)
            RevertPrimaryDecl()
        }
        return ret
    }

    public func ParseEnumDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): EnumDecl {
        let ret = EnumDecl()
        try (cs = ChainScope(this, ret)) {
            ParseInheritableHeader(ret, TokenKind.ENUM, modifiers, annos)
            CheckDeclarationInScope(scopeKind, DefKind.ENUM)
            EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.ENUM))
            if (Skip(TokenKind.LCURL)) {
                ret.leftCurlPos = lastToken.Begin()
                ret.bodyScope = DummyBody()
                if (let Some(bodyScope) <- ret.bodyScope) {
                    bodyScope.begin = ret.leftCurlPos
                }
                if (Seeing(TokenKind.BITOR)) {
                    Next()
                }
                do {
                    if (lastToken.kind == TokenKind.BITOR) {
                        ret.bitOrPosVector.add(lastToken.Begin())
                    }
                    let seeingEllipse = Seeing(TokenKind.ELLIPSIS)
                    if ((!seeingEllipse && !Seeing(TokenKind.IDENTIFIER) && !SeeingMacroCallDecl() &&
                        !SeeingContextualKeyword() && !SeeingAtWhen()) || SeeingKeywordWithDecl()) {
                        if (!ret.TestAttr(Attribute.IS_BROKEN)) {
                            DiagExpectedIdentifierEnumDecl(ret)
                        }
                        TryConsumeUntilAny([TokenKind.BITOR])
                        ret.EnableAttr(Attribute.IS_BROKEN)
                    } else if (seeingEllipse) {
                        Next()
                        if (ret.constructors.isEmpty()) {
                            DiagExpectedIdentifierEnumDecl(ret)
                        }
                        ret.hasEllipsis = true
                        ret.ellipsisPos = lastToken.Begin()
                        break
                    } else {
                        ParseCaseBody(ret)
                    }
                    SkipBlank(TokenKind.SEMI)
                } while (Skip(TokenKind.BITOR))
                while (true) {
                    SkipBlank(TokenKind.SEMI)
                    if (Skip(TokenKind.RCURL)) {
                        ret.rightCurlPos = lastToken.Begin()
                        break
                    }
                    if (DetectPrematureEnd()) {
                        DiagExpectedRightDelimiter("{", ret.leftCurlPos)
                        break
                    }
                    let member = ParseDecl(ScopeKind.ENUM_BODY)
                    if (member.IsInvalid()) {
                        continue
                    }
                    if (member.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_decl,
                            MakeRange(member.identifier.Begin(), member.identifier.End()), member.identifier.Val()).Emit()
                    }
                    SetMemberParentInheritableDecl(ret, member)
                    ret.members.add(member)
                }
                ret.end = ret.rightCurlPos + 1
            }
        }
        return ret
    }

    public func ParseCaseBody(enumDecl: EnumDecl): Unit {
        let caseBody = ParseDecl(ScopeKind.ENUM_CONSTRUCTOR)
        if (caseBody.astKind == ASTKind.FUNC_DECL) {
            enumDecl.hasArguments = true
        }
        if (!caseBody.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_unknown_enum_constructor, caseBody).Emit()
        }
        SetMemberParentInheritableDecl(enumDecl, caseBody)
        if (enumDecl.TestAttr(Attribute.SPECIFIC)) {
            caseBody.EnableAttr(Attribute.SPECIFIC)
        } else if (enumDecl.TestAttr(Attribute.COMMON)) {
            caseBody.EnableAttr(Attribute.COMMON)
        }
        enumDecl.constructors.add(caseBody)
    }

    public func SetMemberParentInheritableDecl(ret: InheritableDecl, decl: Decl): Unit {
        decl.outerDecl = ret
        if (let Some(macroExpandDecl) <- (decl as MacroExpandDecl)) {
            if (let Some(inputDecl) <- macroExpandDecl.invocation.decl) {
                SetMemberParentInheritableDecl(ret, inputDecl)
            }
        } else if (let Some(primaryCtorDecl) <- (decl as PrimaryCtorDecl)) {
            if (let Some(funcBody) <- primaryCtorDecl.funcBody) {
                if (!funcBody.paramLists.isEmpty()) {
                    for (param in funcBody.paramLists[0].params) {
                        if (param.isMemberParam) {
                            param.outerDecl = ret
                        }
                    }
                }
            }
        } else if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(funcBody) <- funcDecl.funcBody) {
                if (ret.IsClassLikeDecl()) {
                    if (let Some(classLikeDecl) <- (ret as ClassLikeDecl)) {
                        funcBody.parentClassLike = classLikeDecl
                    }
                } else if (let Some(enumDecl) <- (ret as EnumDecl)) {
                    funcBody.parentEnum = enumDecl
                }
            }
        }
    }

    public func ParseEnumConstructor(modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): Decl {
        let identifier = ExpectIdentifierWithPos(Node())
        let decl: Decl = if (Skip(TokenKind.LPAREN)) {
            let funcDecl = FuncDecl()
            ApplyModifiersAndAnnotations(funcDecl, modifiers, annos)
            funcDecl.EnableAttr(Attribute.ENUM_CONSTRUCTOR)
            funcDecl.identifier = identifier
            funcDecl.begin = if (funcDecl.begin.IsZero()) { identifier.Begin() } else { funcDecl.begin }
            let paramList = FuncParamList()
            paramList.leftParenPos = lastToken.Begin()
            paramList.begin = paramList.leftParenPos
            var index: Int64 = 1
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
                let param = FuncParam()
                let ty = ParseType()
                param.identifier = SrcIdentifier("p${index}", "p${index}", ty.begin, ty.begin, false)
                param.isIdentifierCompilerAdd = true
                param.typeNode = ty
                param.begin = ty.begin
                param.end = ty.end
                paramList.params.add(param)
                index++
                if (!Skip(TokenKind.COMMA)) { break }
            }
            paramList.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after enum constructor").Begin()
            paramList.end = paramList.rightParenPos + 1
            let body = FuncBody()
            body.begin = paramList.begin
            body.paramLists.add(paramList)
            body.end = paramList.end
            funcDecl.funcBody = body
            funcDecl.end = body.end
            funcDecl
        } else {
            let varDecl = VarDecl()
            ApplyModifiersAndAnnotations(varDecl, modifiers, annos)
            varDecl.EnableAttr(Attribute.ENUM_CONSTRUCTOR)
            varDecl.identifier = identifier
            varDecl.begin = if (varDecl.begin.IsZero()) { varDecl.identifier.Begin() } else { varDecl.begin }
            varDecl.end = varDecl.identifier.End()
            varDecl
        }
        try (cs = ChainScope(this, decl)) {
            if (!modifiers.isEmpty()) {
                let firstMod = SortModifierByPos(modifiers)[0]
                DiagExpectNoModifier(firstMod)
            }
            for (anno in annos) {
                if (anno.kind != AnnotationKind.WHEN && anno.kind != AnnotationKind.DEPRECATED) {
                    DiagUnexpectedAnnoOn(annos[0], identifier.Begin(), annos[0].identifier.Val(), identifier.Val())
                }
            }
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
        if (Skip(TokenKind.UPPERBOUND)) {
            ParseInheritedTypes(ret)
        }
        for (constraint in ParseGenericConstraints()) {
            EnsureDeclGeneric(ret).genericConstraints.add(constraint)
        }
        ret.end = ret.identifier.End()
    }

    public func ParseInheritedTypes(decl: InheritableDecl): Unit {
        decl.upperBoundPos = lastToken.Begin()
        while (true) {
            let inheritedType = ParseType()
            if (IsValidInheritedType(inheritedType)) {
                decl.inheritedTypes.add(inheritedType)
            } else if (!inheritedType.TestAttr(Attribute.IS_BROKEN)) {
                DiagInvalidInheritType(inheritedType)
            }
            if (!Skip(TokenKind.BITAND)) {
                break
            }
            if (!decl.inheritedTypes.isEmpty()) {
                decl.inheritedTypes[decl.inheritedTypes.size - 1].bitAndPos = lastToken.Begin()
            }
        }
    }

    private func IsValidInheritedType(ty: Type): Bool {
        return ty.astKind == ASTKind.REF_TYPE || ty.astKind == ASTKind.QUALIFIED_TYPE
    }

    private func EnsureDeclGeneric(decl: Decl): Generic {
        if (let Some(generic) <- decl.generic) {
            return generic
        }
        let generic = Generic()
        decl.generic = generic
        return generic
    }

    public func ParseClassLikeBody(ret: InheritableDecl, scopeKind: ScopeKind): Unit {
        if (!Skip(TokenKind.LCURL)) {
            if (let Some(classDecl) <- (ret as ClassDecl)) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_brace, lookahead,
                    ConvertToken(lookahead)).Emit()
                ConsumeUntilDecl(TokenKind.LCURL)
                Skip(TokenKind.LCURL)
                let body = ClassBody()
                body.EnableAttr(Attribute.HAS_BROKEN)
                body.EnableAttr(Attribute.IS_BROKEN)
                classDecl.body = body
            } else if (let Some(interfaceDecl) <- (ret as InterfaceDecl)) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_brace, lookahead,
                    ConvertToken(lookahead)).Emit()
                let body = InterfaceBody()
                body.EnableAttr(Attribute.IS_BROKEN)
                body.begin = lastToken.End()
                body.end = lastToken.End()
                interfaceDecl.body = body
            } else if (let Some(structDecl) <- (ret as StructDecl)) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_brace, lookahead,
                    ConvertToken(lookahead)).Emit()
                let body = StructBody()
                body.EnableAttr(Attribute.IS_BROKEN)
                body.begin = lastToken.End()
                body.end = lastToken.End()
                structDecl.body = body
            } else if (let Some(extendDecl) <- (ret as ExtendDecl)) {
                DiagExpectCharacter("'{'", noteStr: "extend declaration must have body")
                extendDecl.EnableAttr(Attribute.HAS_BROKEN)
            }
            return
        }
        let leftCurl = lastToken.Begin()
        SetDeclBodyLeftCurl(ret, leftCurl)
        while (true) {
            if (let Some(classDecl) <- (ret as ClassDecl)) {
                if (CheckSkipRcurOrPrematureEnd(classDecl.body.getOrThrow())) {
                    break
                }
            } else if (let Some(interfaceDecl) <- (ret as InterfaceDecl)) {
                if (CheckSkipRcurOrPrematureEnd(interfaceDecl.body.getOrThrow())) {
                    break
                }
            } else if (let Some(structDecl) <- (ret as StructDecl)) {
                if (CheckSkipRcurOrPrematureEnd(structDecl.body.getOrThrow())) {
                    break
                }
            } else if (let Some(extendDecl) <- (ret as ExtendDecl)) {
                if (Skip(TokenKind.RCURL)) {
                    extendDecl.rightCurlPos = lastToken.Begin()
                    break
                }
                if (DetectPrematureEnd()) {
                    extendDecl.EnableAttr(Attribute.IS_BROKEN)
                    DiagExpectedRightDelimiter("{", extendDecl.leftCurlPos)
                    break
                }
            }
            let member = ParseDecl(scopeKind)
            if (let Some(ctor) <- (member as FuncDecl)) {
                if (ctor.TestAttr(Attribute.CONSTRUCTOR)) {
                    if (let Some(classDecl) <- (ret as ClassDecl)) {
                        if (classDecl.TestAttr(Attribute.JAVA_MIRROR)) {
                            ctor.EnableAttr(Attribute.JAVA_MIRROR)
                        }
                        if (classDecl.TestAttr(Attribute.OBJ_C_MIRROR)) {
                            ctor.EnableAttr(Attribute.OBJ_C_MIRROR)
                        }
                        CheckInitCtorDeclBody(ctor)
                    } else if (let Some(structDecl) <- (ret as StructDecl)) {
                        if (structDecl.TestAttr(Attribute.JAVA_MIRROR)) {
                            ctor.EnableAttr(Attribute.JAVA_MIRROR)
                        }
                        CheckInitCtorDeclBody(ctor)
                    }
                }
            }
            if (!member.IsInvalid()) {
                member.outerDecl = ret
                if ((ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) ||
                    ScopeKindEquals(scopeKind, ScopeKind.INTERFACE_BODY)) &&
                    (let Some(propDecl) <- (member as PropDecl))) {
                    CheckClassLikePropAbstractness(propDecl)
                }
                AddBodyMember(ret, member)
            }
            SkipNLOrSemi()
        }
        if (let Some(classDecl) <- (ret as ClassDecl)) {
            classDecl.body.getOrThrow().end = lastToken.End()
        } else if (let Some(interfaceDecl) <- (ret as InterfaceDecl)) {
            let body = interfaceDecl.body.getOrThrow()
            body.end = body.rightCurlPos + 1
        } else if (let Some(structDecl) <- (ret as StructDecl)) {
            let body = structDecl.body.getOrThrow()
            body.rightCurlPos = lastToken.Begin()
            body.end = lastToken.End()
        } else if (let Some(extendDecl) <- (ret as ExtendDecl)) {
            extendDecl.end = lastToken.End()
        }
    }

    private func CheckSkipRcurOrPrematureEnd(ret: ClassBody): Bool {
        if (Skip(TokenKind.RCURL)) {
            ret.rightCurlPos = lastToken.Begin()
            return true
        }
        if (DetectPrematureEnd() && !ret.TestAttr(Attribute.HAS_BROKEN)) {
            ret.EnableAttr(Attribute.IS_BROKEN)
            DiagExpectedRightDelimiter("{", ret.leftCurlPos)
            return true
        }
        return false
    }

    private func CheckSkipRcurOrPrematureEnd(ret: InterfaceBody): Bool {
        if (Skip(TokenKind.RCURL)) {
            ret.rightCurlPos = lastToken.Begin()
            return true
        }
        if (DetectPrematureEnd() && !ret.TestAttr(Attribute.HAS_BROKEN)) {
            ret.EnableAttr(Attribute.IS_BROKEN)
            DiagExpectedRightDelimiter("{", ret.leftCurlPos)
            return true
        }
        return false
    }

    private func CheckSkipRcurOrPrematureEnd(ret: StructBody): Bool {
        if (Skip(TokenKind.RCURL)) {
            ret.rightCurlPos = lastToken.Begin()
            return true
        }
        if (DetectPrematureEnd() && !ret.TestAttr(Attribute.HAS_BROKEN)) {
            ret.EnableAttr(Attribute.IS_BROKEN)
            DiagExpectedRightDelimiter("{", ret.leftCurlPos)
            return true
        }
        return false
    }

    private func SetDeclBodyLeftCurl(ret: InheritableDecl, pos: Position): Unit {
        if (let Some(classDecl) <- (ret as ClassDecl)) {
            let body = ClassBody()
            body.leftCurlPos = pos
            body.begin = pos
            classDecl.body = body
        } else if (let Some(interfaceDecl) <- (ret as InterfaceDecl)) {
            let body = InterfaceBody()
            body.leftCurlPos = pos
            body.begin = pos
            interfaceDecl.body = body
        } else if (let Some(structDecl) <- (ret as StructDecl)) {
            let body = StructBody()
            body.leftCurlPos = pos
            body.begin = pos
            structDecl.body = body
        } else if (let Some(extendDecl) <- (ret as ExtendDecl)) {
            extendDecl.leftCurlPos = pos
        }
    }

    private func AddBodyMember(ret: InheritableDecl, member: Decl): Unit {
        if (let Some(classDecl) <- (ret as ClassDecl)) {
            if (let Some(body) <- classDecl.body) {
                body.decls.add(member)
            }
        } else if (let Some(interfaceDecl) <- (ret as InterfaceDecl)) {
            if (let Some(body) <- interfaceDecl.body) {
                body.decls.add(member)
            }
        } else if (let Some(structDecl) <- (ret as StructDecl)) {
            if (let Some(body) <- structDecl.body) {
                body.decls.add(member)
            }
        } else if (let Some(extendDecl) <- (ret as ExtendDecl)) {
            extendDecl.members.add(member)
        }
    }

    public func ParseExtendDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): ExtendDecl {
        let ret = ExtendDecl()
        try (cs = ChainScope(this, ret)) {
            ApplyModifiersAndAnnotations(ret, modifiers, annos)
            let key = Expect(TokenKind.EXTEND, "expected 'extend'")
            ret.keywordPos = key.Begin()
            ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
            CheckDeclarationInScope(scopeKind, DefKind.EXTEND)
            EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.EXTEND))
            ParseExtendedType(ret)
            if (Skip(TokenKind.UPPERBOUND)) {
                ParseInheritedTypes(ret)
            }
            for (constraint in ParseGenericConstraints()) {
                EnsureDeclGeneric(ret).genericConstraints.add(constraint)
            }
            ParseClassLikeBody(ret, ScopeKind.EXTEND_BODY)
        }
        return ret
    }

    // C++ anchor: cangjie_compiler/src/Parse/Parser.cpp:505-516
    private func ParseExtendedType(extendDecl: ExtendDecl): Unit {
        if (let Some(generic) <- ParseOptionalGeneric()) {
            extendDecl.EnableAttr(Attribute.GENERIC)
            extendDecl.generic = generic
        }
        let extendedType = ParseType()
        extendDecl.extendedType = extendedType
        if (extendedType.astKind == ASTKind.PAREN_TYPE) {
            DiagUnexpectedTypeIn(extendedType, extendDecl.keywordPos, "extend",
                "Extend declaration cannot extend paren type")
        }
    }

    public func ParseTypeAlias(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): TypeAliasDecl {
        let ret = TypeAliasDecl()
        try (cs = ChainScope(this, ret)) {
            ApplyModifiersAndAnnotations(ret, modifiers, annos)
            let key = Expect(TokenKind.TYPE, "expected 'type'")
            ret.keywordPos = key.Begin()
            ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
            CheckDeclarationInScope(scopeKind, DefKind.TYPE)
            EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.TYPE))
            while (SeeingOperator()) {
                DiagExpectedName("type", "after 'type'")
                Next()
            }
            ret.identifier = ExpectIdentifierWithPos(ret)
            if (let Some(generic) <- ParseOptionalGeneric()) { ret.generic = generic }
            ret.assignPos = Expect(TokenKind.ASSIGN, "expected '=' in type alias").Begin()
            ret.typeNode = ParseType()
            ret.end = if (let Some(ty) <- ret.typeNode) { ty.end } else { ret.identifier.End() }
        }
        return ret
    }

    public func ParsePropDecl(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): PropDecl {
        let ret = PropDecl()
        try (cs = ChainScope(this, ret)) {
            ApplyModifiersAndAnnotations(ret, modifiers, annos)
            let key = Expect(TokenKind.PROP, "expected 'prop'")
            ret.keywordPos = key.Begin()
            ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
            CheckDeclarationInScope(scopeKind, DefKind.PROPERTY)
            ret.identifier = ExpectIdentifierWithPos(ret)
            if (Skip(TokenKind.COLON)) {
                ret.colonPos = lastToken.Begin()
                ret.typeNode = ParseType()
            }
            EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.PROPERTY))
            if (ret.TestAttr(Attribute.MUT)) {
                ret.isVar = true
            }
            if (Skip(TokenKind.ASSIGN)) {
                ret.assignPos = lastToken.Begin()
                ret.initializer = ParseExpr(ExprKind.VAR_INIT)
            }
            let inClassLikeScope = ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY) ||
                ScopeKindEquals(scopeKind, ScopeKind.INTERFACE_BODY)
            if (Skip(TokenKind.LCURL)) {
                ParsePropBody(modifiers, ret)
            } else if (inClassLikeScope || ScopeKindEquals(scopeKind, ScopeKind.UNKNOWN_SCOPE) ||
                ret.TestAttr(Attribute.COMMON)) {
                if (CanBeAbstract(ret, scopeKind)) {
                    ret.EnableAttr(Attribute.ABSTRACT)
                }
                if (let Some(typeNode) <- ret.typeNode) {
                    ret.end = typeNode.end
                }
            } else {
                if (!parseDeclFile) {
                    let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character, Peek(), "'{'",
                        ConvertToken(Peek()))
                    builder.AddMainHintArguments("'{'")
                    builder.AddNote("property declaration must have body")
                    builder.Emit()
                    ret.EnableAttr(Attribute.HAS_BROKEN)
                }
                ret.end = if (let Some(expr) <- ret.initializer) {
                    expr.end
                } else if (let Some(ty) <- ret.typeNode) {
                    ty.end
                } else {
                    ret.identifier.End()
                }
            }
        }
        return ret
    }

    // C++ anchor: cangjie_compiler/src/Parse/Parser.cpp:444-490
    private func CheckClassLikePropAbstractness(property: PropDecl): Unit {
        let outerDecl = property.outerDecl.getOrThrow()
        if (outerDecl.TestAttr(Attribute.JAVA_MIRROR)) {
            property.DisableAttr(Attribute.ABSTRACT)
            return
        }
        let isJavaMirrorOrJavaMirrorSubtype =
            outerDecl.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)
        let isCommon = property.TestAttr(Attribute.COMMON)
        let outerModifiers = outerDecl.modifiers
        let inAbstract = HasModifierToken(outerModifiers, TokenKind.ABSTRACT)
        let inCJMP = HasModifierToken(outerModifiers, TokenKind.SPECIFIC) ||
            HasModifierToken(outerModifiers, TokenKind.COMMON)
        let inAbstractCJMP = inAbstract && inCJMP
        let inClass = outerDecl.astKind == ASTKind.CLASS_DECL
        let inAbstractCJMPClass = inAbstractCJMP && inClass
        let inObjCMirror = outerDecl.TestAttr(Attribute.OBJ_C_MIRROR)

        if (HasModifierToken(property.modifiers, TokenKind.ABSTRACT) && !isCommon && !inAbstractCJMP &&
            !isJavaMirrorOrJavaMirrorSubtype) {
            ParseDiagnoseRefactor(
                DiagKindRefactor.parse_explicitly_abstract_only_for_cjmp_abstract_class,
                lastToken.End(), "property").Emit()
        }
        if (inObjCMirror) {
            property.DisableAttr(Attribute.ABSTRACT)
            return
        }
        if (inAbstractCJMPClass && property.TestAttr(Attribute.ABSTRACT) &&
            !HasModifierToken(property.modifiers, TokenKind.ABSTRACT)) {
            property.DisableAttr(Attribute.ABSTRACT)
            return
        }
        if (HasModifierToken(property.modifiers, TokenKind.ABSTRACT) && !inAbstractCJMPClass) {
            var abstractModifier: Option<Modifier> = None
            for (modifier in property.modifiers) {
                if (modifier.modifier == TokenKind.ABSTRACT) {
                    abstractModifier = modifier
                }
            }
            if (let Some(modifier) <- abstractModifier) {
                try (cs = ChainScope(this, property)) {
                    DiagIllegalModifierInScope(modifier)
                }
            }
        }
    }

    private func CheckGetterAnnotations(annos: ArrayList<Annotation>, getter: Node): Unit {
        for (anno in annos) {
            DiagUnexpectedAnnoOn(anno, getter.begin, anno.identifier.Val(), "get")
        }
    }

    private func CheckSetterAnnotations(annos: ArrayList<Annotation>, setter: Node): Unit {
        for (anno in annos) {
            if (anno.kind != AnnotationKind.DEPRECATED) {
                DiagUnexpectedAnnoOn(anno, setter.begin, anno.identifier.Val(), "set")
            }
        }
    }

    private func SeeingPropMember(): Bool {
        return Seeing(TokenKind.IDENTIFIER) && (Peek().Value() == "get" || Peek().Value() == "set")
    }

    private func ParsePropBody(modifiers: ArrayList<Modifier>, propDecl: PropDecl): Unit {
        propDecl.leftCurlPos = lastToken.Begin()
        var setter: Option<Node> = None
        var getter: Option<Node> = None
        while (true) {
            if (Skip(TokenKind.RCURL)) {
                propDecl.rightCurlPos = lastToken.Begin()
                break
            }
            if (DetectPrematureEnd()) {
                DiagExpectedRightDelimiter("{", propDecl.leftCurlPos)
                break
            }
            let annos = ArrayList<Annotation>()
            ParseAnnotations(annos)
            let modis = ArrayList<Modifier>()
            ParseModifiers(modis)
            if (SeeingPropMember()) {
                if (Peek().Value() == "get") {
                    if (let Some(prevGetter) <- getter) {
                        DiagDuplicatedGetOrSet(prevGetter, propDecl)
                    }
                    let res = ParsePropMemberDecl(modis)
                    CheckGetterAnnotations(annos, res)
                    for (anno in annos) { res.annotations.add(anno) }
                    res.outerDecl = propDecl
                    propDecl.getters.add(res)
                    getter = res
                    SkipSemi()
                    SetBeginToAnnotationsBegin(res, annos)
                } else {
                    if (let Some(prevSetter) <- setter) {
                        DiagDuplicatedGetOrSet(prevSetter, propDecl)
                    }
                    let res = ParsePropMemberDecl(modis)
                    CheckSetterAnnotations(annos, res)
                    for (anno in annos) { res.annotations.add(anno) }
                    res.outerDecl = propDecl
                    propDecl.setters.add(res)
                    setter = res
                    SkipSemi()
                    SetBeginToAnnotationsBegin(res, annos)
                }
            } else {
                DiagExpectedGetOrSetInProp(propDecl.begin)
                ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI])
            }
        }
        propDecl.rightCurlPos = lastToken.Begin()
        for (modifier in modifiers) {
            if (!HasModifierToken(propDecl.modifiers, modifier.modifier)) {
                propDecl.modifiers.add(modifier)
            }
        }
        propDecl.end = Peek().End()
    }

    private func ParsePropMemberDecl(modifiers: ArrayList<Modifier>): FuncDecl {
        let ret = FuncDecl()
        try (cs = ChainScope(this, ret)) {
            ret.identifier = ParseIdentifierFromToken(Peek())
            ret.keywordPos = Peek().Begin()
            ret.begin = Peek().Begin()
            let isGetter = Peek().Value() == "get"
            if (isGetter) {
                ret.isGetter = true
            } else {
                ret.isSetter = true
            }
            Next()
            ret.begin = Peek().Begin()
            if (!modifiers.isEmpty()) {
                var firstModifier = modifiers[0]
                for (modifier in modifiers) {
                    if (modifier < firstModifier) {
                        firstModifier = modifier
                    }
                }
                DiagExpectNoModifier(firstModifier)
                ret.begin = SortModifierByPos(modifiers)[0].begin
            }
            if (!isGetter) {
                ret.funcBody = ParseFuncBody(ScopeKind.PROP_MEMBER_SETTER_BODY)
            } else {
                ret.funcBody = ParseFuncBody(ScopeKind.PROP_MEMBER_GETTER_BODY)
            }
            if (let Some(funcBody) <- ret.funcBody) {
                if (let None <- funcBody.body) {
                    DiagMissingBody(if (!ret.identifier.Valid()) { "" } else { "function" },
                        " '" + ret.identifier.Val() + "'", lastToken.End())
                }
                ret.end = funcBody.end
            }
        }
        return ret
    }

    private func ParsePropMemberBody(scopeKind: ScopeKind, fb: FuncBody): Unit {
        if (let Some(generic) <- fb.generic) {
            if (ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_SETTER_BODY)) {
                DiagGetOrSetCannotBeGeneric("getter", generic)
            }
            if (ScopeKindEquals(scopeKind, ScopeKind.PROP_MEMBER_GETTER_BODY)) {
                DiagGetOrSetCannotBeGeneric("setter", generic)
            }
        }
        if (!Seeing(TokenKind.LCURL)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_brace, Peek(), ConvertToken(Peek())).Emit()
            ConsumeUntilDecl(TokenKind.LCURL)
            if (!Seeing(TokenKind.LCURL)) {
                return
            }
        }
        fb.body = ParseBlock(ScopeKind.FUNC_BODY)
        if (let Some(block) <- fb.body) {
            fb.end = block.end
        }
    }

    public func ParseConstructor(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): FuncDecl {
        let ret = FuncDecl()
        try (cs = ChainScope(this, ret)) {
            ApplyModifiersAndAnnotations(ret, modifiers, annos)
            let key = Expect(TokenKind.INIT, "expected 'init'")
            ret.keywordPos = key.Begin()
            ret.identifier = SrcIdentifier("init", "init", key.Begin(), key.End(), false)
            ret.EnableAttr(Attribute.CONSTRUCTOR)
            if (HasModifierToken(modifiers, TokenKind.CONST)) {
                ret.isConst = true
            }
            ret.begin = if (ret.begin.IsZero()) { key.Begin() } else { ret.begin }
            CheckDeclarationInScope(scopeKind, DefKind.CONSTRUCTOR)
            ret.funcBody = ParseFuncBody(scopeKind)
            if (let Some(body) <- ret.funcBody) { ret.end = body.end }
            EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.CONSTRUCTOR))
            if (ret.TestAttr(Attribute.STATIC)) {
                ret.EnableAttr(Attribute.PRIVATE)
                let body = ret.funcBody.getOrThrow()
                if (!body.paramLists.isEmpty() && !body.paramLists[0].params.isEmpty()) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_static_init_can_not_accept_any_parameter,
                        body.paramLists[0]).Emit()
                }
            }
        }
        CheckConstructorBody(ret, scopeKind)
        return ret
    }

    public func ParseFinalizer(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): FuncDecl {
        let ret = FuncDecl()
        try (cs = ChainScope(this, ret)) {
            ApplyModifiersAndAnnotations(ret, modifiers, annos)
            let tilde = Expect(TokenKind.BITNOT, "expected '~' before finalizer")
            let initTok = Expect(TokenKind.INIT, "expected 'init' after '~'")
            ret.keywordPos = initTok.Begin()
            ret.identifier = SrcIdentifier("~init", "~init", tilde.Begin(), initTok.End(), false)
            ret.EnableAttr(Attribute.FINALIZER)
            ret.begin = if (ret.begin.IsZero()) { tilde.Begin() } else { ret.begin }
            CheckDeclarationInScope(scopeKind, DefKind.FINALIZER)
            ret.funcBody = ParseFuncBody(scopeKind)
            EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.FINALIZER))
            if (let Some(body) <- ret.funcBody) {
                if (!body.paramLists.isEmpty() && !body.paramLists[0].params.isEmpty()) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_finalizer_can_not_accept_any_parameter,
                        body.paramLists[0]).Emit()
                    ret.EnableAttr(Attribute.IS_BROKEN)
                }
                if (let Some(retType) <- body.retType) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_invalid_return_type, retType, "finalizer").Emit()
                    ret.EnableAttr(Attribute.IS_BROKEN)
                }
                ret.end = body.end
            }
            if (HasModifierToken(modifiers, TokenKind.UNSAFE)) {
                SetUnsafe(ret, modifiers: modifiers)
            }
        }
        return ret
    }

    public func ParsePrimaryConstructor(scopeKind: ScopeKind, modifiers: ArrayList<Modifier>, annos: ArrayList<Annotation>): PrimaryCtorDecl {
        let ret = PrimaryCtorDecl()
        try (cs = ChainScope(this, ret)) {
            ApplyModifiersAndAnnotations(ret, modifiers, annos)
            let id = ExpectIdentifierWithPos(ret)
            ret.identifier = id
            ret.keywordPos = id.Begin()
            ret.begin = if (ret.begin.IsZero()) { id.Begin() } else { ret.begin }
            if (!curPrimaryDeclIdent.isEmpty() && id.Val() != curPrimaryDeclIdent) {
                DiagUnknownPrimaryConstructor(curPrimaryDeclIdent)
                ret.EnableAttr(Attribute.IS_BROKEN)
            }
            let bodyScope = if (ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY)) {
                ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_STRUCT
            } else {
                ScopeKind.PRIMARY_CONSTRUCTOR_BODY_FOR_CLASS
            }
            ret.funcBody = ParseFuncBody(bodyScope)
            ret.EnableAttr(Attribute.CONSTRUCTOR)
            EnableModifierAttrs(ret, CheckDeclModifiers(modifiers, scopeKind, DefKind.PRIMARY_CONSTRUCTOR))
            ret.EnableAttr(Attribute.PRIMARY_CONSTRUCTOR)
            if (ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY)) {
                ret.EnableAttr(Attribute.IN_STRUCT)
            } else {
                ret.EnableAttr(Attribute.IN_CLASSLIKE)
            }
            if (HasModifierToken(modifiers, TokenKind.CONST)) {
                ret.isConst = true
            }
            if (let Some(body) <- ret.funcBody) {
                if (let Some(retType) <- body.retType) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_invalid_return_type, retType,
                        "primary constructor").Emit()
                    ret.EnableAttr(Attribute.IS_BROKEN)
                }
                ret.end = body.end
            }
        }
        return ret
    }

    private func SetDeclBeginPos(decl: Decl): Unit {
        if (decl.modifiers.isEmpty()) {
            return
        }
        let modifiers = SortModifierByPos(decl.modifiers)
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

    private func SetBeginToAnnotationsBegin(node: Node, annos: ArrayList<Annotation>): Unit {
        if (!annos.isEmpty()) {
            node.begin = annos[0].begin
        }
    }

    private func CheckModifierInParamList(
        scopeKind: ScopeKind,
        modifiers: ArrayList<Modifier>,
        isMember: Bool,
        fp: FuncParam
    ): Unit {
        if (modifiers.isEmpty()) {
            return
        }
        if (!isMember) {
            if (!fp.TestAttr(Attribute.HAS_BROKEN)) {
                DiagExpectNoModifier(modifiers[0])
            }
        } else {
            if (HasModifierToken(modifiers, TokenKind.CONST)) {
                DiagUnExpectedModifierOnDeclaration(fp)
            }
            EnableModifierAttrs(fp, CheckDeclModifiers(modifiers, scopeKind, DefKind.VARIABLE))
        }
    }

    private func CheckDeprecationOfFuncParam(param: FuncParam): Unit {
        for (anno in param.annotations) {
            if (anno.kind == AnnotationKind.DEPRECATED && !param.isNamedParam) {
                DiagDeprecatedInvalidTarget(anno, "Not named parameter")
            }
        }
    }

    private func EnableModifierAttrs(decl: Decl, attrs: ArrayList<Attribute>): Unit {
        for (attr in attrs) {
            decl.EnableAttr(attr)
        }
    }
}
