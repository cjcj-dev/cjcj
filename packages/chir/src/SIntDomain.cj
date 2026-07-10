package cjcj::chir

import cjcj::utils.OverflowStrategy
import std.collection.*
import std.sort.*

public class SymbolicBound {
    public let symbol: Value
    public let bound: ConstantRange

    public init(symbol: Value, bound: ConstantRange) {
        this.symbol = symbol
        this.bound = bound
    }

    public func IsSame(other: SymbolicBound): Bool {
        return symbol.nodeId == other.symbol.nodeId && bound.IsSame(other.bound)
    }

    public func ToString(asUnsigned!: Bool = true, radix!: Radix = Radix.R10): String {
        return symbol.GetSrcCodeIdentifier() + ":" + bound.ToString(asUnsigned: asUnsigned, radix: radix)
    }
}

public class SIntDomain {
    private let numeric: ConstantRange
    private let symbolics: ArrayList<SymbolicBound> = ArrayList<SymbolicBound>()
    private let unsignedFlag: Bool

    public init(numeric: ConstantRange, isUnsigned: Bool) {
        this.numeric = numeric
        unsignedFlag = isUnsigned
    }

    public init(numeric: ConstantRange, symbolicBounds: ArrayList<SymbolicBound>, isUnsigned: Bool) {
        this.numeric = numeric
        unsignedFlag = isUnsigned
        for (bound in symbolicBounds) {
            if (bound.bound.IsNonTrivial()) {
                AddOrIntersectSymbolic(bound.symbol, bound.bound)
            }
        }
    }

    public init(numeric: ConstantRange, symbol: Value, symbolicBound: ConstantRange) {
        this.numeric = numeric
        unsignedFlag = IsUnsignedSymbol(symbol)
        if (symbolicBound.IsNonTrivial()) {
            symbolics.add(SymbolicBound(symbol, symbolicBound))
        }
    }

    public static func Top(width: IntWidth, isUnsigned: Bool): SIntDomain {
        return SIntDomain(ConstantRange.Full(width), isUnsigned)
    }

    public static func Bottom(width: IntWidth, isUnsigned: Bool): SIntDomain {
        return SIntDomain(ConstantRange.Empty(width), isUnsigned)
    }

    public static func FromIntLiteral(literal: IntLiteral, ty: Type): SIntDomain {
        let isUnsigned = ty.IsUnsignedInteger()
        let width = ToWidth(ty)
        return SIntDomain(ConstantRange(SInt(width, literal.value)), isUnsigned)
    }

    public static func FromNumeric(rel: RelationalOperation, value: SInt, isUnsigned: Bool): SIntDomain {
        return SIntDomain(ConstantRange.From(rel, value, !isUnsigned), isUnsigned)
    }

    public static func FromSymbolic(rel: RelationalOperation, symbol: Value, width: IntWidth,
        isUnsigned: Bool): SIntDomain {
        if (rel == RelationalOperation.NE) {
            return SIntDomain.Top(width, isUnsigned)
        }
        let symbolicRange = ConstantRange.From(rel, SInt.Zero(width), !isUnsigned)
        return SIntDomain(ConstantRange.Full(width), symbol, symbolicRange)
    }

    public static func ToWidth(ty: Type): IntWidth {
        return match (ty.GetTypeKind()) {
            case TypeKind.TYPE_INT8 => IntWidth.I8
            case TypeKind.TYPE_UINT8 => IntWidth.I8
            case TypeKind.TYPE_INT16 => IntWidth.I16
            case TypeKind.TYPE_UINT16 => IntWidth.I16
            case TypeKind.TYPE_INT32 => IntWidth.I32
            case TypeKind.TYPE_UINT32 => IntWidth.I32
            case _ => IntWidth.I64
        }
    }

    public func IsTop(): Bool {
        return numeric.IsFullSet() && symbolics.isEmpty()
    }

    public func IsNonTrivial(): Bool {
        return !IsTop()
    }

    public func IsBottom(): Bool {
        return numeric.IsEmptySet()
    }

    public func NumericBound(): ConstantRange {
        return numeric
    }

    public func Width(): IntWidth {
        return numeric.Width()
    }

    public func IsUnsigned(): Bool {
        return unsignedFlag
    }

    public func SymbolicBounds(): ArrayList<SymbolicBound> {
        let out = ArrayList<SymbolicBound>()
        for (bound in symbolics) {
            out.add(bound)
        }
        return out
    }

    public func FindSymbolicBound(symbol: Value): Option<ConstantRange> {
        for (bound in symbolics) {
            if (bound.symbol.nodeId == symbol.nodeId) {
                return bound.bound
            }
        }
        return None
    }

    public func IsSingleValue(): Bool {
        return numeric.IsSingleElement()
    }

    public func IsSame(domain: SIntDomain): Bool {
        return numeric.IsSame(domain.numeric)
    }

    public func Intersect(rhs: SIntDomain): SIntDomain {
        return SIntDomain.Intersects(this, rhs)
    }

    public func Union(rhs: SIntDomain): SIntDomain {
        return SIntDomain.Unions(this, rhs)
    }

