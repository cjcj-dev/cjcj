package cangjie_compiler::chir

import std.collection.*
import cangjie_compiler::utils.{CJC_ABORT, InternalError, OverflowStrategy}

public class DeadCodeElimination {
    private let builder: CHIRBuilder

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func RunOnPackage(pkg: Package): Int64 {
        var removed: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            removed += RunOnFunction(fn)
        }
        return removed
    }

    public func RunOnFunction(fn: Function): Int64 {
        var removed: Int64 = 0
        if (let Some(body) <- fn.GetBody()) {
            var passRemoved: Int64 = -1
            while (passRemoved != 0) {
                passRemoved = RunOnBody(body)
                removed += passRemoved
            }
        }
        return removed
    }

    public func UnreachableBlockEliminationForPackage(pkg: Package, isDebug!: Bool = false): Unit {
        for (fn in pkg.GetGlobalFunctionsRef()) {
            if (fn.GetBody().isNone() || fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
                continue
            }
            if (let Some(body) <- fn.GetBody()) {
                UnreachableBlockEliminationForFunc(body, isDebug: isDebug)
            }
        }
    }

    public func UnreachableBlockEliminationForFunc(body: BlockGroup, isDebug!: Bool = false): Unit {
        let entryBlock = body.GetEntryBlock().getOrThrow()
        let unreachable = body.GetBlocks()
        let workList = ArrayList<Block>()
        workList.add(entryBlock)
        var entryIdx: Int64 = 0
        while (entryIdx < unreachable.size) {
            if (refEq(unreachable[entryIdx], entryBlock)) {
                unreachable.remove(at: entryIdx)
                break
            }
            entryIdx++
        }

        var workIdx: Int64 = 0
        while (workIdx < workList.size) {
            let block = workList[workIdx]
            workIdx++

            for (expr in block.GetExpressionsRef()) {
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        UnreachableBlockEliminationForFunc(lambdaBody, isDebug: isDebug)
                    }
                }
            }

            let terminator = block.GetTerminator().getOrThrow()
            var targetSucc: Option<Block> = None
            if (let Some(branch) <- (terminator as Branch)) {
                targetSucc = GetBranchTargetSucc(branch)
            } else if (let Some(multiBranch) <- (terminator as MultiBranch)) {
                targetSucc = GetMultiBranchTargetSucc(multiBranch)
            }
            if (let Some(target) <- targetSucc) {
                let cond = terminator.GetOperand(0)
                terminator.RemoveSelfFromBlock()
                if (cond.IsLocalVar() && cond.GetUsersRef().isEmpty()) {
                    let expr = (cond as LocalVar).getOrThrow().GetExpr().getOrThrow()
                    expr.RemoveSelfFromBlock()
                }
                builder.CreateGoTo(target, block)
            }

            let updatedTerminator = block.GetTerminator().getOrThrow()
            var succIdx: Int64 = 0
            while (succIdx < updatedTerminator.GetNumOfSuccessor()) {
                let successor = updatedTerminator.GetSuccessor(succIdx)
                var removed = false
                var idx: Int64 = 0
                while (idx < unreachable.size) {
                    if (refEq(unreachable[idx], successor)) {
                        unreachable.remove(at: idx)
                        removed = true
                        break
                    }
                    idx++
                }
                if (removed) {
                    workList.add(successor)
                }
                succIdx++
            }
        }

        for (block in unreachable) {
            block.RemoveSelfFromBlockGroup()
        }
    }

    public func ClearUnreachableMarkBlock(pkg: Package): Unit {
        for (fn in pkg.GetGlobalFunctionsRef()) {
            if (fn.GetBody().isNone() || fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
                continue
            }
            if (let Some(body) <- fn.GetBody()) {
                ClearUnreachableMarkBlockForFunc(body)
            }
        }
    }

    private func RunOnBody(body: BlockGroup): Int64 {
        var removed: Int64 = 0
        for (block in body.GetBlocksRef()) {
            removed += RunOnBlock(block)
        }
        return removed
    }

    private func RunOnBlock(block: Block): Int64 {
        var removed: Int64 = 0
        let exprs = block.GetExpressionsRef()
        var idx: Int64 = 0
        while (idx < exprs.size) {
            let expr = exprs[idx]
            if (CheckUselessExpr(expr)) {
                expr.RemoveSelfFromBlock()
                removed++
            } else {
                idx++
            }
        }
        return removed
    }

    private func CheckUselessExpr(expr: Expression, isReportWarning!: Bool = false): Bool {
        if (let Some(result) <- expr.GetResult()) {
            if (!result.GetUsersRef().isEmpty()) {
                return false
            }
        }
        if (expr.GetExprKind() == ExprKind.INT_OP_WITH_EXCEPTION && expr.GetNeverOverflowInfo() && isReportWarning) {
            return true
        }
        if (expr.IsTerminator()) {
            return false
        }
        if (expr.GetNeverOverflowInfo()) {
            return true
        }
        let kind = expr.GetExprKind()
        match (expr.GetExprMajorKind()) {
            case ExprMajorKind.UNARY_EXPR =>
                let unary = (expr as UnaryExpression).getOrThrow()
                return kind != ExprKind.NEG || unary.GetOverflowStrategy() != OverflowStrategy.THROWING
            case ExprMajorKind.BINARY_EXPR =>
                if (kind == ExprKind.MOD || kind == ExprKind.DIV || kind == ExprKind.LSHIFT ||
                    kind == ExprKind.RSHIFT) {
                    return false
                }
                let kindIndex = ExprKindIndex(kind)
                if (kindIndex >= ExprKindIndex(ExprKind.ADD) && kindIndex <= ExprKindIndex(ExprKind.EXP)) {
                    let binary = (expr as BinaryExpression).getOrThrow()
                    return binary.GetOverflowStrategy() != OverflowStrategy.THROWING
                }
                return true
            case ExprMajorKind.MEMORY_EXPR => return kind == ExprKind.LOAD || kind == ExprKind.GET_ELEMENT_REF
            case ExprMajorKind.STRUCTURED_CTRL_FLOW_EXPR => return kind == ExprKind.LAMBDA
            case ExprMajorKind.OTHERS => return kind == ExprKind.CONSTANT || kind == ExprKind.TUPLE ||
                kind == ExprKind.FIELD || kind == ExprKind.VARRAY
            case _ =>
                CJC_ABORT()
                return false
        }
    }

    private func BreakBranchConnection(block: Block): Unit {
        for (pred in block.GetPredecessors()) {
            let predTerminator = pred.GetTerminator().getOrThrow()
            if (predTerminator.GetExprKind() == ExprKind.BRANCH) {
                let oprand = predTerminator.GetOperand(0)
                let branch = (predTerminator as Branch).getOrThrow()
                if (block.nodeId != branch.GetFalseBlock().nodeId) {
                    InternalError("Unexpected branch connection")
                }
                let target = branch.GetTrueBlock()
                branch.RemoveSelfFromBlock()
                if (oprand.GetUsersRef().isEmpty()) {
                    let expr = (oprand as LocalVar).getOrThrow().GetExpr().getOrThrow()
                    expr.RemoveSelfFromBlock()
                }
                builder.CreateGoTo(target, pred)
            } else {
                let multi = (predTerminator as MultiBranch).getOrThrow()
                if (block.nodeId != multi.GetDefaultBlock().nodeId) {
                    InternalError("Unexpected multibranch connection")
                }
                multi.ReplaceSuccessor(0, multi.GetSuccessor(1))
            }
        }
    }

    private func ClearUnreachableMarkBlockForFunc(body: BlockGroup): Unit {
        for (block in body.GetBlocks()) {
            if (!block.TestAttr(Attribute.UNREACHABLE)) {
                for (expr in block.GetExpressionsRef()) {
                    if (let Some(lambdaExpr) <- (expr as Lambda)) {
                        if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                            ClearUnreachableMarkBlockForFunc(lambdaBody)
                        }
                    }
                }
                continue
            }
            BreakBranchConnection(block)
            block.RemoveSelfFromBlockGroup()
        }
    }
}

