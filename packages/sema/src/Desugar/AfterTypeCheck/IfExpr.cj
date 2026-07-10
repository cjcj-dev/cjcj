package cjcj::sema.Desugar.AfterTypeCheck

import cjcj::ast.*
import cjcj::sema.*

private func InsertUnitForIfExpr(typeManager: TypeManager, expr: IfExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(exprTy) <- expr.GetTy()) {
        if (!exprTy.IsUnit()) {
            return
        }
        if (let Some(thenBody) <- expr.thenBody) {
            if (let Some(thenTy) <- thenBody.GetTy()) {
                if (typeManager.IsSubtype(thenTy, exprTy)) {
                    return
                }
            } else {
                return
            }
            if (thenBody.body.isEmpty()) {
                return
            }
            let unitExpr = CreateUnitExpr(exprTy)
            CopyBasicInfo(thenBody.body[thenBody.body.size - 1], unitExpr)
            thenBody.body.add(unitExpr)
            thenBody.SetTy(exprTy)
            if (let Some(_) <- expr.elseBody) {
                return
            }
            let elseBlock = Block()
            elseBlock.body.add(CreateUnitExpr(exprTy))
            elseBlock.SetTy(exprTy)
            expr.elseBody = elseBlock
            expr.hasElse = true
            AddCurFile(elseBlock, file: expr.curFile)
        }
    }
}

public func DesugarIfExpr(typeManager: TypeManager, expr: IfExpr): Unit {
    InsertUnitForIfExpr(typeManager, expr)
}
