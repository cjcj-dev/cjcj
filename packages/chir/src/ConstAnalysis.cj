package cangjie_compiler::chir

import cangjie_compiler::basic.{DiagnosticEngine as BasicDiagnosticEngine, DiagKindRefactor}
import cangjie_compiler::utils.{CJC_ABORT, CJC_ASSERT, InternalError, OverflowStrategy}
import std.collection.*

public type ConstDomain = State<ConstValue, FullStatePool<ConstValue>>

private enum ConstExceptionKind {
    | SUCCESS | FAIL | NA
}

private func ConstExceptionKindIndex(kind: ConstExceptionKind): Int64 {
    return match (kind) {
        case ConstExceptionKind.SUCCESS => 0
        case ConstExceptionKind.FAIL => 1
        case ConstExceptionKind.NA => 2
    }
}

extend ConstExceptionKind <: Equatable<ConstExceptionKind> {
    public operator func ==(right: ConstExceptionKind): Bool {
        return ConstExceptionKindIndex(this) == ConstExceptionKindIndex(right)
    }

    public operator func !=(right: ConstExceptionKind): Bool {
        return !(this == right)
    }
}

private let arrayInitFunc = FuncInfo("init", "Array", [NOT_CARE], NOT_CARE, "std.core")
private let arraySliceFunc = FuncInfo("slice", "Array", ["Int64", "Int64"], ANY_TYPE, "std.core")
private let arrayBracketsFunc = FuncInfo("[]", "Array", ["Int64", NOT_CARE], ANY_TYPE, "std.core")
private let arrayGetFunc = FuncInfo("get", "Array", ["Int64"], ANY_TYPE, "std.core")
private let arraySizeGet = FuncInfo("$sizeget", "Array", [], ANY_TYPE, "std.core")
private let rangeInitFunc = FuncInfo("init", "Range", [NOT_CARE], NOT_CARE, "std.core")

private let thisArgIndex: Int64 = 0
private let lenFieldIndex: Int64 = 2

public class ConstAnalysis <: ValueAnalysis<ConstValue, FullStatePool<ConstValue>> {
    private let diag: BasicDiagnosticEngine

    public init(functionValue: Function, builder: CHIRBuilder, diag: BasicDiagnosticEngine,
        isDebug!: Bool = false) {
        super(functionValue, builder, isDebug: isDebug)
        this.diag = diag
    }

    public override func HandleNormalExpressionEffect(state: ConstDomain, expression: Expression): Unit {
        var exceptionKind = ConstExceptionKind.NA
        match (expression.GetExprMajorKind()) {
            case ExprMajorKind.MEMORY_EXPR => return
            case ExprMajorKind.UNARY_EXPR =>
                exceptionKind = HandleUnaryExpr(state, (expression as UnaryExpression).getOrThrow())
            case ExprMajorKind.BINARY_EXPR =>
                exceptionKind = HandleBinaryExpr(state, (expression as BinaryExpression).getOrThrow())
            case ExprMajorKind.OTHERS =>
                exceptionKind = HandleOthersExpr(state, expression)
            case ExprMajorKind.STRUCTURED_CTRL_FLOW_EXPR => CJC_ABORT()
            case _ => CJC_ABORT()
        }
        if (exceptionKind == ConstExceptionKind.SUCCESS) {
            MarkExpressionAsMustNotOverflow(expression)
        }
        if (expression.GetExprMajorKind() != ExprMajorKind.UNARY_EXPR &&
            expression.GetExprMajorKind() != ExprMajorKind.BINARY_EXPR &&
            expression.GetExprKind() != ExprKind.TYPECAST) {
            return
        }
        let exprType = expression.GetResult().getOrThrow().GetType().getOrThrow()
        if (isDebug && (exprType.IsInteger() || exprType.IsFloat() || exprType.IsRune() ||
            exprType.IsBoolean() || exprType.IsString())) {
            if (let Some(absVal) <- state.CheckAbstractValue(expression.GetResult().getOrThrow())) {
                PrintDebugMessage(expression, absVal)
            }
        }
    }

    public override func HandleTerminatorEffect(state: ConstDomain, terminator: Terminator): Option<Block> {
        var res = ConstExceptionKind.NA
        match (terminator.GetExprKind()) {
            case ExprKind.GOTO => ()
            case ExprKind.EXIT => ()
            case ExprKind.BRANCH =>
                return HandleBranchTerminator(state, (terminator as Branch).getOrThrow())
            case ExprKind.MULTIBRANCH =>
                return HandleMultiBranchTerminator(state, (terminator as MultiBranch).getOrThrow())
            case ExprKind.TYPECAST_WITH_EXCEPTION =>
                res = HandleTypeCast(state, (terminator as TypeCastWithException).getOrThrow())
            case ExprKind.INT_OP_WITH_EXCEPTION =>
                res = HandleIntOpWithExcepTerminator(state, (terminator as IntOpWithException).getOrThrow())
            case ExprKind.INTRINSIC_WITH_EXCEPTION =>
                res = HandleIntrinsic(state, (terminator as IntrinsicWithException).getOrThrow())
            case _ =>
                if (let Some(dest) <- terminator.GetResult()) {
                    state.SetToTopOrTopRef(dest, dest.GetType().getOrThrow().IsRef())
                }
        }
        if (res == ConstExceptionKind.SUCCESS) {
            MarkExpressionAsMustNotOverflow(terminator)
            return terminator.GetSuccessor(0)
        } else if (res == ConstExceptionKind.FAIL) {
            return terminator.GetSuccessor(1)
        }
        return None
    }

    public override func HandleApplyExpr(state: ConstDomain, apply: Apply, refObj: Option<Value>): Unit {
        let _ = refObj
        HandleApply(state, apply)
    }

    public override func HandleApplyWithExceptionTerminator(state: ConstDomain,
        apply: ApplyWithException, refObj: Option<Value>): Option<Block> {
        let _ = refObj
        let res = HandleApply(state, apply)
        if (res == ConstExceptionKind.SUCCESS) {
            return apply.GetSuccessBlock()
        } else if (res == ConstExceptionKind.FAIL) {
            return apply.GetErrorBlock()
        }
        return None
    }

    private func PrintDebugMessage(expr: Expression, absVal: ConstValue): Unit {
        let message = "[ConstAnalysis] The const value of " + expr.GetExprKindName() +
            ToPosInfo(expr.GetDebugLocation()) + " has been set to " + absVal.ToString()
        println(message)
    }

    private func MarkExpressionAsMustNotOverflow(expr: Expression): Unit {
        if (isStable) {
            expr.SetNeverOverflowInfo(true)
        }
    }

