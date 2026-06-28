package cangjie_compiler::parse

import std.collection.*

private const PACKAGE_NAME_LEN_LIMIT: Int64 = 200

extend ParserImpl {
    public func SeeingImport(): Bool {
        return Seeing(TokenKind.IMPORT) || Seeing([TokenKind.PUBLIC, TokenKind.IMPORT]) ||
            Seeing([TokenKind.PROTECTED, TokenKind.IMPORT]) || Seeing([TokenKind.INTERNAL, TokenKind.IMPORT]) ||
            Seeing([TokenKind.PRIVATE, TokenKind.IMPORT])
    }

    public func ParsePackageHeader(modifiers: ArrayList<Modifier>): PackageSpec {
        let pkg = PackageSpec()
        if (!modifiers.isEmpty()) {
            pkg.modifier = CloneModifier(modifiers[0])
            if (modifiers[0].modifier == TokenKind.COMMON) {
                pkg.hasCommon = true
            } else if (modifiers[0].modifier == TokenKind.SPECIFIC) {
                pkg.hasSpecific = true
            }
        }
        if (Skip(TokenKind.MACRO)) {
            pkg.macroPos = lastToken.Begin()
            pkg.hasMacro = true
        }
        let token = Expect(TokenKind.PACKAGE, "expected 'package'")
        pkg.packagePos = token.Begin()
        if (let Some(modifier) <- pkg.modifier) {
            pkg.begin = modifier.begin
        } else if (pkg.hasMacro) {
            pkg.begin = pkg.macroPos
        } else {
            pkg.begin = token.Begin()
        }

        var curIdent = SrcIdentifier()
        var skipDoubleColon = false
        while (true) {
            skipDoubleColon = false
            if (!curIdent.Empty()) {
                pkg.prefixPaths.add(curIdent.Val())
                pkg.prefixPoses.add(curIdent.Begin())
                pkg.prefixDotPoses.add(lastToken.Begin())
            }
            curIdent = ExpectPackageIdentifierWithPos(pkg)
            if (curIdent.Empty()) {
                pkg.isBroken = true
                ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI], targetTokenConsumed: false)
                break
            }
            if (curIdent.IsRaw()) {
                pkg.isBroken = true
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    curIdent.Begin(),
                    "raw identifier '${curIdent.GetRawText()}' is not allowed in package name")
                ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI], targetTokenConsumed: false)
                break
            }
            if (pkg.prefixPaths.isEmpty() && Skip(TokenKind.DOUBLE_COLON)) {
                pkg.hasDoubleColon = true
                skipDoubleColon = true
            }
            if (!skipDoubleColon && !Skip(TokenKind.DOT)) {
                break
            }
        }
        if (!curIdent.Empty()) {
            pkg.packageName = curIdent
            pkg.end = curIdent.End()
        } else {
            pkg.end = token.End()
        }
        let fullPackageName = pkg.GetPackageName()
        if (!pkg.isBroken && fullPackageName.size > PACKAGE_NAME_LEN_LIMIT) {
            let start = if (!pkg.prefixPoses.isEmpty()) { pkg.prefixPoses[0] } else { pkg.packagePos }
            diag.DiagnoseRefactor(
                DiagKindRefactor.PARSE_ERROR,
                start,
                "package name length ${fullPackageName.size} exceeds limit ${PACKAGE_NAME_LEN_LIMIT}")
            pkg.isBroken = true
        }
        if (!pkg.prefixPaths.isEmpty()) {
            moduleName = pkg.prefixPaths[0]
        }
        let _ = CheckDeclModifiers(modifiers, ScopeKind.TOPLEVEL, DefKind.PACKAGE)
        SkipNLOrSemi()
        return pkg
    }

    public func ParseImportSpecInTop(imports: ArrayList<ImportSpec>, annos: ArrayList<Annotation>): Unit {
        ParseCommonImportSpec(imports, annos)
        CheckImportSpec(imports)
    }

    public func ParseCommonImportSpec(imports: ArrayList<ImportSpec>, annos: ArrayList<Annotation>): Unit {
        while (SeeingImport() || SeeingBuiltinAnnotation()) {
            if (SeeingBuiltinAnnotation()) {
                ParseAnnotations(annos)
            }
            if (!SeeingImport()) {
                break
            }
            ParseImportSpec(imports, annos)
            annos.clear()
            if (!newlineSkipped) {
                if (Seeing(TokenKind.END)) {
                    break
                }
                if (!Skip(TokenKind.SEMI)) {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.EXPECTED_TOKEN,
                        Peek().Begin(),
                        "expected ';' or newline after import")
                    ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI])
                }
            }
            SkipBlank(TokenKind.SEMI)
        }
    }

    public func ParseImportSpec(annos: ArrayList<Annotation>): ImportSpec {
        let spec = ImportSpec()
        for (anno in annos) { spec.annotations.add(anno) }
        if (SeeingAny([TokenKind.PUBLIC, TokenKind.PROTECTED, TokenKind.INTERNAL, TokenKind.PRIVATE])) {
            Next()
            let modifier = Modifier(lastToken.kind, lastToken.Begin())
            modifier.end = lastToken.End()
            spec.modifier = modifier
        }
        let importTok = Expect(TokenKind.IMPORT, "expected 'import'")
        spec.importPos = importTok.Begin()
        spec.begin = if (let Some(modifier) <- spec.modifier) {
            modifier.begin
        } else {
            importTok.Begin()
        }
        ParseImportContent(spec.content)
        spec.end = spec.content.end
        for (anno in annos) {
            if (anno.kind != AnnotationKind.WHEN) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.INVALID_ANNOTATION,
                    anno.begin,
                    "unexpected annotation '${anno.identifier.Val()}' on import")
                anno.isBroken = true
            }
        }
        return spec
    }

    public func ParseImportSpec(imports: ArrayList<ImportSpec>, annos: ArrayList<Annotation>): Unit {
        let spec = ParseImportSpec(annos)
        imports.add(spec)
        if (spec.IsImportMulti()) {
            DesugarImportMulti(imports, spec)
        }
    }

    public func CheckImportSpec(imports: ArrayList<ImportSpec>): Unit {
        for (importSpec in imports) {
            if (importSpec.TestAttr(Attribute.COMPILER_ADD)) {
                continue
            }
            let content = importSpec.content
            if (content.kind != ImportKind.IMPORT_MULTI) {
                let fullPackageName = content.GetImportedPackageName()
                if (!content.isBroken && fullPackageName.size > PACKAGE_NAME_LEN_LIMIT) {
                    let start = ImportContentBeginPosition(content)
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.PARSE_ERROR,
                        start,
                        "import package name length ${fullPackageName.size} exceeds limit ${PACKAGE_NAME_LEN_LIMIT}")
                    MarkImportContentBroken(content)
                }
                continue
            }
            let commonPrefix = content.GetImportedPackageName()
            for (item in content.items) {
                let suffix = item.GetImportedPackageName()
                let fullPackageName = if (commonPrefix.isEmpty()) { suffix } else { commonPrefix + "." + suffix }
                if (!item.isBroken && fullPackageName.size > PACKAGE_NAME_LEN_LIMIT) {
                    let start = if (!content.prefixPaths.isEmpty()) {
                        content.prefixPoses[0]
                    } else {
                        ImportContentBeginPosition(item)
                    }
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.PARSE_ERROR,
                        start,
                        "import package name length ${fullPackageName.size} exceeds limit ${PACKAGE_NAME_LEN_LIMIT}")
                    MarkImportContentBroken(item)
                }
            }
        }
    }

    public func DesugarImportMulti(imports: ArrayList<ImportSpec>, importSpec: ImportSpec): Unit {
        for (item in importSpec.content.items) {
            let desugared = ImportSpec()
            desugared.begin = item.begin
            desugared.end = item.end
            desugared.importPos = importSpec.importPos
            desugared.withImplicitExport = importSpec.withImplicitExport
            if (let Some(modifier) <- importSpec.modifier) {
                desugared.modifier = CloneModifier(modifier)
            }
            for (anno in importSpec.annotations) { desugared.annotations.add(anno) }
            desugared.content = CloneImportContentPrefix(importSpec.content)
            desugared.content.kind = item.kind
            desugared.content.end = item.end
            for (prefix in item.prefixPaths) {
                desugared.content.prefixPaths.add(prefix)
            }
            for (prefixPos in item.prefixPoses) {
                desugared.content.prefixPoses.add(prefixPos)
            }
            for (dotPos in item.prefixDotPoses) {
                desugared.content.prefixDotPoses.add(dotPos)
            }
            desugared.content.identifier = CloneIdentifier(item.identifier)
            desugared.content.asPos = item.asPos
            desugared.content.aliasName = CloneIdentifier(item.aliasName)
            desugared.content.isBroken = item.isBroken || importSpec.content.hasBroken
            // C++ ParseImports.cpp:164 EnableAttr(COMPILER_ADD, GetModifierAttr(...)); selfhost 无
            // GetModifierAttr(modifier-derived attr 为独立既存 gap), 此处补 COMPILER_ADD 使 CheckImportSpec
            // 的 desugared skip 生效, 避免对超长包名重复诊断。
            desugared.EnableAttr(Attribute.COMPILER_ADD)
            imports.add(desugared)
        }
    }

    public func ParseImportContent(content: ImportContent): Unit {
        if (!ParseImportSingle(content, inMultiImport: false)) {
            ParseImportMulti(content)
        }
        if (content.kind == ImportKind.IMPORT_SINGLE && Skip(TokenKind.AS)) {
            ParseImportAliasPart(content)
        }
    }

    public func ParseImportSingle(content: ImportContent, inMultiImport!: Bool = false): Bool {
        var curIdent = SrcIdentifier()
        var firstIter = true
        var skipDoubleColon = false
        while (true) {
            skipDoubleColon = false
            if (!curIdent.Empty()) {
                content.prefixPaths.add(curIdent.Val())
                content.prefixPoses.add(curIdent.Begin())
                content.prefixDotPoses.add(lastToken.Begin())
            }
            if (!inMultiImport && Skip(TokenKind.LCURL)) {
                if (firstIter) {
                    content.begin = lastToken.Begin()
                }
                content.leftCurlPos = lastToken.Begin()
                return false
            }
            if (!firstIter && Skip(TokenKind.MUL)) {
                curIdent = SrcIdentifier("*", "*", lastToken.Begin(), lastToken.End(), false)
                break
            }
            curIdent = ExpectPackageIdentifierWithPos(content)
            if (curIdent.Empty()) {
                if (inMultiImport) {
                    ConsumeUntilAny([TokenKind.NL, TokenKind.COMMA, TokenKind.RCURL])
                    if (lastToken.kind == TokenKind.RCURL) {
                        content.rightCurlPos = lastToken.Begin()
                    }
                } else {
                    ConsumeUntilAny([TokenKind.NL, TokenKind.COMMA])
                }
                MarkImportContentBroken(content)
                break
            }
            if (firstIter) {
                content.begin = curIdent.Begin()
                firstIter = false
            }
            if (content.prefixPaths.isEmpty() && !inMultiImport && Skip(TokenKind.DOUBLE_COLON)) {
                content.hasDoubleColon = true
                skipDoubleColon = true
                if (curIdent.IsRaw() && !content.isBroken) {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.PARSE_ERROR,
                        curIdent.Begin(),
                        "raw identifier '${curIdent.GetRawText()}' is not allowed as an organization name")
                }
            }
            if (!skipDoubleColon && !Skip(TokenKind.DOT)) {
                break
            }
        }
        content.kind = if (curIdent.Val() == "*") { ImportKind.IMPORT_ALL } else { ImportKind.IMPORT_SINGLE }
        if (lastToken.kind == TokenKind.PACKAGE_IDENTIFIER) {
            DiagExpectedIdentifier(curIdent.Begin())
            content.EnableAttr(Attribute.IS_BROKEN)
        }
        content.identifier = curIdent
        content.end = curIdent.End()
        return true
    }

    public func ParseImportMulti(content: ImportContent): Unit {
        content.kind = ImportKind.IMPORT_MULTI
        var firstIter = true
        while (true) {
            if (!firstIter) {
                let skippedComma = Skip(TokenKind.COMMA)
                if (skippedComma) {
                    content.commaPoses.add(lastToken.Begin())
                }
                if (Skip(TokenKind.RCURL)) {
                    content.rightCurlPos = lastToken.Begin()
                    content.end = lastToken.End()
                    return
                }
                if (!skippedComma) {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.EXPECTED_TOKEN,
                        lastToken.End(),
                        "expected ',' in import list")
                    MarkImportContentBroken(content)
                }
            }
            firstIter = false
            let item = ImportContent()
            ParseImportSingle(item, inMultiImport: true)
            if (item.kind == ImportKind.IMPORT_SINGLE && Skip(TokenKind.AS)) {
                ParseImportAliasPart(item)
            }
            if (item.isBroken) {
                MarkImportContentHasBroken(content)
            }
            content.items.add(item)
            if (!SeeingAny([TokenKind.COMMA, TokenKind.IDENTIFIER, TokenKind.PACKAGE_IDENTIFIER, TokenKind.AS])) {
                break
            }
        }
        if (lastToken.kind != TokenKind.RCURL && !Skip(TokenKind.RCURL)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.UNTERMINATED_DELIMITER,
                content.leftCurlPos,
                "expected '}' after import list")
            MarkImportContentBroken(content)
            content.end = lastToken.End()
        } else {
            content.rightCurlPos = lastToken.Begin()
            if (!content.items.isEmpty()) {
                content.end = content.items[content.items.size - 1].end
            } else {
                content.end = content.rightCurlPos
            }
        }
    }

    public func ParseImportAliasPart(content: ImportContent): Unit {
        content.kind = ImportKind.IMPORT_ALIAS
        content.asPos = lastToken.Begin()
        let curIdent = ExpectIdentifierWithPos(content)
        if (curIdent.Empty()) {
            ConsumeUntilAny([TokenKind.NL, TokenKind.COMMA])
            MarkImportContentBroken(content)
        } else {
            content.aliasName = curIdent
            content.end = lastToken.End()
        }
    }

    public func ParseQualifiedIdentifierList(ids: ArrayList<SrcIdentifier>): Unit {
        while (!Seeing(TokenKind.END)) {
            ids.add(ExpectIdentifierWithPos(Node()))
            if (!Skip(TokenKind.DOT)) {
                break
            }
        }
    }

    public func ExpectPackageIdentifierWithPos(node: Node): SrcIdentifier {
        let token = Peek()
        if (IsPackageIdentifierOrContextualKeyword(token.kind)) {
            Next()
            return ParseIdentifierFromToken(token)
        }
        node.isBroken = true
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_IDENTIFIER, token.Begin(), "expected package identifier")
        return SrcIdentifier("", "", token.Begin(), token.Begin(), false)
    }
}

