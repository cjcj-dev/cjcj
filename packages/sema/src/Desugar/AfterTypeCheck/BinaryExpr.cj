package cjcj::sema.Desugar.AfterTypeCheck

import std.collection.*
import cjcj::ast.*

private let V_COMPILER: String = "v-compiler"

private func IsPipeline(op: TokenKind): Bool {
    return match (op) {
        case TokenKind.PIPELINE => true
        case _ => false
    }
}

private func GetInnerMostCall(expr: Expr): Option<CallExpr> {
    if (let Some(callExpr) <- (expr as CallExpr)) {
        var current = callExpr
        var keepGoing = true
        while (keepGoing) {
            keepGoing = false
            if (let Some(desugar) <- current.desugarExpr) {
                if (let Some(nextCall) <- (desugar as CallExpr)) {
                    current = nextCall
                    keepGoing = true
                }
            }
        }
        return current
    }
    return None
}

private func BlockifyFlowExpr(expr: BinaryExpr): Unit {
    if (!IsPipeline(expr.op)) {
        return
    }
    if (let Some(desugar) <- expr.desugarExpr) {
        if (let Some(innerCall) <- GetInnerMostCall(desugar)) {
            if (innerCall.args.size != 1) {
                return
            }
            if (let Some(argExpr) <- innerCall.args[0].expr) {
                let varDecl = CreateVarDecl(V_COMPILER, argExpr, None)
                varDecl.fullPackageName = expr.GetFullPackageName()
                CopyBasicInfo(argExpr, varDecl)
                let refExpr = CreateRefExpr(varDecl)
                CopyBasicInfo(argExpr, refExpr)
                innerCall.args[0].expr = refExpr
                let nodes = ArrayList<Node>()
                nodes.add(varDecl)
                nodes.add(desugar)
                let block = CreateBlock(nodes, expr.GetTy())
                CopyBasicInfo(expr, block)
                AddCurFile(block, file: expr.curFile)
                expr.desugarExpr = block
            }
        }
    }
}

public func DesugarBinaryExpr(expr: BinaryExpr): Unit {
    if (!Ty.IsTyCorrect(expr.GetTy())) {
        return
    }
    if (IsPipeline(expr.op)) {
        BlockifyFlowExpr(expr)
    }
}