    private func HandleUnaryExpr(state: ConstDomain, unaryExpr: UnaryExpression): ConstExceptionKind {
        let operand = unaryExpr.GetOperand(0)
        let dest = unaryExpr.GetResult().getOrThrow()
        let absValOpt = state.CheckAbstractValue(operand)
        if (absValOpt.isNone()) {
            state.SetToBound(dest, true)
            return ConstExceptionKind.NA
        }
        let absVal = absValOpt.getOrThrow()
        match (unaryExpr.GetExprKind()) {
            case ExprKind.NEG =>
                if (absVal.GetConstKind() == ConstKind.UINT) {
                    return HandleNegOpOfUInt(state, unaryExpr, (absVal as ConstUIntVal).getOrThrow())
                } else if (absVal.GetConstKind() == ConstKind.INT) {
                    return HandleNegOpOfInt(state, unaryExpr, (absVal as ConstIntVal).getOrThrow())
                } else if (absVal.GetConstKind() == ConstKind.FLOAT) {
                    let floatVal = (absVal as ConstFloatVal).getOrThrow()
                    var res = -floatVal.GetVal()
                    res = CutOffHighBits(res, dest.GetType().getOrThrow().GetTypeKind())
                    if (!IsFiniteFloat(res)) {
                        state.SetToBound(dest, true)
                    } else {
                        state.Update(dest, ConstFloatVal(res))
                    }
                    return ConstExceptionKind.NA
                }
                CJC_ABORT()
            case ExprKind.NOT =>
                let boolVal = (absVal as ConstBoolVal).getOrThrow().GetVal()
                state.Update(dest, ConstBoolVal(!boolVal))
            case ExprKind.BITNOT =>
                if (absVal.GetConstKind() == ConstKind.UINT) {
                    let uintVal = (absVal as ConstUIntVal).getOrThrow().GetVal()
                    state.Update(dest,
                        ConstUIntVal(CutOffHighBits(uintVal ^ UInt64.Max,
                            operand.GetType().getOrThrow().GetTypeKind())))
                } else {
                    let intVal = (absVal as ConstIntVal).getOrThrow().GetVal()
                    state.Update(dest,
                        ConstIntVal(CutOffHighBits(BitNotInt64(intVal),
                            operand.GetType().getOrThrow().GetTypeKind())))
                }
            case _ => CJC_ABORT()
        }
        return ConstExceptionKind.NA
    }

    private func HandleBinaryExpr(state: ConstDomain, binaryExpr: BinaryExpression): ConstExceptionKind {
        let kind = binaryExpr.GetExprKind()
        match (kind) {
            case ExprKind.ADD | ExprKind.SUB | ExprKind.MUL | ExprKind.DIV | ExprKind.MOD =>
                return HandleArithmeticOp(state, binaryExpr, kind)
            case ExprKind.EXP =>
                return HandleExpOp(state, binaryExpr)
            case ExprKind.LSHIFT | ExprKind.RSHIFT | ExprKind.BITAND | ExprKind.BITXOR | ExprKind.BITOR =>
                return HandleBitwiseOp(state, binaryExpr, kind)
            case ExprKind.LT | ExprKind.GT | ExprKind.LE | ExprKind.GE | ExprKind.EQUAL | ExprKind.NOTEQUAL =>
                HandleRelationalOp(state, binaryExpr)
                return ConstExceptionKind.NA
            case ExprKind.AND | ExprKind.OR =>
                HandleLogicalOp(state, binaryExpr)
                return ConstExceptionKind.NA
            case _ =>
                CJC_ABORT()
                return ConstExceptionKind.NA
        }
    }

    private func HandleOthersExpr(state: ConstDomain, expression: Expression): ConstExceptionKind {
        match (expression.GetExprKind()) {
            case ExprKind.TYPECAST =>
                return HandleTypeCast(state, (expression as TypeCast).getOrThrow())
            case ExprKind.INTRINSIC =>
                return HandleIntrinsic(state, (expression as Intrinsic).getOrThrow())
            case ExprKind.CONSTANT | ExprKind.APPLY | ExprKind.FIELD =>
                return ConstExceptionKind.NA
            case _ =>
                let dest = expression.GetResult().getOrThrow()
                state.SetToTopOrTopRef(dest, dest.GetType().getOrThrow().IsRef())
                return ConstExceptionKind.NA
        }
    }

    private func HandleBranchTerminator(state: ConstDomain, branch: Branch): Option<Block> {
        if (let Some(condVal) <- state.CheckAbstractValue(branch.GetCondition())) {
            let boolVal = (condVal as ConstBoolVal).getOrThrow().GetVal()
            return if (boolVal) { branch.GetTrueBlock() } else { branch.GetFalseBlock() }
        }
        return None
    }

    private func HandleMultiBranchTerminator(state: ConstDomain, multi: MultiBranch): Option<Block> {
        if (let Some(condVal) <- state.CheckAbstractValue(multi.GetCondition())) {
            let intVal = (condVal as ConstUIntVal).getOrThrow().GetVal()
            let cases = multi.GetCaseVals()
            var idx: Int64 = 0
            while (idx < cases.size) {
                if (intVal == cases[idx]) {
                    return multi.GetCaseBlockByIndex(idx)
                }
                idx++
            }
            return multi.GetDefaultBlock()
        }
        return None
    }

    private func HandleIntOpWithExcepTerminator(state: ConstDomain, intOp: IntOpWithException): ConstExceptionKind {
        let kind = intOp.GetOpKind()
        if (kind == ExprKind.NEG) {
            let operand = intOp.GetOperand(0)
            let absVal = state.CheckAbstractValue(operand)
            if (absVal.isNone()) {
                state.SetToBound(intOp.GetResult().getOrThrow(), true)
                return ConstExceptionKind.NA
            }
            let value = absVal.getOrThrow()
            if (value.GetConstKind() == ConstKind.UINT) {
                return HandleNegOpOfUInt(state, intOp, (value as ConstUIntVal).getOrThrow())
            }
            return HandleNegOpOfInt(state, intOp, (value as ConstIntVal).getOrThrow())
        }
        let kindIndex = ExprKindIndex(kind)
        if (kindIndex >= ExprKindIndex(ExprKind.ADD) && kindIndex < ExprKindIndex(ExprKind.EXP)) {
            return HandleArithmeticOp(state, intOp, kind)
        }
        if (kind == ExprKind.EXP) {
            return HandleExpOp(state, intOp)
        }
        if (kindIndex >= ExprKindIndex(ExprKind.LSHIFT) && kindIndex <= ExprKindIndex(ExprKind.RSHIFT)) {
            return HandleBitwiseOp(state, intOp, kind)
        }
        InternalError("Unsupported IntOpWithException terminator")
        return ConstExceptionKind.NA
    }

    private func HandleNegOpOfInt(state: ConstDomain, expr: Expression, constVal: ConstIntVal): ConstExceptionKind {
        let dest = expr.GetResult().getOrThrow()
        let result = OverflowChecker.IsIntOverflow(dest.GetType().getOrThrow().GetTypeKind(), ExprKind.NEG,
            0, constVal.GetVal(), GetOverflowStrategy(expr))
        if (result.isOverflow && GetOverflowStrategy(expr) == OverflowStrategy.THROWING) {
            RaiseNegOverflowError(expr, constVal)
            state.SetToBound(dest, true)
            return ConstExceptionKind.FAIL
        }
        state.Update(dest, ConstIntVal(result.value))
        return ConstExceptionKind.SUCCESS
    }

    private func HandleNegOpOfUInt(state: ConstDomain, expr: Expression, constVal: ConstUIntVal): ConstExceptionKind {
        let dest = expr.GetResult().getOrThrow()
        let result = OverflowChecker.IsUIntOverflow(dest.GetType().getOrThrow().GetTypeKind(), ExprKind.NEG,
            0u64, constVal.GetVal(), GetOverflowStrategy(expr))
        if (result.isOverflow && GetOverflowStrategy(expr) == OverflowStrategy.THROWING) {
            RaiseNegOverflowError(expr, constVal)
            state.SetToBound(dest, true)
            return ConstExceptionKind.FAIL
        }
        state.Update(dest, ConstUIntVal(result.value))
        return ConstExceptionKind.SUCCESS
    }

