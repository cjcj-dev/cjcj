package cangjie_compiler::chir

import cangjie_compiler::option.{GlobalOptions, OptimizationFlag}
import std.collection.*

private enum FoldedValue {
    | FoldedUnknown
    | FoldedBool(Bool)
    | FoldedInt(Int64)
    | FoldedUInt(UInt64)
}

private func FoldedValueIsUnknown(value: FoldedValue): Bool {
    return match (value) {
        case FoldedUnknown => true
        case _ => false
    }
}

private func FoldedValueEquals(lhs: FoldedValue, rhs: FoldedValue): Bool {
    return match (lhs) {
        case FoldedUnknown => FoldedValueIsUnknown(rhs)
        case FoldedBool(left) => if (let FoldedBool(right) <- rhs) { left == right } else { false }
        case FoldedInt(left) => if (let FoldedInt(right) <- rhs) { left == right } else { false }
        case FoldedUInt(left) => if (let FoldedUInt(right) <- rhs) { left == right } else { false }
    }
}

private func JoinFoldedValue(lhs: FoldedValue, rhs: FoldedValue): FoldedValue {
    if (FoldedValueEquals(lhs, rhs)) {
        return lhs
    }
    return FoldedUnknown
}

private func FoldedValueAsBool(value: FoldedValue): Option<Bool> {
    return match (value) {
        case FoldedBool(v) => Some(v)
        case _ => None
    }
}

private func FoldedValueAsUInt(value: FoldedValue): Option<UInt64> {
    return match (value) {
        case FoldedBool(v) => Some(if (v) { 1u64 } else { 0u64 })
        case FoldedInt(v) => if (v >= 0) { Some(UInt64(v)) } else { None }
        case FoldedUInt(v) => Some(v)
        case _ => None
    }
}

private func FoldConstant(constant: Constant): FoldedValue {
    if (constant.IsBoolLit()) {
        return FoldedBool(constant.GetBoolLitVal())
    }
    if (constant.IsIntLit()) {
        return FoldedInt(constant.GetSignedIntLitVal())
    }
    return FoldedUnknown
}

private func FoldBoolBinary(kind: ExprKind, lhs: Bool, rhs: Bool): Option<Bool> {
    return match (kind) {
        case ExprKind.EQUAL => Some(lhs == rhs)
        case ExprKind.NOTEQUAL => Some(lhs != rhs)
        case ExprKind.AND => Some(lhs && rhs)
        case ExprKind.OR => Some(lhs || rhs)
        case _ => None
    }
}

private func FoldIntBinary(kind: ExprKind, lhs: Int64, rhs: Int64): Option<FoldedValue> {
    return match (kind) {
        case ExprKind.LT => Some(FoldedBool(lhs < rhs))
        case ExprKind.GT => Some(FoldedBool(lhs > rhs))
        case ExprKind.LE => Some(FoldedBool(lhs <= rhs))
        case ExprKind.GE => Some(FoldedBool(lhs >= rhs))
        case ExprKind.EQUAL => Some(FoldedBool(lhs == rhs))
        case ExprKind.NOTEQUAL => Some(FoldedBool(lhs != rhs))
        case _ => None
    }
}

private class ConstTerminatorDomain <: AbstractDomain<ConstTerminatorDomain> {
    private let keys: ArrayList<Value> = ArrayList<Value>()
    private let values: ArrayList<FoldedValue> = ArrayList<FoldedValue>()

    public init() {
        super()
    }

    public init(other: ConstTerminatorDomain) {
        super()
        kind = other.kind
        var idx: Int64 = 0
        while (idx < other.keys.size) {
            keys.add(other.keys[idx])
            values.add(other.values[idx])
            idx++
        }
    }

    public override func Clone(): ConstTerminatorDomain {
        return ConstTerminatorDomain(this)
    }

    public func SetReachable(value: Bool): Unit {
        kind = if (value) { ReachableKind.REACHABLE } else { ReachableKind.UNREACHABLE }
    }

