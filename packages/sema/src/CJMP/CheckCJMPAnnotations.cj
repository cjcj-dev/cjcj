package cangjie_compiler::sema.CJMP

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::sema.*
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor

private func AnnotationKindName(kind: AstAnnotationKind): String {
    return match (kind) {
        case AstAnnotationKind.JAVA => "Java"
        case AstAnnotationKind.CALLING_CONV => "CallingConv"
        case AstAnnotationKind.C => "C"
        case AstAnnotationKind.JAVA_MIRROR => "JavaMirror"
        case AstAnnotationKind.JAVA_IMPL => "JavaImpl"
        case AstAnnotationKind.JAVA_HAS_DEFAULT => "JavaHasDefault"
        case AstAnnotationKind.OBJ_C_MIRROR => "ObjCMirror"
        case AstAnnotationKind.OBJ_C_IMPL => "ObjCImpl"
        case AstAnnotationKind.OBJ_C_INIT => "ObjCInit"
        case AstAnnotationKind.OBJ_C_OPTIONAL => "ObjCOptional"
        case AstAnnotationKind.FOREIGN_NAME => "ForeignName"
        case AstAnnotationKind.FOREIGN_GETTER_NAME => "ForeignGetterName"
        case AstAnnotationKind.FOREIGN_SETTER_NAME => "ForeignSetterName"
        case AstAnnotationKind.ATTRIBUTE => "Attribute"
        case AstAnnotationKind.NUMERIC_OVERFLOW => "Overflow"
        case AstAnnotationKind.INTRINSIC => "Intrinsic"
        case AstAnnotationKind.WHEN => "When"
        case AstAnnotationKind.FASTNATIVE => "FastNative"
        case AstAnnotationKind.ANNOTATION => "Annotation"
        case AstAnnotationKind.CUSTOM => "Custom"
        case AstAnnotationKind.CONSTSAFE => "ConstSafe"
        case AstAnnotationKind.DEPRECATED => "Deprecated"
        case AstAnnotationKind.FROZEN => "Frozen"
        case AstAnnotationKind.ENSURE_PREPARED_TO_MOCK => "EnsurePreparedToMock"
        case AstAnnotationKind.NON_PRODUCT => "NonProduct"
        case AstAnnotationKind.UNKNOWN => "Unknown"
    }
}

private func NonSerializedAnnotationAttr(kind: AstAnnotationKind): Option<Attribute> {
    return match (kind) {
        case AstAnnotationKind.C => Some(Attribute.C)
        case AstAnnotationKind.JAVA_MIRROR => Some(Attribute.JAVA_MIRROR)
        case AstAnnotationKind.JAVA_HAS_DEFAULT => Some(Attribute.JAVA_HAS_DEFAULT)
        case AstAnnotationKind.OBJ_C_MIRROR => Some(Attribute.OBJ_C_MIRROR)
        case AstAnnotationKind.OBJ_C_INIT => Some(Attribute.OBJ_C_INIT)
        case AstAnnotationKind.OBJ_C_OPTIONAL => Some(Attribute.OBJ_C_OPTIONAL)
        case _ => None
    }
}

private func IsNonSerializedAnnotation(kind: AstAnnotationKind): Bool {
    if (let Some(_) <- NonSerializedAnnotationAttr(kind)) {
        return true
    }
    return false
}

private func IsUnsupportedAnnotation(kind: AstAnnotationKind): Bool {
    return kind == AstAnnotationKind.JAVA || kind == AstAnnotationKind.CALLING_CONV ||
        kind == AstAnnotationKind.FOREIGN_GETTER_NAME || kind == AstAnnotationKind.FOREIGN_SETTER_NAME ||
        kind == AstAnnotationKind.CONSTSAFE || kind == AstAnnotationKind.ENSURE_PREPARED_TO_MOCK ||
        kind == AstAnnotationKind.NON_PRODUCT || kind == AstAnnotationKind.UNKNOWN
}

private func IsSpecialHandledAnnotation(annotation: Annotation): Bool {
    return annotation.kind == AstAnnotationKind.DEPRECATED || annotation.kind == AstAnnotationKind.ATTRIBUTE ||
        IsNonSerializedAnnotation(annotation.kind) || IsUnsupportedAnnotation(annotation.kind)
}

