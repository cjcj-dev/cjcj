package cjcj::sema.NativeFFI.Java

import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.{DiagnosticEngine, DiagKindRefactor}
import cjcj::utils.CJC_ASSERT

// C++ src/Sema/NativeFFI/Java/TypeCheck/DiagsInterop.cpp:11-14.
public func DiagJavaHasDefaultNoArgs(diag: DiagnosticEngine, node: Node): Unit {
    DiagnoseRefactor(diag, DiagKindRefactor.sema_java_has_default_annotation_args, node).Emit()
}

// C++ src/Sema/NativeFFI/Java/TypeCheck/DiagsInterop.cpp:16-19.
public func DiagJavaHasDefaultIncorrectScope(diag: DiagnosticEngine, node: Node): Unit {
    DiagnoseRefactor(diag, DiagKindRefactor.sema_java_has_default_annotation_is_in_wrong_place, node).Emit()
}

// C++ src/Sema/NativeFFI/Java/TypeCheck/DiagsInterop.cpp:21-24.
public func DiagJavaHasDefaultConflictWithStatic(diag: DiagnosticEngine, node: Node): Unit {
    DiagnoseRefactor(diag, DiagKindRefactor.sema_java_has_default_conflict_with_static, node).Emit()
}

// C++ src/Sema/NativeFFI/Java/TypeCheck/TypeCheckAnnotation.cpp:12-31.
public func CheckJavaHasDefaultAnnotation(diag: DiagnosticEngine, annotation: Annotation, decl: Decl): Unit {
    CJC_ASSERT(annotation.kind == AstAnnotationKind.JAVA_HAS_DEFAULT)
    if (!annotation.args.isEmpty()) {
        DiagJavaHasDefaultNoArgs(diag, annotation)
    }
    var isOuterDeclJavaMirror = false
    var isOuterDeclInterface = false
    if (let Some(outerDecl) <- decl.outerDecl) {
        isOuterDeclJavaMirror = outerDecl.TestAttr(Attribute.JAVA_MIRROR)
        isOuterDeclInterface = isOuterDeclJavaMirror && outerDecl.astKind == ASTKind.INTERFACE_DECL
    }
    let isCurrentDeclFunc = decl.astKind == ASTKind.FUNC_DECL
    let isInvalidScope = !isOuterDeclJavaMirror || !isOuterDeclInterface || !isCurrentDeclFunc
    if (isInvalidScope) {
        DiagJavaHasDefaultIncorrectScope(diag, annotation)
    }
    if (decl.TestAttr(Attribute.STATIC)) {
        DiagJavaHasDefaultConflictWithStatic(diag, decl)
    }
}
