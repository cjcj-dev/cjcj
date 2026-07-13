package cjcj::chir

import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::utils.{CJC_ABORT, OverflowStrategy}
import std.collection.*

private let RANGE_ANALYSIS_MAX_INQUEUE_TIMES: Int64 = 4

public enum ValueRangeKind {
    | BOOL | SINT
}

private func ValueRangeKindIndex(kind: ValueRangeKind): Int64 {
    return match (kind) {
        case ValueRangeKind.BOOL => 0
        case ValueRangeKind.SINT => 1
    }
}

extend ValueRangeKind <: Equatable<ValueRangeKind> {
    public operator func ==(right: ValueRangeKind): Bool {
        return ValueRangeKindIndex(this) == ValueRangeKindIndex(right)
    }

    public operator func !=(right: ValueRangeKind): Bool {
        return !(this == right)
    }
}

public open class ValueRange <: HasEqual<ValueRange> {
    private let kind: ValueRangeKind

    public init(kind: ValueRangeKind) {
        this.kind = kind
    }

    public func GetRangeKind(): ValueRangeKind {
        return kind
    }

    public open func Join(rhs: ValueRange): Option<Option<ValueRange>> {
        let _ = rhs
        throw IllegalArgumentException("ValueRange.Join must be implemented by concrete range classes")
    }

    public open func Clone(): ValueRange {
        throw IllegalArgumentException("ValueRange.Clone must be implemented by concrete range classes")
    }

    public open func ToString(): String {
        return ""
    }

}

public class BoolRange <: ValueRange {
    private let domain: BoolDomain

    public init(domain: BoolDomain) {
        super(ValueRangeKind.BOOL)
        this.domain = domain
    }

    public override func Join(rhs: ValueRange): Option<Option<ValueRange>> {
        if (rhs.GetRangeKind() != ValueRangeKind.BOOL) {
            throw IllegalArgumentException("BoolRange can only join another BoolRange")
        }
        if (let Some(rhsRange) <- (rhs as BoolRange)) {
            if (domain.IsSame(rhsRange.domain)) {
                return None
            }
            let joined: ValueRange = BoolRange(BoolDomain.Union(domain, rhsRange.domain))
            return Some(Some(joined))
        }
        return None
    }

    public override func Clone(): ValueRange {
        return BoolRange(domain)
    }

    public override func ToString(): String {
        return domain.ToString()
    }

    public func GetVal(): BoolDomain {
        return domain
    }
}

public class SIntRange <: ValueRange {
    private let domain: SIntDomain

    public init(domain: SIntDomain) {
        super(ValueRangeKind.SINT)
        this.domain = domain
    }

    public override func Join(rhs: ValueRange): Option<Option<ValueRange>> {
        if (rhs.GetRangeKind() != ValueRangeKind.SINT) {
            throw IllegalArgumentException("SIntRange can only join another SIntRange")
        }
        if (let Some(rhsRange) <- (rhs as SIntRange)) {
            if (!domain.IsSame(rhsRange.domain) ||
                (domain.NumericBound().IsFullSet() && !domain.SymbolicBounds().isEmpty())) {
                let joined: ValueRange = SIntRange(SIntDomain.Unions(domain, rhsRange.domain))
                return Some(Some(joined))
            }
            return None
        }
        return None
    }

    public override func Clone(): ValueRange {
        return SIntRange(SIntDomain(domain.NumericBound(), domain.SymbolicBounds(), domain.IsUnsigned()))
    }

    public override func ToString(): String {
        return domain.ToString()
    }

    public func GetVal(): SIntDomain {
        return domain
    }
}

public type RangeValueDomain = ValueDomain<ValueRange>
public type RangeStatePool = FullStatePool<RangeValueDomain>
public type RangeDomain = State<RangeValueDomain, RangeStatePool>

// C++ ValueRangeAnalysis.h:94-101 explicit Range template instantiation;
// ValueRangeAnalysis.cpp:90-107 supplies its two free-function specializations.
public let rangeStateGlobals = ValueAnalysisGlobals<RangeValueDomain, RangeStatePool>()

