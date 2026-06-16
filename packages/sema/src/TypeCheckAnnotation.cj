package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.Range as BasicRange

private func TypeCheckAnnotationRange(node: Node): BasicRange {
    var rangeEnd = node.end
    if (node.begin.fileID != node.end.fileID) {
        rangeEnd = node.begin + 1
    }
    return MakeRange(node.begin, rangeEnd)
}

private func TypeCheckAnnotationIdentifierRange(decl: Decl): BasicRange {
    let beginPos = decl.identifier.Begin()
    if (!beginPos.IsZero()) {
        let endPos = decl.identifier.End()
        if (!endPos.IsZero()) {
            return MakeRange(beginPos, endPos)
        }
    }
    return TypeCheckAnnotationRange(decl)
}

private func TypeCheckAnnotationArgTarget(diag: BasicDiagnosticEngine, node: Node): Unit {
    let builder = diag.DiagnoseRefactor(
        BasicDiagKindRefactor.sema_annotation_arg_target,
        TypeCheckAnnotationRange(node))
    builder.Emit()
}

public func TypeCheckAnnotationCustomPlaceIsValid(decl: Decl): Bool {
    let declsInType = decl.TestAnyAttr(Attribute.IN_CLASSLIKE, Attribute.IN_STRUCT, Attribute.IN_ENUM) ||
        decl.TestAttr(Attribute.IN_EXTEND)
    var isVarOrFunc = false
    if (let Some(_) <- (decl as VarDeclAbstract)) {
        isVarOrFunc = true
    }
    if (let Some(_) <- (decl as FuncDecl)) {
        isVarOrFunc = true
    }
    let globalFunctionOrVariable = decl.TestAttr(Attribute.GLOBAL) && isVarOrFunc
    var funcParamWithOuter = false
    if (decl.astKind == ASTKind.FUNC_PARAM) {
        if (let Some(_) <- decl.outerDecl) {
            funcParamWithOuter = true
        }
    }
    return decl.IsNominalDecl() || IsInstanceConstructor(decl) || decl.TestAttr(Attribute.ENUM_CONSTRUCTOR) ||
        declsInType || funcParamWithOuter || globalFunctionOrVariable
}

public func TypeCheckAnnotationCheckCustomAnnotationPlace(
    diag: BasicDiagnosticEngine,
    decl: Decl,
    annotation: Annotation
): Bool {
    if (TypeCheckAnnotationCustomPlaceIsValid(decl)) {
        return true
    }
    let builder = diag.DiagnoseRefactor(
        BasicDiagKindRefactor.sema_annotation_custom_place,
        TypeCheckAnnotationIdentifierRange(decl))
    builder.AddHint(TypeCheckAnnotationRange(annotation))
    builder.AddNote("custom annotations can only be used on non-local declarations")
    builder.Emit()
    return false
}

public func TypeCheckAnnotationCheckAnnotationDecl(
    diag: BasicDiagnosticEngine,
    annotation: Annotation
): Bool {
    if (annotation.TestAttr(Attribute.TOOL_ADD)) {
        return true
    }
    if (annotation.kind != AstAnnotationKind.ANNOTATION) {
        return true
    }
    if (annotation.args.isEmpty()) {
        return true
    }
    if (annotation.args.size > 1) {
        TypeCheckAnnotationArgTarget(diag, annotation)
        return false
    }
    let arg = annotation.args[0]
    if (arg.name.Val() != "target") {
        TypeCheckAnnotationArgTarget(diag, arg)
        return false
    }
    if (let None <- arg.expr) {
        TypeCheckAnnotationArgTarget(diag, arg)
        return false
    }
    let expr = arg.expr.getOrThrow()
    if (expr.astKind != ASTKind.ARRAY_LIT) {
        let builder = diag.DiagnoseRefactor(
            BasicDiagKindRefactor.sema_annotation_arg_target_array_lit,
            TypeCheckAnnotationRange(expr))
        builder.Emit()
        return false
    }
    return true
}

public func TypeCheckAnnotationDesugarCustomAnnotation(annotation: Annotation): Option<CallExpr> {
    if (let None <- annotation.baseExpr) {
        return None
    }
    let callExpr = CallExpr()
    callExpr.baseFunc = annotation.baseExpr
    annotation.baseExpr = None
    for (arg in annotation.args) {
        callExpr.args.add(arg)
    }
    annotation.args.clear()
    callExpr.callKind = CallKind.CALL_ANNOTATION
    callExpr.begin = annotation.begin
    callExpr.end = annotation.end
    callExpr.curFile = annotation.curFile
    AddCurFile(callExpr, file: annotation.curFile)
    return Some(callExpr)
}

