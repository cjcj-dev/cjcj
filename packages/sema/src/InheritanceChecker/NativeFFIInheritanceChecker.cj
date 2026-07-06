package cangjie_compiler::sema.InheritanceChecker

import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::basic.{DiagnosticEngine, DiagKindRefactor, MakeRange}
import cangjie_compiler::sema.*
import cangjie_compiler::sema.NativeFFI.{GetAnnotation, GetForeignNameAnnotation}
import cangjie_compiler::utils.CJC_ASSERT

private func GetAnnoValue(anno: Annotation): String {
    CJC_ASSERT(anno.args.size == 1)
    if (let Some(expr) <- anno.args[0].expr) {
        if (let Some(litExpr) <- (expr as LitConstExpr)) {
            return litExpr.stringValue
        }
    }
    CJC_ASSERT(false)
    return ""
}

private func DiagConflictingForeignName(
    diag: DiagnosticEngine,
    declWithAnno: Decl,
    otherDecl: Decl,
    checkingDecl: Decl
): Unit {
    let annoOpt = GetForeignNameAnnotation(declWithAnno)
    CJC_ASSERT(annoOpt.isSome())
    let anno = annoOpt.getOrThrow()

    let builder = if (!anno.TestAttr(Attribute.COMPILER_ADD)) {
        diag.DiagnoseRefactor(
            DiagKindRefactor.sema_foreign_name_conflicting_annotation,
            MakeRange(anno.GetBegin(), declWithAnno.identifier.End()),
            arguments: [declWithAnno.identifier.Val(), anno.identifier.Val(), anno.identifier.Val()])
    } else {
        diag.DiagnoseRefactor(
            DiagKindRefactor.sema_foreign_name_conflicting_derived_annotation,
            MakeRange(declWithAnno.identifier.Begin(), declWithAnno.identifier.End()),
            arguments: [declWithAnno.identifier.Val(), anno.identifier.Val(), GetAnnoValue(anno)])
    }

    if (let Some(otherAnno) <- GetForeignNameAnnotation(otherDecl)) {
        if (!otherAnno.TestAttr(Attribute.COMPILER_ADD)) {
            builder.AddNote(MakeRange(otherAnno.GetBegin(), otherDecl.identifier.End()),
                "Other declaration '" + otherDecl.identifier.Val() + "' has a different @ForeignName")
        } else {
            builder.AddNote(MakeRange(otherDecl.identifier.Begin(), otherDecl.identifier.End()),
                "Other declaration '" + otherDecl.identifier.Val() + "' has a different derived @ForeignName '" +
                GetAnnoValue(otherAnno) + "'")
        }
    } else {
        builder.AddNote(MakeRange(otherDecl.identifier.Begin(), otherDecl.identifier.End()),
            "Other declaration '" + otherDecl.identifier.Val() + "' doesn't have a @ForeignName")
    }

    builder.AddNote(MakeRange(checkingDecl.identifier.Begin(), checkingDecl.identifier.End()),
        "While checking declaration '" + checkingDecl.identifier.Val() + "'")
    builder.Emit()
}

private func NeedCheck(parent: MemberSignature, child: MemberSignature): Bool {
    CJC_ASSERT(parent.decl.isSome())
    CJC_ASSERT(child.decl.isSome())
    let parentDecl = parent.decl.getOrThrow()
    let childDecl = child.decl.getOrThrow()
    CJC_ASSERT(parentDecl.outerDecl.isSome())
    CJC_ASSERT(childDecl.outerDecl.isSome())
    let parentOuter = parentDecl.outerDecl.getOrThrow()
    let childOuter = childDecl.outerDecl.getOrThrow()

    if (childOuter.TestAttr(Attribute.IMPORTED)) {
        return false
    }
    if (!parentDecl.IsFuncOrProp()) {
        return false
    }
    CJC_ASSERT(childDecl.IsFuncOrProp())

    if (!parentOuter.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)) {
        return false
    }
    if (!childOuter.TestAnyAttr(Attribute.JAVA_MIRROR, Attribute.JAVA_MIRROR_SUBTYPE)) {
        return false
    }
    if (SameDecl(parentOuter, childOuter)) {
        return false
    }

    return true
}

