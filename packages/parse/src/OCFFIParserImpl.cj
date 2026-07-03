package cangjie_compiler::parse

import std.collection.*

public class OCFFIParserImpl {
    public let parser: ParserImpl

    public init(parser: ParserImpl) {
        this.parser = parser
    }

    public func CheckAnnotationForDecl(anno: Annotation, scopeKind: ScopeKind, decl: Decl): Unit {
        if (anno.kind == AnnotationKind.OBJ_C_MIRROR) {
            FFIParserImpl(parser).CheckZeroOrSingleStringLitArgAnnotation(anno, "@ObjCMirror", decl)
            CheckMirrorAnnoTarget(anno, scopeKind, decl)
        } else if (anno.kind == AnnotationKind.OBJ_C_IMPL) {
            FFIParserImpl(parser).CheckZeroOrSingleStringLitArgAnnotation(anno, "@ObjCImpl", decl)
            CheckImplAnnoTarget(anno, decl)
        } else if (anno.kind == AnnotationKind.OBJ_C_INIT) {
            FFIParserImpl(parser).CheckNoArgAnnotation(anno, "@ObjCInit", decl)
            CheckInitAnnoTarget(anno, decl)
        } else if (anno.kind == AnnotationKind.OBJ_C_OPTIONAL) {
            FFIParserImpl(parser).CheckNoArgAnnotation(anno, "@ObjCOptional", decl)
            CheckOptionalAnnoTarget(anno, decl)
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
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_cannot_have_finalizer, node)
    }

    public func DiagObjCMirrorCannotHavePrivateMember(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_cannot_have_private_member, node)
    }

    public func DiagObjCMirrorCannotHaveConstMember(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_cannot_have_const_member, node)
    }

    public func DiagObjCMirrorCannotHaveStaticInit(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_cannot_have_static_init, node)
    }

    public func DiagObjCMirrorFieldCannotHaveInitializer(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_field_cannot_have_initializer, node)
    }

    public func DiagObjCMirrorCannotHavePrimaryCtor(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_cannot_have_primary_ctor, node)
    }

    public func DiagObjCMirrorFieldCannotBeStatic(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_field_cannot_be_static, node)
    }

    public func DiagObjCImplCannotHaveStaticInit(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_impl_cannot_have_static_init, node)
    }

    public func DiagObjCImplCannotBeGeneric(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_impl_cannot_be_generic, node)
    }

    public func DiagObjCInitFuncMustBeStatic(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_init_method_must_be_static, node)
    }

    public func DiagObjCInitFuncMustBeInMirrorClass(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_init_method_must_be_in_mirror_class, node)
    }

    public func DiagObjCOptionalFuncMustBeInMirrorClass(fd: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_optional_method_must_be_in_mirror_class, fd)
    }

    public func DiagObjCMirrorFuncCannotBeForeign(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_cannot_be_foreign, node,
            node.identifier.Val())
    }

    public func DiagObjCMirrorFuncCannotBeC(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_cannot_be_c, node, node.identifier.Val())
    }

    public func DiagObjCMirrorFuncCannotBeGeneric(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_cannot_be_generic, node,
            node.identifier.Val())
    }

    public func DiagObjCMirrorFuncCannotHaveBody(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_cannot_have_body, node,
            node.identifier.Val())
    }

    public func DiagObjCMirrorFuncMustHaveExplicitType(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_must_have_explicit_type, node,
            node.identifier.Val())
    }

    public func DiagObjCMirrorFuncCannotBeConst(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_cannot_be_const, node,
            node.identifier.Val())
    }

    public func DiagObjCMirrorFuncMustBeTopLevel(node: FuncDecl): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_func_must_be_top_level, node,
            node.identifier.Val())
    }

    private func CheckMirrorAnnoTarget(anno: Annotation, scopeKind: ScopeKind, decl: Decl): Unit {
        if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.INTERFACE_DECL) {
            return
        }
        if (decl.astKind == ASTKind.FUNC_DECL && ScopeKindEquals(scopeKind, ScopeKind.TOPLEVEL)) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        let keyword = match (decl.astKind) {
            case ASTKind.FUNC_DECL => "func"
            case ASTKind.MAIN_DECL => "main"
            case ASTKind.MACRO_DECL => "macro"
            case ASTKind.CLASS_DECL => "class"
            case ASTKind.EXTEND_DECL => "extend"
            case ASTKind.INTERFACE_DECL => "interface"
            case ASTKind.STRUCT_DECL => "struct"
            case ASTKind.ENUM_DECL => "enum"
            case ASTKind.TYPE_ALIAS_DECL => "type"
            case ASTKind.PROP_DECL => "prop"
            case _ => "var"
        }
        let qualifier = if (scopeKind == ScopeKind.TOPLEVEL) { "" } else { "member or local " }
        parser.DiagUnexpectedAnnoOn(anno, decl.begin, anno.identifier.Val(), qualifier + keyword)
    }

    private func CheckImplAnnoTarget(anno: Annotation, decl: Decl): Unit {
        if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.INTERFACE_DECL) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        parser.DiagUnexpectedAnnoOnKind(anno, decl.begin, anno.identifier.Val(), decl.astKind)
    }

    private func CheckInitAnnoTarget(anno: Annotation, decl: Decl): Unit {
        if (decl.astKind == ASTKind.FUNC_DECL) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        parser.DiagUnexpectedAnnoOnKind(anno, decl.begin, anno.identifier.Val(), decl.astKind)
    }

    private func CheckOptionalAnnoTarget(anno: Annotation, decl: Decl): Unit {
        if (decl.astKind == ASTKind.FUNC_DECL) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        parser.DiagUnexpectedAnnoOnKind(anno, decl.begin, anno.identifier.Val(), decl.astKind)
    }

    private func DiagObjCMirrorCannotBeSealed(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_mirror_cannot_be_sealed, node)
    }

    private func DiagObjCImplCannotBeInterface(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_impl_cannot_be_interface, node)
    }

    private func DiagObjCImplCannotBeAbstract(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_impl_cannot_be_abstract, node)
    }

    private func DiagObjCImplCannotBeSealed(node: Node): Unit {
        parser.ParseDiagnoseRefactor(DiagKindRefactor.parse_objc_impl_cannot_be_sealed, node)
    }
}

private func HasObjCAnnotation(annos: ArrayList<Annotation>, kind: AnnotationKind): Bool {
    for (anno in annos) {
        if (anno.kind == kind) { return true }
    }
    return false
}