    public func CheckKnown(value: Value): Option<FoldedValue> {
        if (let Some(idx) <- FindIndex(value)) {
            if (!FoldedValueIsUnknown(values[idx])) {
                return values[idx]
            }
        }
        return None
    }

    public func Update(value: Value, folded: FoldedValue): Unit {
        if (let Some(idx) <- FindIndex(value)) {
            values[idx] = folded
            return
        }
        if (!FoldedValueIsUnknown(folded)) {
            keys.add(value)
            values.add(folded)
        }
    }

    public override func Join(rhs: ConstTerminatorDomain): Bool {
        if (rhs.IsBottom()) {
            return false
        }
        if (IsBottom()) {
            CopyFrom(rhs)
            return true
        }
        var changed = false
        var idx: Int64 = 0
        while (idx < keys.size) {
            let joined = if (let Some(rhsIdx) <- rhs.FindIndex(keys[idx])) {
                JoinFoldedValue(values[idx], rhs.values[rhsIdx])
            } else {
                FoldedUnknown
            }
            if (!FoldedValueEquals(values[idx], joined)) {
                values[idx] = joined
                changed = true
            }
            idx++
        }
        return changed
    }

    private func CopyFrom(rhs: ConstTerminatorDomain): Unit {
        kind = rhs.kind
        keys.clear()
        values.clear()
        var idx: Int64 = 0
        while (idx < rhs.keys.size) {
            keys.add(rhs.keys[idx])
            values.add(rhs.values[idx])
            idx++
        }
    }

    private func FindIndex(value: Value): Option<Int64> {
        var idx: Int64 = 0
        while (idx < keys.size) {
            if (keys[idx].nodeId == value.nodeId) {
                return idx
            }
            idx++
        }
        return None
    }
}

private func IsGeneratedForInLocation(value: Value): Bool {
    if (let Some(local) <- value.AsLocalVar()) {
        if (let Some(expr) <- local.GetExpr()) {
            return expr.GetGeneratedFromForIn()
        }
    }
    return false
}

private func UpdateExprResult(state: ConstTerminatorDomain, expr: Expression, folded: FoldedValue): Unit {
    if (let Some(result) <- expr.GetResult()) {
        state.Update(result, folded)
    }
}

private func CheckExprResultValue(state: ConstTerminatorDomain, expr: Expression): Option<FoldedValue> {
    if (let Some(result) <- expr.GetResult()) {
        return state.CheckKnown(result)
    }
    return None
}

private func FoldedValueToLiteral(value: FoldedValue, ty: Type): Option<LiteralValue> {
    return match (value) {
        case FoldedBool(v) => if (ty.IsBoolean()) { Some(BoolLiteral(v)) } else { None }
        case FoldedInt(v) => if (ty.IsInteger()) { Some(IntLiteral(v)) } else { None }
        case FoldedUInt(v) => if (ty.IsInteger()) { Some(IntLiteral(v)) } else { None }
        case _ => None
    }
}

private func CanRewriteFoldedExpression(expr: Expression): Bool {
    if (expr.IsTerminator()) {
        return false
    }
    return expr.IsUnaryExpr() || expr.IsBinaryExpr() || expr.GetExprKind() == ExprKind.LOAD ||
        expr.GetExprKind() == ExprKind.TYPECAST || expr.GetExprKind() == ExprKind.FIELD
}

private func FoldBinaryExpr(expr: Expression, state: ConstTerminatorDomain, depth: Int64): FoldedValue {
    if (expr.GetNumOfOperands() < 2) {
        return FoldedUnknown
    }
    let lhs = EvalFoldedValue(expr.GetOperand(0), state, depth - 1)
    let rhs = EvalFoldedValue(expr.GetOperand(1), state, depth - 1)
    match (lhs) {
        case FoldedBool(leftBool) =>
            if (let FoldedBool(rightBool) <- rhs) {
                if (let Some(value) <- FoldBoolBinary(expr.GetExprKind(), leftBool, rightBool)) {
                    return FoldedBool(value)
                }
            }
        case FoldedInt(leftInt) =>
            if (let FoldedInt(rightInt) <- rhs) {
                if (let Some(value) <- FoldIntBinary(expr.GetExprKind(), leftInt, rightInt)) {
                    return value
                }
            }
        case _ => ()
    }
    return FoldedUnknown
}

