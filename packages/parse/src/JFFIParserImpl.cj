package cangjie_compiler::parse

import std.collection.*

public class JFFIParserImpl {
    public let parser: ParserImpl

    public init(parser: ParserImpl) {
        this.parser = parser
    }

    public func CheckAnnotationForDecl(anno: Annotation, decl: Decl): Unit {
        if (anno.kind == AnnotationKind.JAVA_MIRROR) {
            FFIParserImpl(parser).CheckZeroOrSingleStringLitArgAnnotation(anno, "@JavaMirror", decl)
            CheckMirrorAnnoTarget(anno, decl)
        } else if (anno.kind == AnnotationKind.JAVA_IMPL) {
            FFIParserImpl(parser).CheckZeroOrSingleStringLitArgAnnotation(anno, "@JavaImpl", decl)
            CheckImplAnnoTarget(anno, decl)
        }
    }

    public func CheckClassLikeSignature(decl: Decl, annos: ArrayList<Annotation>): Unit {
        if (HasAnnotation(annos, AnnotationKind.JAVA_MIRROR)) {
            decl.EnableAttr(Attribute.JAVA_MIRROR)
            if (let Some(classLike) <- (decl as InheritableDecl)) {
                if (!classLike.inheritedTypes.isEmpty()) {
                    decl.EnableAttr(Attribute.JAVA_MIRROR_SUBTYPE)
                }
            }
            if (decl.TestAttr(Attribute.SEALED)) {
                DiagJavaMirrorCannotBeSealed(decl)
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
        }
        if (HasAnnotation(annos, AnnotationKind.JAVA_IMPL)) {
            decl.EnableAttr(Attribute.JAVA_MIRROR_SUBTYPE)
            if (let Some(_) <- decl.generic) {
                if (!decl.TestAttr(Attribute.JAVA_CJ_MAPPING)) {
                    DiagJavaImplCannotBeGeneric(decl)
                    decl.EnableAttr(Attribute.IS_BROKEN)
                }
            }
            if (decl.TestAttr(Attribute.ABSTRACT)) {
                DiagJavaImplCannotBeAbstract(decl)
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
            if (decl.TestAttr(Attribute.SEALED)) {
                DiagJavaImplCannotBeSealed(decl)
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
            if (decl.astKind == ASTKind.CLASS_DECL && decl.TestAttr(Attribute.OPEN)) {
                parser.diag.DiagnoseRefactor(
                    DiagKindRefactor.INVALID_ANNOTATION,
                    decl.begin,
                    "@JavaImpl class cannot be open")
                decl.EnableAttr(Attribute.IS_BROKEN)
            } else if (decl.astKind == ASTKind.INTERFACE_DECL) {
                parser.diag.DiagnoseRefactor(
                    DiagKindRefactor.INVALID_ANNOTATION,
                    decl.begin,
                    "@JavaImpl cannot be applied to an interface")
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
        }
    }

    public func CheckJavaHasDefaultAnnotation(anno: Annotation, decl: Decl): Unit {
        if (decl.astKind == ASTKind.FUNC_DECL) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        parser.diag.DiagnoseRefactor(
            DiagKindRefactor.INVALID_ANNOTATION,
            anno.begin,
            "@JavaHasDefault can only be applied to functions")
    }

    public func IsAbstractFunction(fd: FuncDecl, outerDecl: Decl): Bool {
        let hasAbstractModifier = fd.TestAttr(Attribute.ABSTRACT)
        let hasStaticModifier = fd.TestAttr(Attribute.STATIC)
        let hasOuterDeclAbstractModifier = outerDecl.TestAttr(Attribute.ABSTRACT)
        let isOuterDeclInterface = outerDecl.astKind == ASTKind.INTERFACE_DECL
        let isOuterDeclClass = outerDecl.astKind == ASTKind.CLASS_DECL
        let isOuterDeclJavaImpl = outerDecl.TestAttr(Attribute.JAVA_MIRROR_SUBTYPE) && !outerDecl.TestAttr(Attribute.JAVA_MIRROR)
        let isAbstractInsideAbstractClass = hasAbstractModifier && isOuterDeclClass && hasOuterDeclAbstractModifier
        let isAbstractInsideInterface = isOuterDeclInterface && !hasStaticModifier
        return (isAbstractInsideAbstractClass || isAbstractInsideInterface) && !isOuterDeclJavaImpl
    }

    public func DiagJavaMirrorCannotHaveFinalizer(node: Node): Unit {
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, node.begin, "Java mirror cannot have a finalizer")
    }

    public func DiagJavaMirrorCannotHavePrivateMember(node: Node): Unit {
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, node.begin, "Java mirror cannot have private members")
    }

    public func DiagJavaMirrorCannotHaveStaticInit(node: Node): Unit {
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, node.begin, "Java mirror cannot have a static initializer")
    }

    public func DiagJavaMirrorCannotHaveConstMember(node: Node): Unit {
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, node.begin, "Java mirror cannot have const members")
    }

    public func DiagJavaImplCannotBeGeneric(node: Node): Unit {
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, node.begin, "@JavaImpl declaration cannot be generic")
    }

    public func DiagJavaImplCannotBeAbstract(node: Node): Unit {
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, node.begin, "@JavaImpl declaration cannot be abstract")
    }

    public func DiagJavaImplCannotBeSealed(node: Node): Unit {
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, node.begin, "@JavaImpl declaration cannot be sealed")
    }

    public func DiagJavaMirrorCannotBeSealed(node: Node): Unit {
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, node.begin, "@JavaMirror declaration cannot be sealed")
    }

    public func DiagJavaImplCannotHaveStaticInit(node: Node): Unit {
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, node.begin, "@JavaImpl declaration cannot have a static initializer")
    }

    private func CheckMirrorAnnoTarget(anno: Annotation, decl: Decl): Unit {
        if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.INTERFACE_DECL) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        parser.diag.DiagnoseRefactor(
            DiagKindRefactor.INVALID_ANNOTATION,
            anno.begin,
            "@JavaMirror can only be applied to classes and interfaces")
    }

    private func CheckImplAnnoTarget(anno: Annotation, decl: Decl): Unit {
        if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.INTERFACE_DECL) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        parser.diag.DiagnoseRefactor(
            DiagKindRefactor.INVALID_ANNOTATION,
            anno.begin,
            "@JavaImpl can only be applied to classes and interfaces")
    }
}

private func HasAnnotation(annos: ArrayList<Annotation>, kind: AnnotationKind): Bool {
    for (anno in annos) {
        if (anno.kind == kind) { return true }
    }
    return false
}