    private func HandleArithmeticOp(state: ConstDomain, expr: Expression, kind: ExprKind): ConstExceptionKind {
        let lhs = GetLHSOperand(expr)
        let rhs = GetRHSOperand(expr)
        CJC_ASSERT(refEq(lhs.GetType().getOrThrow(), rhs.GetType().getOrThrow()))
        let lhsAbsVal = state.CheckAbstractValue(lhs)
        let rhsAbsVal = state.CheckAbstractValue(rhs)
        if (lhsAbsVal.isNone() && rhsAbsVal.isNone()) {
            state.SetToBound(expr.GetResult().getOrThrow(), true)
            return ConstExceptionKind.NA
        }
        if (lhs.GetType().getOrThrow().IsInteger()) {
            let intTy = (lhs.GetType().getOrThrow() as IntType).getOrThrow()
            if (intTy.IsSigned()) {
                return HandleArithmeticOpOfInt(state, expr, kind, AsConstInt(lhsAbsVal), AsConstInt(rhsAbsVal))
            }
            return HandleArithmeticOpOfUInt(state, expr, kind, AsConstUInt(lhsAbsVal), AsConstUInt(rhsAbsVal))
        } else if (expr.GetExprKind() != ExprKind.INT_OP_WITH_EXCEPTION) {
            HandleArithmeticOpOfFloat(state, (expr as BinaryExpression).getOrThrow(), lhsAbsVal, rhsAbsVal)
        }
        return ConstExceptionKind.NA
    }

    private func HandleArithmeticOpOfInt(state: ConstDomain, expr: Expression, kind: ExprKind,
        lhs: Option<ConstIntVal>, rhs: Option<ConstIntVal>): ConstExceptionKind {
        let dest = expr.GetResult().getOrThrow()
        let trivial = HandleTrivialArithmeticOpOfInt(state, expr, kind, lhs, rhs)
        if (trivial != ConstExceptionKind.NA) {
            return trivial
        }
        if (refEq(GetLHSOperand(expr), GetRHSOperand(expr)) && kind == ExprKind.SUB) {
            state.Update(dest, ConstIntVal(0))
            return ConstExceptionKind.SUCCESS
        }
        if (lhs.isNone() || rhs.isNone()) {
            state.SetToBound(dest, true)
            return ConstExceptionKind.NA
        }
        let left = lhs.getOrThrow()
        let right = rhs.getOrThrow()
        let result = OverflowChecker.IsIntOverflow(dest.GetType().getOrThrow().GetTypeKind(), kind,
            left.GetVal(), right.GetVal(), GetOverflowStrategy(expr))
        if (result.isOverflow && GetOverflowStrategy(expr) == OverflowStrategy.THROWING) {
            RaiseArithmeticOverflowError(expr, kind, left, right)
            state.SetToBound(dest, true)
            return ConstExceptionKind.FAIL
        }
        state.Update(dest, ConstIntVal(result.value))
        return ConstExceptionKind.SUCCESS
    }

    private func HandleArithmeticOpOfUInt(state: ConstDomain, expr: Expression, kind: ExprKind,
        lhs: Option<ConstUIntVal>, rhs: Option<ConstUIntVal>): ConstExceptionKind {
        let dest = expr.GetResult().getOrThrow()
        let trivial = HandleTrivialArithmeticOpOfUInt(state, expr, kind, lhs, rhs)
        if (trivial != ConstExceptionKind.NA) {
            return trivial
        }
        if (refEq(GetLHSOperand(expr), GetRHSOperand(expr)) && kind == ExprKind.SUB) {
            state.Update(dest, ConstUIntVal(0u64))
            return ConstExceptionKind.SUCCESS
        }
        if (lhs.isNone() || rhs.isNone()) {
            state.SetToBound(dest, true)
            return ConstExceptionKind.NA
        }
        let left = lhs.getOrThrow()
        let right = rhs.getOrThrow()
        let result = OverflowChecker.IsUIntOverflow(dest.GetType().getOrThrow().GetTypeKind(), kind,
            left.GetVal(), right.GetVal(), GetOverflowStrategy(expr))
        if (result.isOverflow && GetOverflowStrategy(expr) == OverflowStrategy.THROWING) {
            RaiseArithmeticOverflowError(expr, kind, left, right)
            state.SetToBound(dest, true)
            return ConstExceptionKind.FAIL
        }
        state.Update(dest, ConstUIntVal(result.value))
        return ConstExceptionKind.SUCCESS
    }

    private func HandleTrivialArithmeticOpOfInt(state: ConstDomain, expr: Expression, kind: ExprKind,
        lhs: Option<ConstIntVal>, rhs: Option<ConstIntVal>): ConstExceptionKind {
        let dest = expr.GetResult().getOrThrow()
        if (let Some(right) <- rhs) {
            if (right.GetVal() == 0) {
                if (kind == ExprKind.DIV || kind == ExprKind.MOD) {
                    RaiseDivByZeroError(expr, kind)
                    state.SetToBound(dest, true)
                    return ConstExceptionKind.FAIL
                } else if (kind == ExprKind.MUL) {
                    state.Update(dest, ConstIntVal(0))
                    return ConstExceptionKind.SUCCESS
                }
            }
            if (right.GetVal() == 1 && kind == ExprKind.MOD) {
                state.Update(dest, ConstIntVal(0))
                return ConstExceptionKind.SUCCESS
            }
        }
        if (let Some(left) <- lhs) {
            if (left.GetVal() == 0 && (kind == ExprKind.MUL || kind == ExprKind.DIV || kind == ExprKind.MOD)) {
                state.Update(dest, ConstIntVal(0))
                return ConstExceptionKind.SUCCESS
            }
        }
        return ConstExceptionKind.NA
    }

    private func HandleTrivialArithmeticOpOfUInt(state: ConstDomain, expr: Expression, kind: ExprKind,
        lhs: Option<ConstUIntVal>, rhs: Option<ConstUIntVal>): ConstExceptionKind {
        let dest = expr.GetResult().getOrThrow()
        if (let Some(right) <- rhs) {
            if (right.GetVal() == 0u64) {
                if (kind == ExprKind.DIV || kind == ExprKind.MOD) {
                    RaiseDivByZeroError(expr, kind)
                    state.SetToBound(dest, true)
                    return ConstExceptionKind.FAIL
                } else if (kind == ExprKind.MUL) {
                    state.Update(dest, ConstUIntVal(0u64))
                    return ConstExceptionKind.SUCCESS
                }
            }
            if (right.GetVal() == 1u64 && kind == ExprKind.MOD) {
                state.Update(dest, ConstUIntVal(0u64))
                return ConstExceptionKind.SUCCESS
            }
        }
        if (let Some(left) <- lhs) {
            if (left.GetVal() == 0u64 && (kind == ExprKind.MUL || kind == ExprKind.DIV || kind == ExprKind.MOD)) {
                state.Update(dest, ConstUIntVal(0u64))
                return ConstExceptionKind.SUCCESS
            }
        }
        return ConstExceptionKind.NA
    }

    private func HandleExpOp(state: ConstDomain, expr: Expression): ConstExceptionKind {
        let dest = expr.GetResult().getOrThrow()
        if (!dest.GetType().getOrThrow().IsInteger()) {
            state.SetToBound(dest, true)
            return ConstExceptionKind.NA
        }
        let lhsAbsVal = AsConstInt(state.CheckAbstractValue(GetLHSOperand(expr)))
        let rhsAbsVal = AsConstUInt(state.CheckAbstractValue(GetRHSOperand(expr)))
        if (let Some(rhs) <- rhsAbsVal) {
            if (rhs.GetVal() == 0u64) {
                state.Update(dest, ConstIntVal(1))
                return ConstExceptionKind.SUCCESS
            }
        }
        if (let Some(lhs) <- lhsAbsVal) {
            let value = lhs.GetVal()
            if (value == 0 || value == 1) {
                state.Update(dest, ConstIntVal(value))
                return ConstExceptionKind.SUCCESS
            }
        }
        if (lhsAbsVal.isNone() || rhsAbsVal.isNone()) {
            state.SetToBound(dest, true)
            return ConstExceptionKind.NA
        }
        let result = OverflowChecker.IsExpOverflow(lhsAbsVal.getOrThrow().GetVal(),
            rhsAbsVal.getOrThrow().GetVal(), GetOverflowStrategy(expr))
        if (result.isOverflow && GetOverflowStrategy(expr) == OverflowStrategy.THROWING) {
            RaiseArithmeticOverflowError(expr, ExprKind.EXP, lhsAbsVal.getOrThrow(), rhsAbsVal.getOrThrow())
            state.SetToBound(dest, true)
            return ConstExceptionKind.FAIL
        }
        state.Update(dest, ConstIntVal(result.value))
        return ConstExceptionKind.SUCCESS
    }

