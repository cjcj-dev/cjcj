package cangjie_compiler::chir

import cangjie_compiler::utils.OverflowStrategy
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

public open class ValueRange {
    private let kind: ValueRangeKind

    public init(kind: ValueRangeKind) {
        this.kind = kind
    }

    public func GetRangeKind(): ValueRangeKind {
        return kind
    }

    public open func Join(rhs: ValueRange): Option<ValueRange> {
        let _ = rhs
        throw IllegalArgumentException("ValueRange.Join must be implemented by concrete range classes")
    }

    public open func CloneRange(): ValueRange {
        throw IllegalArgumentException("ValueRange.CloneRange must be implemented by concrete range classes")
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

    public override func Join(rhs: ValueRange): Option<ValueRange> {
        if (rhs.GetRangeKind() != ValueRangeKind.BOOL) {
            throw IllegalArgumentException("BoolRange can only join another BoolRange")
        }
        if (let Some(rhsRange) <- (rhs as BoolRange)) {
            if (domain.IsSame(rhsRange.domain)) {
                return None
            }
            return BoolRange(BoolDomain.Union(domain, rhsRange.domain))
        }
        return None
    }

    public override func CloneRange(): ValueRange {
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

    public override func Join(rhs: ValueRange): Option<ValueRange> {
        if (rhs.GetRangeKind() != ValueRangeKind.SINT) {
            throw IllegalArgumentException("SIntRange can only join another SIntRange")
        }
        if (let Some(rhsRange) <- (rhs as SIntRange)) {
            if (!domain.IsSame(rhsRange.domain) ||
                (domain.NumericBound().IsFullSet() && !domain.SymbolicBounds().isEmpty())) {
                return SIntRange(SIntDomain.Unions(domain, rhsRange.domain))
            }
            return None
        }
        return None
    }

    public override func CloneRange(): ValueRange {
        return SIntRange(SIntDomain(domain.NumericBound(), domain.SymbolicBounds(), domain.IsUnsigned()))
    }

    public override func ToString(): String {
        return domain.ToString()
    }

    public func GetVal(): SIntDomain {
        return domain
    }
}

public enum RangeValueDomainKind {
    | BOTTOM | VALUE | TOP
}

private func RangeValueDomainKindIndex(kind: RangeValueDomainKind): Int64 {
    return match (kind) {
        case RangeValueDomainKind.BOTTOM => 0
        case RangeValueDomainKind.VALUE => 1
        case RangeValueDomainKind.TOP => 2
    }
}

extend RangeValueDomainKind <: Equatable<RangeValueDomainKind> {
    public operator func ==(right: RangeValueDomainKind): Bool {
        return RangeValueDomainKindIndex(this) == RangeValueDomainKindIndex(right)
    }

    public operator func !=(right: RangeValueDomainKind): Bool {
        return !(this == right)
    }
}

public class RangeValueDomain {
    private var kind: RangeValueDomainKind
    private var range: Option<ValueRange> = None

    public init(isTop: Bool) {
        kind = if (isTop) { RangeValueDomainKind.TOP } else { RangeValueDomainKind.BOTTOM }
    }

    public init(range: ValueRange) {
        kind = RangeValueDomainKind.VALUE
        this.range = range
    }

    public static func Top(): RangeValueDomain {
        return RangeValueDomain(true)
    }

    public static func Bottom(): RangeValueDomain {
        return RangeValueDomain(false)
    }

    public func IsTop(): Bool {
        return kind == RangeValueDomainKind.TOP
    }

    public func IsBottom(): Bool {
        return kind == RangeValueDomainKind.BOTTOM
    }

    public func IsValue(): Bool {
        return kind == RangeValueDomainKind.VALUE
    }

    public func GetRange(): Option<ValueRange> {
        return range
    }

    public func Clone(): RangeValueDomain {
        if (let Some(value) <- range) {
            return RangeValueDomain(value.CloneRange())
        }
        return RangeValueDomain(kind == RangeValueDomainKind.TOP)
    }

    public func Join(rhs: RangeValueDomain): Bool {
        if (IsTop() || rhs.IsBottom()) {
            return false
        }
        if (rhs.IsTop()) {
            SetToBound(true)
            return true
        }
        if (IsBottom()) {
            CopyFrom(rhs)
            return true
        }
        if (let Some(leftRange) <- range) {
            if (let Some(rightRange) <- rhs.range) {
                if (let Some(joined) <- leftRange.Join(rightRange)) {
                    range = joined
                    kind = RangeValueDomainKind.VALUE
                    return true
                }
                return false
            }
        }
        SetToBound(true)
        return true
    }

    public func SetToBound(isTop: Bool): Unit {
        kind = if (isTop) { RangeValueDomainKind.TOP } else { RangeValueDomainKind.BOTTOM }
        range = None
    }

    public func IsSame(rhs: RangeValueDomain): Bool {
        if (kind != rhs.kind) {
            return false
        }
        if (kind != RangeValueDomainKind.VALUE) {
            return true
        }
        if (let Some(leftRange) <- range) {
            if (let Some(rightRange) <- rhs.range) {
                if (leftRange.GetRangeKind() != rightRange.GetRangeKind()) {
                    return false
                }
                return leftRange.Join(rightRange).isNone() && rightRange.Join(leftRange).isNone()
            }
        }
        return false
    }

    public func ToString(): String {
        return match (kind) {
            case RangeValueDomainKind.BOTTOM => "Bottom"
            case RangeValueDomainKind.TOP => "Top"
            case RangeValueDomainKind.VALUE => if (let Some(value) <- range) {
                value.ToString()
            } else {
                "Top"
            }
        }
    }

    private func CopyFrom(rhs: RangeValueDomain): Unit {
        kind = rhs.kind
        if (let Some(rhsRange) <- rhs.range) {
            range = rhsRange.CloneRange()
        } else {
            range = None
        }
    }
}

public class RangeDomain {
    private let keys: ArrayList<Value> = ArrayList<Value>()
    private let values: ArrayList<RangeValueDomain> = ArrayList<RangeValueDomain>()

    public init() {}

    public init(other: RangeDomain) {
        var idx: Int64 = 0
        while (idx < other.keys.size) {
            keys.add(other.keys[idx])
            values.add(other.values[idx].Clone())
            idx++
        }
    }

    public func Clone(): RangeDomain {
        return RangeDomain(this)
    }

    public func ClearState(): Unit {
        keys.clear()
        values.clear()
    }

    public func Size(): Int64 {
        return keys.size
    }

    public func Update(value: Value, rangeValue: ValueRange): Unit {
        SetDomain(value, RangeValueDomain(rangeValue.CloneRange()))
    }

    public func Update(value: Value, domain: RangeValueDomain): Unit {
        SetDomain(value, domain)
    }

    public func SetToBound(value: Value, isTop: Bool): Unit {
        SetDomain(value, RangeValueDomain(isTop))
    }

    public func SetToTopOrTopRef(value: Value, isRef: Bool): Unit {
        let _ = isRef
        SetToBound(value, true)
    }

    public func CheckAbstractValue(value: Value): Option<ValueRange> {
        if (let Some(idx) <- FindIndex(value)) {
            return values[idx].GetRange()
        }
        return None
    }

    public func CheckAbstractValueWithTopBottom(value: Value): Option<RangeValueDomain> {
        if (let Some(idx) <- FindIndex(value)) {
            return values[idx].Clone()
        }
        return None
    }

    public func Join(rhs: RangeDomain): Bool {
        var changed = false
        var idx: Int64 = 0
        while (idx < rhs.keys.size) {
            let rhsKey = rhs.keys[idx]
            let rhsValue = rhs.values[idx]
            if (let Some(localIdx) <- FindIndex(rhsKey)) {
                if (values[localIdx].Join(rhsValue)) {
                    changed = true
                }
            } else {
                keys.add(rhsKey)
                values.add(rhsValue.Clone())
                changed = true
            }
            idx++
        }
        return changed
    }

    public func ToString(): String {
        let parts = ArrayList<String>()
        var idx: Int64 = 0
        while (idx < keys.size) {
            parts.add(keys[idx].GetIdentifier() + "=" + values[idx].ToString())
            idx++
        }
        return "{" + JoinStrings(parts, ", ") + "}"
    }

    private func SetDomain(value: Value, domain: RangeValueDomain): Unit {
        if (let Some(idx) <- FindIndex(value)) {
            values[idx] = domain.Clone()
            return
        }
        keys.add(value)
        values.add(domain.Clone())
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
    return RangeValueDomain.Top()
}

public func HandleNonNullLiteralValue(constant: Constant): RangeValueDomain {
    return HandleNonNullLiteralValue(constant.literal, constant.GetResultType())
}

public func CanAnalyseRange(typeValue: Type): Bool {
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
    return RangeValueDomain.Top()
}

public func IsBasicBinaryExpr(expr: Expression): Bool {
    let kindIndex = ExprKindIndex(expr.GetExprKind())
    return kindIndex >= ExprKindIndex(ExprKind.ADD) && kindIndex <= ExprKindIndex(ExprKind.MOD)
}

public class RangeAnalysis {
    private let inqueueBlocks: ArrayList<Block> = ArrayList<Block>()
    private let inqueueCounts: ArrayList<Int64> = ArrayList<Int64>()

    public init() {}

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
            if (let Some(absVal) <- domain.GetRange()) {
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
            if (let Some(absVal) <- domain.GetRange()) {
                if (absVal.GetRangeKind() == ValueRangeKind.SINT) {
                    if (let Some(intRange) <- (absVal as SIntRange)) {
                        return intRange.GetVal()
                    }
                }
            }
        }
        return defaultRange
    }

    public func CheckInQueueTimes(block: Block, curState: RangeDomain): Bool {
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

    public func HandleNormalExpressionEffect(state: RangeDomain, expression: Expression): Unit {
        match (expression.GetExprMajorKind()) {
            case ExprMajorKind.MEMORY_EXPR => return
            case ExprMajorKind.UNARY_EXPR => HandleUnaryExpr(state, expression)
            case ExprMajorKind.BINARY_EXPR => if (let Some(binaryExpr) <- (expression as BinaryExpression)) {
                HandleBinaryExpr(state, binaryExpr)
            } else {
                SetResultToTop(state, expression)
            }
            case ExprMajorKind.OTHERS => HandleOthersExpr(state, expression)
            case ExprMajorKind.TERMINATOR => return
            case ExprMajorKind.STRUCTURED_CTRL_FLOW_EXPR => return
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
                return ComputeRelIntBinop(CHIRRelIntBinopArgs(lhsRange, rhsRange, lhs, rhs, binaryExpr.GetExprKind(),
                    IsUnsignedArithmetic(binaryExpr)))
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

    public func HandleTerminatorEffect(state: RangeDomain, terminator: Terminator): Option<Block> {
        let kind = terminator.GetExprKind()
        if (kind == ExprKind.GOTO || kind == ExprKind.EXIT) {
            return None
        }
        if (kind == ExprKind.BRANCH) {
            return HandleBranchTerminator(state, terminator)
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
                    return CanAnalyseRange(destTy) && CanAnalyseRange(lhsTy) && CanAnalyseRange(rhsTy)
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
            return lhsTy.IsUnsignedInteger() || lhsTy.IsEnum()
        }
        return false
    }
}
