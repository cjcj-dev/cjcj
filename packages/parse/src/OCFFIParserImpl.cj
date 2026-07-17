package cjcj::parse

import std.collection.*
import cjcj::utils.CJC_ABORT

public class OCFFIParserImpl {
    public let parser: ParserImpl

    public init(parser: ParserImpl) {
        this.parser = parser
    }

    public func CheckAnnotation(anno: Annotation, scopeKind: ScopeKind): Unit {
        match (anno.kind) {
            case AnnotationKind.OBJ_C_MIRROR =>
                CheckMirrorAnnoArgs(anno)
                CheckMirrorAnnoTarget(anno, scopeKind)
            case AnnotationKind.OBJ_C_IMPL =>
                CheckImplAnnoArgs(anno)
                CheckImplAnnoTarget(anno)
            case AnnotationKind.OBJ_C_INIT =>
                CheckInitAnnoArgs(anno)
                CheckInitAnnoTarget(anno)
            case AnnotationKind.OBJ_C_OPTIONAL =>
                CheckOptionalAnnoArgs(anno)
                CheckOptionalAnnoTarget(anno)
            case _ => CJC_ABORT()
        }
    }

    public func CheckInitAnnotation(fd: FuncDecl): Unit {
        for (anno in fd.annotations) {
            if (anno.kind != AnnotationKind.OBJ_C_INIT) {
                continue
            }
            if (let Some(outer) <- fd.outerDecl) {
                if (outer.astKind != ASTKind.CLASS_DECL || !outer.TestAttr(Attribute.OBJ_C_MIRROR)) {
                    DiagObjCInitFuncMustBeInMirrorClass(fd)
                    fd.EnableAttr(Attribute.IS_BROKEN)
                }
            } else {
                DiagObjCInitFuncMustBeInMirrorClass(fd)
                fd.EnableAttr(Attribute.IS_BROKEN)
            }
            if (!fd.TestAttr(Attribute.STATIC)) {
                DiagObjCInitFuncMustBeStatic(fd)
                fd.EnableAttr(Attribute.IS_BROKEN)
            }
            if (!fd.TestAttr(Attribute.IS_BROKEN)) {
                fd.EnableAttr(Attribute.OBJ_C_INIT)
            }
        }
    }

    public func CheckOptionalAnnotation(fd: FuncDecl): Unit {
        for (anno in fd.annotations) {
            if (anno.kind != AnnotationKind.OBJ_C_OPTIONAL) {
                continue
            }
            if (let Some(outer) <- fd.outerDecl) {
                if (outer.astKind == ASTKind.INTERFACE_DECL && outer.TestAttr(Attribute.OBJ_C_MIRROR)) {
                    if (!fd.TestAttr(Attribute.IS_BROKEN)) {
                        fd.EnableAttr(Attribute.OBJ_C_OPTIONAL)
                    }
                    continue
                }
            }
            DiagObjCOptionalFuncMustBeInMirrorClass(fd)
            fd.EnableAttr(Attribute.IS_BROKEN)
        }
    }

    public func CheckClassLikeSignature(decl: Decl, annos: ArrayList<Annotation>): Unit {
        if (HasObjCAnnotation(annos, AnnotationKind.OBJ_C_MIRROR)) {
            decl.EnableAttr(Attribute.OBJ_C_MIRROR)
            if (decl.TestAttr(Attribute.SEALED)) {
                DiagObjCMirrorCannotBeSealed(decl)
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
        }
        if (HasObjCAnnotation(annos, AnnotationKind.OBJ_C_IMPL)) {
            decl.EnableAttr(Attribute.OBJ_C_MIRROR_SUBTYPE)
            if (let Some(_) <- decl.generic) {
                DiagObjCImplCannotBeGeneric(decl)
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
            if (decl.TestAttr(Attribute.ABSTRACT)) {
                DiagObjCImplCannotBeAbstract(decl)
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
            if (decl.TestAttr(Attribute.SEALED)) {
                DiagObjCImplCannotBeSealed(decl)
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
            if (decl.astKind == ASTKind.INTERFACE_DECL) {
                DiagObjCImplCannotBeInterface(decl)
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
        }
    }

    public func CheckMirrorSignature(decl: FuncDecl, annos: ArrayList<Annotation>): Unit {
        if (!HasObjCAnnotation(annos, AnnotationKind.OBJ_C_MIRROR)) {
            return
        }
        decl.EnableAttr(Attribute.OBJ_C_MIRROR)
        if (decl.TestAttr(Attribute.FOREIGN)) {
            DiagObjCMirrorFuncCannotBeForeign(decl)
            decl.EnableAttr(Attribute.IS_BROKEN)
        }
        if (let Some(body) <- decl.funcBody) {
            if (let Some(_) <- body.generic) {
                DiagObjCMirrorFuncCannotBeGeneric(decl)
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
            if (let Some(_) <- body.body) {
                DiagObjCMirrorFuncCannotHaveBody(decl)
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
            if (let None <- body.retType) {
                DiagObjCMirrorFuncMustHaveExplicitType(decl)
                decl.EnableAttr(Attribute.IS_BROKEN)
            }
        }
        if (decl.isConst) {
            DiagObjCMirrorFuncCannotBeConst(decl)
            decl.EnableAttr(Attribute.IS_BROKEN)
        }
        if (let Some(_) <- decl.outerDecl) {
            DiagObjCMirrorFuncMustBeTopLevel(decl)
            decl.EnableAttr(Attribute.IS_BROKEN)
        }
    }

    public func DiagObjCMirrorCannotHaveFinalizer(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_cannot_have_finalizer, node).Emit()
    }

    public func DiagObjCMirrorCannotHavePrivateMember(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_cannot_have_private_member, node).Emit()
    }

    public func DiagObjCMirrorCannotHaveConstMember(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_cannot_have_const_member, node).Emit()
    }

    public func DiagObjCMirrorCannotHaveStaticInit(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_cannot_have_static_init, node).Emit()
    }

    public func DiagObjCMirrorFieldCannotHaveInitializer(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_field_cannot_have_initializer, node).Emit()
    }

    public func DiagObjCMirrorCannotHavePrimaryCtor(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_cannot_have_primary_ctor, node).Emit()
    }

    public func DiagObjCMirrorFieldCannotBeStatic(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_field_cannot_be_static, node).Emit()
    }