    private func HandleArithmeticOpOfFloat(state: ConstDomain, binaryExpr: BinaryExpression,
        lhs: Option<ConstValue>, rhs: Option<ConstValue>): Unit {
        let dest = binaryExpr.GetResult().getOrThrow()
        if (lhs.isNone() || rhs.isNone()) {
            state.SetToBound(dest, true)
            return
        }
        let left = (lhs.getOrThrow() as ConstFloatVal).getOrThrow()
        let right = (rhs.getOrThrow() as ConstFloatVal).getOrThrow()
        var res = match (binaryExpr.GetExprKind()) {
            case ExprKind.ADD => left.GetVal() + right.GetVal()
            case ExprKind.SUB => left.GetVal() - right.GetVal()
            case ExprKind.MUL => left.GetVal() * right.GetVal()
            case ExprKind.DIV => left.GetVal() / right.GetVal()
            case _ =>
                CJC_ABORT()
                0.0
        }
        if (!IsFiniteFloat(res)) {
            state.SetToBound(dest, true)
        } else {
            res = CutOffHighBits(res, dest.GetType().getOrThrow().GetTypeKind())
            state.Update(dest, ConstFloatVal(res))
        }
    }

    private func HandleBitwiseOp(state: ConstDomain, expr: Expression, kind: ExprKind): ConstExceptionKind {
        let lhs = GetLHSOperand(expr)
        let rhs = GetRHSOperand(expr)
        let isLSigned = (lhs.GetType().getOrThrow() as IntType).getOrThrow().IsSigned()
        let isRSigned = (rhs.GetType().getOrThrow() as IntType).getOrThrow().IsSigned()
        let lhsAbsVal = state.CheckAbstractValue(lhs)
        let rhsAbsVal = state.CheckAbstractValue(rhs)
        let dest = expr.GetResult().getOrThrow()
        let isShiftOp = kind == ExprKind.LSHIFT || kind == ExprKind.RSHIFT
        if (rhsAbsVal.isNone()) {
            state.SetToBound(dest, true)
            return ConstExceptionKind.NA
        }
        let rightSigned = AsConstInt(rhsAbsVal)
        if (isShiftOp && isRSigned && rightSigned.getOrThrow().GetVal() < 0) {
            RaiseNegativeShiftError(expr, rightSigned.getOrThrow().GetVal())
            state.SetToBound(dest, true)
            return ConstExceptionKind.FAIL
        }
        let rightVal = ConstValueToUInt(rhsAbsVal.getOrThrow())
        if (isShiftOp) {
            let lhsValBit = (lhs.GetType().getOrThrow() as IntType).getOrThrow().GetBitness()
            if (rightVal >= lhsValBit) {
                RaiseOvershiftError(expr, rightVal, lhsValBit)
                state.SetToBound(dest, true)
                return ConstExceptionKind.FAIL
            }
        }
        if (lhsAbsVal.isNone()) {
            state.SetToBound(dest, true)
            return ConstExceptionKind.NA
        }
        let leftValue = lhsAbsVal.getOrThrow()
        let lhsTy = lhs.GetType().getOrThrow()
        let rawResult = EvalBitwiseRaw(leftValue, rhsAbsVal.getOrThrow(), isLSigned, isRSigned, kind, rightVal)
        if (isLSigned) {
            state.Update(dest,
                ConstIntVal(BitsToSignedLocal(rawResult, Int64((lhsTy as IntType).getOrThrow().GetBitness()))))
        } else {
            state.Update(dest, ConstUIntVal(CutOffHighBits(rawResult, lhsTy.GetTypeKind())))
        }
        return ConstExceptionKind.SUCCESS
    }

    private func HandleRelationalOp(state: ConstDomain, binaryExpr: BinaryExpression): Unit {
        let kind = binaryExpr.GetExprKind()
        let dest = binaryExpr.GetResult().getOrThrow()
        let lhs = binaryExpr.GetOperand(0)
        let rhs = binaryExpr.GetOperand(1)
        let lhsTy = lhs.GetType().getOrThrow()
        CJC_ASSERT(refEq(lhsTy, rhs.GetType().getOrThrow()))
        if (lhsTy.IsUnit() || (refEq(lhs, rhs) && !lhsTy.IsFloat())) {
            var res = true
            if (kind == ExprKind.LT || kind == ExprKind.GT || kind == ExprKind.NOTEQUAL) {
                res = false
            }
            state.Update(dest, ConstBoolVal(res))
            return
        }
        let lhsAbsVal = state.CheckAbstractValue(lhs)
        let rhsAbsVal = state.CheckAbstractValue(rhs)
        if (lhsAbsVal.isNone() || rhsAbsVal.isNone()) {
            state.SetToBound(dest, true)
            return
        }
        state.Update(dest, ConstBoolVal(CompareConst(kind, lhsAbsVal.getOrThrow(), rhsAbsVal.getOrThrow())))
    }

    private func HandleLogicalOp(state: ConstDomain, binaryExpr: BinaryExpression): Unit {
        let lhsVal = AsConstBool(state.CheckAbstractValue(binaryExpr.GetOperand(0)))
        let rhsVal = AsConstBool(state.CheckAbstractValue(binaryExpr.GetOperand(1)))
        let dest = binaryExpr.GetResult().getOrThrow()
        if (binaryExpr.GetExprKind() == ExprKind.AND) {
            if (lhsVal.isSome() && rhsVal.isSome()) {
                state.Update(dest, ConstBoolVal(lhsVal.getOrThrow().GetVal() && rhsVal.getOrThrow().GetVal()))
            } else if ((lhsVal.isSome() && !lhsVal.getOrThrow().GetVal()) ||
                (rhsVal.isSome() && !rhsVal.getOrThrow().GetVal())) {
                state.Update(dest, ConstBoolVal(false))
            } else {
                state.SetToBound(dest, true)
            }
        } else {
            if (lhsVal.isSome() && rhsVal.isSome()) {
                state.Update(dest, ConstBoolVal(lhsVal.getOrThrow().GetVal() && rhsVal.getOrThrow().GetVal()))
            } else if ((lhsVal.isSome() && lhsVal.getOrThrow().GetVal()) ||
                (rhsVal.isSome() && rhsVal.getOrThrow().GetVal())) {
                state.Update(dest, ConstBoolVal(true))
            } else {
                state.SetToBound(dest, true)
            }
        }
    }

    private func HandleTypeCast(state: ConstDomain, cast: TypeCast): ConstExceptionKind {
        return HandleTypeCastImpl(state, cast, cast.GetSourceValue(), cast.GetSourceTy().getOrThrow(),
            cast.GetTargetTy().getOrThrow(), cast.GetOverflowStrategy())
    }

    private func HandleTypeCast(state: ConstDomain, cast: TypeCastWithException): ConstExceptionKind {
        return HandleTypeCastImpl(state, cast, cast.GetSourceValue(), cast.GetSourceTy().getOrThrow(),
            cast.GetTargetTy().getOrThrow(), cast.GetOverflowStrategy())
    }

