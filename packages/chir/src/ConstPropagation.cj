package cjcj::chir

import cjcj::option.{GlobalOptions, OptimizationFlag}
import std.collection.*
import std.sync.Mutex

private let constPropagationEffectMap: OptEffectCHIRMap = OptEffectCHIRMap()
private let constPropagationEffectMapMutex = Mutex()

private class RewriteInfo {
    public let oldExpr: Expression
    public let index: Int64
    public let literalVal: Option<LiteralValue>

    public init(oldExpr: Expression, index: Int64, literalVal: Option<LiteralValue>) {
        this.oldExpr = oldExpr
        this.index = index
        this.literalVal = literalVal
    }
}

private class TerminatorRewriteInfo {
    public let terminator: Terminator
    public let literalVal: Option<LiteralValue>
    public let target: Block

    public init(terminator: Terminator, literalVal: Option<LiteralValue>, target: Block) {
        this.terminator = terminator
        this.literalVal = literalVal
        this.target = target
    }
}

public class ConstPropagation {
    private let builder: Option<CHIRBuilder>
    private let analysisWrapper: ConstAnalysisWrapper
    private let opts: GlobalOptions
    private let funcsNeedRemoveBlocks: ArrayList<Function> = ArrayList<Function>()

    public init(builder!: Option<CHIRBuilder> = None, wrapper!: ConstAnalysisWrapper,
        opts!: GlobalOptions = GlobalOptions()) {
        this.builder = builder
        this.analysisWrapper = wrapper
        this.opts = opts
    }

    public func RunOnPackage(pkg: Package, isDebug!: Bool = false, isCJLint!: Bool = false): Unit {
        for (funcValue in pkg.GetGlobalFuncsWithBody()) {
            RunOnFunc(funcValue, isDebug: isDebug, isCJLint: isCJLint)
        }
    }

    public func RunOnFunc(funcValue: Function, isDebug!: Bool = false, isCJLint!: Bool = false): Unit {
        if (funcValue.TestAttr(Attribute.SKIP_ANALYSIS)) {
            return
        }
        if (let Some(result) <- analysisWrapper.CheckFuncResult(funcValue)) {
            VisitFunc(funcValue, isDebug, isCJLint, result)
        }
    }

    public func GetFuncsNeedRemoveBlocks(): ArrayList<Function> {
        return funcsNeedRemoveBlocks
    }

    public func GetEffectMap(): OptEffectCHIRMap {
        return constPropagationEffectMap
    }

