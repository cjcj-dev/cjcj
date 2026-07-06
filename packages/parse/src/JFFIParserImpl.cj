package cangjie_compiler::parse

import std.collection.*
import cangjie_compiler::utils.CJC_ASSERT

public class JFFIParserImpl {
    public let parser: ParserImpl

    public init(parser: ParserImpl) {
        this.parser = parser
    }

    public func CheckAnnotation(anno: Annotation, decl: Decl): Unit {
        if (anno.kind == AnnotationKind.JAVA_MIRROR) {
            CheckMirrorAnnoArgs(anno, decl)
            CheckMirrorAnnoTarget(anno, decl)
        } else {
            CJC_ASSERT(anno.kind == AnnotationKind.JAVA_IMPL)
            CheckImplAnnoArgs(anno, decl)
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
                parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_java_impl_cannot_be_open, decl).Emit()
                decl.EnableAttr(Attribute.IS_BROKEN)
            } else if (decl.astKind == ASTKind.INTERFACE_DECL) {
                parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_java_impl_cannot_be_interface, decl).Emit()
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
        }
    }

    public func CheckJavaHasDefaultAnnotation(anno: Annotation, decl: Decl): Unit {
        if (decl.astKind == ASTKind.FUNC_DECL) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        parser.DiagUnexpectedAnnoOnKind(anno, decl.begin, anno.identifier.Val(), decl.astKind)
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
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_java_mirror_cannot_have_finalizer, node).Emit()
    }

    public func DiagJavaMirrorCannotHavePrivateMember(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_java_mirror_cannot_have_private_member, node).Emit()
    }

    public func DiagJavaMirrorCannotHaveStaticInit(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_java_mirror_cannot_have_static_init, node).Emit()
    }

    public func DiagJavaMirrorCannotHaveConstMember(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_java_mirror_cannot_have_const_member, node).Emit()
    }

    public func DiagJavaImplCannotBeGeneric(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_java_impl_cannot_be_generic, node).Emit()
    }

    public func DiagJavaImplCannotBeAbstract(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_java_impl_cannot_be_abstract, node).Emit()
    }

    public func DiagJavaImplCannotBeSealed(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_java_impl_cannot_be_sealed, node).Emit()
    }

    public func DiagJavaMirrorCannotBeSealed(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_java_mirror_cannot_be_sealed, node).Emit()
    }

    public func DiagJavaImplCannotHaveStaticInit(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_java_impl_cannot_have_static_init, node).Emit()
    }

    private func CheckMirrorAnnoArgs(anno: Annotation, decl: Decl): Unit {
        FFIParserImpl(parser).CheckZeroOrSingleStringLitArgAnnotation(anno, "@JavaMirror", decl)
    }

    private func CheckImplAnnoArgs(anno: Annotation, decl: Decl): Unit {
        FFIParserImpl(parser).CheckZeroOrSingleStringLitArgAnnotation(anno, "@JavaImpl", decl)
    }

    private func CheckMirrorAnnoTarget(anno: Annotation, decl: Decl): Unit {
        if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.INTERFACE_DECL) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        parser.DiagUnexpectedAnnoOnKind(anno, decl.begin, anno.identifier.Val(), decl.astKind)
    }

    private func CheckImplAnnoTarget(anno: Annotation, decl: Decl): Unit {
        if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.INTERFACE_DECL) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        parser.DiagUnexpectedAnnoOnKind(anno, decl.begin, anno.identifier.Val(), decl.astKind)
    }
}

private func HasAnnotation(annos: ArrayList<Annotation>, kind: AnnotationKind): Bool {
    for (anno in annos) {
        if (anno.kind == kind) { return true }
    }
    return false
}
