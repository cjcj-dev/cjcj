package cjcj::parse

import std.collection.*

public let CONFLICTED_FFI_ANNOS: Array<AnnotationKind> = [
    AnnotationKind.JAVA_MIRROR, AnnotationKind.JAVA_IMPL,
    AnnotationKind.OBJ_C_IMPL, AnnotationKind.OBJ_C_MIRROR,
    AnnotationKind.C, AnnotationKind.JAVA
]

public open class FFIParserImpl {
    public let parser: ParserImpl
    private let jp: JFFIParserImpl
    private let op: OCFFIParserImpl

    public init(parser: ParserImpl) {
        this.parser = parser
        this.jp = JFFIParserImpl(parser)
        this.op = OCFFIParserImpl(parser)
    }

    public func Java(): JFFIParserImpl {
        return jp
    }

    public func ObjC(): OCFFIParserImpl {
        return op
    }

    // C++ anchor: cangjie_compiler/src/Parse/NativeFFI/FFIParserImpl.cpp:47-70
    public func CheckAnnotationsConflict(annos: ArrayList<Annotation>): Unit {
        let candidates = ArrayList<Annotation>()
        for (anno in annos) {
            if (CONFLICTED_FFI_ANNOS.contains(anno.kind)) {
                candidates.add(anno)
            }
        }
        if (candidates.size < 2) {
            return
        }
        let first = candidates[0]
        var index: Int64 = 1
        while (index < candidates.size) {
            let current = candidates[index]
            if (first.identifier.Val() != current.identifier.Val()) {
                DiagConflictingAnnos(parser.diag, first, current, parser.lookahead.Value())
            }
            index++
        }
    }

    // C++ anchor: cangjie_compiler/src/Parse/NativeFFI/FFIParserImpl.cpp:72-107
    public func CheckAnnotations(annos: ArrayList<Annotation>, scopeKind: ScopeKind): Unit {
        let java = Java()
        let objc = ObjC()
        for (anno in annos) {
            if (anno.kind == AnnotationKind.JAVA_MIRROR || anno.kind == AnnotationKind.JAVA_IMPL) {
                java.CheckAnnotation(anno)
            } else if (anno.kind == AnnotationKind.FOREIGN_NAME) {
                CheckForeignNameAnnoArgs(anno)
                CheckForeignNameAnnoTarget(anno)
            } else if (anno.kind == AnnotationKind.FOREIGN_GETTER_NAME ||
                anno.kind == AnnotationKind.FOREIGN_SETTER_NAME) {
                CheckForeignGetterSetterNameAnnoArgs(anno)
                CheckForeignGetterSetterNameAnnoTarget(anno)
            } else if (anno.kind == AnnotationKind.JAVA_HAS_DEFAULT) {
                java.CheckJavaHasDefaultAnnotation(anno)
            } else if (anno.kind == AnnotationKind.OBJ_C_MIRROR ||
                anno.kind == AnnotationKind.OBJ_C_IMPL ||
                anno.kind == AnnotationKind.OBJ_C_INIT ||
                anno.kind == AnnotationKind.OBJ_C_OPTIONAL) {
                objc.CheckAnnotation(anno, scopeKind)
            }
        }
        CheckAnnotationsConflict(annos)
    }