private func GetBranchTargetSucc(branch: Branch): Option<Block> {
    if (!branch.GetCondition().IsLocalVar()) {
        return None
    }
    let condExpr = (branch.GetCondition() as LocalVar).getOrThrow().GetExpr().getOrThrow()
    if (condExpr.GetExprKind() != ExprKind.CONSTANT) {
        return None
    }
    let constant = (condExpr as Constant).getOrThrow()
    return if (constant.GetBoolLitVal()) { branch.GetTrueBlock() } else { branch.GetFalseBlock() }
}

private func GetMultiBranchTargetSucc(branch: MultiBranch): Option<Block> {
    if (!branch.GetCondition().IsLocalVar()) {
        return None
    }
    var condExpr = (branch.GetCondition() as LocalVar).getOrThrow().GetExpr().getOrThrow()
    if (condExpr.GetExprKind() == ExprKind.TYPECAST) {
        if (!condExpr.GetOperand(0).IsLocalVar()) {
            return None
        }
        condExpr = (condExpr.GetOperand(0) as LocalVar).getOrThrow().GetExpr().getOrThrow()
    }
    if (condExpr.GetExprKind() != ExprKind.CONSTANT) {
        return None
    }
    let constant = (condExpr as Constant).getOrThrow()
    let condVal = if (constant.IsBoolLit()) {
        if (constant.GetBoolLitVal()) { 1u64 } else { 0u64 }
    } else if (constant.IsIntLit()) {
        constant.GetUnsignedIntLitVal()
    } else if (constant.IsRuneLit()) {
        UInt64(UInt32(constant.GetRuneLitVal()))
    } else {
        InternalError("Unexpected const val kind")
        0u64
    }
    let cases = branch.GetCaseVals()
    var idx: Int64 = 0
    while (idx < cases.size) {
        if (condVal == cases[idx]) {
            return branch.GetSuccessor(idx + 1)
        }
        idx++
    }
    return branch.GetDefaultBlock()
}