    private func HandleTypeCastImpl(state: ConstDomain, cast: Expression, sourceValue: Value, sourceTy: Type,
        targetTy: Type, overflowStrategy: OverflowStrategy): ConstExceptionKind {
        let dest = cast.GetResult().getOrThrow()
        if (sourceTy.IsInteger()) {
            if (let Some(srcAbsVal) <- state.CheckAbstractValue(sourceValue)) {
                return HandleTypecastOfInt(state, cast, sourceTy, targetTy, overflowStrategy, srcAbsVal)
            }
        }
        if (sourceTy.IsRef() || sourceTy.IsClass()) {
            state.Propagate(sourceValue, dest)
            return ConstExceptionKind.NA
        }
        state.SetToTopOrTopRef(dest, dest.GetType().getOrThrow().IsRef())
        return ConstExceptionKind.NA
    }

    private func HandleTypecastOfInt(state: ConstDomain, cast: Expression, sourceTy: Type, targetTy: Type,
        overflowStrategy: OverflowStrategy, srcAbsVal: ConstValue): ConstExceptionKind {
        match (sourceTy.GetTypeKind()) {
            case TypeKind.TYPE_INT8 =>
                let constVal = (srcAbsVal as ConstIntVal).getOrThrow().GetVal()
                return HandleTypecastOfIntDispatcherSigned(state, cast,
                    CutOffHighBits(constVal, TypeKind.TYPE_INT8), targetTy, overflowStrategy)
            case TypeKind.TYPE_INT16 =>
                let constVal = (srcAbsVal as ConstIntVal).getOrThrow().GetVal()
                return HandleTypecastOfIntDispatcherSigned(state, cast,
                    CutOffHighBits(constVal, TypeKind.TYPE_INT16), targetTy, overflowStrategy)
            case TypeKind.TYPE_INT32 =>
                let constVal = (srcAbsVal as ConstIntVal).getOrThrow().GetVal()
                return HandleTypecastOfIntDispatcherSigned(state, cast,
                    CutOffHighBits(constVal, TypeKind.TYPE_INT32), targetTy, overflowStrategy)
            case TypeKind.TYPE_INT64 =>
                let constVal = (srcAbsVal as ConstIntVal).getOrThrow().GetVal()
                return HandleTypecastOfIntDispatcherSigned(state, cast,
                    CutOffHighBits(constVal, TypeKind.TYPE_INT64), targetTy, overflowStrategy)
            case TypeKind.TYPE_INT_NATIVE =>
                let constVal = (srcAbsVal as ConstIntVal).getOrThrow().GetVal()
                return HandleTypecastOfIntDispatcherSigned(state, cast,
                    CutOffHighBits(constVal, TypeKind.TYPE_INT_NATIVE), targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT8 =>
                let constVal = (srcAbsVal as ConstUIntVal).getOrThrow().GetVal()
                return HandleTypecastOfIntDispatcherUnsigned(state, cast,
                    CutOffHighBits(constVal, TypeKind.TYPE_UINT8), targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT16 =>
                let constVal = (srcAbsVal as ConstUIntVal).getOrThrow().GetVal()
                return HandleTypecastOfIntDispatcherUnsigned(state, cast,
                    CutOffHighBits(constVal, TypeKind.TYPE_UINT16), targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT32 =>
                let constVal = (srcAbsVal as ConstUIntVal).getOrThrow().GetVal()
                return HandleTypecastOfIntDispatcherUnsigned(state, cast,
                    CutOffHighBits(constVal, TypeKind.TYPE_UINT32), targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT64 =>
                let constVal = (srcAbsVal as ConstUIntVal).getOrThrow().GetVal()
                return HandleTypecastOfIntDispatcherUnsigned(state, cast,
                    CutOffHighBits(constVal, TypeKind.TYPE_UINT64), targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT_NATIVE =>
                let constVal = (srcAbsVal as ConstUIntVal).getOrThrow().GetVal()
                return HandleTypecastOfIntDispatcherUnsigned(state, cast,
                    CutOffHighBits(constVal, TypeKind.TYPE_UINT_NATIVE), targetTy, overflowStrategy)
            case _ =>
                state.SetToBound(cast.GetResult().getOrThrow(), true)
                return ConstExceptionKind.NA
        }
    }

    private func HandleTypecastOfIntDispatcherSigned(state: ConstDomain, cast: Expression, value: Int64,
        targetTy: Type, overflowStrategy: OverflowStrategy): ConstExceptionKind {
        match (targetTy.GetTypeKind()) {
            case TypeKind.TYPE_INT8 =>
                return CastOrRaiseExceptionForInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_INT16 =>
                return CastOrRaiseExceptionForInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_INT32 =>
                return CastOrRaiseExceptionForInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_INT64 =>
                return CastOrRaiseExceptionForInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_INT_NATIVE =>
                return CastOrRaiseExceptionForInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT8 =>
                return CastOrRaiseExceptionForInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT16 =>
                return CastOrRaiseExceptionForInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT32 =>
                return CastOrRaiseExceptionForInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT64 =>
                return CastOrRaiseExceptionForInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT_NATIVE =>
                return CastOrRaiseExceptionForInt(state, cast, value, targetTy, overflowStrategy)
            case _ =>
                state.SetToBound(cast.GetResult().getOrThrow(), true)
                return ConstExceptionKind.NA
        }
    }

    private func HandleTypecastOfIntDispatcherUnsigned(state: ConstDomain, cast: Expression, value: UInt64,
        targetTy: Type, overflowStrategy: OverflowStrategy): ConstExceptionKind {
        match (targetTy.GetTypeKind()) {
            case TypeKind.TYPE_INT8 =>
                return CastOrRaiseExceptionForUInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_INT16 =>
                return CastOrRaiseExceptionForUInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_INT32 =>
                return CastOrRaiseExceptionForUInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_INT64 =>
                return CastOrRaiseExceptionForUInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_INT_NATIVE =>
                return CastOrRaiseExceptionForUInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT8 =>
                return CastOrRaiseExceptionForUInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT16 =>
                return CastOrRaiseExceptionForUInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT32 =>
                return CastOrRaiseExceptionForUInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT64 =>
                return CastOrRaiseExceptionForUInt(state, cast, value, targetTy, overflowStrategy)
            case TypeKind.TYPE_UINT_NATIVE =>
                return CastOrRaiseExceptionForUInt(state, cast, value, targetTy, overflowStrategy)
            case _ =>
                state.SetToBound(cast.GetResult().getOrThrow(), true)
                return ConstExceptionKind.NA
        }
    }

    private func CastOrRaiseExceptionForInt(state: ConstDomain, cast: Expression, value: Int64, targetTy: Type,
        overflowStrategy: OverflowStrategy): ConstExceptionKind {
        let result = OverflowChecker.IsTypecastOverflowForInt(value, targetTy.GetTypeKind(), overflowStrategy)
        if (result.isOverflow && overflowStrategy == OverflowStrategy.THROWING) {
            RaiseTypeCastOverflowError(cast, value.toString(), targetTy)
            state.SetToBound(cast.GetResult().getOrThrow(), true)
            return ConstExceptionKind.FAIL
        }
        UpdateTypecastResult(state, cast.GetResult().getOrThrow(), targetTy, result.value)
        return ConstExceptionKind.SUCCESS
    }

    private func CastOrRaiseExceptionForUInt(state: ConstDomain, cast: Expression, value: UInt64, targetTy: Type,
        overflowStrategy: OverflowStrategy): ConstExceptionKind {
        let result = OverflowChecker.IsTypecastOverflowForInt(value, targetTy.GetTypeKind(), overflowStrategy)
        if (result.isOverflow && overflowStrategy == OverflowStrategy.THROWING) {
            RaiseTypeCastOverflowError(cast, value.toString(), targetTy)
            state.SetToBound(cast.GetResult().getOrThrow(), true)
            return ConstExceptionKind.FAIL
        }
        UpdateTypecastResult(state, cast.GetResult().getOrThrow(), targetTy, result.value)
        return ConstExceptionKind.SUCCESS
    }

    private func HandleApply(state: ConstDomain, apply: Apply): ConstExceptionKind {
        return HandleApplyImpl(state, apply, apply.GetCallee(), apply.GetArgs())
    }

    private func HandleApply(state: ConstDomain, apply: ApplyWithException): ConstExceptionKind {
        return HandleApplyImpl(state, apply, apply.GetCallee(), apply.GetArgs())
    }

    private func HandleApplyImpl(state: ConstDomain, apply: Expression, callee: Value,
        args: ArrayList<Value>): ConstExceptionKind {
        let calleeFunc = callee.AsFunction() ?? return ConstExceptionKind.NA
        if (IsExpectedFunction(calleeFunc, arrayInitFunc)) {
            HandleArrayInit(state, apply, args)
        } else if (IsExpectedFunction(calleeFunc, arraySliceFunc)) {
            HandleArraySlice(state, apply, args)
        } else if (IsExpectedFunction(calleeFunc, arraySizeGet)) {
            HandleArraySizeGet(state, apply, args)
        } else if (IsExpectedFunction(calleeFunc, arrayBracketsFunc) ||
            IsExpectedFunction(calleeFunc, arrayGetFunc)) {
            return HandleArrayAccess(state, apply, args)
        } else if (IsExpectedFunction(calleeFunc, rangeInitFunc)) {
            return HandleRangeInit(state, apply, args)
        }
        return ConstExceptionKind.NA
    }

    private func HandleArrayInit(state: ConstDomain, apply: Expression, args: ArrayList<Value>): Unit {
        let _ = apply
        CJC_ASSERT(args.size > 0)
        let lenChild = state.GetChild(args[thisArgIndex], lenFieldIndex).getOrThrow()
        match (args.size) {
            case 1 =>
                state.Update(lenChild, ConstIntVal(0))
            case 2 =>
                let collectionParameterIndex: Int64 = 1
                let boxedValIndex: Int64 = 0
                if (let Some(boxedVal) <- state.GetChild(args[collectionParameterIndex], boxedValIndex)) {
                    if (let Some(collectionLen) <- state.GetChild(boxedVal, lenFieldIndex)) {
                        state.Propagate(collectionLen, lenChild)
                    }
                }
            case 3 =>
                let sizeParameterIndex: Int64 = 1
                state.Propagate(args[sizeParameterIndex], lenChild)
            case 4 =>
                let lenParameterIndex: Int64 = 3
                state.Propagate(args[lenParameterIndex], lenChild)
            case _ =>
                InternalError("Unsupported array init func")
        }
    }

    private func HandleArraySlice(state: ConstDomain, apply: Expression, args: ArrayList<Value>): Unit {
        CJC_ASSERT(args.size == 3)
        let lenChild = state.GetChild(apply.GetResult().getOrThrow(), lenFieldIndex).getOrThrow()
        let lenParameterIndex: Int64 = 2
        state.Propagate(args[lenParameterIndex], lenChild)
    }

    private func HandleArraySizeGet(state: ConstDomain, apply: Expression, args: ArrayList<Value>): Unit {
        let _ = apply
        CJC_ASSERT(args.size == 1)
        if (let Some(lenChild) <- state.GetChild(args[thisArgIndex], lenFieldIndex)) {
            state.Propagate(lenChild, apply.GetResult().getOrThrow())
        }
    }

    private func HandleArrayAccess(state: ConstDomain, apply: Expression, args: ArrayList<Value>): ConstExceptionKind {
        CJC_ASSERT(args.size >= 2)
        let lenNode = state.GetChild(args[0], 2) ?? return ConstExceptionKind.NA
        let lenVal = state.CheckAbstractValue(lenNode) ?? return ConstExceptionKind.NA
        CJC_ASSERT(lenVal.GetConstKind() == ConstKind.INT)
        let indexParameterIndex: Int64 = 1
        let indexVal = state.CheckAbstractValue(args[indexParameterIndex]) ?? return ConstExceptionKind.NA
        if (indexVal.GetConstKind() != ConstKind.INT) {
            return ConstExceptionKind.NA
        }
        let len = (lenVal as ConstIntVal).getOrThrow().GetVal()
        let index = (indexVal as ConstIntVal).getOrThrow().GetVal()
        return RaiseOutOfBoundError(apply, UInt64(len), index)
    }

    private func HandleRangeInit(state: ConstDomain, apply: Expression, args: ArrayList<Value>): ConstExceptionKind {
        let _ = state
        CJC_ASSERT(args.size == 7)
        let stepParameterIndex: Int64 = 3
        let stepVal = state.CheckAbstractValue(args[stepParameterIndex]) ?? return ConstExceptionKind.NA
        CJC_ASSERT(stepVal.GetConstKind() == ConstKind.INT)
        let step = (stepVal as ConstIntVal).getOrThrow().GetVal()
        if (step != 0) {
            return ConstExceptionKind.SUCCESS
        }
        if (isStable) {
            let _ = diag.DiagnoseRefactor(DiagKindRefactor.chir_step_non_zero_range, ToRange(apply.GetDebugLocation()))
            return ConstExceptionKind.FAIL
        }
        return ConstExceptionKind.NA
    }

    private func HandleIntrinsic(state: ConstDomain, intrinsic: Intrinsic): ConstExceptionKind {
        return HandleIntrinsicImpl(state, intrinsic)
    }

    private func HandleIntrinsic(state: ConstDomain, intrinsic: IntrinsicWithException): ConstExceptionKind {
        return HandleIntrinsicImpl(state, intrinsic)
    }

    private func HandleIntrinsicImpl(state: ConstDomain, intrinsic: Expression): ConstExceptionKind {
        let dest = intrinsic.GetResult().getOrThrow()
        state.SetToTopOrTopRef(dest, dest.GetType().getOrThrow().IsRef())
        let kind = if (let Some(normal) <- (intrinsic as Intrinsic)) {
            normal.GetIntrinsicKind()
        } else {
            (intrinsic as IntrinsicWithException).getOrThrow().GetIntrinsicKind()
        }
        if (kind == IntrinsicKind.VARRAY_GET) {
            return HandleVArrayGet(state, intrinsic)
        }
        if (kind == IntrinsicKind.VARRAY_SET) {
            return HandleVArraySet(state, intrinsic)
        }
        return ConstExceptionKind.NA
    }

    private func HandleVArrayGet(state: ConstDomain, intrinsic: Expression): ConstExceptionKind {
        if (intrinsic.GetNumOfOperands() != 2) {
            return ConstExceptionKind.NA
        }
        let arrNode = intrinsic.GetOperand(0)
        let indexNode = intrinsic.GetOperand(1)
        let indexVal = state.CheckAbstractValue(indexNode) ?? return ConstExceptionKind.NA
        CJC_ASSERT(indexVal.GetConstKind() == ConstKind.INT)
        let index = (indexVal as ConstIntVal).getOrThrow().GetVal()
        CJC_ASSERT(arrNode.GetType().getOrThrow().IsVArray())
        let len = (arrNode.GetType().getOrThrow() as VArrayType).getOrThrow().GetSize()
        return RaiseOutOfBoundError(intrinsic, len, index)
    }

    private func HandleVArraySet(state: ConstDomain, intrinsic: Expression): ConstExceptionKind {
        let _ = state
        CJC_ASSERT(intrinsic.GetNumOfOperands() == 3)
        let arrRefNode = intrinsic.GetOperand(0)
        let indexNode = intrinsic.GetOperand(2)
        let indexVal = state.CheckAbstractValue(indexNode) ?? return ConstExceptionKind.NA
        CJC_ASSERT(indexVal.GetConstKind() == ConstKind.INT)
        let index = (indexVal as ConstIntVal).getOrThrow().GetVal()
        CJC_ASSERT(arrRefNode.GetType().getOrThrow().IsRef())
        let arrType = (arrRefNode.GetType().getOrThrow() as RefType).getOrThrow().GetBaseType()
        CJC_ASSERT(arrType.IsVArray())
        let len = (arrType as VArrayType).getOrThrow().GetSize()
        let res = RaiseOutOfBoundError(intrinsic, len, index)
        if (res == ConstExceptionKind.SUCCESS) {
            intrinsic.SetNeedCheckArrayBound(false)
        }
        return res
    }

    private func RaiseOutOfBoundError(expr: Expression, len: UInt64, index: Int64): ConstExceptionKind {
        if (index < 0) {
            if (isStable) {
                let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_idx_out_of_bounds,
                    ToRange(expr.GetDebugLocation()))
                builder.AddMainHintArguments("array index can not be negative")
            }
            return ConstExceptionKind.FAIL
        } else if (UInt64(index) >= len) {
            if (isStable) {
                let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_idx_out_of_bounds,
                    ToRange(expr.GetDebugLocation()))
                let hint = "array index " + index.toString() + " is past the end of array (which contains " +
                    len.toString() + " elements)"
                builder.AddMainHintArguments(hint)
            }
            return ConstExceptionKind.FAIL
        }
        return ConstExceptionKind.SUCCESS
    }

    private func RaiseDivByZeroError(expr: Expression, kind: ExprKind): Unit {
        if (isStable) {
            let prompt = if (kind == ExprKind.DIV) { "divide" } else { "modulo" }
            let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_divisor_is_zero,
                ToRange(expr.GetDebugLocation()), prompt)
            builder.AddMainHintArguments(prompt)
        }
    }

    private func RaiseNegOverflowError(expr: Expression, value: ConstValue): Unit {
        if (isStable) {
            let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_arithmetic_operator_overflow,
                ToRange(expr.GetDebugLocation()), "-")
            let tyText = expr.GetResult().getOrThrow().GetType().getOrThrow().ToString()
            builder.AddMainHintArguments("-" + tyText + "(" + value.ToString() + ")")
            builder.AddNote(GenerateTypeRangePrompt(expr.GetResult().getOrThrow().GetType().getOrThrow()))
        }
    }

    private func RaiseArithmeticOverflowError(expr: Expression, kind: ExprKind,
        leftVal: ConstValue, rightVal: ConstValue): Unit {
        if (isStable) {
            let token = ArithmeticToken(kind)
            let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_arithmetic_operator_overflow,
                ToRange(expr.GetDebugLocation()), token)
            let ty = expr.GetResult().getOrThrow().GetType().getOrThrow()
            let hint = ty.ToString() + "(" + leftVal.ToString() + ") " + token + " " +
                GetRHSOperand(expr).GetType().getOrThrow().ToString() + "(" + rightVal.ToString() + ")"
            builder.AddMainHintArguments(hint)
            builder.AddNote(GenerateTypeRangePrompt(expr.GetResult().getOrThrow().GetType().getOrThrow()))
        }
    }

