package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::modules.SemaImportManager
import cjcj::sema.*
import cjcj::sema.NativeFFI.Java.CheckJavaHasDefaultAnnotation
import cjcj::utils.CJC_ASSERT

// C++ src/Sema/TypeCheckAnnotation.cpp:27-30.
internal func DiagAnnotationArgTarget(diag: BasicDiagnosticEngine, node: Node): Unit {
    DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_annotation_arg_target, node).Emit()
}

// C++ src/Sema/TypeCheckAnnotation.cpp:32-42.
private func DesugarCustomAnnotation(annotation: Annotation): Option<CallExpr> {
    if (let None <- annotation.baseExpr) {
        return None
    }
    let baseExpr = annotation.baseExpr.getOrThrow()
    annotation.baseExpr = None
    let args = ArrayList<FuncArg>()
    for (arg in annotation.args) {
        args.add(arg)
    }
    annotation.args.clear()
    let callExpr = CreateCallExpr(baseExpr, args)
    callExpr.callKind = CallKind.CALL_ANNOTATION
    CopyBasicInfo(annotation, callExpr)
    AddCurFile(callExpr, file: annotation.curFile)
    return Some(callExpr)
}

// C++ src/Sema/TypeCheckAnnotation.cpp:44-55.
private func RecoverToCustomAnnotation(annotation: Annotation, callExpr: CallExpr): Unit {
    RecoverToCallExpr(callExpr)
    if (let Some(baseFunc) <- callExpr.baseFunc) {
        if (let Some(refExpr) <- (baseFunc as RefExpr)) {
            if ((let Some(callOrPattern) <- refExpr.callOrPattern) && callOrPattern == callExpr) {
                refExpr.callOrPattern = None
            }
        }
    }
    annotation.baseExpr = callExpr.baseFunc
    callExpr.baseFunc = None
    for (arg in callExpr.args) {
        annotation.args.add(arg)
    }
    callExpr.args.clear()
}

// C++ src/Sema/TypeCheckAnnotation.cpp:57-75.
private func DesugarAnnotationsArray(
    importManager: SemaImportManager,
    typeManager: TypeManager,
    decl: Decl,
    annotations: ArrayList<Annotation>,
    annotationsArray: ArrayList<Expr>
): Unit {
    if (!annotationsArray.isEmpty()) {
        let objectClass = importManager.GetCoreDecl<ClassDecl>("Object")
        let arrayStruct = importManager.GetCoreDecl<StructDecl>("Array")
        if ((let Some(objectDecl) <- objectClass) && (let Some(arrayDecl) <- arrayStruct)) {
            let arrayTy = typeManager.GetStructTy(arrayDecl, [objectDecl.GetTy().getOrThrow()])
            let arrayLit = CreateArrayLit(annotationsArray, arrayTy)
            decl.annotationsArray = Some(arrayLit)
            arrayLit.EnableAttr(Attribute.IS_ANNOTATION)
        } else {
            CJC_ASSERT(annotations.size == annotationsArray.size)
            var idx: Int64 = 0
            while (idx < annotations.size) {
                RecoverToCustomAnnotation(annotations[idx],
                    (annotationsArray[idx] as CallExpr).getOrThrow())
                idx++
            }
        }
    }
}

// C++ src/Sema/TypeCheckAnnotation.cpp:77-93.
private func CheckCustomAnnotationPlace(
    diag: BasicDiagnosticEngine,
    decl: Decl,
    annotation: Annotation
): Bool {
    let declsInType = decl.TestAnyAttr(Attribute.IN_CLASSLIKE, Attribute.IN_STRUCT, Attribute.IN_ENUM) ||
        decl.TestAttr(Attribute.IN_EXTEND)
    let isVarOrFunc = (decl as VarDeclAbstract).isSome() || (decl as FuncDecl).isSome()
    let validCustomAnnotationPlace = decl.IsNominalDecl() || IsInstanceConstructor(decl) ||
        decl.TestAttr(Attribute.ENUM_CONSTRUCTOR) || declsInType ||
        (decl.astKind == ASTKind.FUNC_PARAM && decl.outerDecl.isSome()) ||
        (decl.TestAttr(Attribute.GLOBAL) && isVarOrFunc)
    if (!validCustomAnnotationPlace) {
        let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_annotation_custom_place,
            MakeRangeForDeclIdentifier(decl))
        AddHint(builder, annotation)
        builder.AddNote("custom annotations can only be used on non-local declarations")
        builder.Emit()
    }
    return validCustomAnnotationPlace
}

