package cangjie_compiler::sema.Desugar

import cangjie_compiler::ast.*
import cangjie_compiler::option.GlobalOptions
import cangjie_compiler::sema.*
import cangjie_compiler::sema.Desugar.AfterTypeCheck.*

public func PerformDesugarAfterTypeCheck(typeManager: TypeManager, pkg: Package,
    context!: Option<ASTContext> = None, options!: GlobalOptions = GlobalOptions(),
    synthesizer!: Option<(ASTContext, SynPos, Node) -> Ty> = None): Unit {
    DesugarDeclsForPackage(pkg, options.enableCoverage)
    let walker = Walker(pkg, visitPre: { node: Node =>
        match (node.astKind) {
            case ASTKind.FOR_IN_EXPR =>
                if (let Some(forInExpr) <- (node as ForInExpr)) {
                    DesugarForInExpr(typeManager, forInExpr, context: context, synthesizer: synthesizer)
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
                    DesugarTokenCallExpr(callExpr)
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
                    DesugarTryToFrame(typeManager, pkg, tryExpr)
                }
            case ASTKind.PERFORM_EXPR =>
                if (let Some(performExpr) <- (node as PerformExpr)) {
                    DesugarPerformExpr(typeManager, pkg, performExpr)
                }
            case ASTKind.RESUME_EXPR =>
                if (let Some(resumeExpr) <- (node as ResumeExpr)) {
                    DesugarResumeExpr(typeManager, pkg, resumeExpr)
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
}

public func SelfhostPortStatus_Desugar_AfterTypeCheck(): Bool {
    return false
}