    private func RaiseNegativeShiftError(expr: Expression, rightVal: Int64): Unit {
        if (isStable) {
            let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_shift_length_overflow,
                ToRange(expr.GetDebugLocation()))
            builder.AddMainHintArguments(rightVal.toString(), GetLHSOperand(expr).GetType().getOrThrow().ToString())
            builder.AddNote("right operand can not be negative")
        }
    }

    private func RaiseOvershiftError(expr: Expression, rightVal: UInt64, leftValBit: UInt64): Unit {
        if (isStable) {
            let lhsTyString = GetLHSOperand(expr).GetType().getOrThrow().ToString()
            let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_shift_length_overflow,
                ToRange(expr.GetDebugLocation()))
            builder.AddMainHintArguments(rightVal.toString(), lhsTyString)
            builder.AddNote("the type of left operand is " + lhsTyString +
                ", the most bits that expected to shift are " + (leftValBit - 1u64).toString())
        }
    }

    private func RaiseTypeCastOverflowError(cast: Expression, srcVal: String, targetTy: Type): Unit {
        if (isStable) {
            let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_typecast_overflow,
                ToRange(cast.GetDebugLocation()))
            let sourceTy = if (let Some(typeCast) <- (cast as TypeCast)) {
                typeCast.GetSourceTy().getOrThrow()
            } else {
                (cast as TypeCastWithException).getOrThrow().GetSourceTy().getOrThrow()
            }
            let srcValStr = sourceTy.ToString() + "(" + srcVal + ")"
            builder.AddMainHintArguments(srcValStr, targetTy.ToString())
            builder.AddNote(GenerateTypeRangePrompt(targetTy))
        }
    }
}