public func TypeCheckAnnotationRecoverCustomAnnotation(annotation: Annotation, callExpr: CallExpr): Unit {
    RecoverToCallExpr(callExpr)
    annotation.baseExpr = callExpr.baseFunc
    callExpr.baseFunc = None
    for (arg in callExpr.args) {
        annotation.args.add(arg)
    }
    callExpr.args.clear()
    TypeCheckAnnotationClearRecoveredCallLink(annotation)
}

private func TypeCheckAnnotationClearRecoveredCallLink(annotation: Annotation): Unit {
    if (let Some(baseValue) <- annotation.baseExpr) {
        if (let Some(refExprValue) <- (baseValue as RefExpr)) {
            if (let Some(nodeValue) <- refExprValue.callOrPattern) {
                if (nodeValue.astKind == ASTKind.CALL_EXPR) {
                    refExprValue.callOrPattern = None
                }
            }
        }
    }
}

private func TypeCheckAnnotationPreserveCustomAnnotationPayload(
    annotation: Annotation,
    callExpr: CallExpr
): Unit {
    annotation.baseExpr = None
    annotation.args.clear()
    if (let Some(baseValue) <- callExpr.baseFunc) {
        annotation.baseExpr = ASTCloner.Clone(baseValue) as Expr
    }
    for (arg in callExpr.args) {
        if (let Some(clonedArg) <- (ASTCloner.Clone(arg) as FuncArg)) {
            annotation.args.add(clonedArg)
        }
    }
    TypeCheckAnnotationClearRecoveredCallLink(annotation)
}

public func TypeCheckAnnotationCheckCustomAnnotation(
    diag: BasicDiagnosticEngine,
    decl: Decl,
    annotation: Annotation
): Option<CallExpr> {
    if (annotation.kind != AstAnnotationKind.CUSTOM) {
        return None
    }
    let callExprOpt = TypeCheckAnnotationDesugarCustomAnnotation(annotation)
    if (let None <- callExprOpt) {
        return None
    }
    let callExpr = callExprOpt.getOrThrow()
    if (!TypeCheckAnnotationCheckCustomAnnotationPlace(diag, decl, annotation)) {
        TypeCheckAnnotationRecoverCustomAnnotation(annotation, callExpr)
        return None
    }
    TypeCheckAnnotationPreserveCustomAnnotationPayload(annotation, callExpr)
    return Some(callExpr)
}

public func TypeCheckAnnotationDesugarAnnotationsArray(
    tm: TypeManager,
    decl: Decl,
    annotations: ArrayList<Annotation>,
    annotationExprs: ArrayList<Expr>,
    objectClass: Option<ClassDecl>,
    arrayStruct: Option<StructDecl>
): Bool {
    if (annotationExprs.isEmpty()) {
        return true
    }
    if (let Some(objectDecl) <- objectClass) {
        if (let Some(arrayDecl) <- arrayStruct) {
            let arrayLit = ArrayLit()
            for (expr in annotationExprs) {
                arrayLit.children.add(expr)
            }
            let objectTy = objectDecl.GetTy() ?? TypeManager.GetInvalidTy()
            arrayLit.SetTy(tm.GetStructTy(arrayDecl, [objectTy]))
            arrayLit.EnableAttr(Attribute.IS_ANNOTATION)
            decl.annotationsArray = Some(arrayLit)
            return true
        }
    }
    if (annotations.size != annotationExprs.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < annotations.size) {
        if (let Some(callExpr) <- (annotationExprs[idx] as CallExpr)) {
            TypeCheckAnnotationRecoverCustomAnnotation(annotations[idx], callExpr)
        }
        idx++
    }
    return false
}

public func TypeCheckAnnotationCheckAnnotations(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    decl: Decl,
    objectClass!: Option<ClassDecl> = None,
    arrayStruct!: Option<StructDecl> = None
): Bool {
    var valid = true
    let checkedAnnotations = ArrayList<Annotation>()
    let annotationExprs = ArrayList<Expr>()
    for (annotation in decl.annotations) {
        if (annotation.kind == AstAnnotationKind.ANNOTATION) {
            if (!TypeCheckAnnotationCheckAnnotationDecl(diag, annotation)) {
                valid = false
            }
        } else if (annotation.kind == AstAnnotationKind.CUSTOM) {
            if (let Some(callExpr) <- TypeCheckAnnotationCheckCustomAnnotation(diag, decl, annotation)) {
                if (!annotation.isCompileTimeVisible) {
                    callExpr.EnableAttr(Attribute.NO_REFLECT_INFO)
                }
                annotationExprs.add(callExpr)
                checkedAnnotations.add(annotation)
            } else {
                valid = false
            }
        }
    }
    if (!TypeCheckAnnotationDesugarAnnotationsArray(tm, decl, checkedAnnotations, annotationExprs,
        objectClass, arrayStruct)) {
        valid = false
    }
    return valid
}

public func SelfhostPortStatus_TypeCheckAnnotation(): Bool {
    return true
}
