package cangjie_compiler::chir

import cangjie_compiler::option.{GlobalOptions, OptimizationFlag}

public class ConstPropagation {
    private let builder: Option<CHIRBuilder>
    private let constEval: ConstEval = ConstEval()
    private let opts: GlobalOptions

    public init(builder!: Option<CHIRBuilder> = None, opts!: GlobalOptions = GlobalOptions()) {
        this.builder = builder
        this.opts = opts
    }

    public func RunOnPackage(pkg: Package): Int64 {
        var changed: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            changed += RunOnFunction(fn)
        }
        return changed
    }

    public func RunOnFunction(fn: Function): Int64 {
        if (fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
            return 0
        }
        if (let Some(body) <- fn.GetBody()) {
            return SimplifyBody(body)
        }
        return 0
    }

    private func SimplifyBody(body: BlockGroup): Int64 {
        var changed: Int64 = 0
        for (block in body.GetBlocksRef()) {
            changed += SimplifyBlock(block)
            for (expr in block.GetExpressions()) {
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        changed += SimplifyBody(lambdaBody)
                    }
                }
            }
        }
        return changed
    }

    private func SimplifyBlock(block: Block): Int64 {
        var changed: Int64 = 0
        let exprs = block.GetExpressionsRef()
        var idx: Int64 = 0
        while (idx < exprs.size) {
            let expr = exprs[idx]
            if (SkipCP(expr)) {
                idx++
            } else if (TryRewriteConstantBranch(expr)) {
                changed++
            } else if (TrySimplifyUnary(expr)) {
                changed++
            } else if (TrySimplifyBinary(expr)) {
                changed++
            } else {
                idx++
            }
        }
        return changed
    }

    private func SkipCP(expr: Expression): Bool {
        if (!opts.IsOptimizationExisted(OptimizationFlag.CONST_PROPAGATION)) {
            if (expr.GetGeneratedFromForIn()) {
                return false
            }
            if (let Some(branch) <- (expr as Branch)) {
                return branch.GetSourceExpr() != SourceExpr.FOR_IN_EXPR
            }
            if (let Some(load) <- (expr as Load)) {
                if (let Some(alloc) <- load.GetLocation().AsLocalVar()) {
                    return !alloc.GetExpr().getOrThrow().GetGeneratedFromForIn()
                }
            }
            return true
        }
        return false
    }

    private func TryRewriteConstantBranch(expr: Expression): Bool {
        if (expr.GetExprKind() != ExprKind.BRANCH || expr.GetNumOfOperands() != 1 || builder.isNone()) {
            return false
        }
        if (let Some(takenTrue) <- BoolLiteralValue(expr.GetOperand(0))) {
            if (let Some(term) <- expr.AsTerminator()) {
                let successors = term.GetSuccessors()
                if (successors.size < 2) {
                    return false
                }
                if (let Some(parentBlock) <- expr.GetParentBlock()) {
                    let target = if (takenTrue) { successors[0] } else { successors[1] }
                    let loc = expr.GetDebugLocation()
                    expr.RemoveSelfFromBlock()
                    if (let Some(chirBuilder) <- builder) {
                        let gotoExpr = chirBuilder.CreateGoTo(target, parentBlock)
                        gotoExpr.SetDebugLocation(loc)
                        return true
                    }
                }
            }
        }
        return false
    }

    private func TrySimplifyUnary(expr: Expression): Bool {
        if (!expr.IsUnaryExpr() || expr.GetNumOfOperands() != 1) {
            return false
        }
        let kind = expr.GetExprKind()
        if (kind != ExprKind.NOT && kind != ExprKind.BITNOT) {
            return false
        }
        let operand = expr.GetOperand(0)
        if (let Some(local) <- operand.AsLocalVar()) {
            if (let Some(operandExpr) <- local.GetExpr()) {
                let operandKind = operandExpr.GetExprKind()
                if ((operandKind == ExprKind.NOT || operandKind == ExprKind.BITNOT) &&
                    operandExpr.GetNumOfOperands() == 1) {
                    return ReplaceResultWithOperand(expr, operandExpr.GetOperand(0))
                }
            }
        }
        return false
    }

    private func TrySimplifyBinary(expr: Expression): Bool {
        if (!expr.IsBinaryExpr() || expr.GetNumOfOperands() != 2) {
            return false
        }
        let lhs = expr.GetOperand(0)
        let rhs = expr.GetOperand(1)
        let kind = expr.GetExprKind()
        if (kind == ExprKind.ADD && IsIntLiteral(lhs, 0)) {
            return ReplaceResultWithOperand(expr, rhs)
        }
        if ((kind == ExprKind.ADD || kind == ExprKind.SUB || kind == ExprKind.LSHIFT ||
            kind == ExprKind.RSHIFT) && IsIntLiteral(rhs, 0)) {
            return ReplaceResultWithOperand(expr, lhs)
        }
        if (kind == ExprKind.MUL && IsIntLiteral(lhs, 1)) {
            return ReplaceResultWithOperand(expr, rhs)
        }
        if ((kind == ExprKind.MUL || kind == ExprKind.DIV || kind == ExprKind.EXP) && IsIntLiteral(rhs, 1)) {
            return ReplaceResultWithOperand(expr, lhs)
        }
        if ((kind == ExprKind.BITAND || kind == ExprKind.BITOR) && lhs.nodeId == rhs.nodeId) {
            return ReplaceResultWithOperand(expr, lhs)
        }
        return false
    }

    private func ReplaceResultWithOperand(expr: Expression, operand: Value): Bool {
        if (let Some(result) <- expr.GetResult()) {
            result.ReplaceWith(operand, expr.GetParentBlockGroup())
            expr.RemoveSelfFromBlock()
            return true
        }
        return false
    }

    private func IsIntLiteral(value: Value, expected: Int64): Bool {
        if (let Some(local) <- value.AsLocalVar()) {
            if (let Some(expr) <- local.GetExpr()) {
                if (let Some(constant) <- (expr as Constant)) {
                    if (let Some(intLiteral) <- (constant.literal as IntLiteral)) {
                        return intLiteral.value == expected
                    }
                }
            }
        }
        return false
    }

    private func BoolLiteralValue(value: Value): Option<Bool> {
        if (let Some(local) <- value.AsLocalVar()) {
            if (let Some(expr) <- local.GetExpr()) {
                if (let Some(literal) <- constEval.EvaluateToLiteral(expr)) {
                    if (let Some(boolLiteral) <- (literal as BoolLiteral)) {
                        return boolLiteral.value
                    }
                }
            }
        }
        if (let Some(globalVar) <- value.AsGlobalVar()) {
            if (let Some(initValue) <- globalVar.GetInitializer()) {
                if (let Some(boolLiteral) <- (initValue as BoolLiteral)) {
                    return boolLiteral.value
                }
            }
        }
        return None
    }
}