    private func VisitFunc(funcValue: Function, isDebug: Bool, isCJLint: Bool,
        result: Results<ConstDomain>): Unit {
        let toBeRewrited = ArrayList<RewriteInfo>()
        let targetSuccMap = ArrayList<TerminatorRewriteInfo>()
        result.VisitWith(
            { _: ConstDomain, _: Expression, _: Int64 => () },
            { state: ConstDomain, expr: Expression, index: Int64 =>
                let exprResult = expr.GetResult() ?? return
                let exprType = exprResult.GetType().getOrThrow()
                if (expr.IsBinaryExpr()) {
                    if (let Some(absVal) <- state.CheckAbstractValue(exprResult)) {
                        toBeRewrited.add(RewriteInfo(expr, index, GenerateConstExpr(exprType, absVal, isCJLint)))
                        return
                    } else if (exprResult.GetType().getOrThrow().IsInteger()) {
                        let binary = (expr as BinaryExpression).getOrThrow()
                        TrySimplifyingBinaryExpr(state, binary, isDebug)
                        return
                    }
                }
                if (expr.IsUnaryExpr()) {
                    if (let Some(absVal) <- state.CheckAbstractValue(exprResult)) {
                        toBeRewrited.add(RewriteInfo(expr, index, GenerateConstExpr(exprType, absVal, isCJLint)))
                        return
                    }
                    TrySimplifyingUnaryExpr((expr as UnaryExpression).getOrThrow(), isDebug)
                    return
                }
                if ((exprType.IsInteger() || exprType.IsFloat() || exprType.IsRune() ||
                    exprType.IsBoolean() || exprType.IsString()) &&
                    (expr.GetExprKind() == ExprKind.LOAD || expr.GetExprKind() == ExprKind.TYPECAST ||
                    expr.GetExprKind() == ExprKind.FIELD)) {
                    if (let Some(absVal) <- state.CheckAbstractValue(exprResult)) {
                        toBeRewrited.add(RewriteInfo(expr, index, GenerateConstExpr(exprType, absVal, isCJLint)))
                        RecordEffectMap(expr, funcValue)
                    }
                }
            },
            { state: ConstDomain, terminator: Terminator, targetSucc: Option<Block> =>
                if (targetSucc.isNone()) {
                    return
                }
                let target = targetSucc.getOrThrow()
                match (terminator.GetExprKind()) {
                    case ExprKind.BRANCH | ExprKind.MULTIBRANCH =>
                        targetSuccMap.add(TerminatorRewriteInfo(terminator, None, target))
                    case ExprKind.INT_OP_WITH_EXCEPTION | ExprKind.TYPECAST_WITH_EXCEPTION =>
                        if (let Some(res) <- terminator.GetResult()) {
                            if (let Some(absVal) <- state.CheckAbstractValue(res)) {
                                let literal = GenerateConstExpr(res.GetType().getOrThrow(), absVal, isCJLint)
                                targetSuccMap.add(TerminatorRewriteInfo(terminator, literal, target))
                            }
                        }
                    case _ => ()
                }
            }
        )
        for (rewriteInfo in toBeRewrited) {
            RewriteToConstExpr(rewriteInfo, isDebug)
        }
        for (rewriteInfo in targetSuccMap) {
            RewriteTerminator(rewriteInfo.terminator, rewriteInfo.literalVal, rewriteInfo.target, isDebug)
        }
        if (!targetSuccMap.isEmpty()) {
            funcsNeedRemoveBlocks.add(funcValue)
        }
    }

