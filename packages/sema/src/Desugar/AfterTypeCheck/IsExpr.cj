package cangjie_compiler::sema.Desugar.AfterTypeCheck

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public func DesugarIsExpr(typeManager: TypeManager, expr: IsExpr): Unit {
    if (!Ty.IsTyCorrect(expr.GetTy())) {
        return
    }
    if (let Some(resultTy) <- expr.GetTy()) {
        if (!resultTy.IsBoolean()) {
            return
        }
    }
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(left) <- expr.leftExpr) {
        if (let Some(typeNode) <- expr.isType) {
            if (let Some(boolTy) <- expr.GetTy()) {
                if (let Some(selectorTy) <- left.GetTy()) {
                    let trueExpr = CreateLitConstExpr(LitConstKind.BOOL, "true", boolTy)
                    trueExpr.begin = expr.isPos
                    let falseExpr = CreateLitConstExpr(LitConstKind.BOOL, "false", boolTy)
                    falseExpr.begin = expr.isPos
                    let wildcard = WildcardPattern()
                    let typePattern = CreateRuntimePreparedTypePattern(typeManager, wildcard, typeNode, left)
                    let matchCases = ArrayList<MatchCase>()
                    matchCases.add(CreateMatchCase(typePattern, trueExpr))
                    let falseWildcard = WildcardPattern()
                    falseWildcard.SetTy(selectorTy)
                    matchCases.add(CreateMatchCase(falseWildcard, falseExpr))
                    let matchExpr = CreateMatchExpr(left, matchCases, boolTy, SugarKind.IS)
                    AddCurFile(matchExpr, file: expr.curFile)
                    expr.desugarExpr = matchExpr
                }
            }
        }
    }
}
