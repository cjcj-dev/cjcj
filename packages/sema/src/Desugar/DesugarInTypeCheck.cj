package cangjie_compiler::sema.Desugar

import std.collection.*
import cangjie_compiler::ast.*

private let COMPOSITION_FUNC_NAME: String = "composition"

private func TryDesugarFunctionCallExpr(base: Expr): Expr {
    if (!Ty.IsInitialTy(base.GetTy()) && base.TyKind() != TypeKind.TYPE_FUNC) {
        let memberAccess = CreateMemberAccess(base, "()")
        memberAccess.scopeName = base.scopeName
        memberAccess.scopeLevel = base.scopeLevel
        memberAccess.begin = base.begin
        memberAccess.end = base.end
        return memberAccess
    }
    return base
}

private func CopyUnsafeAttr(source: Expr, target: Expr): Unit {
    if (source.TestAttr(Attribute.UNSAFE)) {
        target.EnableAttr(Attribute.UNSAFE)
    }
}

private func DesugarPipelineExpr(expr: BinaryExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(left) <- expr.leftExpr) {
        if (let Some(right) <- expr.rightExpr) {
            let callExpr = CallExpr()
            CopyBasicInfo(expr, callExpr)
            callExpr.baseFunc = TryDesugarFunctionCallExpr(right)
            let funcArg = FuncArg()
            CopyBasicInfo(left, funcArg)
            funcArg.expr = left
            callExpr.args.add(funcArg)
            callExpr.sourceExpr = expr
            CopyUnsafeAttr(expr, callExpr)
            AddCurFile(callExpr, file: expr.curFile)
            expr.desugarExpr = callExpr
        }
    }
}

private func MakeFlowFuncArg(source: Expr): FuncArg {
    let arg = FuncArg()
    CopyBasicInfo(source, arg)
    let callee = TryDesugarFunctionCallExpr(source)
    callee.isInFlowExpr = true
    arg.expr = callee
    return arg
}

private func DesugarCompositionExpr(expr: BinaryExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(left) <- expr.leftExpr) {
        if (let Some(right) <- expr.rightExpr) {
            let callExpr = CallExpr()
            CopyBasicInfo(expr, callExpr)
            let baseFunc = CreateRefExprInCore(COMPOSITION_FUNC_NAME)
            CopyBasicInfo(expr, baseFunc)
            callExpr.baseFunc = baseFunc
            callExpr.args.add(MakeFlowFuncArg(left))
            callExpr.args.add(MakeFlowFuncArg(right))
            callExpr.sourceExpr = expr
            CopyUnsafeAttr(expr, callExpr)
            AddCurFile(callExpr, file: expr.curFile)
            expr.desugarExpr = callExpr
        }
    }
}

public func DesugarInTypeCheck(root: Node): Unit {
    let walker = Walker(root, visitPost: { node: Node =>
        if (let Some(binaryExpr) <- (node as BinaryExpr)) {
            if (binaryExpr.op == TokenKind.PIPELINE) {
                DesugarPipelineExpr(binaryExpr)
            } else if (binaryExpr.op == TokenKind.COMPOSITION) {
                DesugarCompositionExpr(binaryExpr)
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

public func SelfhostPortStatus_Desugar_DesugarInTypeCheck(): Bool {
    return false
}