public func HandleNonNullLiteralValue(literal: LiteralValue, ty: Option<Type>): RangeValueDomain {
    if (let Some(boolLiteral) <- (literal as BoolLiteral)) {
        return RangeValueDomain(BoolRange(BoolDomain.FromBool(boolLiteral.value)))
    }
    if (let Some(intLiteral) <- (literal as IntLiteral)) {
        if (let Some(intType) <- ty) {
            if (intType.IsInteger()) {
                return RangeValueDomain(SIntRange(SIntDomain.FromIntLiteral(intLiteral, intType)))
            }
        }
    }
    return RangeValueDomain(true)
}

public func HandleNonNullLiteralValue(constant: Constant): RangeValueDomain {
    return HandleNonNullLiteralValue(constant.literal, constant.GetResultType())
}

public func CanAnalyse(typeValue: Type): Bool {
    return typeValue.IsInteger() || typeValue.IsBoolean()
}

public func IsTrackedGVForRangeAnalysis(globalVar: GlobalVar): Bool {
    if (let Some(globalTy) <- globalVar.GetType()) {
        let baseTy = globalTy.StripAllRefs()
        return baseTy.IsInteger() || baseTy.IsBoolean() || baseTy.IsEnum()
    }
    return false
}

public func GetDefaultIntRange(typeValue: Type): SIntDomain {
    let width = SIntDomain.ToWidth(typeValue)
    return SIntDomain.Top(width, typeValue.IsUnsignedInteger())
}

public func GetDefaultRangeForType(typeValue: Type): RangeValueDomain {
    if (typeValue.IsBoolean()) {
        return RangeValueDomain(BoolRange(BoolDomain.Top()))
    }
    if (typeValue.IsInteger()) {
        return RangeValueDomain(SIntRange(GetDefaultIntRange(typeValue)))
    }
    return RangeValueDomain(true)
}

public func IsBasicBinaryExpr(expr: Expression): Bool {
    let kindIndex = ExprKindIndex(expr.GetExprKind())
    return kindIndex >= ExprKindIndex(ExprKind.ADD) && kindIndex <= ExprKindIndex(ExprKind.MOD)
}

public class RangeAnalysis <: ValueAnalysis<RangeValueDomain, RangeStatePool> {
    private let inqueueBlocks: ArrayList<Block> = ArrayList<Block>()
    private let inqueueCounts: ArrayList<Int64> = ArrayList<Int64>()
    private let diag: BasicDiagnosticEngine

    public init(functionValue: Function, builder: CHIRBuilder, diag: BasicDiagnosticEngine,
        isDebug!: Bool = false) {
        super(functionValue, builder, rangeStateGlobals,
            { literal: LiteralValue => HandleNonNullLiteralValue(literal, Some(literal.GetType().getOrThrow())) },
            isDebug: isDebug)
        this.diag = diag
    }

    public override func GetAnalysisName(): String {
        return "range-analysis"
    }

    public override func GetBlockLimit(): Option<UInt32> {
        return 80u32
    }

    public static func GetBoolDomainFromState(state: RangeDomain, value: Value): BoolDomain {
        if (let Some(valueTy) <- value.GetType()) {
            if (!valueTy.IsBoolean()) {
                return BoolDomain.Top()
            }
        } else {
            return BoolDomain.Top()
        }
        if (let Some(domain) <- state.CheckAbstractValueWithTopBottom(value)) {
            if (domain.IsTop()) {
                return BoolDomain.Top()
            }
            if (let Some(absVal) <- domain.CheckAbsVal()) {
                if (absVal.GetRangeKind() == ValueRangeKind.BOOL) {
                    if (let Some(boolRange) <- (absVal as BoolRange)) {
                        return boolRange.GetVal()
                    }
                }
            }
        }
        return BoolDomain.Top()
    }

