package cjcj::sema.Desugar

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::mangle.BaseMangler
import cjcj::option.GlobalOptions
import cjcj::sema.*
import cjcj::sema.Desugar.AfterTypeCheck.*
import cjcj::sema.NativeFFI.Java.JavaInteropManager
import cjcj::sema.NativeFFI.ObjC.InteropContext
import cjcj::sema.NativeFFI.ObjC.Desugar as DesugarObjC
import cjcj::modules.SemaImportManager

public func UpdatePosForMacroExpandedNodes(pkgs: ArrayList<Package>): Unit {
    let visit = { curNode: Node =>
        if (let None <- curNode.curMacroCall) {
            return VisitAction.WALK_CHILDREN
        }
        curNode.begin = curNode.GetDebugPos(curNode.begin)
        curNode.end = curNode.GetDebugPos(curNode.end)
        VisitAction.WALK_CHILDREN
    }
    for (pkg in pkgs) {
        let walker = Walker(pkg, visitPre: visit)
        walker.Walk()
    }
}

public func PerformDesugarAfterTypeCheck(typeManager: TypeManager, importManager: SemaImportManager,
    mangler: BaseMangler, structMemberMap: HashMap<InheritableDecl, MemberMap>, pkg: Package,
    context!: Option<ASTContext> = None, options!: GlobalOptions = GlobalOptions(),
    synthesizer!: Option<(ASTContext, SynPos, Node) -> Ty> = None,
    callChecker!: Option<(ASTContext, Ty, CallExpr) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Unit {
    let diagValue = diag.getOrThrow()
    let javaInteropManager = JavaInteropManager(importManager, typeManager, diagValue, mangler,
        options.outputJavaGenDir, options.output)
    javaInteropManager.CheckImplRedefinition(pkg)
    for (file in pkg.files) {
        javaInteropManager.CheckTypes(file)
    }
    javaInteropManager.DesugarPackage(pkg, structMemberMap,
        { node: Node => DesugarForPropDecl(typeManager, node) })
    DesugarObjC(InteropContext(pkg, typeManager, importManager, diagValue, mangler, options.output,
        options.outputObjCGenDir, structMemberMap, options.target.os,
        { node: Node => DesugarForPropDecl(typeManager, node) }))
    DesugarDeclsForPackage(pkg, options.enableCoverage)
    let walker = Walker(pkg, visitPre: { node: Node =>
        match (node.astKind) {
            case ASTKind.FOR_IN_EXPR =>
                if (let Some(forInExpr) <- (node as ForInExpr)) {
                    @When[backend == "cjnative"]
                    let shouldRearrangeForIn = true
                    @When[backend != "cjnative"]
                    let shouldRearrangeForIn = false
                    if (shouldRearrangeForIn && forInExpr.inExpression.isSome()) {
                        ReArrangeForInExpr(typeManager, forInExpr, context: context, synthesizer: synthesizer,
                            diag: diag)
                    }
                }
            case ASTKind.LIT_CONST_EXPR =>
                if (let Some(litConstExpr) <- (node as LitConstExpr)) {
                    if (litConstExpr.siExpr.isSome() && Ty.IsTyCorrect(litConstExpr.GetTy())) {
                        DesugarStrInterpolationExpr(typeManager, pkg, litConstExpr, context: context)
                    }
                }
            case ASTKind.FUNC_PARAM =>
                if (let Some(param) <- (node as FuncParam)) {
                    PostProcessFuncParam(param, options)
                }
            case ASTKind.RANGE_EXPR =>
                if (let Some(rangeExpr) <- (node as RangeExpr)) {
                    DesugarRangeExpr(typeManager, rangeExpr)
                }
            case ASTKind.CALL_EXPR =>
                if (let Some(callExpr) <- (node as CallExpr)) {
                    DesugarIntrinsicCallExpr(callExpr)
                    if (let Some(ctx) <- context) {
                        if (let Some(synthesize) <- synthesizer) {
                            DesugarTokenCallExpr(ctx, callExpr, synthesize)
                        }
                    }
                }
            case ASTKind.BINARY_EXPR =>
                if (let Some(binaryExpr) <- (node as BinaryExpr)) {
                    DesugarBinaryExpr(binaryExpr)
                }
            case ASTKind.IS_EXPR =>
                if (let Some(isExpr) <- (node as IsExpr)) {
                    DesugarIsExpr(typeManager, isExpr)
                }
            case ASTKind.AS_EXPR =>
                if (let Some(asExpr) <- (node as AsExpr)) {
                    DesugarAsExpr(typeManager, asExpr)
                }
            case ASTKind.ARRAY_LIT =>
                if (let Some(arrayLit) <- (node as ArrayLit)) {
                    AddArrayLitConstructor(arrayLit)
                }
            case ASTKind.IF_EXPR =>
                if (let Some(ifExpr) <- (node as IfExpr)) {
                    DesugarIfExpr(typeManager, ifExpr)
                }
            case ASTKind.SPAWN_EXPR =>
                if (let Some(spawnExpr) <- (node as SpawnExpr)) {
                    DesugarSpawnExpr(typeManager, spawnExpr)
                }
            case ASTKind.TRY_EXPR =>
                if (let Some(tryExpr) <- (node as TryExpr)) {
                    DesugarTryWithResourcesExpr(typeManager, pkg, tryExpr, context: context, synthesizer: synthesizer)
                    DesugarTryToFrame(typeManager, importManager, context.getOrThrow(), pkg, tryExpr,
                        { pos: SynPos, node: Node => synthesizer.getOrThrow()(context.getOrThrow(), pos, node) },
                        { target: Ty, call: CallExpr => callChecker.getOrThrow()(context.getOrThrow(), target, call) })
                }
            case ASTKind.PERFORM_EXPR =>
                if (let Some(performExpr) <- (node as PerformExpr)) {
                    DesugarPerformExpr(typeManager, importManager, pkg, performExpr,
                        { target: Ty, call: CallExpr => callChecker.getOrThrow()(context.getOrThrow(), target, call) })
                }
            case ASTKind.RESUME_EXPR =>
                if (let Some(resumeExpr) <- (node as ResumeExpr)) {
                    DesugarResumeExpr(typeManager, importManager, pkg, resumeExpr,
                        { target: Ty, call: CallExpr => callChecker.getOrThrow()(context.getOrThrow(), target, call) })
                }
            case _ => ()
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}
