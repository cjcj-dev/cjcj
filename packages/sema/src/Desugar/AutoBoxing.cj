package cangjie_compiler::sema.Desugar

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*
import cangjie_compiler::sema.Desugar.AfterTypeCheck.LookupEnumMember

private let OPTION_VALUE_CTOR: String = "Some"

private func NeedBoxOption(typeManager: TypeManager, child: Ty, target: Ty): Bool {
    if (Ty.IsInitialTy(Some(child)) || Ty.IsInitialTy(Some(target))) {
        return false
    }
    if (typeManager.CheckTypeCompatibility(child, target, implicitBoxed: false,
        isGeneric: target.IsGeneric()) != TypeCompatibility.INCOMPATIBLE) {
        return false
    }
    if (child.kind == TypeKind.TYPE_NOTHING || target.kind != TypeKind.TYPE_ENUM) {
        return false
    }
    let leftLevel = CountOptionNestedLevel(child)
    let rightLevel = CountOptionNestedLevel(target)
    if (leftLevel == rightLevel && child.HasGeneric()) {
        return false
    }
    return target.IsCoreOptionType()
}

private func GetTargetEnumDecl(target: EnumTy): Option<EnumDecl> {
    if (let Some(enumDecl) <- target.decl) {
        return Some(enumDecl)
    }
    return target.declPtr
}

private func FindSomeConstructor(target: EnumTy): Option<FuncDecl> {
    if (let Some(enumDecl) <- GetTargetEnumDecl(target)) {
        if (let Some(someDeclNode) <- LookupEnumMember(enumDecl, OPTION_VALUE_CTOR)) {
            return someDeclNode as FuncDecl
        }
    }
    return None
}

private func CreateSomeRef(typeManager: TypeManager, target: EnumTy, someDecl: FuncDecl): RefExpr {
    let baseFunc = CreateRefExpr(someDecl)
    baseFunc.EnableAttr(Attribute.IMPLICIT_ADD)
    baseFunc.ref.targets.add(someDecl)
    if (let Some(enumDecl) <- GetTargetEnumDecl(target)) {
        if (let Some(someTy) <- someDecl.GetTy()) {
            let typeMapping = GenerateTypeMapping(enumDecl, target.typeArgs)
            baseFunc.SetTy(typeManager.GetInstantiatedTy(someTy, typeMapping))
        }
    } else if (let Some(someTy) <- someDecl.GetTy()) {
        baseFunc.SetTy(someTy)
    }
    return baseFunc
}

private func CloneExprForBox(expr: Expr): Option<Expr> {
    if (let Some(existing) <- expr.desugarExpr) {
        expr.desugarExpr = None
        return existing
    }
    return ASTCloner.Clone(expr) as Expr
}

private func TryOptionBox(typeManager: TypeManager, target: EnumTy, expr: Expr): Unit {
    if (target.typeArgs.size != 1) {
        return
    }
    let targetArg = target.typeArgs[0]
    if (let Some(exprTy) <- expr.GetTy()) {
        if (NeedBoxOption(typeManager, exprTy, targetArg)) {
            if (let Some(innerTarget) <- (targetArg as EnumTy)) {
                TryOptionBox(typeManager, innerTarget, expr)
            }
        }
    }
    if (let Some(someDecl) <- FindSomeConstructor(target)) {
        if (let Some(argExpr) <- CloneExprForBox(expr)) {
            let args = ArrayList<FuncArg>()
            args.add(CreateFuncArg(argExpr))
            let someRef = CreateSomeRef(typeManager, target, someDecl)
            let callExpr = CreateCallExpr(someRef, args, someDecl, target, CallKind.CALL_DECLARED_FUNCTION)
            callExpr.callKind = CallKind.CALL_DECLARED_FUNCTION
            callExpr.SetTy(target)
            if (expr.astKind == ASTKind.BLOCK) {
                let block = Block()
                block.SetTy(target)
                block.body.add(callExpr)
                AddCurFile(block, file: expr.curFile)
                expr.desugarExpr = block
            } else {
                AddCurFile(callExpr, file: expr.curFile)
                expr.desugarExpr = callExpr
            }
            expr.SetTy(target)
        }
    }
}

private func BoxExprIfNeeded(typeManager: TypeManager, target: Ty, expr: Expr): Unit {
    if (!Ty.IsTyCorrect(expr.GetTy())) {
        return
    }
    if (NeedBoxOption(typeManager, expr.GetTy().getOrThrow(), target)) {
        if (let Some(optionTarget) <- (target as EnumTy)) {
            TryOptionBox(typeManager, optionTarget, expr)
        }
    }
}

private func AddOptionBoxHandleTupleLit(typeManager: TypeManager, tupleLit: TupleLit): Unit {
    if (let Some(litTy) <- tupleLit.GetTy()) {
        if (let Some(tupleTy) <- (litTy as TupleTy)) {
            var idx: Int64 = 0
            while (idx < tupleTy.typeArgs.size && idx < tupleLit.children.size) {
                BoxExprIfNeeded(typeManager, tupleTy.typeArgs[idx], tupleLit.children[idx])
                idx++
            }
        }
    }
}