func CheckForeignName(
    diag: DiagnosticEngine,
    typeManager: TypeManager,
    parent: MemberSignature,
    child: MemberSignature,
    checkingDecl: Decl
): Unit {
    if (!NeedCheck(parent, child)) {
        return
    }

    let parentDecl = parent.decl.getOrThrow()
    let childDecl = child.decl.getOrThrow()
    let childAnno = GetForeignNameAnnotation(childDecl)
    let parentAnno = GetForeignNameAnnotation(parentDecl)
    if (!childAnno.isSome() && !parentAnno.isSome()) {
        return
    }

    CJC_ASSERT(parent.structTy.isSome())
    CJC_ASSERT(child.structTy.isSome())
    if (!typeManager.IsSubtype(child.structTy.getOrThrow(), parent.structTy.getOrThrow())) {
        if (!childAnno.isSome() && parentAnno.isSome()) {
            DiagConflictingForeignName(diag, parentDecl, childDecl, checkingDecl)
        } else if (!parentAnno.isSome() && childAnno.isSome()) {
            DiagConflictingForeignName(diag, childDecl, parentDecl, checkingDecl)
        } else if (childAnno.isSome() && parentAnno.isSome() &&
            GetAnnoValue(childAnno.getOrThrow()) != GetAnnoValue(parentAnno.getOrThrow())) {
            DiagConflictingForeignName(diag, parentDecl, childDecl, checkingDecl)
        }
        return
    }

    if (childAnno.isSome() && !childAnno.getOrThrow().TestAttr(Attribute.COMPILER_ADD)) {
        diag.DiagnoseRefactor(
            DiagKindRefactor.sema_foreign_name_appeared_in_child,
            MakeRange(childAnno.getOrThrow().GetBegin(), childDecl.identifier.End()),
            arguments: [childAnno.getOrThrow().identifier.Val()]).Emit()
    } else if (childAnno.isSome() && !parentAnno.isSome()) {
        DiagConflictingForeignName(diag, childDecl, parentDecl, checkingDecl)
    } else if (!childAnno.isSome() && parentAnno.isSome() && child.replaceOther) {
        DiagConflictingForeignName(diag, parentDecl, childDecl, checkingDecl)
    } else if (!childAnno.isSome() && parentAnno.isSome()) {
        let clonedAnnoOpt = ASTCloner.Clone(parentAnno.getOrThrow()) as Annotation
        CJC_ASSERT(clonedAnnoOpt.isSome())
        let clonedAnno = clonedAnnoOpt.getOrThrow()
        clonedAnno.EnableAttr(Attribute.COMPILER_ADD)
        CopyBasicInfo(childDecl, clonedAnno)
        childDecl.annotations.add(clonedAnno)
    } else if (childAnno.isSome() && parentAnno.isSome() &&
        GetAnnoValue(childAnno.getOrThrow()) != GetAnnoValue(parentAnno.getOrThrow())) {
        DiagConflictingForeignName(diag, parentDecl, childDecl, checkingDecl)
    }
}

private func DiagConflictingAnnotation(
    diag: DiagnosticEngine,
    declWithAnno: Decl,
    otherDecl: Decl,
    checkingDecl: Decl,
    annotationKind: AstAnnotationKind
): Unit {
    let annoOpt = GetAnnotation(declWithAnno, annotationKind)
    CJC_ASSERT(annoOpt.isSome())
    let anno = annoOpt.getOrThrow()

    let builder = if (!anno.TestAttr(Attribute.COMPILER_ADD)) {
        diag.DiagnoseRefactor(
            DiagKindRefactor.sema_foreign_name_conflicting_annotation,
            MakeRange(anno.GetBegin(), declWithAnno.identifier.End()),
            arguments: [declWithAnno.identifier.Val(), anno.identifier.Val()])
    } else {
        diag.DiagnoseRefactor(
            DiagKindRefactor.sema_foreign_name_conflicting_derived_annotation,
            MakeRange(declWithAnno.identifier.Begin(), declWithAnno.identifier.End()),
            arguments: [declWithAnno.identifier.Val(), anno.identifier.Val(), GetAnnoValue(anno)])
    }

    if (let Some(otherAnno) <- GetForeignNameAnnotation(otherDecl)) {
        if (!otherAnno.TestAttr(Attribute.COMPILER_ADD)) {
            builder.AddNote(MakeRange(otherAnno.GetBegin(), otherDecl.identifier.End()),
                "Other declaration '" + otherDecl.identifier.Val() + "' has a different @" + anno.identifier.Val())
        } else {
            builder.AddNote(MakeRange(otherDecl.identifier.Begin(), otherDecl.identifier.End()),
                "Other declaration '" + otherDecl.identifier.Val() + "' has a different derived @" +
                anno.identifier.Val() + " '" + GetAnnoValue(otherAnno) + "'")
        }
    } else {
        builder.AddNote(MakeRange(otherDecl.identifier.Begin(), otherDecl.identifier.End()),
            "Other declaration '" + otherDecl.identifier.Val() + "' doesn't have a @" + anno.identifier.Val())
    }

    builder.AddNote(MakeRange(checkingDecl.identifier.Begin(), checkingDecl.identifier.End()),
        "While checking declaration '" + checkingDecl.identifier.Val() + "'")
    builder.Emit()
}