private func EvalFoldedExpr(expr: Expression, state: ConstTerminatorDomain, depth: Int64): FoldedValue {
    if (depth <= 0) {
        return FoldedUnknown
    }
    if (let Some(constant) <- (expr as Constant)) {
        return FoldConstant(constant)
    }
    if (let Some(load) <- (expr as Load)) {
        if (IsGeneratedForInLocation(load.GetLocation())) {
            return state.CheckKnown(load.GetLocation()) ?? FoldedUnknown
        }
        return FoldedUnknown
    }
    if (expr.IsUnaryExpr() && expr.GetNumOfOperands() == 1) {
        if (expr.GetExprKind() == ExprKind.NOT) {
            if (let Some(value) <- FoldedValueAsBool(EvalFoldedValue(expr.GetOperand(0), state, depth - 1))) {
                return FoldedBool(!value)
            }
        }
        return FoldedUnknown
    }
    if (expr.IsBinaryExpr()) {
        return FoldBinaryExpr(expr, state, depth)
    }
    return FoldedUnknown
}

private func EvalFoldedValue(value: Value, state: ConstTerminatorDomain, depth: Int64): FoldedValue {
    if (depth <= 0) {
        return FoldedUnknown
    }
    if (let Some(known) <- state.CheckKnown(value)) {
        return known
    }
    if (let Some(local) <- value.AsLocalVar()) {
        if (let Some(expr) <- local.GetExpr()) {
            return EvalFoldedExpr(expr, state, depth - 1)
        }
    }
    if (let Some(globalVar) <- value.AsGlobalVar()) {
        if (let Some(initValue) <- globalVar.GetInitializer()) {
            if (let Some(boolLiteral) <- (initValue as BoolLiteral)) {
                return FoldedBool(boolLiteral.value)
            }
            if (let Some(intLiteral) <- (initValue as IntLiteral)) {
                return FoldedInt(intLiteral.value)
            }
        }
    }
    return FoldedUnknown
}

private func EvaluateTerminatorTarget(term: Terminator, state: ConstTerminatorDomain): Option<Block> {
    if (let Some(branch) <- (term as Branch)) {
        if (let Some(takenTrue) <- FoldedValueAsBool(EvalFoldedValue(branch.GetCondition(), state, 12))) {
            return if (takenTrue) { branch.GetTrueBlock() } else { branch.GetFalseBlock() }
        }
        return None
    }
    if (let Some(multi) <- (term as MultiBranch)) {
        if (let Some(selector) <- FoldedValueAsUInt(EvalFoldedValue(multi.GetCondition(), state, 12))) {
            var idx: Int64 = 0
            while (idx < multi.GetCaseVals().size) {
                if (selector == multi.GetCaseValByIndex(idx)) {
                    return multi.GetCaseBlockByIndex(idx)
                }
                idx++
            }
            return multi.GetDefaultBlock()
        }
    }
    return None
}

private class ConstTerminatorAnalysis <: Analysis<ConstTerminatorDomain> {
    public init(fn: Function) {
        super(fn)
    }

    public override func Bottom(): ConstTerminatorDomain {
        return ConstTerminatorDomain()
    }

    public override func InitializeFuncEntryState(state: ConstTerminatorDomain): Unit {
        state.SetReachable(true)
    }