    public func DiagObjCImplCannotHaveStaticInit(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_impl_cannot_have_static_init, node).Emit()
    }

    public func DiagObjCImplCannotBeGeneric(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_impl_cannot_be_generic, node).Emit()
    }

    public func DiagObjCInitFuncMustBeStatic(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_init_method_must_be_static, node).Emit()
    }

    public func DiagObjCInitFuncMustBeInMirrorClass(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_init_method_must_be_in_mirror_class, node).Emit()
    }

    public func DiagObjCOptionalFuncMustBeInMirrorClass(fd: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_optional_method_must_be_in_mirror_class, fd).Emit()
    }

    public func DiagObjCMirrorFuncCannotBeForeign(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_cannot_be_foreign, node,
            node.identifier.Val()).Emit()
    }

    public func DiagObjCMirrorFuncCannotBeC(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_cannot_be_c, node, node.identifier.Val()).Emit()
    }

    public func DiagObjCMirrorFuncCannotBeGeneric(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_cannot_be_generic, node,
            node.identifier.Val()).Emit()
    }

    public func DiagObjCMirrorFuncCannotHaveBody(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_cannot_have_body, node,
            node.identifier.Val()).Emit()
    }

    public func DiagObjCMirrorFuncMustHaveExplicitType(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_must_have_explicit_type, node,
            node.identifier.Val()).Emit()
    }

    public func DiagObjCMirrorFuncCannotBeConst(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_cannot_be_const, node,
            node.identifier.Val()).Emit()
    }

    public func DiagObjCMirrorFuncMustBeTopLevel(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_must_be_top_level, node,
            node.identifier.Val()).Emit()
    }

    private func CheckMirrorAnnoArgs(anno: Annotation): Unit {
        FFIParserImpl(parser).CheckZeroOrSingleStringLitArgAnnotation(anno, "@ObjCMirror")
    }

    private func CheckImplAnnoArgs(anno: Annotation): Unit {
        FFIParserImpl(parser).CheckZeroOrSingleStringLitArgAnnotation(anno, "@ObjCImpl")
    }

    private func CheckInitAnnoArgs(anno: Annotation): Unit {
        FFIParserImpl(parser).CheckNoArgAnnotation(anno, "@ObjCInit")
    }

    private func CheckOptionalAnnoArgs(anno: Annotation): Unit {
        FFIParserImpl(parser).CheckNoArgAnnotation(anno, "@ObjCOptional")
    }

    private func CheckMirrorAnnoTarget(anno: Annotation, scopeKind: ScopeKind): Unit {
        if (parser.SeeingAny([TokenKind.CLASS, TokenKind.INTERFACE])) {
            return
        }
        if (parser.Seeing(TokenKind.FUNC) && ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
            return
        }
        if (anno.kind == AnnotationKind.OBJ_C_MIRROR) {
            let qualifier = if (ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) { "" } else { "member or local " }
            parser.DiagUnexpectedAnnoOn(
                anno, parser.lookahead.Begin(), anno.identifier.Val(), qualifier + parser.lookahead.Value())
        }
    }

    private func CheckImplAnnoTarget(anno: Annotation): Unit {
        if (parser.SeeingAny([TokenKind.CLASS, TokenKind.INTERFACE])) {
            return
        }
        if (anno.kind == AnnotationKind.OBJ_C_IMPL) {
            parser.DiagUnexpectedAnnoOn(
                anno, parser.lookahead.Begin(), anno.identifier.Val(), parser.lookahead.Value())
        }
    }

    private func CheckInitAnnoTarget(anno: Annotation): Unit {
        if (parser.Seeing(TokenKind.FUNC)) {
            return
        }
        if (anno.kind == AnnotationKind.OBJ_C_INIT) {
            parser.DiagUnexpectedAnnoOn(
                anno, parser.lookahead.Begin(), anno.identifier.Val(), parser.lookahead.Value())
        }
    }

    private func CheckOptionalAnnoTarget(anno: Annotation): Unit {
        if (parser.Seeing(TokenKind.FUNC)) {
            return
        }
        if (anno.kind == AnnotationKind.OBJ_C_OPTIONAL) {
            parser.DiagUnexpectedAnnoOn(
                anno, parser.lookahead.Begin(), anno.identifier.Val(), parser.lookahead.Value())
        }
    }

    private func DiagObjCMirrorCannotBeSealed(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_cannot_be_sealed, node).Emit()
    }

    private func DiagObjCImplCannotBeInterface(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_impl_cannot_be_interface, node).Emit()
    }

    private func DiagObjCImplCannotBeAbstract(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_impl_cannot_be_abstract, node).Emit()
    }

    private func DiagObjCImplCannotBeSealed(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_impl_cannot_be_sealed, node).Emit()
    }
}

private func HasObjCAnnotation(annos: ArrayList<Annotation>, kind: AnnotationKind): Bool {
    for (anno in annos) {
        if (anno.kind == kind) { return true }
    }
    return false
}
