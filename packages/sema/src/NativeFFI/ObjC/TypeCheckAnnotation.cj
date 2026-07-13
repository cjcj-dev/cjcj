package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.{DiagnosticEngine, DiagKindRefactor}
import cjcj::utils.CJC_ASSERT

// Mirrors CheckForeignSetterNameAnnotation, TypeCheckAnnotation.cpp:18-30.
public func CheckForeignSetterNameAnnotation(diag: DiagnosticEngine, ann: Annotation, decl: Decl): Unit {
    CJC_ASSERT(ann.kind == AstAnnotationKind.FOREIGN_SETTER_NAME)
    if (decl.astKind == ASTKind.PROP_DECL) {
        let propDecl = (decl as PropDecl).getOrThrow()
        if (!propDecl.isVar) {
            DiagnoseRefactor(diag, DiagKindRefactor.sema_objc_setter_name_on_immutable_prop, ann).Emit()
            return
        }
    }
}