private func NeedCheckForeignName(parent: MemberSignature, child: MemberSignature): Bool {
    CJC_ASSERT(parent.decl.isSome())
    CJC_ASSERT(child.decl.isSome())
    let parentDecl = parent.decl.getOrThrow()
    let childDecl = child.decl.getOrThrow()
    CJC_ASSERT(parentDecl.outerDecl.isSome())
    CJC_ASSERT(childDecl.outerDecl.isSome())
    let parentOuter = parentDecl.outerDecl.getOrThrow()
    let childOuter = childDecl.outerDecl.getOrThrow()

    if (childOuter.TestAttr(Attribute.IMPORTED)) {
        return false
    }
    if (!parentDecl.IsFuncOrProp()) {
        return false
    }
    CJC_ASSERT(childDecl.IsFuncOrProp())

    if (!parentOuter.TestAnyAttr(Attribute.OBJ_C_MIRROR, Attribute.OBJ_C_MIRROR_SUBTYPE)) {
        return false
    }
    if (!childOuter.TestAnyAttr(Attribute.OBJ_C_MIRROR, Attribute.OBJ_C_MIRROR_SUBTYPE)) {
        return false
    }
    if (SameDecl(parentOuter, childOuter)) {
        return false
    }

    return true
}

private func IsForeignNameLikeAnnotation(annotationKind: AstAnnotationKind): Bool {
    return annotationKind == AstAnnotationKind.FOREIGN_NAME ||
        annotationKind == AstAnnotationKind.FOREIGN_GETTER_NAME ||
        annotationKind == AstAnnotationKind.FOREIGN_SETTER_NAME
}

func CheckAnnotation(
    diag: DiagnosticEngine,
    typeManager: TypeManager,
    annotationKind: AstAnnotationKind,
    parent: MemberSignature,
    child: MemberSignature,
    checkingDecl: Decl
): Unit {
    if (!NeedCheckForeignName(parent, child)) {
        return
    }

    let parentDecl = parent.decl.getOrThrow()
    let childDecl = child.decl.getOrThrow()
    let childAnno = GetAnnotation(childDecl, annotationKind)
    let parentAnno = GetAnnotation(parentDecl, annotationKind)
    if (!childAnno.isSome() && !parentAnno.isSome()) {
        return
    }

    CJC_ASSERT(parent.structTy.isSome())
    CJC_ASSERT(child.structTy.isSome())
    if (!typeManager.IsSubtype(child.structTy.getOrThrow(), parent.structTy.getOrThrow())) {
        if (!childAnno.isSome() && parentAnno.isSome()) {
            DiagConflictingAnnotation(diag, parentDecl, childDecl, checkingDecl, annotationKind)
        } else if (!parentAnno.isSome() && childAnno.isSome()) {
            DiagConflictingAnnotation(diag, childDecl, parentDecl, checkingDecl, annotationKind)
        } else if (IsForeignNameLikeAnnotation(annotationKind) && childAnno.isSome() && parentAnno.isSome() &&
            GetAnnoValue(childAnno.getOrThrow()) != GetAnnoValue(parentAnno.getOrThrow())) {
            DiagConflictingAnnotation(diag, parentDecl, childDecl, checkingDecl, annotationKind)
        }
        return
    }

    if (childAnno.isSome() && !childAnno.getOrThrow().TestAttr(Attribute.COMPILER_ADD)) {
        diag.DiagnoseRefactor(
            DiagKindRefactor.sema_foreign_name_appeared_in_child,
            MakeRange(childAnno.getOrThrow().GetBegin(), childDecl.identifier.End()),
            arguments: [childAnno.getOrThrow().identifier.Val()]).Emit()
    } else if (childAnno.isSome() && !parentAnno.isSome()) {
        DiagConflictingAnnotation(diag, childDecl, parentDecl, checkingDecl, annotationKind)
    } else if (!childAnno.isSome() && parentAnno.isSome() && child.replaceOther) {
        DiagConflictingAnnotation(diag, parentDecl, childDecl, checkingDecl, annotationKind)
    } else if (!childAnno.isSome() && parentAnno.isSome()) {
        let clonedAnnoOpt = ASTCloner.Clone(parentAnno.getOrThrow()) as Annotation
        CJC_ASSERT(clonedAnnoOpt.isSome())
        let clonedAnno = clonedAnnoOpt.getOrThrow()
        clonedAnno.EnableAttr(Attribute.COMPILER_ADD)
        CopyBasicInfo(childDecl, clonedAnno)
        childDecl.annotations.add(clonedAnno)
    } else if (IsForeignNameLikeAnnotation(annotationKind) && childAnno.isSome() && parentAnno.isSome() &&
        GetAnnoValue(childAnno.getOrThrow()) != GetAnnoValue(parentAnno.getOrThrow())) {
        DiagConflictingAnnotation(diag, parentDecl, childDecl, checkingDecl, annotationKind)
    }
}

func CheckForeignAnnotations(
    diag: DiagnosticEngine,
    typeManager: TypeManager,
    parent: MemberSignature,
    child: MemberSignature,
    checkingDecl: Decl
): Unit {
    CheckAnnotation(diag, typeManager, AstAnnotationKind.FOREIGN_NAME, parent, child, checkingDecl)
    CheckAnnotation(diag, typeManager, AstAnnotationKind.FOREIGN_GETTER_NAME, parent, child, checkingDecl)
    CheckAnnotation(diag, typeManager, AstAnnotationKind.FOREIGN_SETTER_NAME, parent, child, checkingDecl)
    CheckAnnotation(diag, typeManager, AstAnnotationKind.OBJ_C_OPTIONAL, parent, child, checkingDecl)
}