    public override func PropagateExpressionEffect(state: ConstTerminatorDomain, expression: Expression): Unit {
        if (let Some(store) <- (expression as Store)) {
            if (IsGeneratedForInLocation(store.GetLocation())) {
                state.Update(store.GetLocation(), EvalFoldedValue(store.GetValue(), state, 12))
            }
            return
        }
        if (let Some(load) <- (expression as Load)) {
            UpdateExprResult(state, expression, if (IsGeneratedForInLocation(load.GetLocation())) {
                state.CheckKnown(load.GetLocation()) ?? FoldedUnknown
            } else {
                FoldedUnknown
            })
            return
        }
        if (let Some(constant) <- (expression as Constant)) {
            UpdateExprResult(state, expression, FoldConstant(constant))
            return
        }
        if (expression.IsUnaryExpr() || expression.IsBinaryExpr()) {
            UpdateExprResult(state, expression, EvalFoldedExpr(expression, state, 12))
            return
        }
        UpdateExprResult(state, expression, FoldedUnknown)
    }

    public override func PropagateTerminatorEffect(state: ConstTerminatorDomain, terminator: Terminator): Option<Block> {
        if (let Some(target) <- EvaluateTerminatorTarget(terminator, state)) {
            return target
        }
        UpdateExprResult(state, terminator, FoldedUnknown)
        return None
    }
}

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
        var changed: Int64 = TryRewriteDataflowConstantTerminators(fn)
        if (let Some(body) <- fn.GetBody()) {
            changed += SimplifyBody(body)
        }
        return changed
    }

    private func TryRewriteDataflowConstantTerminators(fn: Function): Int64 {
        if (builder.isNone()) {
            return 0
        }
        if (let None <- fn.GetBody()) {
            return 0
        }
        let analysis = ConstTerminatorAnalysis(fn)
        let result = Engine<ConstTerminatorDomain>(fn, analysis).IterateToFixpoint() ?? return 0
        let exprsToBeConst = ArrayList<(Expression, FoldedValue)>()
        let toBeRewritten = ArrayList<(Terminator, Block)>()
        result.VisitWith(
            { _: ConstTerminatorDomain, _: Expression, _: Int64 => () },
            { state: ConstTerminatorDomain, expr: Expression, _: Int64 =>
                if (SkipCP(expr) || !CanRewriteFoldedExpression(expr)) {
                    return
                }
                if (let Some(folded) <- CheckExprResultValue(state, expr)) {
                    exprsToBeConst.add((expr, folded))
                }
            },
            { _: ConstTerminatorDomain, term: Terminator, targetSucc: Option<Block> =>
                if (SkipCP(term)) {
                    return
                }
                if (let Some(target) <- targetSucc) {
                    toBeRewritten.add((term, target))
                }
            }
        )
        var changed: Int64 = 0
        for ((expr, folded) in exprsToBeConst) {
            if (expr.GetParentBlock().isSome() && RewriteExpressionToConstant(expr, folded)) {
                changed++
            }
        }
        for ((term, target) in toBeRewritten) {
            if (term.GetParentBlock().isSome() && RewriteTerminatorToGoto(term, target)) {
                changed++
            }
        }
        return changed
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

    private func RewriteExpressionToConstant(expr: Expression, folded: FoldedValue): Bool {
        let parentBlock = expr.GetParentBlock() ?? return false
        let result = expr.GetResult() ?? return false
        let resultTy = result.GetType() ?? return false
        let literal = FoldedValueToLiteral(folded, resultTy) ?? return false
        if (let Some(chirBuilder) <- builder) {
            let loc = expr.GetDebugLocation()
            let constant = chirBuilder.CreateConstant(resultTy, literal, parentBlock)
            constant.SetDebugLocation(loc)
            expr.ReplaceWith(constant)
            return true
        }
        return false
    }

    private func RewriteTerminatorToGoto(term: Terminator, target: Block): Bool {
        let parentBlock = term.GetParentBlock() ?? return false
        let loc = term.GetDebugLocation()
        term.RemoveSelfFromBlock()
        if (let Some(chirBuilder) <- builder) {
            let gotoExpr = chirBuilder.CreateGoTo(target, parentBlock)
            gotoExpr.SetDebugLocation(loc)
            return true
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