private func GetLHSOperand(expr: Expression): Value {
    if (let Some(binary) <- (expr as BinaryExpression)) {
        return binary.GetOperand(0)
    }
    if (let Some(intOp) <- (expr as IntOpWithException)) {
        return intOp.GetLHSOperand()
    }
    CJC_ABORT()
    return expr.GetOperand(0)
}

private func GetRHSOperand(expr: Expression): Value {
    if (let Some(binary) <- (expr as BinaryExpression)) {
        return binary.GetOperand(1)
    }
    if (let Some(intOp) <- (expr as IntOpWithException)) {
        return intOp.GetRHSOperand().getOrThrow()
    }
    CJC_ABORT()
    return expr.GetOperand(1)
}

private func GetOverflowStrategy(expr: Expression): OverflowStrategy {
    if (let Some(unary) <- (expr as UnaryExpression)) {
        return unary.GetOverflowStrategy()
    }
    if (let Some(binary) <- (expr as BinaryExpression)) {
        return binary.GetOverflowStrategy()
    }
    if (let Some(intOp) <- (expr as IntOpWithException)) {
        return intOp.GetOverflowStrategy()
    }
    if (let Some(typeCast) <- (expr as TypeCast)) {
        return typeCast.GetOverflowStrategy()
    }
    if (let Some(typeCastEx) <- (expr as TypeCastWithException)) {
        return typeCastEx.GetOverflowStrategy()
    }
    return OverflowStrategy.NA
}

private func AsConstInt(value: Option<ConstValue>): Option<ConstIntVal> {
    if (let Some(realValue) <- value) {
        return realValue as ConstIntVal
    }
    return None
}

private func AsConstUInt(value: Option<ConstValue>): Option<ConstUIntVal> {
    if (let Some(realValue) <- value) {
        return realValue as ConstUIntVal
    }
    return None
}

private func AsConstBool(value: Option<ConstValue>): Option<ConstBoolVal> {
    if (let Some(realValue) <- value) {
        return realValue as ConstBoolVal
    }
    return None
}

private func ConstValueToUInt(value: ConstValue): UInt64 {
    if (let Some(uintVal) <- (value as ConstUIntVal)) {
        return uintVal.GetVal()
    }
    return IntBitsToUInt64((value as ConstIntVal).getOrThrow().GetVal())
}

private func EvalBitwiseRaw(left: ConstValue, right: ConstValue, isLSigned: Bool, isRSigned: Bool,
    kind: ExprKind, shift: UInt64): UInt64 {
    let leftRaw = ConstValueToUInt(left)
    let rightRaw = ConstValueToUInt(right)
    return match (kind) {
        case ExprKind.LSHIFT => leftRaw << shift
        case ExprKind.RSHIFT =>
            if (isLSigned && isRSigned) {
                IntBitsToUInt64((left as ConstIntVal).getOrThrow().GetVal() >> shift)
            } else {
                leftRaw >> shift
            }
        case ExprKind.BITAND => leftRaw & rightRaw
        case ExprKind.BITXOR => leftRaw ^ rightRaw
        case ExprKind.BITOR => leftRaw | rightRaw
        case _ =>
            CJC_ABORT()
            0u64
    }
}