    public static func GetSIntDomainFromState(state: RangeDomain, value: Value): SIntDomain {
        var defaultRange = SIntDomain.Top(IntWidth.I64, false)
        if (let Some(valueTy) <- value.GetType()) {
            if (!valueTy.IsInteger()) {
                return defaultRange
            }
            defaultRange = GetDefaultIntRange(valueTy)
        }
        if (let Some(domain) <- state.CheckAbstractValueWithTopBottom(value)) {
            if (domain.IsTop()) {
                return defaultRange
            }
            if (let Some(absVal) <- domain.CheckAbsVal()) {
                if (absVal.GetRangeKind() == ValueRangeKind.SINT) {
                    if (let Some(intRange) <- (absVal as SIntRange)) {
                        return intRange.GetVal()
                    }
                }
            }
        }
        return defaultRange
    }

    public override func CheckInQueueTimes(block: Block, curState: RangeDomain): Bool {
        if (let Some(idx) <- FindInqueueIndex(block)) {
            inqueueCounts[idx] = inqueueCounts[idx] + 1
            if (inqueueCounts[idx] >= RANGE_ANALYSIS_MAX_INQUEUE_TIMES) {
                curState.ClearState()
                return true
            }
            return false
        }
        inqueueBlocks.add(block)
        inqueueCounts.add(1)
        return false
    }

    public override func HandleNormalExpressionEffect(state: RangeDomain, expression: Expression): Unit {
        match (expression.GetExprMajorKind()) {
            case ExprMajorKind.MEMORY_EXPR => return
            case ExprMajorKind.UNARY_EXPR => HandleUnaryExpr(state, expression)
            case ExprMajorKind.BINARY_EXPR => if (let Some(binaryExpr) <- (expression as BinaryExpression)) {
                HandleBinaryExpr(state, binaryExpr)
            } else {
                SetResultToTop(state, expression)
            }
            case ExprMajorKind.OTHERS => HandleOthersExpr(state, expression)
            case ExprMajorKind.TERMINATOR =>
                CJC_ABORT()
                return
            case ExprMajorKind.STRUCTURED_CTRL_FLOW_EXPR =>
                CJC_ABORT()
                return
        }
    }

    public func HandleUnaryExpr(state: RangeDomain, unaryExpr: Expression): Unit {
        SetResultToTop(state, unaryExpr)
    }

    public func HandleBinaryExpr(state: RangeDomain, binaryExpr: BinaryExpression,
        overflowStrategy!: OverflowStrategy = OverflowStrategy.THROWING): Unit {
        if (let Some(dest) <- binaryExpr.GetResult()) {
            if (binaryExpr.GetNumOfOperands() < 2) {
                state.SetToBound(dest, true)
                return
            }
            let lhs = binaryExpr.GetOperand(0)
            let rhs = binaryExpr.GetOperand(1)
            if (!CanAnalyseBinaryRange(dest, lhs, rhs)) {
                state.SetToBound(dest, true)
                return
            }
            if (let Some(destTy) <- dest.GetType()) {
                if (destTy.IsInteger()) {
                    if (!IsBasicBinaryExpr(binaryExpr)) {
                        state.SetToBound(dest, true)
                        return
                    }
                    let lhsRange = RangeAnalysis.GetSIntDomainFromState(state, lhs)
                    let rhsRange = RangeAnalysis.GetSIntDomainFromState(state, rhs)
                    let result = ComputeArithmeticBinop(CHIRArithmeticBinopArgs(lhsRange, rhsRange, lhs, rhs,
                        binaryExpr.GetExprKind(), overflowStrategy, IsUnsignedArithmetic(binaryExpr)))
                    if (result.IsNonTrivial()) {
                        state.Update(dest, SIntRange(result))
                        return
                    }
                } else if (destTy.IsBoolean()) {
                    let boolResult = GenerateBoolRangeFromBinaryOp(state, binaryExpr)
                    if (boolResult.IsNonTrivial()) {
                        state.Update(dest, BoolRange(boolResult))
                        return
                    }
                }
            }
            state.SetToBound(dest, true)
        }
    }

