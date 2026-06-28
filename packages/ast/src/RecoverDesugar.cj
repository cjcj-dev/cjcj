package cangjie_compiler::ast

import cangjie_compiler::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK}
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

private func RecoverToPipelineExpr(be: BinaryExpr): Unit {
    CJC_NULLPTR_CHECK(be.desugarExpr)
    if (let Some(desugar) <- be.desugarExpr) {
        CJC_ASSERT((desugar as CallExpr).isSome())
        if (let Some(callExpr) <- (desugar as CallExpr)) {
            be.rightExpr = TryRecoverFunctionCallExpr(callExpr.baseFunc)
            if (let Some(right) <- be.rightExpr) {
                UnsetCallExprOfNode(right)
            }
            CJC_ASSERT(callExpr.args.size == 1)
            be.leftExpr = callExpr.args[0].expr
            be.desugarExpr = None
        }
    }
}

private func RecoverToCompositionExpr(be: BinaryExpr): Unit {
    CJC_NULLPTR_CHECK(be.desugarExpr)
    if (let Some(desugar) <- be.desugarExpr) {
        CJC_ASSERT((desugar as CallExpr).isSome())
        if (let Some(callExpr) <- (desugar as CallExpr)) {
            CJC_ASSERT(callExpr.args.size == 2)
            be.leftExpr = TryRecoverFunctionCallExpr(callExpr.args[0].expr)
            if (let Some(left) <- be.leftExpr) {
                UnsetCallExprOfNode(left)
            }
            be.rightExpr = TryRecoverFunctionCallExpr(callExpr.args[1].expr)
            if (let Some(right) <- be.rightExpr) {
                UnsetCallExprOfNode(right)
            }
            be.desugarExpr = None
        }
    }
}

public func RecoverToSubscriptExpr(se: SubscriptExpr): Unit {
    if (let Some(desugar) <- se.desugarExpr) {
        if (let Some(callExpr) <- (desugar as CallExpr)) {
            RecoverToCallExpr(callExpr)
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                CJC_ASSERT((baseFunc as MemberAccess).isSome())
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
        CJC_ASSERT((desugar as CallExpr).isSome())
        if (let Some(callExpr) <- (desugar as CallExpr)) {
            RecoverToCallExpr(callExpr)
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                CJC_ASSERT((baseFunc as MemberAccess).isSome())
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
                RecoverToPipelineExpr(be)
                return
            }
            if (be.op == TokenKind.COMPOSITION) {
                RecoverToCompositionExpr(be)
                return
            }
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                CJC_ASSERT((baseFunc as MemberAccess).isSome())
                if (let Some(member) <- (baseFunc as MemberAccess)) {
                    be.leftExpr = member.baseExpr
                    be.rightExpr = callExpr.args[0].expr
                    if (let Some(left) <- be.leftExpr) {
                        UnsetCallExprOfNode(left)
                    }
                    CJC_NULLPTR_CHECK(be.curFile)
                    if (let Some(file) <- be.curFile) {
                        file.trashBin.add(desugar)
                    }
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
            CJC_ASSERT(ae.leftValue.isSome())
            if (let Some(leftValue) <- ae.leftValue) {
                if (let Some(subscript) <- (leftValue as SubscriptExpr)) {
                    RecoverToCallExpr(callExpr)
                    if (let Some(baseFunc) <- callExpr.baseFunc) {
                        CJC_ASSERT((baseFunc as MemberAccess).isSome())
                        if (let Some(member) <- (baseFunc as MemberAccess)) {
                            subscript.baseExpr = member.baseExpr
                            CJC_ASSERT(!callExpr.args.isEmpty())
                            let rightIdx = callExpr.args.size - 1
                            ReplaceIndexExprs(subscript.indexExprs, callExpr.args, rightIdx)
                            leftValue.curFile = ae.curFile
                            if (ae.isCompound) {
                                CJC_ASSERT(callExpr.args[rightIdx].expr.isSome())
                                if (let Some(lastExpr) <- callExpr.args[rightIdx].expr) {
                                    CJC_ASSERT((lastExpr as BinaryExpr).isSome())
                                    if (let Some(binary) <- (lastExpr as BinaryExpr)) {
                                        ae.rightExpr = binary.rightExpr
                                    }
                                }
                            } else {
                                ae.rightExpr = callExpr.args[rightIdx].expr
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
            CJC_ASSERT(assignExpr.rightExpr.isSome())
            if (let Some(right) <- assignExpr.rightExpr) {
                CJC_ASSERT((right as CallExpr).isSome())
                if (let Some(callExpr) <- (right as CallExpr)) {
                    RecoverToCallExpr(callExpr)
                    ae.leftValue = assignExpr.leftValue
                    ae.rightExpr = callExpr.args[0].expr
                    ae.desugarExpr = None
                    CJC_ASSERT(ae.leftValue.isSome())
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
            CJC_ASSERT((desugar as CallExpr).isSome())
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
                        ce.args.clear()
                        for (arg in callExpr.args) {
                            ce.args.add(arg)
                        }
                        CJC_NULLPTR_CHECK(ce.curFile)
                        if (let Some(file) <- ce.curFile) {
                            file.trashBin.add(desugar)
                        }
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
            CJC_ASSERT(!callExpr.args.isEmpty())
            var idx: Int64 = 0
            var arrayLitIdx: Int64 = 0
            var arraySize: Int64 = 0
            while (idx < callExpr.args.size) {
                if (idx + 1 < callExpr.args.size && callExpr.args[idx + 1].name.Empty()) {
                    ce.args[idx] = callExpr.args[idx]
                    idx++
                    continue
                }
                arrayLitIdx = idx
                CJC_ASSERT(callExpr.args[arrayLitIdx].expr.isSome())
                if (let Some(argExpr) <- callExpr.args[arrayLitIdx].expr) {
                    CJC_ASSERT((argExpr as ArrayLit).isSome())
                    if (let Some(arrayLit) <- (argExpr as ArrayLit)) {
                        arraySize = arrayLit.children.size
                        var childIdx: Int64 = 0
                        while (childIdx < arraySize) {
                            ce.args[arrayLitIdx + childIdx].expr = arrayLit.children[childIdx]
                            childIdx++
                        }
                    }
                }
                break
            }
            idx++
            while (idx < callExpr.args.size) {
                CJC_ASSERT(idx + arraySize > 0)
                let originIdx = (idx + arraySize) - 1
                CJC_ASSERT(originIdx < ce.args.size)
                ce.args[originIdx] = callExpr.args[idx]
                idx++
            }
            ce.desugarExpr = None
        }
    }
}