private func CompareConst(kind: ExprKind, lhs: ConstValue, rhs: ConstValue): Bool {
    match (lhs.GetConstKind()) {
        case ConstKind.UINT =>
            let left = (lhs as ConstUIntVal).getOrThrow().GetVal()
            let right = (rhs as ConstUIntVal).getOrThrow().GetVal()
            return CompareUInt(kind, left, right)
        case ConstKind.INT =>
            let left = (lhs as ConstIntVal).getOrThrow().GetVal()
            let right = (rhs as ConstIntVal).getOrThrow().GetVal()
            return CompareInt(kind, left, right)
        case ConstKind.FLOAT =>
            let left = (lhs as ConstFloatVal).getOrThrow().GetVal()
            let right = (rhs as ConstFloatVal).getOrThrow().GetVal()
            return CompareFloat(kind, left, right)
        case ConstKind.BOOL =>
            let left = (lhs as ConstBoolVal).getOrThrow().GetVal()
            let right = (rhs as ConstBoolVal).getOrThrow().GetVal()
            return CompareBool(kind, left, right)
        case ConstKind.RUNE =>
            let left = UInt32((lhs as ConstRuneVal).getOrThrow().GetVal())
            let right = UInt32((rhs as ConstRuneVal).getOrThrow().GetVal())
            return CompareUInt(kind, UInt64(left), UInt64(right))
        case ConstKind.STRING =>
            let left = (lhs as ConstStrVal).getOrThrow().GetVal()
            let right = (rhs as ConstStrVal).getOrThrow().GetVal()
            return CompareString(kind, left, right)
    }
}

private func CompareInt(kind: ExprKind, left: Int64, right: Int64): Bool {
    return match (kind) {
        case ExprKind.LT => left < right
        case ExprKind.LE => left <= right
        case ExprKind.GT => left > right
        case ExprKind.GE => left >= right
        case ExprKind.EQUAL => left == right
        case ExprKind.NOTEQUAL => left != right
        case _ =>
            CJC_ABORT()
            false
    }
}

private func CompareUInt(kind: ExprKind, left: UInt64, right: UInt64): Bool {
    return match (kind) {
        case ExprKind.LT => left < right
        case ExprKind.LE => left <= right
        case ExprKind.GT => left > right
        case ExprKind.GE => left >= right
        case ExprKind.EQUAL => left == right
        case ExprKind.NOTEQUAL => left != right
        case _ =>
            CJC_ABORT()
            false
    }
}

private func CompareFloat(kind: ExprKind, left: Float64, right: Float64): Bool {
    return match (kind) {
        case ExprKind.LT => left < right
        case ExprKind.LE => left <= right
        case ExprKind.GT => left > right
        case ExprKind.GE => left >= right
        case ExprKind.EQUAL => left == right
        case ExprKind.NOTEQUAL => left != right
        case _ =>
            CJC_ABORT()
            false
    }
}

private func CompareBool(kind: ExprKind, left: Bool, right: Bool): Bool {
    let leftValue = if (left) { 1 } else { 0 }
    let rightValue = if (right) { 1 } else { 0 }
    return CompareInt(kind, leftValue, rightValue)
}

private func CompareString(kind: ExprKind, left: String, right: String): Bool {
    return match (kind) {
        case ExprKind.LT => left < right
        case ExprKind.LE => left <= right
        case ExprKind.GT => left > right
        case ExprKind.GE => left >= right
        case ExprKind.EQUAL => left == right
        case ExprKind.NOTEQUAL => left != right
        case _ =>
            CJC_ABORT()
            false
    }
}

private func UpdateTypecastResult(state: ConstDomain, dest: LocalVar, targetTy: Type, rawValue: Int64): Unit {
    let kindIndex = TypeKindIndex(targetTy.GetTypeKind())
    if (kindIndex >= TypeKindIndex(TypeKind.TYPE_INT8) && kindIndex <= TypeKindIndex(TypeKind.TYPE_INT_NATIVE)) {
        state.Update(dest, ConstIntVal(rawValue))
    } else if (kindIndex >= TypeKindIndex(TypeKind.TYPE_UINT8) &&
        kindIndex <= TypeKindIndex(TypeKind.TYPE_UINT_NATIVE)) {
        state.Update(dest, ConstUIntVal(IntBitsToUInt64(rawValue)))
    } else {
        state.SetToBound(dest, true)
    }
}

private func ArithmeticToken(kind: ExprKind): String {
    return match (kind) {
        case ExprKind.ADD => "+"
        case ExprKind.SUB => "-"
        case ExprKind.MUL => "*"
        case ExprKind.DIV => "/"
        case ExprKind.MOD => "%"
        case ExprKind.EXP => "**"
        case _ =>
            CJC_ABORT()
            ""
    }
}

private func GenerateTypeRangePrompt(typeValue: Type): String {
    let typeKind = typeValue.GetTypeKind()
    let range = match (typeKind) {
        case TypeKind.TYPE_INT8 => (Int64(Int8.Min), UInt64(Int8.Max))
        case TypeKind.TYPE_INT16 => (Int64(Int16.Min), UInt64(Int16.Max))
        case TypeKind.TYPE_INT32 => (Int64(Int32.Min), UInt64(Int32.Max))
        case TypeKind.TYPE_INT64 => (Int64.Min, UInt64(Int64.Max))
        case TypeKind.TYPE_INT_NATIVE => (Int64.Min, UInt64(Int64.Max))
        case TypeKind.TYPE_UINT8 => (0, UInt64(UInt8.Max))
        case TypeKind.TYPE_UINT16 => (0, UInt64(UInt16.Max))
        case TypeKind.TYPE_UINT32 => (0, UInt64(UInt32.Max))
        case TypeKind.TYPE_UINT64 => (0, UInt64.Max)
        case TypeKind.TYPE_UINT_NATIVE => (0, UInt64.Max)
        case _ => (0, 0u64)
    }
    return "range of " + typeValue.ToString() + " is " + range[0].toString() + " ~ " + range[1].toString()
}

private func IsFiniteFloat(value: Float64): Bool {
    let maxFinite = 1.7976931348623157e308
    return value == value && value <= maxFinite && value >= -maxFinite
}

private func IntBitsToUInt64(value: Int64): UInt64 {
    if (value >= 0) {
        return UInt64(value)
    }
    return 0x8000000000000000u64 + UInt64(value - Int64.Min)
}

private func BitNotInt64(value: Int64): Int64 {
    return BitsToSignedLocal(IntBitsToUInt64(value) ^ UInt64.Max, 64)
}

private func BitsToSignedLocal(value: UInt64, width: Int64): Int64 {
    let mask = BitMaskForWidthLocal(width)
    let truncated = value & mask
    let signBit = 1u64 << UInt64(width - 1)
    if ((truncated & signBit) == 0u64) {
        return Int64(truncated)
    }
    if (width == 64 && truncated == 0x8000000000000000u64) {
        return Int64.Min
    }
    let magnitude = ((truncated ^ mask) + 1u64) & mask
    return -Int64(magnitude)
}

private func BitMaskForWidthLocal(width: Int64): UInt64 {
    if (width == 64) {
        return UInt64.Max
    }
    var value = 1u64
    var idx: Int64 = 0
    while (idx < width) {
        value *= 2u64
        idx++
    }
    return value - 1u64
}
