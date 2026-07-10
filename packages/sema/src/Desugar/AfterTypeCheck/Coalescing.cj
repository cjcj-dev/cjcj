package cjcj::sema.Desugar.AfterTypeCheck

import std.collection.*
import cjcj::ast.*
import cjcj::sema.*

private let OPTION_VALUE_CTOR: String = "Some"
private let SOME_VALUE_NAME: String = "x"

private func GetValueMatchCase(ctor: RefExpr, someExpr: Block, someVar: RefExpr, selector: Expr): Option<MatchCase> {
    if (let Some(selectorTy) <- selector.GetTy()) {
        if (!selectorTy.IsCoreOptionType() || selectorTy.typeArgs.isEmpty()) {
            return None
        }
        let innerTy = selectorTy.typeArgs[0]
        let valMatchCase = MatchCase()
        CopyBasicInfo(selector, valMatchCase)
        let someArg = CreateVarPattern(someVar.ref.identifier.Val(), innerTy)
        someArg.begin = someVar.begin
        someArg.end = someVar.end
        if (let Some(varDecl) <- someArg.varDecl) {
            varDecl.identifier = SrcIdentifier(
                someVar.ref.identifier.Val(), someVar.ref.identifier.Begin(),
                someVar.ref.identifier.End(), someVar.ref.identifier.IsRaw())
            varDecl.SetTy(innerTy)
            varDecl.EnableAttr(Attribute.COMPILER_ADD)
            someVar.ref.target = varDecl
            someVar.SetTy(innerTy)
        }
        someArg.SetTy(innerTy)
        someArg.EnableAttr(Attribute.COMPILER_ADD)
        let enumPattern = EnumPattern()
        CopyBasicInfo(someExpr, enumPattern)
        enumPattern.constructor = ctor
        enumPattern.patterns.add(someArg)
        enumPattern.SetTy(selectorTy)
        someExpr.SetTy(innerTy)
        someExpr.curFile = selector.curFile
        valMatchCase.patterns.add(enumPattern)
        valMatchCase.SetCtxExprForPatterns(selector)
        valMatchCase.patternGuard = None
        valMatchCase.exprOrDecls = someExpr
        if (let Some(body) <- valMatchCase.exprOrDecls) {
            if (let Some(bodyTy) <- body.GetTy()) {
                valMatchCase.SetTy(bodyTy)
            }
        }
        return valMatchCase
    }
    return None
}

public func ConstructOptionMatch(selector: Expr, someExpr: Block, otherExpr: Block, someVar: RefExpr,
    someTy: Ty): Option<Expr> {
    if (let Some(selectorTy) <- selector.GetTy()) {
        if (let Some(enumTy) <- (selectorTy as EnumTy)) {
            if (let Some(enumDecl) <- enumTy.decl) {
                if (let Some(ctorDeclNode) <- LookupEnumMember(enumDecl, OPTION_VALUE_CTOR)) {
                    if (let Some(ctorDecl) <- (ctorDeclNode as FuncDecl)) {
                        let matchExpr = MatchExpr()
                        matchExpr.matchMode = true
                        matchExpr.sugarKind = SugarKind.QUEST
                        matchExpr.selector = selector
                        let valueRef = CreateRefExpr(ctorDecl)
                        valueRef.SetTy(someTy)
                        valueRef.ref.targets.add(ctorDecl)
                        if (let Some(valCase) <- GetValueMatchCase(valueRef, someExpr, someVar, selector)) {
                            matchExpr.matchCases.add(valCase)
                            otherExpr.curFile = selector.curFile
                            let wildMatchCase = MatchCase()
                            let wildcard = WildcardPattern()
                            wildMatchCase.patterns.add(wildcard)
                            wildMatchCase.SetCtxExprForPatterns(selector)
                            wildMatchCase.patternGuard = None
                            wildMatchCase.exprOrDecls = otherExpr
                            if (let Some(body) <- wildMatchCase.exprOrDecls) {
                                if (let Some(bodyTy) <- body.GetTy()) {
                                    wildMatchCase.SetTy(bodyTy)
                                }
                            }
                            CopyBasicInfo(selector, wildMatchCase)
                            matchExpr.matchCases.add(wildMatchCase)
                            return matchExpr
                        }
                    }
                }
            }
        }
    }
    return None
}

public func DesugarForCoalescing(typeManager: TypeManager, expr: BinaryExpr): Unit {
    if (let Some(_) <- expr.desugarExpr) {
        return
    }
    if (let Some(left) <- expr.leftExpr) {
        if (let Some(right) <- expr.rightExpr) {
            if (let Some(leftTy) <- left.GetTy()) {
                if (!leftTy.IsCoreOptionType() || leftTy.typeArgs.isEmpty()) {
                    return
                }
                let someVar = CreateRefExpr(SOME_VALUE_NAME)
                let caseBody = Block()
                caseBody.body.add(someVar)
                let wildBody = Block()
                wildBody.body.add(right)
                if (let Some(rightTy) <- right.GetTy()) {
                    wildBody.SetTy(rightTy)
                }
                let paramTys = ArrayList<Ty>()
                paramTys.add(leftTy.typeArgs[0])
                let someTy = typeManager.GetFunctionTy(paramTys.toArray(), leftTy)
                if (let Some(desugar) <- ConstructOptionMatch(left, caseBody, wildBody, someVar, someTy)) {
                    if (let Some(exprTy) <- expr.GetTy()) {
                        desugar.SetTy(exprTy)
                    }
                    expr.desugarExpr = desugar
                    AddCurFile(desugar, file: expr.curFile)
                }
            }
        }
    }
}

public func TryDesugarForCoalescing(typeManager: TypeManager, root: Node): Unit {
    let walker = Walker(root, visitPre: { node: Node =>
        if (let Some(expr) <- (node as BinaryExpr)) {
            if (expr.op == TokenKind.COALESCING) {
                DesugarForCoalescing(typeManager, expr)
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}