    public func GenerateBoolRangeFromBinaryOp(state: RangeDomain, binaryExpr: BinaryExpression): BoolDomain {
        if (binaryExpr.GetNumOfOperands() < 2) {
            return BoolDomain.Top()
        }
        let lhs = binaryExpr.GetOperand(0)
        let rhs = binaryExpr.GetOperand(1)
        if (let Some(lhsTy) <- lhs.GetType()) {
            if (lhsTy.IsInteger()) {
                let lhsRange = RangeAnalysis.GetSIntDomainFromState(state, lhs)
                let rhsRange = RangeAnalysis.GetSIntDomainFromState(state, rhs)
                return ComputeRelIntBinop(CHIRRelIntBinopArgs(lhsRange, rhsRange, Some(lhs), Some(rhs),
                    binaryExpr.GetExprKind(), IsUnsignedArithmetic(binaryExpr)))
            }
        }
        let lhsBool = RangeAnalysis.GetBoolDomainFromState(state, lhs)
        let rhsBool = RangeAnalysis.GetBoolDomainFromState(state, rhs)
        return ComputeEqualityBoolBinop(lhsBool, rhsBool, binaryExpr.GetExprKind())
    }

    public func ComputeTypeCast(state: RangeDomain, oldSymbol: Value, valueRange: SIntDomain, dstSize: IntWidth,
        dstUnsigned: Bool, overflowStrategy: OverflowStrategy): SIntDomain {
        let numericRange = ComputeTypeCastNumericBound(valueRange, dstSize, dstUnsigned, overflowStrategy)
        if (IntWidthBits(dstSize) < IntWidthBits(valueRange.Width()) || valueRange.IsUnsigned() || !dstUnsigned ||
            overflowStrategy == OverflowStrategy.SATURATING ||
            numericRange.SMinValue().Slt(SInt(dstSize, 0))) {
            return SIntDomain(numericRange, valueRange.IsUnsigned())
        }
        let bounds = ArrayList<SymbolicBound>()
        for (bound in valueRange.SymbolicBounds()) {
            if (let Some(absVal) <- state.CheckAbstractValue(bound.symbol)) {
                if (absVal.GetRangeKind() == ValueRangeKind.SINT) {
                    if (let Some(storedRange) <- (absVal as SIntRange)) {
                        let storedDomain = storedRange.GetVal()
                        if (storedDomain.NumericBound().SMinValue().Sge(SInt(storedDomain.Width(), 0))) {
                            bounds.add(SymbolicBound(bound.symbol, NumericConversion(bound.bound, dstSize, false,
                                false, OverflowStrategy.THROWING)))
                        }
                    }
                }
            }
        }
        bounds.add(SymbolicBound(oldSymbol, ConstantRange(SInt(dstSize, 0))))
        return SIntDomain(numericRange, bounds, valueRange.IsUnsigned())
    }

    public func HandleTypeCastExpression(state: RangeDomain, castExpr: Expression,
        overflowStrategy!: OverflowStrategy = OverflowStrategy.THROWING): Unit {
        if (let Some(dest) <- castExpr.GetResult()) {
            if (castExpr.GetNumOfOperands() == 0) {
                state.SetToBound(dest, true)
                return
            }
            let sourceValue = castExpr.GetOperand(0)
            if (let Some(sourceTy) <- sourceValue.GetType()) {
                if (let Some(destTy) <- dest.GetType()) {
                    if (!sourceTy.IsInteger() || !destTy.IsInteger()) {
                        state.SetToTopOrTopRef(dest, destTy.IsRef())
                        return
                    }
                    let sourceDomain = RangeAnalysis.GetSIntDomainFromState(state, sourceValue)
                    let resultDomain = ComputeTypeCast(state, sourceValue, sourceDomain, SIntDomain.ToWidth(destTy),
                        destTy.IsUnsignedInteger(), overflowStrategy)
                    state.Update(dest, SIntRange(resultDomain))
                    return
                }
            }
            state.SetToBound(dest, true)
        }
    }