    public static func Intersects(lhs: SIntDomain, rhs: SIntDomain): SIntDomain {
        let preferred = PreferFromBool(lhs.unsignedFlag)
        let numeric = lhs.numeric.IntersectWith(rhs.numeric, preferredType: preferred)
        let outBounds = ArrayList<SymbolicBound>()
        MergeIntersectedBounds(outBounds, lhs, rhs)
        if (HasEmptySymbolicBound(outBounds)) {
            return SIntDomain.Bottom(lhs.Width(), lhs.unsignedFlag)
        }
        let result = SIntDomain(numeric, outBounds, lhs.unsignedFlag)
        if (result.IsBottom()) {
            return SIntDomain.Bottom(lhs.Width(), lhs.unsignedFlag)
        }
        return result
    }

    public static func Unions(lhs: SIntDomain, rhs: SIntDomain): SIntDomain {
        let preferred = PreferFromBool(lhs.unsignedFlag)
        let numeric = lhs.numeric.UnionWith(rhs.numeric, preferredType: preferred)
        let outBounds = ArrayList<SymbolicBound>()
        for (bound in lhs.symbolics) {
            if (let Some(rhsBound) <- rhs.FindSymbolicBound(bound.symbol)) {
                let unioned = bound.bound.UnionWith(rhsBound, preferredType: PreferredRangeType.SIGNED)
                if (unioned.IsEmptySet()) {
                    return SIntDomain.Bottom(lhs.Width(), lhs.unsignedFlag)
                }
                if (unioned.IsNonTrivial()) {
                    outBounds.add(SymbolicBound(bound.symbol, unioned))
                }
            }
        }
        return SIntDomain(numeric, outBounds, lhs.unsignedFlag)
    }

    public func Add(rhs: SIntDomain): SIntDomain {
        return SIntDomain(numeric.Add(rhs.numeric), unsignedFlag)
    }

    public func Sub(rhs: SIntDomain): SIntDomain {
        return SIntDomain(numeric.Sub(rhs.numeric), unsignedFlag)
    }

    public func Mul(rhs: SIntDomain): SIntDomain {
        let result = if (unsignedFlag) { numeric.UMul(rhs.numeric) } else { numeric.SMul(rhs.numeric) }
        return SIntDomain(result, unsignedFlag)
    }

    public func Div(rhs: SIntDomain): SIntDomain {
        if (rhs.numeric.Contains(SInt.Zero(rhs.Width()))) {
            return SIntDomain.Top(Width(), unsignedFlag)
        }
        let result = if (unsignedFlag) { numeric.UDiv(rhs.numeric) } else { numeric.SDiv(rhs.numeric) }
        return SIntDomain(result, unsignedFlag)
    }

    public func Mod(rhs: SIntDomain): SIntDomain {
        let result = if (unsignedFlag) { numeric.URem(rhs.numeric) } else { numeric.SRem(rhs.numeric) }
        return SIntDomain(result, unsignedFlag)
    }

    public func AddSat(rhs: SIntDomain): SIntDomain {
        let result = if (unsignedFlag) { numeric.UAddSat(rhs.numeric) } else { numeric.SAddSat(rhs.numeric) }
        return SIntDomain(result, unsignedFlag)
    }

    public func SubSat(rhs: SIntDomain): SIntDomain {
        let result = if (unsignedFlag) { numeric.USubSat(rhs.numeric) } else { numeric.SSubSat(rhs.numeric) }
        return SIntDomain(result, unsignedFlag)
    }

    public func MulSat(rhs: SIntDomain): SIntDomain {
        let result = if (unsignedFlag) { numeric.UMulSat(rhs.numeric) } else { numeric.SMulSat(rhs.numeric) }
        return SIntDomain(result, unsignedFlag)
    }

    public func DivSat(rhs: SIntDomain): SIntDomain {
        if (rhs.numeric.Contains(SInt.Zero(rhs.Width()))) {
            return SIntDomain.Top(Width(), unsignedFlag)
        }
        let result = if (unsignedFlag) { numeric.UDiv(rhs.numeric) } else { numeric.SDivSat(rhs.numeric) }
        return SIntDomain(result, unsignedFlag)
    }

