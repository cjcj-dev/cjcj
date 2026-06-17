package cangjie_compiler::sema.Desugar

import cangjie_compiler::ast.*
import cangjie_compiler::option.GlobalOptions
import cangjie_compiler::sema.*
import cangjie_compiler::sema.Desugar.AfterTypeCheck.*

public func PerformDesugarAfterTypeCheck(typeManager: TypeManager, pkg: Package,
    options!: GlobalOptions = GlobalOptions()): Unit {
    DesugarDeclsForPackage(pkg, options.enableCoverage)
    let walker = Walker(pkg, visitPre: { node: Node =>
        if (node.TestAnyAttr(Attribute.HAS_BROKEN, Attribute.IS_BROKEN)) {
            return VisitAction.SKIP_CHILDREN
        }
        match (node.astKind) {
            case ASTKind.FOR_IN_EXPR =>
                if (let Some(forInExpr) <- (node as ForInExpr)) {
                    DesugarForInExpr(typeManager, forInExpr)
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
                    DesugarTryWithResourcesExpr(typeManager, pkg, tryExpr)
                }
            case ASTKind.LIT_CONST_EXPR =>
                if (let Some(litConstExpr) <- (node as LitConstExpr)) {
                    DesugarStrInterpolationExpr(typeManager, pkg, litConstExpr)
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