    public func HandleOthersExpr(state: RangeDomain, expression: Expression): Unit {
        match (expression.GetExprKind()) {
            case ExprKind.CONSTANT => if (let Some(constantExpr) <- (expression as Constant)) {
                if (let Some(dest) <- constantExpr.GetResult()) {
                    state.Update(dest, HandleNonNullLiteralValue(constantExpr))
                }
            }
            case ExprKind.TYPECAST => HandleTypeCastExpression(state, expression)
            case ExprKind.APPLY => return
            case ExprKind.FIELD => return
            case _ => SetResultToTop(state, expression)
        }
    }

    public override func HandleTerminatorEffect(state: RangeDomain, terminator: Terminator): Option<Block> {
        let kind = terminator.GetExprKind()
        if (kind == ExprKind.GOTO || kind == ExprKind.EXIT) {
            return None
        }
        if (kind == ExprKind.BRANCH) {
            return HandleBranchTerminator(state, terminator)
        }
        if (kind == ExprKind.MULTIBRANCH) {
            return HandleMultiBranchTerminator(state, (terminator as MultiBranch).getOrThrow())
        }
        if (kind == ExprKind.TYPECAST_WITH_EXCEPTION) {
            HandleTypeCastExpression(state, terminator)
            return None
        }
        SetResultToTop(state, terminator)
        return None
    }

    public func HandleBranchTerminator(state: RangeDomain, branch: Terminator): Option<Block> {
        if (branch.GetNumOfOperands() == 0) {
            return None
        }
        let cond = branch.GetOperand(0)
        let condVal = RangeAnalysis.GetBoolDomainFromState(state, cond)
        if (!condVal.IsSingleValue()) {
            return None
        }
        let successors = branch.GetSuccessors()
        if (successors.size < 2) {
            return None
        }
        return if (condVal.IsTrue()) { successors[0] } else { successors[1] }
    }

    public func HandleMultiBranchTerminator(state: RangeDomain, multi: MultiBranch): Option<Block> {
        let cond = multi.GetCondition()
        let condVal = RangeAnalysis.GetSIntDomainFromState(state, cond)
        if (!condVal.IsSingleValue()) {
            return None
        }
        let value = UInt64(condVal.NumericBound().Lower().UVal())
        let cases = multi.GetCaseVals()
        var idx: Int64 = 0
        while (idx < cases.size) {
            if (value == cases[idx]) {
                return multi.GetSuccessor(idx + 1)
            }
            idx++
        }
        return multi.GetDefaultBlock()
    }

    private func FindInqueueIndex(block: Block): Option<Int64> {
        var idx: Int64 = 0
        while (idx < inqueueBlocks.size) {
            if (inqueueBlocks[idx].nodeId == block.nodeId) {
                return idx
            }
            idx++
        }
        return None
    }

    private func SetResultToTop(state: RangeDomain, expression: Expression): Unit {
        if (let Some(dest) <- expression.GetResult()) {
            if (let Some(destTy) <- dest.GetType()) {
                state.SetToTopOrTopRef(dest, destTy.IsRef())
            } else {
                state.SetToBound(dest, true)
            }
        }
    }

    private func CanAnalyseBinaryRange(dest: Value, lhs: Value, rhs: Value): Bool {
        if (let Some(destTy) <- dest.GetType()) {
            if (let Some(lhsTy) <- lhs.GetType()) {
                if (let Some(rhsTy) <- rhs.GetType()) {
                    return CanAnalyse(destTy) && CanAnalyse(lhsTy) && CanAnalyse(rhsTy)
                }
            }
        }
        return false
    }

    private func IsUnsignedArithmetic(binaryExpr: BinaryExpression): Bool {
        if (binaryExpr.GetNumOfOperands() == 0) {
            return false
        }
        if (let Some(lhsTy) <- binaryExpr.GetOperand(0).GetType()) {
            return lhsTy.IsUnsignedInteger() || IsStructEnum(lhsTy)
        }
        return false
    }
}