    public func ToString(asUnsigned!: Bool = unsignedFlag, radix!: Radix = Radix.R10): String {
        if (IsBottom()) {
            return numeric.ToString(asUnsigned: asUnsigned, radix: radix)
        }
        if (symbolics.isEmpty()) {
            return numeric.ToString(asUnsigned: asUnsigned, radix: radix)
        }
        var out = "|"
        if (numeric.IsNonTrivial()) {
            out += numeric.ToString(asUnsigned: asUnsigned, radix: radix)
        }
        let sortedBounds = SymbolicBounds()
        sort(sortedBounds, by: { left: SymbolicBound, right: SymbolicBound =>
            let leftName = left.symbol.GetSrcCodeIdentifier()
            let rightName = right.symbol.GetSrcCodeIdentifier()
            if (leftName < rightName) {
                Ordering.LT
            } else if (leftName > rightName) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        for (bound in sortedBounds) {
            out += ";" + bound.ToString(asUnsigned: false, radix: radix)
        }
        return out + "|"
    }

    private func AddOrIntersectSymbolic(symbol: Value, bound: ConstantRange): Unit {
        var idx: Int64 = 0
        while (idx < symbolics.size) {
            if (symbolics[idx].symbol.nodeId == symbol.nodeId) {
                let intersected = symbolics[idx].bound.IntersectWith(bound, preferredType: PreferredRangeType.SIGNED)
                symbolics[idx] = SymbolicBound(symbol, intersected)
                return
            }
            idx++
        }
        symbolics.add(SymbolicBound(symbol, bound))
    }
}

public func SymbolicNeg(rel: RelationalOperation): RelationalOperation {
    return match (rel) {
        case RelationalOperation.LT => RelationalOperation.GT
        case RelationalOperation.LE => RelationalOperation.GE
        case RelationalOperation.EQ => RelationalOperation.EQ
        case RelationalOperation.GE => RelationalOperation.LE
        case RelationalOperation.GT => RelationalOperation.LT
        case RelationalOperation.NE => RelationalOperation.NE
    }
}

public func RelationalOperationFromExprKind(kind: ExprKind): Option<RelationalOperation> {
    return match (kind) {
        case ExprKind.EQUAL => Some(RelationalOperation.EQ)
        case ExprKind.LE => Some(RelationalOperation.LE)
        case ExprKind.LT => Some(RelationalOperation.LT)
        case ExprKind.GT => Some(RelationalOperation.GT)
        case ExprKind.GE => Some(RelationalOperation.GE)
        case ExprKind.NOTEQUAL => Some(RelationalOperation.NE)
        case _ => None
    }
}

public class CHIRArithmeticBinopArgs {
    public let left: SIntDomain
    public let right: SIntDomain
    public let leftSymbol: Option<Value>
    public let rightSymbol: Option<Value>
    public let op: ExprKind
    public let overflowStrategy: OverflowStrategy
    public let isUnsigned: Bool

    public init(left: SIntDomain, right: SIntDomain, isUnsigned: Bool) {
        this.left = left
        this.right = right
        leftSymbol = None
        rightSymbol = None
        op = ExprKind.INVALID
        overflowStrategy = OverflowStrategy.THROWING
        this.isUnsigned = isUnsigned
    }

    public init(left: SIntDomain, right: SIntDomain, leftSymbol: Value, rightSymbol: Value, op: ExprKind,
        overflowStrategy: OverflowStrategy, isUnsigned: Bool) {
        this.left = left
        this.right = right
        this.leftSymbol = leftSymbol
        this.rightSymbol = rightSymbol
        this.op = op
        this.overflowStrategy = overflowStrategy
        this.isUnsigned = isUnsigned
    }
}

public class CHIRRelIntBinopArgs {
    public let left: SIntDomain
    public let right: SIntDomain
    public let leftSymbol: Value
    public let rightSymbol: Value
    public let op: ExprKind
    public let isUnsigned: Bool

    public init(left: SIntDomain, right: SIntDomain, leftSymbol: Value, rightSymbol: Value, op: ExprKind,
        isUnsigned: Bool) {
        this.left = left
        this.right = right
        this.leftSymbol = leftSymbol
        this.rightSymbol = rightSymbol
        this.op = op
        this.isUnsigned = isUnsigned
    }
}

public func ComputeArithmeticBinop(args: CHIRArithmeticBinopArgs): SIntDomain {
    return match (args.op) {
        case ExprKind.ADD => ComputeAdd(args)
        case ExprKind.SUB => ComputeSub(args)
        case ExprKind.MUL => ComputeMul(args)
        case ExprKind.DIV => ComputeDiv(args)
        case ExprKind.MOD => ComputeMod(args)
        case _ => SIntDomain.Bottom(args.left.Width(), args.isUnsigned)
    }
}

public func ComputeRelIntBinop(args: CHIRRelIntBinopArgs): BoolDomain {
    if (args.leftSymbol.nodeId == args.rightSymbol.nodeId) {
        return BoolDomain.FromBool(TrueOnSameSymbol(args.op))
    }
    if (let Some(rel) <- RelationalOperationFromExprKind(args.op)) {
        if (rel == RelationalOperation.EQ || rel == RelationalOperation.NE) {
            return ComputeEqualityIntBinop(args.left, args.right, args.leftSymbol, args.rightSymbol,
                args.op == ExprKind.NOTEQUAL)
        }
        return ComputeTotalOrderingIntBinop(args, rel)
    }
    return BoolDomain.Top()
}

public func ComputeEqualityBoolBinop(left: BoolDomain, right: BoolDomain, op: ExprKind): BoolDomain {
    if (left.IsBottom() || right.IsBottom()) {
        return BoolDomain.Bottom()
    }
    if (left.IsSingleValue() && right.IsSingleValue()) {
        return BoolDomain.FromBool((left.GetSingleValue() == right.GetSingleValue()) != (op == ExprKind.NOTEQUAL))
    }
    return BoolDomain.Top()
}

public func NumericConversion(src: ConstantRange, dstSize: IntWidth, srcUnsigned: Bool, dstUnsigned: Bool,
    ov: OverflowStrategy): ConstantRange {
    if (srcUnsigned == dstUnsigned) {
        return NumericConversionWithSameSigness(src, dstSize, srcUnsigned, ov)
    }
    if (srcUnsigned) {
        return NumericConversionU2S(src, dstSize, ov)
    }
    return NumericConversionS2U(src, dstSize, ov)
}

public func ComputeTypeCastNumericBound(v: SIntDomain, dstSize: IntWidth, dstUnsigned: Bool,
    ov: OverflowStrategy): ConstantRange {
    if (v.IsBottom()) {
        return ConstantRange.Empty(dstSize)
    }
    return NumericConversion(v.NumericBound(), dstSize, v.IsUnsigned(), dstUnsigned, ov)
}

private func MergeIntersectedBounds(outBounds: ArrayList<SymbolicBound>, lhs: SIntDomain, rhs: SIntDomain): Unit {
    for (bound in lhs.SymbolicBounds()) {
        if (let Some(rhsBound) <- rhs.FindSymbolicBound(bound.symbol)) {
            let intersected = bound.bound.IntersectWith(rhsBound, preferredType: PreferredRangeType.SIGNED)
            if (intersected.IsNonTrivial()) {
                outBounds.add(SymbolicBound(bound.symbol, intersected))
            }
        } else {
            outBounds.add(bound)
        }
    }
    for (bound in rhs.SymbolicBounds()) {
        if (lhs.FindSymbolicBound(bound.symbol).isNone()) {
            outBounds.add(bound)
        }
    }
}

private func HasEmptySymbolicBound(bounds: ArrayList<SymbolicBound>): Bool {
    for (bound in bounds) {
        if (bound.bound.IsEmptySet()) {
            return true
        }
    }
    return false
}

private func IsUnsignedSymbol(symbol: Value): Bool {
    if (let Some(ty) <- symbol.GetType()) {
        return ty.IsUnsignedInteger()
    }
    return false
}

private enum CompareResult {
    | UNO | TRUE | FALSE
}

private func CompareResultIndex(result: CompareResult): Int64 {
    return match (result) {
        case CompareResult.UNO => 0
        case CompareResult.TRUE => 1
        case CompareResult.FALSE => 2
    }
}

extend CompareResult <: Equatable<CompareResult> {
    public operator func ==(right: CompareResult): Bool {
        return CompareResultIndex(this) == CompareResultIndex(right)
    }

    public operator func !=(right: CompareResult): Bool {
        return !(this == right)
    }
}

private func IsSaturating(ov: OverflowStrategy): Bool {
    return ov == OverflowStrategy.SATURATING
}

private func NumericBoundToSignedSymbolicBound(origin: ConstantRange, isUnsigned: Bool): Option<ConstantRange> {
    if (!isUnsigned) {
        return origin
    }
    let converted = NumericConversionU2SSameWidth(origin)
    if (converted.IsSame(origin)) {
        return converted
    }
    return None
}

private func ComputeAdd(args: CHIRArithmeticBinopArgs): SIntDomain {
    let leftNumeric = args.left.NumericBound()
    let rightNumeric = args.right.NumericBound()
    let numeric = if (!IsSaturating(args.overflowStrategy)) {
        leftNumeric.Add(rightNumeric)
    } else if (args.isUnsigned) {
        leftNumeric.UAddSat(rightNumeric)
    } else {
        leftNumeric.SAddSat(rightNumeric)
    }
    if (numeric.IsEmptySet() || args.overflowStrategy != OverflowStrategy.THROWING) {
        return SIntDomain(numeric, args.isUnsigned)
    }

    let bounds = ArrayList<SymbolicBound>()
    if (!leftNumeric.IsSingleElement() && rightNumeric.IsNonTrivial()) {
        if (let Some(leftSym) <- args.leftSymbol) {
            if (let Some(rhsAsSymbolic) <- NumericBoundToSignedSymbolicBound(rightNumeric, args.isUnsigned)) {
                bounds.add(SymbolicBound(leftSym, rhsAsSymbolic))
            }
        }
    }
    if (!rightNumeric.IsSingleElement() && leftNumeric.IsNonTrivial()) {
        if (let Some(rightSym) <- args.rightSymbol) {
            if (let Some(lhsAsSymbolic) <- NumericBoundToSignedSymbolicBound(leftNumeric, args.isUnsigned)) {
                bounds.add(SymbolicBound(rightSym, lhsAsSymbolic))
            }
        }
    }
    return SIntDomain(numeric, bounds, args.isUnsigned)
}

private func ComputeSub(args: CHIRArithmeticBinopArgs): SIntDomain {
    let leftNumeric = args.left.NumericBound()
    let rightNumeric = args.right.NumericBound()
    let numeric = if (!IsSaturating(args.overflowStrategy)) {
        leftNumeric.Sub(rightNumeric)
    } else if (args.isUnsigned) {
        leftNumeric.USubSat(rightNumeric)
    } else {
        leftNumeric.SSubSat(rightNumeric)
    }
    if (numeric.IsEmptySet() || args.overflowStrategy != OverflowStrategy.THROWING) {
        return SIntDomain(numeric, args.isUnsigned)
    }
    if (!leftNumeric.IsSingleElement() && rightNumeric.IsNonTrivial()) {
        let sMinSingleton = ConstantRange(SInt.SMinValue(rightNumeric.Width()))
        if (!rightNumeric.IsSame(sMinSingleton)) {
            if (let Some(leftSym) <- args.leftSymbol) {
                return SIntDomain(numeric, leftSym, rightNumeric.Negate())
            }
        }
    }
    return SIntDomain(numeric, args.isUnsigned)
}

private func ComputeMul(args: CHIRArithmeticBinopArgs): SIntDomain {
    let leftNumeric = args.left.NumericBound()
    let rightNumeric = args.right.NumericBound()
    let result = if (!IsSaturating(args.overflowStrategy)) {
        if (args.isUnsigned) { leftNumeric.UMul(rightNumeric) } else { leftNumeric.SMul(rightNumeric) }
    } else if (args.isUnsigned) {
        leftNumeric.UMulSat(rightNumeric)
    } else {
        leftNumeric.SMulSat(rightNumeric)
    }
    return SIntDomain(result, args.isUnsigned)
}

private func ComputeDiv(args: CHIRArithmeticBinopArgs): SIntDomain {
    let leftNumeric = args.left.NumericBound()
    let rightNumeric = args.right.NumericBound()
    if (rightNumeric.Contains(SInt.Zero(rightNumeric.Width()))) {
        return SIntDomain(ConstantRange.Full(leftNumeric.Width()), args.isUnsigned)
    }
    let result = if (args.isUnsigned) {
        leftNumeric.UDiv(rightNumeric)
    } else if (IsSaturating(args.overflowStrategy)) {
        leftNumeric.SDivSat(rightNumeric)
    } else {
        leftNumeric.SDiv(rightNumeric)
    }
    return SIntDomain(result, args.isUnsigned)
}

private func ComputeMod(args: CHIRArithmeticBinopArgs): SIntDomain {
    let leftNumeric = args.left.NumericBound()
    let rightNumeric = args.right.NumericBound()
    let result = if (args.isUnsigned) { leftNumeric.URem(rightNumeric) } else { leftNumeric.SRem(rightNumeric) }
    return SIntDomain(result, args.isUnsigned)
}

private func ToBool(result: CompareResult): Bool {
    return result == CompareResult.TRUE
}

private func NegCompareResult(result: CompareResult): CompareResult {
    return match (result) {
        case CompareResult.UNO => CompareResult.UNO
        case CompareResult.TRUE => CompareResult.FALSE
        case CompareResult.FALSE => CompareResult.TRUE
    }
}

private func Unless(exp: Bool): CompareResult {
    return if (exp) { CompareResult.TRUE } else { CompareResult.UNO }
}

private func LtRange(left: ConstantRange, right: ConstantRange, isUnsigned: Bool): CompareResult {
    return Unless(if (isUnsigned) { left.UMaxValue().Ult(right.UMinValue()) } else {
        left.SMaxValue().Slt(right.SMinValue())
    })
}

private func LeRange(left: ConstantRange, right: ConstantRange, isUnsigned: Bool): CompareResult {
    return Unless(if (isUnsigned) { left.UMaxValue().Ule(right.UMinValue()) } else {
        left.SMaxValue().Sle(right.SMinValue())
    })
}

private func GeRange(left: ConstantRange, right: ConstantRange, isUnsigned: Bool): CompareResult {
    return Unless(if (isUnsigned) { left.UMinValue().Uge(right.UMaxValue()) } else {
        left.SMinValue().Sge(right.SMaxValue())
    })
}

private func GtRange(left: ConstantRange, right: ConstantRange, isUnsigned: Bool): CompareResult {
    return Unless(if (isUnsigned) { left.UMinValue().Ugt(right.UMaxValue()) } else {
        left.SMinValue().Sgt(right.SMaxValue())
    })
}

private func UnlessBothUnordered(left: CompareResult, right: CompareResult): CompareResult {
    return if (left != CompareResult.UNO) { left } else { right }
}

private func NegRel(rel: RelationalOperation): RelationalOperation {
    return match (rel) {
        case RelationalOperation.LT => RelationalOperation.GE
        case RelationalOperation.LE => RelationalOperation.GT
        case RelationalOperation.EQ => RelationalOperation.NE
        case RelationalOperation.GE => RelationalOperation.LT
        case RelationalOperation.GT => RelationalOperation.LE
        case RelationalOperation.NE => RelationalOperation.EQ
    }
}

private func PartialCompare(rel: RelationalOperation, left: ConstantRange, right: ConstantRange,
    isUnsigned: Bool): CompareResult {
    if (isUnsigned) {
        if (left.IsWrappedSet() || right.IsWrappedSet()) {
            return CompareResult.UNO
        }
    } else if (left.IsSignWrappedSet() || right.IsSignWrappedSet()) {
        return CompareResult.UNO
    }
    return match (rel) {
        case RelationalOperation.LE => LeRange(left, right, isUnsigned)
        case RelationalOperation.LT => LtRange(left, right, isUnsigned)
        case RelationalOperation.GT => GtRange(left, right, isUnsigned)
        case RelationalOperation.GE => GeRange(left, right, isUnsigned)
        case _ => CompareResult.FALSE
    }
}

private func IsUnsignedCompareToZero(range: ConstantRange): Bool {
    return range.IsSingleElement() && range.GetSingleElement().IsZero()
}

private func CompareRanges(rel: RelationalOperation, left: ConstantRange, right: ConstantRange,
    isUnsigned: Bool): CompareResult {
    if (left.IsEmptySet() || right.IsEmptySet()) {
        return CompareResult.UNO
    }
    if ((left.IsFullSet() && !IsUnsignedCompareToZero(right)) ||
        (right.IsFullSet() && !IsUnsignedCompareToZero(left))) {
        return CompareResult.UNO
    }
    return UnlessBothUnordered(PartialCompare(rel, left, right, isUnsigned),
        NegCompareResult(PartialCompare(NegRel(rel), left, right, isUnsigned)))
}

private func ComputeTotalOrderingIntBinop(args: CHIRRelIntBinopArgs, rel: RelationalOperation): BoolDomain {
    let leftDomain = args.left
    let rightDomain = args.right
    if (leftDomain.IsBottom() || rightDomain.IsBottom()) {
        return BoolDomain.Bottom()
    }
    let width = leftDomain.Width()
    let numericResult = CompareRanges(rel, leftDomain.NumericBound(), rightDomain.NumericBound(), args.isUnsigned)
    if (numericResult != CompareResult.UNO) {
        return BoolDomain.FromBool(ToBool(numericResult))
    }
    if (let Some(leftAgainstRight) <- leftDomain.FindSymbolicBound(args.rightSymbol)) {
        let symbolicResult = CompareRanges(rel, leftAgainstRight, ConstantRange(SInt.Zero(width)), false)
        if (symbolicResult != CompareResult.UNO) {
            return BoolDomain.FromBool(ToBool(symbolicResult))
        }
    }
    if (let Some(rightAgainstLeft) <- rightDomain.FindSymbolicBound(args.leftSymbol)) {
        let symbolicResult2 = CompareRanges(SymbolicNeg(rel), rightAgainstLeft, ConstantRange(SInt.Zero(width)), false)
        if (symbolicResult2 != CompareResult.UNO) {
            return BoolDomain.FromBool(ToBool(symbolicResult2))
        }
    }
    for (leftBound in leftDomain.SymbolicBounds()) {
        if (let Some(rightBound) <- rightDomain.FindSymbolicBound(leftBound.symbol)) {
            let transitiveResult = CompareRanges(rel, leftBound.bound, rightBound, false)
            if (transitiveResult != CompareResult.UNO) {
                return BoolDomain.FromBool(ToBool(transitiveResult))
            }
        }
    }
    return BoolDomain.Top()
}

private func CompareTransitiveEquality(left: SIntDomain, right: SIntDomain, compareNotEqual: Bool): BoolDomain {
    for (leftBound in left.SymbolicBounds()) {
        if (let Some(rightBound) <- right.FindSymbolicBound(leftBound.symbol)) {
            let leftRange = leftBound.bound
            if (leftRange.IsSingleElement() && rightBound.IsSingleElement()) {
                return BoolDomain.FromBool(leftRange.GetSingleElement().IsSame(rightBound.GetSingleElement()) !=
                    compareNotEqual)
            }
            if (leftRange.IntersectWith(rightBound, preferredType: PreferredRangeType.SIGNED).IsEmptySet()) {
                return BoolDomain.FromBool(compareNotEqual)
            }
        }
    }
    return BoolDomain.Top()
}

private func ComputeEqualityIntBinop(left: SIntDomain, right: SIntDomain, leftSymbol: Value, rightSymbol: Value,
    compareNotEqual: Bool): BoolDomain {
    if (left.IsBottom() || right.IsBottom()) {
        return BoolDomain.Bottom()
    }
    if (left.NumericBound().IsSingleElement() && right.NumericBound().IsSingleElement()) {
        let leftValue = left.NumericBound().GetSingleElement()
        let rightValue = right.NumericBound().GetSingleElement()
        return BoolDomain.FromBool(leftValue.IsSame(rightValue) != compareNotEqual)
    }
    if (left.NumericBound().IntersectWith(right.NumericBound(), preferredType: PreferFromBool(left.IsUnsigned()))
        .IsEmptySet()) {
        return BoolDomain.FromBool(compareNotEqual)
    }
    if (let Some(leftAgainstRight) <- left.FindSymbolicBound(rightSymbol)) {
        if (leftAgainstRight.IsSingleElement()) {
            return BoolDomain.FromBool(leftAgainstRight.GetSingleElement().IsZero() != compareNotEqual)
        }
        if (!leftAgainstRight.Contains(SInt.Zero(left.Width()))) {
            return BoolDomain.FromBool(compareNotEqual)
        }
    }
    if (let Some(rightAgainstLeft) <- right.FindSymbolicBound(leftSymbol)) {
        if (rightAgainstLeft.IsSingleElement()) {
            return BoolDomain.FromBool(rightAgainstLeft.GetSingleElement().IsZero() != compareNotEqual)
        }
        if (!rightAgainstLeft.Contains(SInt.Zero(left.Width()))) {
            return BoolDomain.FromBool(compareNotEqual)
        }
    }
    let transitive = CompareTransitiveEquality(left, right, compareNotEqual)
    if (transitive.IsNonTrivial()) {
        return transitive
    }
    return BoolDomain.Top()
}

private func TrueOnSameSymbol(op: ExprKind): Bool {
    return op == ExprKind.EQUAL || op == ExprKind.LE || op == ExprKind.GE
}

private func NCSameSignessInner(src: ConstantRange, dstSize: IntWidth, isUnsigned: Bool,
    ov: OverflowStrategy): ConstantRange {
    let srcSize = src.Width()
    if (src.IsFullSet()) {
        return ConstantRange.Full(dstSize)
    }
    if (src.IsEmptySet()) {
        return ConstantRange.Empty(dstSize)
    }
    let lowerLimit = if (isUnsigned) { SInt.UMinValue(dstSize).ZExt(srcSize) } else {
        SInt.SMinValue(dstSize).SExt(srcSize)
    }
    let upperLimit = if (isUnsigned) { SInt.UMaxValue(dstSize).ZExt(srcSize) } else {
        SInt.SMaxValue(dstSize).SExt(srcSize)
    }
    let higherPart = ConstantRange.From(RelationalOperation.GE, lowerLimit, !isUnsigned)
        .IntersectWith(src, preferredType: PreferFromBool(isUnsigned))
    let unchangedPart = ConstantRange.From(RelationalOperation.LE, upperLimit, !isUnsigned)
        .IntersectWith(higherPart, preferredType: PreferFromBool(isUnsigned))
    var result = unchangedPart.Truncate(dstSize)
    if (src.IsSame(unchangedPart) || ov == OverflowStrategy.THROWING) {
        return result
    }
    if (ov == OverflowStrategy.WRAPPING) {
        return ConstantRange.Full(dstSize)
    }
    if (src.Difference(higherPart).IsNotEmptySet()) {
        let minValue = if (isUnsigned) { SInt.UMinValue(dstSize) } else { SInt.SMinValue(dstSize) }
        result = result.UnionWith(ConstantRange(minValue), preferredType: PreferFromBool(isUnsigned))
    }
    if (higherPart.Difference(unchangedPart).IsNotEmptySet()) {
        let maxValue = if (isUnsigned) { SInt.UMaxValue(dstSize) } else { SInt.SMaxValue(dstSize) }
        result = result.UnionWith(ConstantRange(maxValue), preferredType: PreferFromBool(isUnsigned))
    }
    return result
}

private func NumericConversionWithSameSigness(src: ConstantRange, dstSize: IntWidth, isUnsigned: Bool,
    ov: OverflowStrategy): ConstantRange {
    let srcSize = src.Width()
    if (srcSize == dstSize) {
        return src
    }
    if (IntWidthBits(srcSize) < IntWidthBits(dstSize)) {
        return if (isUnsigned) { src.ZeroExtend(dstSize) } else { src.SignExtend(dstSize) }
    }
    if (if (isUnsigned) { src.IsWrappedSet() } else { src.IsSignWrappedSet() }) {
        let split = src.SplitWrapping(isUnsigned)
        let leftConverted = NCSameSignessInner(split[0], dstSize, isUnsigned, ov)
        let rightConverted = NCSameSignessInner(split[1], dstSize, isUnsigned, ov)
        return leftConverted.UnionWith(rightConverted, preferredType: PreferFromBool(isUnsigned))
    }
    return NCSameSignessInner(src, dstSize, isUnsigned, ov)
}

private func TruncWithUpperWrapped(src: ConstantRange, dstUnsigned: Bool, dstSize: IntWidth): ConstantRange {
    let one = SInt(src.Width(), 1)
    let upperLimit = if (dstUnsigned) { SInt.UMaxValue(dstSize).ZExt(src.Width()) } else {
        SInt.SMaxValue(dstSize).ZExt(src.Width())
    }
    if (src.Upper().IsSame(upperLimit.Add(one))) {
        let newLower = src.Lower().Trunc(dstSize)
        let newUpper = src.Upper().Sub(one).Trunc(dstSize).Add(SInt(dstSize, 1))
        if (newLower.IsSame(newUpper)) {
            return ConstantRange.Full(dstSize)
        }
        return ConstantRange(newLower, newUpper)
    }
    return src.Truncate(dstSize)
}

private func NCU2SInner(src: ConstantRange, dstSize: IntWidth, ov: OverflowStrategy): ConstantRange {
    var dstMax = SInt.SMaxValue(dstSize)
    let srcSize = src.Width()
    if (IntWidthBits(srcSize) > IntWidthBits(dstSize)) {
        dstMax = dstMax.SExt(srcSize)
    }
    if (src.IsEmptySet()) {
        return ConstantRange.Empty(dstSize)
    }
    let unchangedRange = ConstantRange.From(RelationalOperation.LE, dstMax, false)
        .IntersectWith(src, preferredType: PreferredRangeType.UNSIGNED)
    if (unchangedRange.IsSame(src) || ov == OverflowStrategy.THROWING) {
        if (IntWidthBits(srcSize) > IntWidthBits(dstSize)) {
            return TruncWithUpperWrapped(unchangedRange, false, dstSize)
        }
        return unchangedRange
    }
    if (ov == OverflowStrategy.SATURATING) {
        var answer = unchangedRange.UnionWith(ConstantRange(dstMax), preferredType: PreferredRangeType.SIGNED)
        if (IntWidthBits(srcSize) > IntWidthBits(dstSize)) {
            answer = TruncWithUpperWrapped(answer, false, dstSize)
        }
        return answer
    }
    if (srcSize == dstSize) {
        return src
    }
    return ConstantRange.Full(dstSize)
}

private func NumericConversionU2S(src: ConstantRange, dstSize: IntWidth, ov: OverflowStrategy): ConstantRange {
    let srcSize = src.Width()
    if (IntWidthBits(dstSize) > IntWidthBits(srcSize)) {
        return src.ZeroExtend(dstSize)
    }
    if (!src.IsWrappedSet()) {
        return NCU2SInner(src, dstSize, ov)
    }
    let split = src.SplitWrapping(true)
    return NCU2SInner(split[0], dstSize, ov).UnionWith(NCU2SInner(split[1], dstSize, ov),
        preferredType: PreferredRangeType.SIGNED)
}

private func NumericConversionU2SSameWidth(src: ConstantRange): ConstantRange {
    return NumericConversionU2S(src, src.Width(), OverflowStrategy.THROWING)
}

private func NCS2UInnerTrunc(src: ConstantRange, dstSize: IntWidth, ov: OverflowStrategy): ConstantRange {
    if (src.IsEmptySet()) {
        return ConstantRange.Empty(dstSize)
    }
    let srcSize = src.Width()
    let nonNegRange = src.IntersectWith(ConstantRange.From(RelationalOperation.GE, SInt.Zero(srcSize), true),
        preferredType: PreferredRangeType.SIGNED)
    let negRange = src.Difference(nonNegRange)
    let unchangedRange = nonNegRange.IntersectWith(
        ConstantRange.From(RelationalOperation.LE, SInt.UMaxValue(dstSize).ZExt(srcSize), true))
    if (unchangedRange.IsSame(src) || ov == OverflowStrategy.THROWING) {
        return TruncWithUpperWrapped(unchangedRange, true, dstSize)
    }
    if (ov == OverflowStrategy.SATURATING) {
        var result = unchangedRange
        if (negRange.IsNotEmptySet()) {
            result = result.UnionWith(ConstantRange(SInt.Zero(srcSize)), preferredType: PreferredRangeType.UNSIGNED)
        }
        if (!unchangedRange.IsSame(nonNegRange)) {
            result = result.UnionWith(ConstantRange(SInt.UMaxValue(dstSize).ZExt(srcSize)),
                preferredType: PreferredRangeType.UNSIGNED)
        }
        return TruncWithUpperWrapped(result, true, dstSize)
    }
    return ConstantRange.Full(dstSize)
}

private func NCS2UInnerExtend(src: ConstantRange, dstSize: IntWidth, ov: OverflowStrategy): ConstantRange {
    if (src.IsEmptySet()) {
        return ConstantRange.Empty(dstSize)
    }
    let srcSize = src.Width()
    var nonNegRange = src.IntersectWith(ConstantRange.From(RelationalOperation.GE, SInt.Zero(srcSize), true),
        preferredType: PreferredRangeType.SIGNED)
    let negRange = src.Difference(nonNegRange)
    if (nonNegRange.IsSame(src) || ov == OverflowStrategy.THROWING) {
        return if (srcSize == dstSize) { nonNegRange } else { nonNegRange.ZeroExtend(dstSize) }
    }
    if (ov == OverflowStrategy.SATURATING) {
        if (negRange.IsNotEmptySet()) {
            nonNegRange = nonNegRange.UnionWith(ConstantRange(SInt.UMinValue(srcSize)))
        }
        return if (srcSize == dstSize) { nonNegRange } else { nonNegRange.ZeroExtend(dstSize) }
    }
    let negOverflowRange = ConstantRange.NonEmpty(negRange.SMinValue().SExt(dstSize),
        negRange.SMaxValue().SExt(dstSize).Add(SInt(dstSize, 1)))
    let extendedNonNeg = if (srcSize == dstSize) { nonNegRange } else { nonNegRange.ZeroExtend(dstSize) }
    return negOverflowRange.UnionWith(extendedNonNeg, preferredType: PreferredRangeType.UNSIGNED)
}

private func NumericConversionS2U(src: ConstantRange, dstSize: IntWidth, ov: OverflowStrategy): ConstantRange {
    let srcSize = src.Width()
    if (IntWidthBits(dstSize) < IntWidthBits(srcSize)) {
        if (src.IsSignWrappedSet()) {
            let split = src.SplitWrapping(false)
            return NCS2UInnerTrunc(split[0], dstSize, ov).UnionWith(NCS2UInnerTrunc(split[1], dstSize, ov),
                preferredType: PreferredRangeType.UNSIGNED)
        }
        return NCS2UInnerTrunc(src, dstSize, ov)
    }
    return NCS2UInnerExtend(src, dstSize, ov)
}
