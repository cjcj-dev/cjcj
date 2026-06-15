package cangjie_compiler::chir

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
            return RunOnBody(body, isDebug)
        }
        return 0
    }

    private func RunOnBody(body: BlockGroup, isDebug: Bool): Int64 {
        var changed: Int64 = 0
        var unitConstant: Option<Constant> = None
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
                    continue
                }
                if (unitConstant.isNone()) {
                    unitConstant = LoadOrCreateUnit(body)
                }
                if (let Some(unitExpr) <- unitConstant) {
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
            }
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

    private func LoadOrCreateUnit(group: BlockGroup): Option<Constant> {
        if (let Some(entryBlock) <- group.GetEntryBlock()) {
            var oldFirst: Option<Expression> = None
            if (entryBlock.GetExpressionsNum() > 0) {
                oldFirst = entryBlock.GetExpressionByIdx(0)
            }
            let unitExpr = builder.CreateConstant(builder.context.GetUnitTy(), UnitLiteral(), entryBlock)
            if (let Some(firstExpr) <- oldFirst) {
                unitExpr.MoveBefore(firstExpr)
            }
            return unitExpr
        }
        return None
    }
}