private func CloneIdentifier(identifier: Identifier): Identifier {
    return Identifier(identifier.Val(), identifier.Begin(), identifier.End())
}

private func CloneModifier(modifier: Modifier): Option<Modifier> {
    return Modifier(modifier.modifier, modifier.begin)
}

private func CloneImportContentPrefix(content: ImportContent): ImportContent {
    let clone = ImportContent()
    clone.begin = content.begin
    clone.end = content.end
    clone.hasDoubleColon = content.hasDoubleColon
    for (prefix in content.prefixPaths) {
        clone.prefixPaths.add(prefix)
    }
    for (prefixPos in content.prefixPoses) {
        clone.prefixPoses.add(prefixPos)
    }
    for (dotPos in content.prefixDotPoses) {
        clone.prefixDotPoses.add(dotPos)
    }
    return clone
}

private func ImportContentBeginPosition(content: ImportContent): Position {
    if (!content.prefixPoses.isEmpty()) {
        return content.prefixPoses[0]
    }
    if (!content.identifier.Empty()) {
        return content.identifier.Begin()
    }
    return content.begin
}

private func MarkImportContentBroken(content: ImportContent): Unit {
    content.isBroken = true
}

private func MarkImportContentHasBroken(content: ImportContent): Unit {
    content.hasBroken = true
    content.isBroken = true
}