// C++ src/Sema/NativeFFI/ObjC/TypeCheck/TypeCheckAnnotation.cpp:18-30.
private func CheckForeignSetterNameAnnotation(
    diag: BasicDiagnosticEngine,
    annotation: Annotation,
    decl: Decl
): Unit {
    CJC_ASSERT(annotation.kind == AstAnnotationKind.FOREIGN_SETTER_NAME)
    if ((let Some(propDecl) <- (decl as PropDecl)) && !propDecl.isVar) {
        DiagnoseRefactor(diag,
            BasicDiagKindRefactor.sema_objc_setter_name_on_immutable_prop, annotation).Emit()
    }
}

extend TypeChecker {
    // C++ src/Sema/TypeCheckAnnotation.cpp:132-154.
    private func CheckCustomAnnotation(
        ctx: ASTContext,
        decl: Decl,
        annotation: Annotation
    ): Option<CallExpr> {
        CJC_ASSERT(annotation.kind == AstAnnotationKind.CUSTOM)
        let callExpr = DesugarCustomAnnotation(annotation) ?? return None
        if (Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, callExpr)) &&
            CheckCustomAnnotationPlace(impl.diag.getOrThrow(), decl, annotation)) {
            CJC_ASSERT(callExpr.GetTy().getOrThrow().IsClass())
            let args = ArrayList<FuncArg>()
            for (arg in callExpr.args) {
                args.add((ASTCloner.Clone(arg) as FuncArg).getOrThrow())
            }
            annotation.baseExpr = ASTCloner.Clone(callExpr.baseFunc.getOrThrow()) as Expr
            annotation.args.clear()
            for (arg in args) {
                annotation.args.add(arg)
            }
            return Some(callExpr)
        }
        RecoverToCustomAnnotation(annotation, callExpr)
        return None
    }

    // C++ src/Sema/TypeCheckAnnotation.cpp:156-208.
    internal func CheckAnnotations(ctx: ASTContext, decl: Decl): Unit {
        let annotations = ArrayList<Annotation>()
        let annotationsArray = ArrayList<Expr>()
        for (annotation in decl.annotations) {
            if (annotation.kind == AstAnnotationKind.ANNOTATION) {
                CheckAnnotationDecl(ctx, annotation)
            } else if (annotation.kind == AstAnnotationKind.CUSTOM) {
                if (let Some(callExpr) <- CheckCustomAnnotation(ctx, decl, annotation)) {
                    CJC_ASSERT(Ty.IsTyCorrect(callExpr.GetTy()))
                    @When[backend == "cjnative"]
                    let isCJNATIVEBackend = true
                    @When[backend != "cjnative"]
                    let isCJNATIVEBackend = false
                    if (isCJNATIVEBackend && !annotation.isCompileTimeVisible) {
                        callExpr.EnableAttr(Attribute.NO_REFLECT_INFO)
                    }
                    annotationsArray.add(callExpr)
                    annotations.add(annotation)
                }
            } else if (annotation.kind == AstAnnotationKind.C ||
                annotation.kind == AstAnnotationKind.CALLING_CONV ||
                annotation.kind == AstAnnotationKind.FASTNATIVE ||
                annotation.kind == AstAnnotationKind.FROZEN) {
                continue
            } else if (annotation.kind == AstAnnotationKind.JAVA_HAS_DEFAULT) {
                CheckJavaHasDefaultAnnotation(impl.diag.getOrThrow(), annotation, decl)
            } else if (annotation.kind == AstAnnotationKind.FOREIGN_SETTER_NAME) {
                CheckForeignSetterNameAnnotation(impl.diag.getOrThrow(), annotation, decl)
            } else {
                for (arg in annotation.args) {
                    let _ = SynthesizeNode(ctx, SynPos.EXPR_ARG, arg)
                }
            }
        }
        DesugarAnnotationsArray(impl.importManager.getOrThrow(), impl.typeManager, decl,
            annotations, annotationsArray)
    }
}