private func PostCheckDeprecatedAnnotation(specific: Decl, checker: MPTypeCheckerImpl): Bool {
    if (let Some(specificDeprecation) <- FindFirstAnnotation(specific, AstAnnotationKind.DEPRECATED)) {
        if (!specificDeprecation.TestAttr(Attribute.COMPILER_ADD)) {
            let builder = DiagnoseRefactor(
                checker.diag,
                BasicDiagKindRefactor.sema_specific_has_deprecated_annotation,
                specificDeprecation,
                arguments: ["Deprecated", DeclKindToString(specific), specific.identifier.Val()])
            builder.AddNote("specific declarations implicitly inherit deprecation from the common declarations")
            builder.Emit()
            return false
        }
    }
    return true
}

private func FuncArgEquals(left: FuncArg, right: FuncArg): Bool {
    if (left.name.Val() != right.name.Val()) {
        return false
    }
    if (let Some(leftExpr) <- left.expr) {
        if (let Some(rightExpr) <- right.expr) {
            if (let Some(leftLit) <- (leftExpr as LitConstExpr)) {
                if (let Some(rightLit) <- (rightExpr as LitConstExpr)) {
                    return leftLit.kind == rightLit.kind && leftLit.ToString() == rightLit.ToString()
                }
            }
        }
    }
    return false
}

private func AnnotationEquals(left: Annotation, right: Annotation): Bool {
    if (left.kind != right.kind) {
        return false
    }
    if (left.kind == AstAnnotationKind.CUSTOM && left.identifier.Val() != right.identifier.Val()) {
        return false
    }
    if (left.args.size != right.args.size) {
        return false
    }
    for (idx in 0..left.args.size) {
        if (!FuncArgEquals(left.args[idx], right.args[idx])) {
            return false
        }
    }
    return true
}

private func FindAnnotationIndex(target: Decl, sample: Annotation, matchedTarget: ArrayList<Bool>): Option<Int64> {
    for (idx in 0..target.annotations.size) {
        if (!matchedTarget[idx] && AnnotationEquals(sample, target.annotations[idx])) {
            return Some(idx)
        }
    }
    return None
}

private func FormatAnnotationMismatchNote(annotation: Annotation): String {
    var out = "The mismatched annotation is @" + annotation.identifier.Val()
    if (!annotation.args.isEmpty()) {
        let parts = ArrayList<String>()
        for (arg in annotation.args) {
            parts.add(arg.ToString())
        }
        out += "(" + JoinStrings(parts, ", ") + ")"
    }
    return out
}

private func FormatAnnotationMismatchNote(kind: AstAnnotationKind): String {
    return "The mismatched annotation is @" + AnnotationKindName(kind)
}

private func ReportAnnotationMismatch(annotation: Annotation, decl: Decl, checker: MPTypeCheckerImpl): Unit {
    if (decl.TestAttr(Attribute.SPECIFIC)) {
        let builder = DiagnoseRefactor(
            checker.diag,
            BasicDiagKindRefactor.sema_specific_has_different_annotation,
            decl,
            arguments: [DeclKindToString(decl)])
        builder.AddNote(FormatAnnotationMismatchNote(annotation))
        builder.Emit()
        return
    }

    let builder = DiagnoseRefactor(
        checker.diag,
        BasicDiagKindRefactor.sema_specific_has_different_annotation,
        annotation,
        arguments: [DeclKindToString(decl)])
    AddHint(builder, decl, arguments: ["The corresponding common declaration"])
    builder.AddNote("Either remove the specific annotation or add it to the common declaration")
    builder.Emit()
}

private func PostCheckNonSerializedAnnotations(common: Decl, specific: Decl, checker: MPTypeCheckerImpl): Bool {
    var result = true
    let kinds = [
        AstAnnotationKind.C,
        AstAnnotationKind.JAVA_MIRROR,
        AstAnnotationKind.JAVA_HAS_DEFAULT,
        AstAnnotationKind.OBJ_C_MIRROR,
        AstAnnotationKind.OBJ_C_INIT,
        AstAnnotationKind.OBJ_C_OPTIONAL
    ]
    for (kind in kinds) {
        if (let Some(attr) <- NonSerializedAnnotationAttr(kind)) {
            if (common.TestAttr(attr) != specific.TestAttr(attr)) {
                if (let Some(specificAnnotation) <- FindFirstAnnotation(specific, kind)) {
                    ReportAnnotationMismatch(specificAnnotation, specific, checker)
                } else {
                    let builder = DiagnoseRefactor(
                        checker.diag,
                        BasicDiagKindRefactor.sema_specific_has_different_annotation,
                        specific,
                        arguments: [DeclKindToString(specific)])
                    builder.AddNote(FormatAnnotationMismatchNote(kind))
                    builder.Emit()
                }
                result = false
            }
        }
    }
    return result
}

