package cangjie_compiler::ast

import std.collection.*

private func UnsetCallExprOfNode(expr: Expr): Unit {
    if (let Some(nameRef) <- (expr as NameReferenceExpr)) {
        nameRef.isAlone = true
        nameRef.callOrPattern = None
    }
}

private func TryRecoverFunctionCallExpr(base: Option<Expr>): Option<Expr> {
    if (let Some(expr) <- base) {
        if (let Some(member) <- (expr as MemberAccess)) {
            if (member.field == "()") {
                return member.baseExpr
            }
        }
        return expr
    }
    return None
}

private func AddToTrash(owner: Node, expr: Expr): Unit {
    if (let Some(file) <- owner.curFile) {
        file.trashBin.add(expr)
    }
}

private func ReplaceFuncArgs(target: ArrayList<FuncArg>, source: ArrayList<FuncArg>): Unit {
    target.clear()
    for (arg in source) {
        target.add(arg)
    }
}

private func EnsureFuncArg(target: ArrayList<FuncArg>, idx: Int64): FuncArg {
    while (target.size <= idx) {
        target.add(FuncArg())
    }
    return target[idx]
}

private func SetFuncArg(target: ArrayList<FuncArg>, idx: Int64, arg: FuncArg): Unit {
    while (target.size <= idx) {
        target.add(FuncArg())
    }
    let values = ArrayList<FuncArg>()
    var curIdx: Int64 = 0
    while (curIdx < target.size) {
        if (curIdx == idx) {
            values.add(arg)
        } else {
            values.add(target[curIdx])
        }
        curIdx++
    }
    target.clear()
    for (value in values) {
        target.add(value)
    }
}

private func ReplaceIndexExprs(target: ArrayList<Expr>, args: ArrayList<FuncArg>, limit: Int64): Unit {
    target.clear()
    var idx: Int64 = 0
    while (idx < args.size && idx < limit) {
        if (let Some(expr) <- args[idx].expr) {
            expr.mapExpr = None
            target.add(expr)
        }
        idx++
    }
}

private func FirstArgExpr(args: ArrayList<FuncArg>): Option<Expr> {
    if (args.isEmpty()) {
        return None
    }
    return args[0].expr
}

private func RecoverToPipelineExpr(be: BinaryExpr, callExpr: CallExpr): Unit {
    be.rightExpr = TryRecoverFunctionCallExpr(callExpr.baseFunc)
    if (let Some(right) <- be.rightExpr) {
        UnsetCallExprOfNode(right)
    }
    be.leftExpr = FirstArgExpr(callExpr.args)
    be.desugarExpr = None
}

private func RecoverToCompositionExpr(be: BinaryExpr, callExpr: CallExpr): Unit {
    if (callExpr.args.size > 0) {
        be.leftExpr = TryRecoverFunctionCallExpr(callExpr.args[0].expr)
        if (let Some(left) <- be.leftExpr) {
            UnsetCallExprOfNode(left)
        }
    }
    if (callExpr.args.size > 1) {
        be.rightExpr = TryRecoverFunctionCallExpr(callExpr.args[1].expr)
        if (let Some(right) <- be.rightExpr) {
            UnsetCallExprOfNode(right)
        }
    }
    be.desugarExpr = None
}

public func RecoverToSubscriptExpr(se: SubscriptExpr): Unit {
    if (let Some(desugar) <- se.desugarExpr) {
        if (let Some(callExpr) <- (desugar as CallExpr)) {
            RecoverToCallExpr(callExpr)
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                if (let Some(member) <- (baseFunc as MemberAccess)) {
                    se.baseExpr = member.baseExpr
                    ReplaceIndexExprs(se.indexExprs, callExpr.args, callExpr.args.size)
                    se.desugarExpr = None
                    if (let Some(base) <- se.baseExpr) {
                        UnsetCallExprOfNode(base)
                    }
                }
            }
        }
    }
}

