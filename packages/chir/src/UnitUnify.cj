package cangjie_compiler::chir

private class UnitUnifyState {
    public var unitConstant: Option<Constant> = None

    public init() {}
}

public class UnitUnify {
    private let builder: CHIRBuilder

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func RunOnPackage(pkg: Package, isDebug!: Bool = false): Int64 {
        var changed: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            changed += RunOnFunction(fn, isDebug: isDebug)
        }
        return changed
    }

    public func RunOnFunction(fn: Function, isDebug!: Bool = false): Int64 {
        if (let Some(body) <- fn.GetBody()) {
            let state = UnitUnifyState()
            return RunOnBody(body, body, state, isDebug)
        }
        return 0
    }

    private func RunOnBody(body: BlockGroup, unitOwner: BlockGroup, state: UnitUnifyState, isDebug: Bool): Int64 {
        var changed: Int64 = 0
        for (block in body.GetBlocksRef()) {
            let exprs = block.GetExpressions()
            for (expr in exprs) {
                if (expr.IsLambda()) {
                    continue
                }
                if (expr.GetExprKind() == ExprKind.GET_RTTI || expr.GetExprKind() == ExprKind.GET_RTTI_STATIC) {
                    continue
                }
                if (!NeedUnify(expr)) {
                    changed += RunOnChildGroups(expr, unitOwner, state, isDebug)
                } else {
                    LoadOrCreateUnit(unitOwner, state)
                    if (let Some(unitExpr) <- state.unitConstant) {
                        if (let Some(unitResult) <- unitExpr.GetResult()) {
                            if (let Some(result) <- expr.GetResult()) {
                                result.ReplaceWith(unitResult, expr.GetParentBlockGroup())
                                changed++
                                if (isDebug) {
                                    println("[UnitUnify] unit unify " + expr.GetDebugLocation().ToString() + ".")
                                }
                            }
                        }
                    }
                    changed += RunOnChildGroups(expr, unitOwner, state, isDebug)
                }
            }
        }
        return changed
    }

    private func RunOnChildGroups(expr: Expression, unitOwner: BlockGroup, state: UnitUnifyState,
        isDebug: Bool): Int64 {
        var changed: Int64 = 0
        for (child in expr.GetBlockGroups()) {
            changed += RunOnBody(child, unitOwner, state, isDebug)
        }
        return changed
    }

    private func NeedUnify(expr: Expression): Bool {
        if (expr.IsTerminator()) {
            return false
        }
        if (let Some(result) <- expr.GetResult()) {
            if (result.GetUsersRef().isEmpty()) {
                return false
            }
            if (let Some(resultTy) <- result.GetType()) {
                if (!resultTy.IsUnit()) {
                    return false
                }
            } else {
                return false
            }
            if (let Some(constant) <- (expr as Constant)) {
                if (constant.literal.IsNullLit() || constant.literal.IsUnitLit()) {
                    return false
                }
            }
            return true
        }
        return false
    }

    private func LoadOrCreateUnit(group: BlockGroup, state: UnitUnifyState): Unit {
        if (state.unitConstant.isSome()) {
            return
        }
        if (let Some(entryBlock) <- group.GetEntryBlock()) {
            var oldFirst: Option<Expression> = None
            if (entryBlock.GetExpressionsNum() > 0) {
                oldFirst = entryBlock.GetExpressionByIdx(0)
            }
            let unitExpr = builder.CreateConstant(builder.context.GetUnitTy(), UnitLiteral(), entryBlock)
            if (let Some(firstExpr) <- oldFirst) {
                unitExpr.MoveBefore(firstExpr)
            }
            state.unitConstant = unitExpr
        }
    }
}
