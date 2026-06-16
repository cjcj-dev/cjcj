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
                if (outer.astKind == ASTKind.CLASS_DECL && outer.TestAttr(Attribute.OBJ_C_MIRROR)) {
                    if (!fd.TestAttr(Attribute.STATIC)) {
                        DiagObjCInitFuncMustBeStatic(fd)
                        fd.EnableAttr(Attribute.IS_BROKEN)
                    }
                    if (!fd.TestAttr(Attribute.IS_BROKEN)) {
                        fd.EnableAttr(Attribute.OBJ_C_INIT)
                    }
                    continue
                }
            }
            DiagObjCInitFuncMustBeInMirrorClass(fd)
            fd.EnableAttr(Attribute.IS_BROKEN)
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

    public func DiagObjCMirrorCannotHaveFinalizer(node: Node): Unit { Emit(node, "Objective-C mirror cannot have a finalizer") }
    public func DiagObjCMirrorCannotHavePrivateMember(node: Node): Unit { Emit(node, "Objective-C mirror cannot have private members") }
    public func DiagObjCMirrorCannotHaveConstMember(node: Node): Unit { Emit(node, "Objective-C mirror cannot have const members") }
    public func DiagObjCMirrorCannotHaveStaticInit(node: Node): Unit { Emit(node, "Objective-C mirror cannot have a static initializer") }
    public func DiagObjCMirrorFieldCannotHaveInitializer(node: Node): Unit { Emit(node, "Objective-C mirror field cannot have an initializer") }
    public func DiagObjCMirrorCannotHavePrimaryCtor(node: Node): Unit { Emit(node, "Objective-C mirror cannot have a primary constructor") }
    public func DiagObjCMirrorFieldCannotBeStatic(node: Node): Unit { Emit(node, "Objective-C mirror field cannot be static") }
    public func DiagObjCImplCannotHaveStaticInit(node: Node): Unit { Emit(node, "Objective-C implementation cannot have a static initializer") }
    public func DiagObjCImplCannotBeGeneric(node: Node): Unit { Emit(node, "@ObjCImpl declaration cannot be generic") }
    public func DiagObjCInitFuncMustBeStatic(node: Node): Unit { Emit(node, "@ObjCInit function must be static") }
    public func DiagObjCInitFuncMustBeInMirrorClass(node: FuncDecl): Unit { Emit(node, "@ObjCInit function must be in an @ObjCMirror class") }
    public func DiagObjCOptionalFuncMustBeInMirrorClass(fd: FuncDecl): Unit { Emit(fd, "@ObjCOptional function must be in an @ObjCMirror interface") }
    public func DiagObjCMirrorFuncCannotBeForeign(node: FuncDecl): Unit { Emit(node, "@ObjCMirror function cannot be foreign") }
    public func DiagObjCMirrorFuncCannotBeC(node: FuncDecl): Unit { Emit(node, "@ObjCMirror function cannot be @C") }
    public func DiagObjCMirrorFuncCannotBeGeneric(node: FuncDecl): Unit { Emit(node, "@ObjCMirror function cannot be generic") }
    public func DiagObjCMirrorFuncCannotHaveBody(node: FuncDecl): Unit { Emit(node, "@ObjCMirror function cannot have a body") }
    public func DiagObjCMirrorFuncMustHaveExplicitType(node: FuncDecl): Unit { Emit(node, "@ObjCMirror function must have an explicit return type") }
    public func DiagObjCMirrorFuncCannotBeConst(node: FuncDecl): Unit { Emit(node, "@ObjCMirror function cannot be const") }
    public func DiagObjCMirrorFuncMustBeTopLevel(node: FuncDecl): Unit { Emit(node, "@ObjCMirror function must be top-level") }

    private func CheckMirrorAnnoTarget(anno: Annotation, scopeKind: ScopeKind, decl: Decl): Unit {
        if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.INTERFACE_DECL) {
            return
        }
        if (decl.astKind == ASTKind.FUNC_DECL && scopeKind == ScopeKind.TOPLEVEL) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, anno.begin, "@ObjCMirror target is invalid")
    }

    private func CheckImplAnnoTarget(anno: Annotation, decl: Decl): Unit {
        if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.INTERFACE_DECL) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, anno.begin, "@ObjCImpl can only be applied to classes and interfaces")
    }

    private func CheckInitAnnoTarget(anno: Annotation, decl: Decl): Unit {
        if (decl.astKind == ASTKind.FUNC_DECL) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, anno.begin, "@ObjCInit can only be applied to functions")
    }

    private func CheckOptionalAnnoTarget(anno: Annotation, decl: Decl): Unit {
        if (decl.astKind == ASTKind.FUNC_DECL) {
            return
        }
        decl.EnableAttr(Attribute.IS_BROKEN)
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, anno.begin, "@ObjCOptional can only be applied to functions")
    }

    private func DiagObjCMirrorCannotBeSealed(node: Node): Unit { Emit(node, "@ObjCMirror declaration cannot be sealed") }
    private func DiagObjCImplCannotBeInterface(node: Node): Unit { Emit(node, "@ObjCImpl cannot be applied to an interface") }
    private func DiagObjCImplCannotBeAbstract(node: Node): Unit { Emit(node, "@ObjCImpl declaration cannot be abstract") }
    private func DiagObjCImplCannotBeSealed(node: Node): Unit { Emit(node, "@ObjCImpl declaration cannot be sealed") }

    private func Emit(node: Node, message: String): Unit {
        parser.diag.DiagnoseRefactor(DiagKindRefactor.INVALID_ANNOTATION, node.begin, message)
    }
}

private func HasObjCAnnotation(annos: ArrayList<Annotation>, kind: AnnotationKind): Bool {
    for (anno in annos) {
        if (anno.kind == kind) { return true }
    }
    return false
}