private func MatchAnnotationsFromSource(source: Decl, target: Decl, matchedSource: ArrayList<Bool>,
    matchedTarget: ArrayList<Bool>, checker: MPTypeCheckerImpl): Bool {
    var result = true
    for (idx in 0..source.annotations.size) {
        let annotation = source.annotations[idx]
        if (IsSpecialHandledAnnotation(annotation) || matchedSource[idx]) {
            continue
        }
        if (let Some(targetIdx) <- FindAnnotationIndex(target, annotation, matchedTarget)) {
            matchedSource[idx] = true
            matchedTarget[targetIdx] = true
        } else {
            ReportAnnotationMismatch(annotation, target, checker)
            result = false
        }
    }
    return result
}

private func MatchedFlags(size: Int64): ArrayList<Bool> {
    let out = ArrayList<Bool>()
    for (_ in 0..size) {
        out.add(false)
    }
    return out
}

private func IsCommonOrSpecific(node: Node): Bool {
    return node.TestAnyAttr(Attribute.COMMON, Attribute.SPECIFIC)
}

private func PropagateDeprecatedAnnotations(common: Decl, specific: Decl): Unit {
    if (let Some(commonDeprecation) <- FindFirstAnnotation(common, AstAnnotationKind.DEPRECATED)) {
        if (let None <- FindFirstAnnotation(specific, AstAnnotationKind.DEPRECATED)) {
            if (let Some(cloned) <- (ASTCloner.Clone(commonDeprecation) as Annotation)) {
                specific.annotations.add(cloned)
            }
        }
    }
}

private func PropagateAttributeAnnotations(common: Decl, specific: Decl): Unit {
    for (annotation in common.annotations) {
        if (annotation.kind == AstAnnotationKind.ATTRIBUTE) {
            if (let Some(cloned) <- (ASTCloner.Clone(annotation) as Annotation)) {
                specific.annotations.add(cloned)
            }
        }
    }
}

extend MPTypeCheckerImpl {
    public func MatchCJMPDeclAnnotations(common: Decl, specific: Decl): Bool {
        var result = PostCheckDeprecatedAnnotation(specific, this)
        result = PostCheckNonSerializedAnnotations(common, specific, this) && result

        let matchedCommonAnnotations = MatchedFlags(common.annotations.size)
        let matchedSpecificAnnotations = MatchedFlags(specific.annotations.size)
        result = MatchAnnotationsFromSource(common, specific, matchedCommonAnnotations,
            matchedSpecificAnnotations, this) && result
        result = MatchAnnotationsFromSource(specific, common, matchedSpecificAnnotations,
            matchedCommonAnnotations, this) && result
        return result
    }

    public func CheckNotAllowedAnnotations(pkg: Package): Unit {
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (node.IsDecl() && IsCommonOrSpecific(node) && !node.TestAttr(Attribute.FROM_COMMON_PART)) {
                if (let Some(decl) <- (node as Decl)) {
                    for (annotation in decl.annotations) {
                        if (IsUnsupportedAnnotation(annotation.kind)) {
                            let builder = DiagnoseRefactor(
                                diag,
                                BasicDiagKindRefactor.sema_common_specific_annotation_not_allowed,
                                annotation,
                                arguments: [AnnotationKindName(annotation.kind)])
                            builder.AddNote("This annotation kind is not supported on common/specific")
                            builder.Emit()
                        }
                    }
                }
            }
            if (node.astKind == ASTKind.FUNC_BODY) {
                return VisitAction.SKIP_CHILDREN
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    public func PropagateCJMPDeclAnnotations(common: Decl, specific: Decl): Unit {
        PropagateDeprecatedAnnotations(common, specific)
        PropagateAttributeAnnotations(common, specific)
    }
}
