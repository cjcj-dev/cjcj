package cjcj::sema.Desugar

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::option.GlobalOptions
import cjcj::sema.*
import cjcj::sema.Desugar.AfterTypeCheck.*

private func UpdatePosForMacroExpandedNodes(pkgs: ArrayList<Package>): Unit {
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

private func CheckExtendDecl(diag: BasicDiagnosticEngine, decl: ExtendDecl): Unit {
    let ty = decl.extendedType.getOrThrow().GetTy().getOrThrow()
    if (!IsMirror(ty) && !IsImpl(ty)) {
        return
    }
    if (!decl.inheritedTypes.isEmpty()) {
        DiagJavaDeclCannotBeExtendedWithInterface(diag, decl)
        decl.EnableAttr(Attribute.IS_BROKEN)
    }
}

public func PerformDesugarAfterTypeCheck(typeManager: TypeManager, pkg: Package,
    context!: Option<ASTContext> = None, options!: GlobalOptions = GlobalOptions(),
    synthesizer!: Option<(ASTContext, SynPos, Node) -> Ty> = None,
    callChecker!: Option<(ASTContext, Ty, CallExpr) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Unit {
    if (let Some(diagValue) <- diag) {
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                    CheckExtendDecl(diagValue, extendDecl)
                }
            }
        }
    }
    DesugarDeclsForPackage(pkg, options.enableCoverage)
    let walker = Walker(pkg, visitPre: { node: Node =>
        match (node.astKind) {
            case ASTKind.FOR_IN_EXPR =>
                if (let Some(forInExpr) <- (node as ForInExpr)) {
                    ReArrangeForInExpr(typeManager, forInExpr, context: context, synthesizer: synthesizer,
                        diag: diag)
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
                    if (binaryExpr.op == TokenKind.COALESCING) {
                        DesugarForCoalescing(typeManager, binaryExpr)
                    }
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
                    DesugarTryToFrame(typeManager, pkg, tryExpr,
                        { target: Ty, call: CallExpr => callChecker.getOrThrow()(context.getOrThrow(), target, call) })
                }
            case ASTKind.PERFORM_EXPR =>
                if (let Some(performExpr) <- (node as PerformExpr)) {
                    DesugarPerformExpr(typeManager, pkg, performExpr,
                        { target: Ty, call: CallExpr => callChecker.getOrThrow()(context.getOrThrow(), target, call) })
                }
            case ASTKind.RESUME_EXPR =>
                if (let Some(resumeExpr) <- (node as ResumeExpr)) {
                    DesugarResumeExpr(typeManager, pkg, resumeExpr,
                        { target: Ty, call: CallExpr => callChecker.getOrThrow()(context.getOrThrow(), target, call) })
                }
            case ASTKind.LIT_CONST_EXPR =>
                if (let Some(litConstExpr) <- (node as LitConstExpr)) {
                    DesugarStrInterpolationExpr(typeManager, pkg, litConstExpr, context: context)
                }
            case _ => ()
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
    AddOptionBox(typeManager, pkg)
    if (options.enableCompileDebug || options.displayLineInfo) {
        let pkgs = ArrayList<Package>()
        pkgs.add(pkg)
        UpdatePosForMacroExpandedNodes(pkgs)
    }
}
