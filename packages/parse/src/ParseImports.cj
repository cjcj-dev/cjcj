package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func SeeingImport(): Bool {
        return Seeing(TokenKind.IMPORT) || Seeing([TokenKind.PUBLIC, TokenKind.IMPORT]) ||
            Seeing([TokenKind.PROTECTED, TokenKind.IMPORT]) || Seeing([TokenKind.INTERNAL, TokenKind.IMPORT]) ||
            Seeing([TokenKind.PRIVATE, TokenKind.IMPORT])
    }

    public func ParsePackageHeader(modifiers: ArrayList<Modifier>): PackageSpec {
        let pkg = PackageSpec()
        for (modifier in modifiers) { pkg.modifiers.add(modifier) }
        let token = Expect(TokenKind.PACKAGE, "expected 'package'")
        pkg.packagePos = token.Begin()
        pkg.begin = if (!pkg.modifiers.isEmpty()) { pkg.modifiers[0].begin } else { token.Begin() }
        ParseQualifiedIdentifierList(pkg.identifiers)
        pkg.end = if (!pkg.identifiers.isEmpty()) { pkg.identifiers[pkg.identifiers.size - 1].End() } else { token.End() }
        SkipNLOrSemi()
        return pkg
    }

    public func ParseImportSpec(annos: ArrayList<Annotation>): ImportSpec {
        let spec = ImportSpec()
        for (anno in annos) { spec.annotations.add(anno) }
        let maybeModifier = ModifierKindFromToken(Peek().kind)
        if (let Some(kind) <- maybeModifier) {
            let tok = Peek()
            if (kind == ModifierKind.PUBLIC || kind == ModifierKind.PROTECTED || kind == ModifierKind.INTERNAL || kind == ModifierKind.PRIVATE) {
                spec.modifier = Modifier(kind, tok.kind, tok.Begin(), tok.End())
                Next()
            }
        }
        let importTok = Expect(TokenKind.IMPORT, "expected 'import'")
        spec.importPos = importTok.Begin()
        spec.begin = if (!spec.annotations.isEmpty()) { spec.annotations[0].begin } else { importTok.Begin() }
        ParseImportContent(spec.content)
        spec.end = spec.content.end
        SkipNLOrSemi()
        return spec
    }

    public func ParseImportContent(content: ImportContent): Unit {
        content.begin = Peek().Begin()
        while (!Seeing(TokenKind.END)) {
            if (Skip(TokenKind.MUL)) {
                content.importAll = true
                break
            }
            let id = ExpectIdentifierWithPos(content)
            content.prefixPaths.add(id)
            if (!Skip(TokenKind.DOT)) {
                break
            }
        }
        if (Skip(TokenKind.AS)) {
            content.aliasName = ExpectIdentifierWithPos(content)
        }
        content.end = if (!content.aliasName.Empty()) {
            content.aliasName.End()
        } else if (!content.prefixPaths.isEmpty()) {
            content.prefixPaths[content.prefixPaths.size - 1].End()
        } else {
            content.begin
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
}