    private func GenerateConstExpr(typeValue: Type, constVal: ConstValue, isCJLint: Bool): Option<LiteralValue> {
        let chirBuilder = builder ?? return None
        match (constVal.GetConstKind()) {
            case ConstKind.UINT =>
                let value = (constVal as ConstUIntVal).getOrThrow().GetVal()
                return chirBuilder.CreateLiteralValue(IntLiteral(value), typeValue)
            case ConstKind.INT =>
                let value = (constVal as ConstIntVal).getOrThrow().GetVal()
                return chirBuilder.CreateLiteralValue(IntLiteral(value), typeValue)
            case ConstKind.FLOAT =>
                let value = (constVal as ConstFloatVal).getOrThrow().GetVal()
                return chirBuilder.CreateLiteralValue(FloatLiteral(value), typeValue)
            case ConstKind.RUNE =>
                let value = (constVal as ConstRuneVal).getOrThrow().GetVal()
                return chirBuilder.CreateLiteralValue(RuneLiteral(value), typeValue)
            case ConstKind.BOOL =>
                let value = (constVal as ConstBoolVal).getOrThrow().GetVal()
                return chirBuilder.CreateLiteralValue(BoolLiteral(value), typeValue)
            case ConstKind.STRING =>
                if (isCJLint) {
                    let value = (constVal as ConstStrVal).getOrThrow().GetVal()
                    return chirBuilder.CreateLiteralValue(StringLiteral(value), typeValue)
                }
                return None
        }
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

    private func TrySimplifyingBinaryExpr(state: ConstDomain, binary: BinaryExpression, isDebug: Bool): Unit {
        if (SkipCP(binary)) {
            return
        }
        let lhs = state.CheckAbstractValue(binary.GetOperand(0))
        let rhs = state.CheckAbstractValue(binary.GetOperand(1))
        match (binary.GetExprKind()) {
            case ExprKind.ADD =>
                if (ConstValueIsZero(lhs)) {
                    return ReplaceUsageOfExprResult(binary, binary.GetOperand(1), isDebug)
                } else if (ConstValueIsZero(rhs)) {
                    return ReplaceUsageOfExprResult(binary, binary.GetOperand(0), isDebug)
                }
            case ExprKind.LSHIFT | ExprKind.RSHIFT | ExprKind.SUB =>
                if (ConstValueIsZero(rhs)) {
                    return ReplaceUsageOfExprResult(binary, binary.GetOperand(0), isDebug)
                }
            case ExprKind.MUL =>
                if (ConstValueIsOne(lhs)) {
                    return ReplaceUsageOfExprResult(binary, binary.GetOperand(1), isDebug)
                } else if (ConstValueIsOne(rhs)) {
                    return ReplaceUsageOfExprResult(binary, binary.GetOperand(0), isDebug)
                }
            case ExprKind.DIV | ExprKind.EXP =>
                if (ConstValueIsOne(rhs)) {
                    return ReplaceUsageOfExprResult(binary, binary.GetOperand(0), isDebug)
                }
            case ExprKind.BITAND | ExprKind.BITOR =>
                if (refEq(binary.GetOperand(0), binary.GetOperand(1))) {
                    return ReplaceUsageOfExprResult(binary, binary.GetOperand(0), isDebug)
                }
            case _ => ()
        }
    }

    private func RewriteToConstExpr(rewriteInfo: RewriteInfo, isDebug: Bool): Unit {
        let literalVal = rewriteInfo.literalVal ?? return
        let oldExpr = rewriteInfo.oldExpr
        if (SkipCP(oldExpr)) {
            return
        }
        let oldExprResult = oldExpr.GetResult() ?? return
        let oldExprParent = oldExpr.GetParentBlock() ?? return
        let chirBuilder = builder ?? return
        let newExpr = chirBuilder.CreateConstant(oldExprResult.GetType().getOrThrow(), literalVal, oldExprParent)
        newExpr.SetDebugLocation(oldExpr.GetDebugLocation())
        oldExprParent.GetExpressionByIdx(rewriteInfo.index).ReplaceWith(newExpr)
        if (isDebug) {
            println("[ConstPropagation] The " + oldExpr.GetExprKindName() +
                ToPosInfo(oldExpr.GetDebugLocation(), isPrintFileName: true) + " has been rewrited to a constant")
        }
    }

    private func TrySimplifyingUnaryExpr(unary: UnaryExpression, isDebug: Bool): Unit {
        if (SkipCP(unary)) {
            return
        }
        if (unary.GetExprKind() != ExprKind.NOT && unary.GetExprKind() != ExprKind.BITNOT) {
            return
        }
        let operand = unary.GetOperand(0)
        if (let Some(localVar) <- operand.AsLocalVar()) {
            if (let Some(operandExpr) <- localVar.GetExpr()) {
                if (operandExpr.GetExprKind() != ExprKind.NOT &&
                    operandExpr.GetExprKind() != ExprKind.BITNOT) {
                    return
                }
                let targetVal = (operandExpr as UnaryExpression).getOrThrow().GetOperand(0)
                ReplaceUsageOfExprResult(unary, targetVal, isDebug)
            }
        }
    }

    private func ReplaceUsageOfExprResult(expr: Expression, newVal: Value, isDebug: Bool): Unit {
        if (let Some(result) <- expr.GetResult()) {
            result.ReplaceWith(newVal, expr.GetParentBlockGroup())
        }
        if (isDebug) {
            println("[ConstPropagation] The result of the trivial " + expr.GetExprKindName() +
                ToPosInfo(expr.GetDebugLocation()) + " has been optimised")
        }
    }

    private func RewriteTerminator(oldTerminator: Terminator, newValue: Option<LiteralValue>,
        newTarget: Block, isDebug: Bool): Unit {
        if (SkipCP(oldTerminator)) {
            return
        }
        let parentBlock = oldTerminator.GetParentBlock() ?? return
        let loc = oldTerminator.GetDebugLocation()
        if (builder.isNone()) {
            return
        }
        let chirBuilder = builder.getOrThrow()
        oldTerminator.RemoveSelfFromBlock()
        if (let Some(literal) <- newValue) {
            if (let Some(res) <- oldTerminator.GetResult()) {
                let constant = chirBuilder.CreateConstant(literal.GetType().getOrThrow(), literal, parentBlock)
                constant.SetDebugLocation(loc)
                res.ReplaceWith(constant.GetResult().getOrThrow(), constant.GetParentBlockGroup())
            }
        }
        let newTerminator = chirBuilder.CreateGoTo(newTarget, parentBlock)
        newTerminator.SetDebugLocation(loc)
        if (isDebug) {
            println("[ConstPropagation] The terminator " + oldTerminator.GetExprKindName() +
                ToPosInfo(oldTerminator.GetDebugLocation()) + " has been optimised")
        }
    }

    private func RecordEffectMap(expr: Expression, funcValue: Function): Unit {
        if (!opts.enIncrementalCompilation ||
            !opts.IsOptimizationExisted(OptimizationFlag.CONST_PROPAGATION)) {
            return
        }
        var globalVar: Option<GlobalVar> = None
        if (expr.GetExprKind() == ExprKind.LOAD) {
            let location = (expr as Load).getOrThrow().GetLocation()
            if (location.IsGlobalVarWithInitializer()) {
                globalVar = location.AsGlobalVar()
            } else if (let Some(localVar) <- location.AsLocalVar()) {
                let locationExpr = localVar.GetExpr().getOrThrow()
                if (locationExpr.GetExprKind() == ExprKind.GET_ELEMENT_REF) {
                    let base = (locationExpr as GetElementRef).getOrThrow().GetLocation()
                    if (base.IsGlobalVarWithInitializer()) {
                        globalVar = base.AsGlobalVar()
                    }
                }
            }
        } else if (expr.GetExprKind() == ExprKind.FIELD) {
            let base = (expr as Field).getOrThrow().GetBase()
            if (let Some(localVar) <- base.AsLocalVar()) {
                let baseExpr = localVar.GetExpr().getOrThrow()
                if (baseExpr.GetExprKind() == ExprKind.LOAD) {
                    let location = (baseExpr as Load).getOrThrow().GetLocation()
                    if (location.IsGlobalVarWithInitializer()) {
                        globalVar = location.AsGlobalVar()
                    }
                }
            }
        }
        if (let Some(gv) <- globalVar) {
            if (opts.GetJobs() > 1u64) {
                synchronized(constPropagationEffectMapMutex) {
                    if (let Some(affectedFunctions) <- constPropagationEffectMap.get(gv)) {
                        affectedFunctions.add(funcValue)
                    } else {
                        constPropagationEffectMap[gv] = HashSet<Value>([funcValue])
                    }
                }
            } else {
                if (let Some(affectedFunctions) <- constPropagationEffectMap.get(gv)) {
                    affectedFunctions.add(funcValue)
                } else {
                    constPropagationEffectMap[gv] = HashSet<Value>([funcValue])
                }
            }
        }
    }
}

private func ConstValueIsZero(value: Option<ConstValue>): Bool {
    if (let Some(realValue) <- value) {
        if (let Some(intVal) <- (realValue as ConstIntVal)) {
            return intVal.GetVal() == 0
        }
        if (let Some(uintVal) <- (realValue as ConstUIntVal)) {
            return uintVal.GetVal() == 0u64
        }
    }
    return false
}

private func ConstValueIsOne(value: Option<ConstValue>): Bool {
    if (let Some(realValue) <- value) {
        if (let Some(intVal) <- (realValue as ConstIntVal)) {
            return intVal.GetVal() == 1
        }
        if (let Some(uintVal) <- (realValue as ConstUIntVal)) {
            return uintVal.GetVal() == 1u64
        }
    }
    return false
}