public func RecoverToUnaryExpr(ue: UnaryExpr): Unit {
    if (let Some(desugar) <- ue.desugarExpr) {
        if (let Some(callExpr) <- (desugar as CallExpr)) {
            RecoverToCallExpr(callExpr)
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                if (let Some(member) <- (baseFunc as MemberAccess)) {
                    ue.expr = member.baseExpr
                    if (let Some(expr) <- ue.expr) {
                        UnsetCallExprOfNode(expr)
                    }
                    ue.desugarExpr = None
                }
            }
        }
    }
}

public func RecoverToBinaryExpr(be: BinaryExpr): Unit {
    if (let Some(desugar) <- be.desugarExpr) {
        if (let Some(callExpr) <- (desugar as CallExpr)) {
            RecoverToCallExpr(callExpr)
            if (be.op == TokenKind.PIPELINE) {
                RecoverToPipelineExpr(be, callExpr)
                return
            }
            if (be.op == TokenKind.COMPOSITION) {
                RecoverToCompositionExpr(be, callExpr)
                return
            }
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                if (let Some(member) <- (baseFunc as MemberAccess)) {
                    be.leftExpr = member.baseExpr
                    be.rightExpr = FirstArgExpr(callExpr.args)
                    if (let Some(left) <- be.leftExpr) {
                        UnsetCallExprOfNode(left)
                    }
                    AddToTrash(be, desugar)
                    be.desugarExpr = None
                }
            }
        } else {
            be.desugarExpr = None
        }
    }
}

public func RecoverToAssignExpr(ae: AssignExpr): Unit {
    if (let Some(desugar) <- ae.desugarExpr) {
        if (let Some(callExpr) <- (desugar as CallExpr)) {
            if (let Some(leftValue) <- ae.leftValue) {
                if (let Some(subscript) <- (leftValue as SubscriptExpr)) {
                    RecoverToCallExpr(callExpr)
                    if (let Some(baseFunc) <- callExpr.baseFunc) {
                        if (let Some(member) <- (baseFunc as MemberAccess)) {
                            subscript.baseExpr = member.baseExpr
                            let rightIdx = callExpr.args.size - 1
                            ReplaceIndexExprs(subscript.indexExprs, callExpr.args, rightIdx)
                            leftValue.curFile = ae.curFile
                            if (rightIdx >= 0) {
                                if (ae.isCompound) {
                                    if (let Some(lastExpr) <- callExpr.args[rightIdx].expr) {
                                        if (let Some(binary) <- (lastExpr as BinaryExpr)) {
                                            ae.rightExpr = binary.rightExpr
                                        } else {
                                            ae.rightExpr = lastExpr
                                        }
                                    }
                                } else {
                                    ae.rightExpr = callExpr.args[rightIdx].expr
                                }
                            }
                            if (let Some(base) <- subscript.baseExpr) {
                                base.mapExpr = None
                                UnsetCallExprOfNode(base)
                            }
                            ae.desugarExpr = None
                        }
                    }
                }
            }
        } else if (let Some(assignExpr) <- (desugar as AssignExpr)) {
            if (let Some(right) <- assignExpr.rightExpr) {
                if (let Some(callExpr) <- (right as CallExpr)) {
                    RecoverToCallExpr(callExpr)
                    ae.leftValue = assignExpr.leftValue
                    ae.rightExpr = FirstArgExpr(callExpr.args)
                    ae.desugarExpr = None
                    if (let Some(leftValue) <- ae.leftValue) {
                        leftValue.mapExpr = None
                    }
                }
            }
        }
    }
}

public func RecoverCallFromArrayExpr(ce: CallExpr): Unit {
    if (let Some(desugar) <- ce.desugarExpr) {
        if (let Some(arrayExpr) <- (desugar as ArrayExpr)) {
            for (arg in arrayExpr.args) {
                ce.args.add(arg)
            }
            ce.desugarExpr = None
        }
    }
}

public func RecoverJArrayCtorCall(ce: CallExpr): Unit {
    RecoverCallFromArrayExpr(ce)
}