private func AddOptionBoxHandleArrayLit(typeManager: TypeManager, arrayLit: ArrayLit): Unit {
    if (!Ty.IsTyCorrect(arrayLit.GetTy())) {
        return
    }
    if (let Some(arrayTy) <- arrayLit.GetTy()) {
        if (!arrayTy.IsStructArray() || arrayTy.typeArgs.size != 1) {
            return
        }
        let targetTy = arrayTy.typeArgs[0]
        for (child in arrayLit.children) {
            BoxExprIfNeeded(typeManager, targetTy, child)
        }
    }
}

private func AddOptionBoxHandleBlock(typeManager: TypeManager, block: Block, target: Ty): Unit {
    var lastNode: Option<Node> = block.GetLastExprOrDecl()
    var lastTy: Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
    if (let Some(node) <- lastNode) {
        if (let Some(expr) <- (node as Expr)) {
            if (let Some(exprTy) <- expr.GetTy()) {
                lastTy = exprTy
            }
        }
    }
    if (!NeedBoxOption(typeManager, lastTy, target)) {
        return
    }
    if (let None <- lastNode) {
        let unitExpr = CreateUnitExpr(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        unitExpr.curFile = block.curFile
        block.body.add(unitExpr)
        lastNode = unitExpr
    } else if (let Some(node) <- lastNode) {
        if (node.IsDecl()) {
            let unitExpr = CreateUnitExpr(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
            unitExpr.curFile = block.curFile
            block.body.add(unitExpr)
            lastNode = unitExpr
        }
    }
    if (let Some(node) <- lastNode) {
        if (let Some(expr) <- (node as Expr)) {
            if (let Some(optionTarget) <- (target as EnumTy)) {
                TryOptionBox(typeManager, optionTarget, expr)
                if (let Some(exprTy) <- expr.GetTy()) {
                    block.SetTy(exprTy)
                }
            }
        }
    }
}

private func AddOptionBoxHandleMatchExpr(typeManager: TypeManager, matchExpr: MatchExpr): Unit {
    if (let Some(matchTy) <- matchExpr.GetTy()) {
        for (matchCase in matchExpr.matchCases) {
            if (let Some(block) <- matchCase.exprOrDecls) {
                AddOptionBoxHandleBlock(typeManager, block, matchTy)
            }
        }
        for (matchOther in matchExpr.matchCaseOthers) {
            if (let Some(block) <- matchOther.exprOrDecls) {
                AddOptionBoxHandleBlock(typeManager, block, matchTy)
            }
        }
    }
}

private func AddOptionBoxHandleIfExpr(typeManager: TypeManager, ifExpr: IfExpr): Unit {
    if (!Ty.IsTyCorrect(ifExpr.GetTy())) {
        return
    }
    if (let Some(ifTy) <- ifExpr.GetTy()) {
        if (ifTy.IsUnitOrNothing()) {
            return
        }
        if (let Some(thenBlock) <- ifExpr.thenBody) {
            AddOptionBoxHandleBlock(typeManager, thenBlock, ifTy)
        }
        if (ifExpr.hasElse) {
            if (let Some(elseBody) <- ifExpr.elseBody) {
                if (let Some(block) <- (elseBody as Block)) {
                    AddOptionBoxHandleBlock(typeManager, block, ifTy)
                } else if (let Some(elseIfExpr) <- (elseBody as IfExpr)) {
                    if (Ty.IsTyCorrect(elseIfExpr.GetTy())) {
                        BoxExprIfNeeded(typeManager, ifTy, elseIfExpr)
                    }
                }
            }
        }
    }
}

private func AddOptionBoxHandleTryExpr(typeManager: TypeManager, tryExpr: TryExpr): Unit {
    if (let Some(tryTy) <- tryExpr.GetTy()) {
        if (let Some(block) <- tryExpr.tryBlock) {
            AddOptionBoxHandleBlock(typeManager, block, tryTy)
        }
        for (catchBlock in tryExpr.catchBlocks) {
            AddOptionBoxHandleBlock(typeManager, catchBlock, tryTy)
        }
    }
}

private func AddOptionBoxHandleArrayExpr(typeManager: TypeManager, arrayExpr: ArrayExpr): Unit {
    if (!Ty.IsTyCorrect(arrayExpr.GetTy()) || arrayExpr.initFunc.isSome() || arrayExpr.args.isEmpty()) {
        return
    }
    if (let Some(arrayTy) <- arrayExpr.GetTy()) {
        let typeArgs = typeManager.GetTypeArgs(arrayTy)
        if (typeArgs.isEmpty()) {
            return
        }
        var targetArg: Option<FuncArg> = None
        if (arrayExpr.isValueArray) {
            targetArg = arrayExpr.args[0]
        } else if (arrayExpr.args.size > 1) {
            targetArg = arrayExpr.args[1]
        }
        if (let Some(arg) <- targetArg) {
            if (let Some(expr) <- arg.expr) {
                if (let Some(exprTy) <- expr.GetTy()) {
                    if (NeedBoxOption(typeManager, exprTy, typeArgs[0])) {
                        if (let Some(optionTarget) <- (typeArgs[0] as EnumTy)) {
                            TryOptionBox(typeManager, optionTarget, expr)
                            if (let Some(boxedTy) <- expr.GetTy()) {
                                arg.SetTy(boxedTy)
                            }
                        }
                    }
                }
            }
        }
    }
}

private func AddOptionBoxHandleCallArgs(typeManager: TypeManager, args: ArrayList<FuncArg>, funcTy: FuncTy): Unit {
    var idx: Int64 = 0
    while (idx < args.size && idx < funcTy.paramTys.size) {
        if (let Some(expr) <- args[idx].expr) {
            if (let Some(exprTy) <- expr.GetTy()) {
                let paramTy = funcTy.paramTys[idx]
                if (NeedBoxOption(typeManager, exprTy, paramTy)) {
                    if (let Some(optionTarget) <- (paramTy as EnumTy)) {
                        TryOptionBox(typeManager, optionTarget, expr)
                        if (let Some(boxedTy) <- expr.GetTy()) {
                            args[idx].SetTy(boxedTy)
                        }
                    }
                }
            }
        }
        idx++
    }
}

private func AddOptionBoxHandleCallExpr(typeManager: TypeManager, callExpr: CallExpr): Unit {
    if (let Some(base) <- callExpr.baseFunc) {
        if (let Some(baseTy) <- base.GetTy()) {
            if (let Some(funcTy) <- (baseTy as FuncTy)) {
                if (let Some(desugarArgs) <- callExpr.desugarArgs) {
                    AddOptionBoxHandleCallArgs(typeManager, desugarArgs, funcTy)
                } else {
                    AddOptionBoxHandleCallArgs(typeManager, callExpr.args, funcTy)
                }
            }
        }
    }
}

private func AddOptionBoxHandleAssignExpr(typeManager: TypeManager, assignExpr: AssignExpr): Unit {
    if (let Some(_) <- assignExpr.desugarExpr) {
        return
    }
    if (let Some(rightExpr) <- assignExpr.rightExpr) {
        if (let Some(leftValue) <- assignExpr.leftValue) {
            if (let Some(leftTy) <- leftValue.GetTy()) {
                BoxExprIfNeeded(typeManager, leftTy, rightExpr)
            }
        }
    }
}

private func AddOptionBoxHandleVarDecl(typeManager: TypeManager, varDecl: VarDecl): Unit {
    if (let Some(initializer) <- varDecl.initializer) {
        if (let Some(varTy) <- varDecl.GetTy()) {
            BoxExprIfNeeded(typeManager, varTy, initializer)
        }
    }
}

private func AddOptionBoxHandleReturnExpr(typeManager: TypeManager, returnExpr: ReturnExpr): Unit {
    if (let Some(funcBody) <- returnExpr.refFuncBody) {
        if (let Some(funcBodyTy) <- funcBody.GetTy()) {
            if (let Some(funcTy) <- (funcBodyTy as FuncTy)) {
                if (let Some(expr) <- returnExpr.expr) {
                    if (let Some(exprTy) <- expr.GetTy()) {
                        if (NeedBoxOption(typeManager, exprTy, funcTy.retTy)) {
                            if (let Some(optionTarget) <- (funcTy.retTy as EnumTy)) {
                                if (let Some(boxTarget) <- returnExpr.desugarExpr) {
                                    TryOptionBox(typeManager, optionTarget, boxTarget)
                                } else {
                                    TryOptionBox(typeManager, optionTarget, expr)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

public func AddOptionBox(typeManager: TypeManager, pkg: Package): Unit {
    let walker = Walker(pkg, visitPre: { node: Node =>
        if (let Some(varDecl) <- (node as VarDecl)) {
            AddOptionBoxHandleVarDecl(typeManager, varDecl)
        } else if (let Some(assignExpr) <- (node as AssignExpr)) {
            AddOptionBoxHandleAssignExpr(typeManager, assignExpr)
        } else if (let Some(callExpr) <- (node as CallExpr)) {
            AddOptionBoxHandleCallExpr(typeManager, callExpr)
        } else if (let Some(ifExpr) <- (node as IfExpr)) {
            AddOptionBoxHandleIfExpr(typeManager, ifExpr)
        } else if (let Some(tryExpr) <- (node as TryExpr)) {
            AddOptionBoxHandleTryExpr(typeManager, tryExpr)
        } else if (let Some(returnExpr) <- (node as ReturnExpr)) {
            AddOptionBoxHandleReturnExpr(typeManager, returnExpr)
        } else if (let Some(arrayLit) <- (node as ArrayLit)) {
            AddOptionBoxHandleArrayLit(typeManager, arrayLit)
        } else if (let Some(matchExpr) <- (node as MatchExpr)) {
            AddOptionBoxHandleMatchExpr(typeManager, matchExpr)
        } else if (let Some(tupleLit) <- (node as TupleLit)) {
            AddOptionBoxHandleTupleLit(typeManager, tupleLit)
        } else if (let Some(arrayExpr) <- (node as ArrayExpr)) {
            AddOptionBoxHandleArrayExpr(typeManager, arrayExpr)
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}