    public func CheckForeignNameAnnotation(decl: Decl): Unit {
        for (anno in decl.annotations) {
            if (anno.kind != AnnotationKind.FOREIGN_NAME) {
                continue
            }
            if (let Some(outer) <- decl.outerDecl) {
                if (outer.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE) ||
                    outer.TestAnyAttr(Attribute.OBJ_C_MIRROR, Attribute.OBJ_C_MIRROR_SUBTYPE)) {
                    return
                }
            }
            decl.EnableAttr(Attribute.IS_BROKEN)
            parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_foreign_name_on_ffi_decl_member, decl).Emit()
            return
        }
    }

    public func CheckZeroOrSingleStringLitArgAnnotation(anno: Annotation, annotationName: String): Unit {
        if (anno.args.isEmpty()) {
            return
        }
        if (anno.args.size > 1 || !IsLitStringArg(anno.args[0])) {
            parser.DiagAnnotationMoreThanOneArgs(anno, annotationName, "'String' literal")
        }
    }

    public func CheckNoArgAnnotation(anno: Annotation, annotationName: String): Unit {
        if (!anno.args.isEmpty()) {
            parser.DiagAnnotationShouldNotHaveArgs(anno, annotationName)
        }
    }

    public func CheckClassLikeSignature(decl: Decl, annos: ArrayList<Annotation>): Unit {
        let java = Java()
        let objc = ObjC()
        let classLikeDecl = (decl as ClassLikeDecl).getOrThrow()
        for (anno in annos) {
            if (anno.kind == AnnotationKind.JAVA_MIRROR) {
                java.CheckMirrorSignature(classLikeDecl, annos)
            } else if (anno.kind == AnnotationKind.JAVA_IMPL) {
                java.CheckImplSignature(classLikeDecl, annos)
            }
        }
        objc.CheckClassLikeSignature(decl, annos)
    }

    public func CheckFuncSignature(decl: FuncDecl, annos: ArrayList<Annotation>): Unit {
        let objc = ObjC()
        objc.CheckMirrorSignature(decl, annos)
    }

    private func CheckForeignNameAnnoArgs(anno: Annotation): Unit {
        if (anno.args.size != 1 || !IsLitStringArg(anno.args[0])) {
            parser.DiagAnnotationExpectsOneArgument(anno, "@ForeignName", "'String' literal")
        }
    }

    private func CheckForeignNameAnnoTarget(anno: Annotation): Unit {
        if (parser.SeeingAny([TokenKind.FUNC, TokenKind.PROP, TokenKind.INIT, TokenKind.LET,
            TokenKind.VAR, TokenKind.CONST])) {
            return
        }
        if (anno.kind == AnnotationKind.FOREIGN_NAME) {
            parser.DiagUnexpectedAnnoOn(
                anno, parser.lookahead.Begin(), anno.identifier.Val(), parser.lookahead.Value())
        }
    }

    private func CheckForeignGetterSetterNameAnnoArgs(anno: Annotation): Unit {
        if (anno.args.size != 1 || !IsLitStringArg(anno.args[0]) || !anno.args[0].name.Empty()) {
            parser.DiagAnnotationExpectsOneArgument(anno, "@" + anno.identifier.Val(), "'String' literal")
        }
    }

    private func CheckForeignGetterSetterNameAnnoTarget(anno: Annotation): Unit {
        if (parser.Seeing(TokenKind.PROP)) {
            return
        }
        if (anno.kind == AnnotationKind.FOREIGN_GETTER_NAME ||
            anno.kind == AnnotationKind.FOREIGN_SETTER_NAME) {
            parser.DiagUnexpectedAnnoOn(
                anno, parser.lookahead.Begin(), anno.identifier.Val(), parser.lookahead.Value())
        }
    }
}

public func DiagConflictingAnnos(diag: DiagnosticEngine, first: Annotation, second: Annotation, onStr: String): Unit {
    let pos = if (first.begin < second.begin) { first.begin } else { second.begin }
    let end = if (first.end > second.end) { first.end } else { second.end }
    diag.DiagnoseRefactor(
        DiagKindRefactor.parse_conflict_annotation,
        MakeRange(pos, end),
        first.identifier.Val(),
        second.identifier.Val(),
        onStr).Emit()
}

public func IsLitStringArg(arg: FuncArg): Bool {
    if (let Some(expr) <- arg.expr) {
        if (let Some(lit) <- (expr as LitConstExpr)) {
            return lit.kind == LitConstKind.STRING
        }
    }
    return false
}