public func RecoverToCallExpr(ce: CallExpr): Unit {
    if (let Some(desugar) <- ce.desugarExpr) {
        if (let Some(nested) <- desugar.desugarExpr) {
            if (let Some(desugarCallExpr) <- (desugar as CallExpr)) {
                RecoverToCallExpr(desugarCallExpr)
                ce.callKind = desugarCallExpr.callKind
            }
        }
        if (ce.callKind == CallKind.CALL_VARIADIC_FUNCTION) {
            RecoverFromVariadicCallExpr(ce)
            return
        }
        if (let Some(callExpr) <- (desugar as CallExpr)) {
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                if (let Some(member) <- (baseFunc as MemberAccess)) {
                    if (member.field == "()") {
                        ce.baseFunc = member.baseExpr
                        ReplaceFuncArgs(ce.args, callExpr.args)
                        AddToTrash(ce, desugar)
                        ce.desugarExpr = None
                    }
                }
            }
            return
        }
        if (desugar.astKind == ASTKind.ARRAY_EXPR) {
            RecoverCallFromArrayExpr(ce)
            return
        }
        if (let Some(pointerExpr) <- (desugar as PointerExpr)) {
            if (let Some(arg) <- pointerExpr.arg) {
                ce.args.add(arg)
            }
            ce.desugarExpr = None
        }
    }
}

public func RecoverFromVariadicCallExpr(ce: CallExpr): Unit {
    if (let Some(desugar) <- ce.desugarExpr) {
        if (let Some(callExpr) <- (desugar as CallExpr)) {
            ce.callKind = callExpr.callKind
            ce.baseFunc = callExpr.baseFunc
            var idx: Int64 = 0
            var arrayLitIdx: Int64 = -1
            var arraySize: Int64 = 0
            while (idx < callExpr.args.size) {
                if (idx + 1 < callExpr.args.size && callExpr.args[idx + 1].name.Empty()) {
                    SetFuncArg(ce.args, idx, callExpr.args[idx])
                    idx++
                    continue
                }
                arrayLitIdx = idx
                if (let Some(argExpr) <- callExpr.args[arrayLitIdx].expr) {
                    if (let Some(arrayLit) <- (argExpr as ArrayLit)) {
                        arraySize = arrayLit.children.size
                        var childIdx: Int64 = 0
                        while (childIdx < arraySize) {
                            let destArg = EnsureFuncArg(ce.args, arrayLitIdx + childIdx)
                            destArg.expr = arrayLit.children[childIdx]
                            childIdx++
                        }
                    }
                }
                break
            }
            idx++
            while (idx < callExpr.args.size) {
                let originIdx = (idx + arraySize) - 1
                SetFuncArg(ce.args, originIdx, callExpr.args[idx])
                idx++
            }
            ce.desugarExpr = None
        }
    }
}

public class RecoverDesugar {
    public init() {}

    public static func Recover(root: Node): Unit {
        let walker = Walker(root, visitPre: { node: Node =>
            var handled = false
            if (let Some(binary) <- (node as BinaryExpr)) {
                RecoverToBinaryExpr(binary)
                handled = true
            }
            if (let Some(unary) <- (node as UnaryExpr)) {
                RecoverToUnaryExpr(unary)
                handled = true
            }
            if (let Some(subscript) <- (node as SubscriptExpr)) {
                RecoverToSubscriptExpr(subscript)
                handled = true
            }
            if (let Some(assignExpr) <- (node as AssignExpr)) {
                RecoverToAssignExpr(assignExpr)
                handled = true
            }
            if (let Some(callExpr) <- (node as CallExpr)) {
                RecoverToCallExpr(callExpr)
                handled = true
            }
            if (let Some(expr) <- (node as Expr)) {
                if (!handled) {
                    expr.desugarExpr = None
                }
                expr.mapExpr = None
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }
}

public func RecoverDesugarExpr(root: Node): Unit {
    RecoverDesugar.Recover(root)
}
