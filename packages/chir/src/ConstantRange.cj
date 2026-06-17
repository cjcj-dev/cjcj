package cangjie_compiler::chir

public enum PreferredRangeType {
    | SMALLEST | UNSIGNED | SIGNED
}

public func PreferredRangeTypeIndex(kind: PreferredRangeType): Int64 {
    return match (kind) {
        case PreferredRangeType.SMALLEST => 0
        case PreferredRangeType.UNSIGNED => 1
        case PreferredRangeType.SIGNED => 2
    }
}

extend PreferredRangeType <: Equatable<PreferredRangeType> {
    public operator func ==(right: PreferredRangeType): Bool {
        return PreferredRangeTypeIndex(this) == PreferredRangeTypeIndex(right)
    }

    public operator func !=(right: PreferredRangeType): Bool {
        return !(this == right)
    }
}

public func PreferFromBool(useUnsigned: Bool): PreferredRangeType {
    return if (useUnsigned) { PreferredRangeType.UNSIGNED } else { PreferredRangeType.SIGNED }
}

public enum RelationalOperation {
    | LT | LE | EQ | GT | GE | NE
}

extend RelationalOperation <: Equatable<RelationalOperation> {
    public operator func ==(right: RelationalOperation): Bool {
        return RelationalOperationIndex(this) == RelationalOperationIndex(right)
    }

    public operator func !=(right: RelationalOperation): Bool {
        return !(this == right)
    }
}

private func RelationalOperationIndex(op: RelationalOperation): Int64 {
    return match (op) {
        case RelationalOperation.LT => 0
        case RelationalOperation.LE => 1
        case RelationalOperation.EQ => 2
        case RelationalOperation.GT => 3
        case RelationalOperation.GE => 4
        case RelationalOperation.NE => 5
    }
}

public struct ConstantRange {
    private let lower: SInt
    private let upper: SInt

    public init(width: IntWidth, full: Bool) {
        if (full) {
            lower = SInt.UMaxValue(width)
            upper = SInt.UMaxValue(width)
        } else {
            lower = SInt.Zero(width)
            upper = SInt.Zero(width)
        }
    }

    public init(value: SInt) {
        lower = value
        upper = value.Add(SInt(value.Width(), 1))
    }

    public init(lower: SInt, upper: SInt) {
        this.lower = lower
        this.upper = upper
    }

    public static func Empty(width: IntWidth): ConstantRange {
        return ConstantRange(width, false)
    }

    public static func Full(width: IntWidth): ConstantRange {
        return ConstantRange(width, true)
    }

    public static func NonEmpty(lower: SInt, upper: SInt): ConstantRange {
        if (lower.IsSame(upper)) {
            return ConstantRange.Full(lower.Width())
        }
        return ConstantRange(lower, upper)
    }

    public static func From(rel: RelationalOperation, value: SInt, isSigned: Bool): ConstantRange {
        let width = value.Width()
        let isMin = if (isSigned) { value.IsSMinValue() } else { value.IsUMinValue() }
        let isMax = if (isSigned) { value.IsSMaxValue() } else { value.IsUMaxValue() }
        if ((rel == RelationalOperation.LT && isMin) || (rel == RelationalOperation.GT && isMax)) {
            return ConstantRange.Empty(width)
        }
        if ((rel == RelationalOperation.LE && isMax) || (rel == RelationalOperation.GE && isMin)) {
            return ConstantRange.Full(width)
        }
        let maxValue = if (isSigned) { SInt.SMaxValue(width) } else { SInt.UMaxValue(width) }
        let minValue = if (isSigned) { SInt.SMinValue(width) } else { SInt.UMinValue(width) }
        return match (rel) {
            case RelationalOperation.EQ => ConstantRange(value)
            case RelationalOperation.NE => ConstantRange(value.Add(SInt(width, 1)), value)
            case RelationalOperation.GE => ConstantRange(value, maxValue.Add(SInt(width, 1)))
            case RelationalOperation.GT => ConstantRange(value.Add(SInt(width, 1)), maxValue.Add(SInt(width, 1)))
            case RelationalOperation.LE => ConstantRange(minValue, value.Add(SInt(width, 1)))
            case RelationalOperation.LT => ConstantRange(minValue, value)
        }
    }

    public func Lower(): SInt { return lower }
    public func Upper(): SInt { return upper }
    public func Width(): IntWidth { return lower.Width() }

    public func IsFullSet(): Bool {
        return lower.IsUMaxValue() && upper.IsUMaxValue()
    }

    public func IsEmptySet(): Bool {
        return lower.IsZero() && upper.IsZero()
    }

    public func IsNotEmptySet(): Bool {
        return !IsEmptySet()
    }

    public func IsNonTrivial(): Bool {
        return !IsFullSet()
    }

    public func IsWrappedSet(): Bool {
        return lower.Ugt(upper) && !upper.IsZero()
    }

    public func IsUpperWrapped(): Bool {
        return lower.Ugt(upper)
    }

    public func IsSignWrappedSet(): Bool {
        return lower.Sgt(upper) && !upper.IsSMinValue()
    }

    public func IsUpperSignWrapped(): Bool {
        return lower.Sgt(upper)
    }

    public func Contains(value: SInt): Bool {
        if (value.Width() != Width()) {
            return false
        }
        if (lower.IsSame(upper)) {
            return IsFullSet()
        }
        if (!IsUpperWrapped()) {
            return lower.Ule(value) && value.Ult(upper)
        }
        return lower.Ule(value) || value.Ult(upper)
    }

    public func GetSingleElement(): SInt {
        return lower
    }

    public func IsSingleElement(): Bool {
        return lower.Add(SInt(Width(), 1)).IsSame(upper)
    }

    public func IsSizeStrictlySmallerThan(rhs: ConstantRange): Bool {
        if (IsFullSet()) {
            return false
        }
        if (rhs.IsFullSet()) {
            return true
        }
        return upper.Sub(lower).Ult(rhs.upper.Sub(rhs.lower))
    }

    public func UMaxValue(): SInt {
        if (IsFullSet() || IsUpperWrapped()) {
            return SInt.UMaxValue(Width())
        }
        return upper.Sub(SInt(Width(), 1))
    }

    public func UMinValue(): SInt {
        if (IsFullSet() || IsWrappedSet()) {
            return SInt.UMinValue(Width())
        }
        return lower
    }

    public func SMaxValue(): SInt {
        if (IsFullSet() || IsUpperSignWrapped()) {
            return SInt.SMaxValue(Width())
        }
        return upper.Sub(SInt(Width(), 1))
    }

    public func SMinValue(): SInt {
        if (IsFullSet() || IsSignWrappedSet()) {
            return SInt.SMinValue(Width())
        }
        return lower
    }

    public func MaxValue(isUnsigned: Bool): SInt {
        return if (isUnsigned) { UMaxValue() } else { SMaxValue() }
    }

    public func MinValue(isUnsigned: Bool): SInt {
        return if (isUnsigned) { UMinValue() } else { SMinValue() }
    }

    public func IsSame(rhs: ConstantRange): Bool {
        return lower.IsSame(rhs.lower) && upper.IsSame(rhs.upper)
    }

    public func Subtract(value: SInt): ConstantRange {
        if (IsEmptySet() || IsFullSet()) {
            return this
        }
        return ConstantRange(lower.Sub(value), upper.Sub(value))
    }

    public func Inverse(): ConstantRange {
        if (IsFullSet()) {
            return ConstantRange.Empty(Width())
        }
        if (IsEmptySet()) {
            return ConstantRange.Full(Width())
        }
        return ConstantRange(upper, lower)
    }

    public func Difference(rhs: ConstantRange): ConstantRange {
        return IntersectWith(rhs.Inverse())
    }

    public func IntersectWith(rhs: ConstantRange,
        preferredType!: PreferredRangeType = PreferredRangeType.SMALLEST): ConstantRange {
        if (IsEmptySet() || rhs.IsFullSet()) {
            return this
        }
        if (rhs.IsEmptySet() || IsFullSet()) {
            return rhs
        }
        let thisWrapped = IsUpperWrapped()
        let rhsWrapped = rhs.IsUpperWrapped()
        if (!thisWrapped && rhsWrapped) {
            return rhs.IntersectWith(this, preferredType: preferredType)
        }
        if (!thisWrapped && !rhsWrapped) {
            return IntersectBothUnwrapped(rhs)
        }
        if (thisWrapped && !rhsWrapped) {
            return IntersectWrappedWithUnwrapped(rhs, preferredType)
        }
        return IntersectBothWrapped(rhs, preferredType)
    }

    public func UnionWith(rhs: ConstantRange,
        preferredType!: PreferredRangeType = PreferredRangeType.SMALLEST): ConstantRange {
        if (IsFullSet() || rhs.IsEmptySet()) {
            return this
        }
        if (rhs.IsFullSet() || IsEmptySet()) {
            return rhs
        }
        let thisWrapped = IsUpperWrapped()
        let rhsWrapped = rhs.IsUpperWrapped()
        if (thisWrapped) {
            if (rhsWrapped) {
                return UnionBothWrapped(rhs)
            }
            return UnionWrappedWithUnwrapped(rhs, preferredType)
        } else {
            if (rhsWrapped) {
                return rhs.UnionWith(this, preferredType: preferredType)
            }
            return UnionBothUnwrapped(rhs, preferredType)
        }
    }

    public func SplitWrapping(asUnsigned: Bool): (ConstantRange, ConstantRange) {
        return (ConstantRange.From(RelationalOperation.LT, upper, !asUnsigned),
            ConstantRange.From(RelationalOperation.GE, lower, !asUnsigned))
    }

    public func ZeroExtend(newWidth: IntWidth): ConstantRange {
        if (IsEmptySet()) {
            return ConstantRange.Empty(newWidth)
        }
        if (IntWidthBits(Width()) >= IntWidthBits(newWidth)) {
            throw IllegalArgumentException("zero extension requires a larger width")
        }
        if (IsFullSet() || IsWrappedSet()) {
            return ConstantRange(SInt(newWidth, 0), SInt.GetOneBitSet(newWidth, IntWidthBits(Width())))
        }
        if (upper.IsUMinValue()) {
            return ConstantRange(lower.ZExt(newWidth), SInt.GetOneBitSet(newWidth, IntWidthBits(Width())))
        }
        return ConstantRange(lower.ZExt(newWidth), upper.ZExt(newWidth))
    }

    public func SignExtend(newWidth: IntWidth): ConstantRange {
        if (IsEmptySet()) {
            return ConstantRange.Empty(newWidth)
        }
        if (IntWidthBits(Width()) >= IntWidthBits(newWidth)) {
            throw IllegalArgumentException("sign extension requires a larger width")
        }
        if (IsFullSet() || IsSignWrappedSet()) {
            let oldBits = IntWidthBits(Width())
            let newBits = IntWidthBits(newWidth)
            let lowerValue = SInt.GetHighBitsSet(newWidth, (newBits - oldBits) + 1)
            let upperValue = SInt.GetLowBitsSet(newWidth, oldBits - 1).Add(SInt(newWidth, 1))
            return ConstantRange(lowerValue, upperValue)
        }
        if (upper.IsSMinValue()) {
            return ConstantRange(lower.SExt(newWidth), upper.ZExt(newWidth))
        }
        return ConstantRange(lower.SExt(newWidth), upper.SExt(newWidth))
    }

    public func Truncate(dstWidth: IntWidth): ConstantRange {
        if (IntWidthBits(Width()) <= IntWidthBits(dstWidth)) {
            throw IllegalArgumentException("truncation requires a smaller width")
        }
        if (IsEmptySet()) {
            return ConstantRange.Empty(dstWidth)
        }
        if (IsFullSet()) {
            return ConstantRange.Full(dstWidth)
        }

        var lowerDiv = lower
        var upperDiv = upper
        var wrappedPart = ConstantRange.Empty(dstWidth)
        if (IsUpperWrapped()) {
            let dstMaxValue = SInt.UMaxValue(dstWidth)
            if (upper.Uge(dstMaxValue.ZExt(Width()))) {
                return ConstantRange.Full(dstWidth)
            }
            wrappedPart = ConstantRange(dstMaxValue, upper.Trunc(dstWidth))
            if (lowerDiv.IsUMaxValue()) {
                return wrappedPart
            }
            upperDiv = SInt.AllOnes(Width())
        }

        let dstBits = IntWidthBits(dstWidth)
        if (lowerDiv.ActiveBits() > dstBits) {
            let adjust = lowerDiv.BitAnd(SInt.GetBitsSetFrom(Width(), dstBits))
            lowerDiv = lowerDiv.Sub(adjust)
            upperDiv = upperDiv.Sub(adjust)
        }

        let upperDivWidth = upperDiv.ActiveBits()
        if (upperDivWidth <= dstBits) {
            return ConstantRange(lowerDiv.Trunc(dstWidth), upperDiv.Trunc(dstWidth)).UnionWith(wrappedPart)
        }
        if (upperDivWidth == dstBits + 1) {
            let clearedUpper = upperDiv.ClearBit(dstBits)
            if (clearedUpper.Ult(lowerDiv)) {
                return ConstantRange(lowerDiv.Trunc(dstWidth), clearedUpper.Trunc(dstWidth)).UnionWith(wrappedPart)
            }
            return ConstantRange.Full(dstWidth)
        }
        return ConstantRange.Full(dstWidth)
    }

    public func Add(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        if (IsFullSet() || rhs.IsFullSet()) {
            return ConstantRange.Full(Width())
        }
        let newLower = lower.Add(rhs.lower)
        let newUpper = upper.Add(rhs.upper).Sub(SInt(Width(), 1))
        if (newLower.IsSame(newUpper)) {
            return ConstantRange.Full(Width())
        }
        let result = ConstantRange(newLower, newUpper)
        if (result.IsSizeStrictlySmallerThan(this) || result.IsSizeStrictlySmallerThan(rhs)) {
            return ConstantRange.Full(Width())
        }
        return result
    }

    public func Sub(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        if (IsFullSet() || rhs.IsFullSet()) {
            return ConstantRange.Full(Width())
        }
        let newLower = lower.Sub(rhs.upper).Add(SInt(Width(), 1))
        let newUpper = upper.Sub(rhs.lower)
        if (newLower.IsSame(newUpper)) {
            return ConstantRange.Full(Width())
        }
        let result = ConstantRange(newLower, newUpper)
        if (result.IsSizeStrictlySmallerThan(this) || result.IsSizeStrictlySmallerThan(rhs)) {
            return ConstantRange.Full(Width())
        }
        return result
    }

    public func UMul(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        let lhsMin = UMinValue()
        let lhsMax = UMaxValue()
        let rhsMin = rhs.UMinValue()
        let rhsMax = rhs.UMaxValue()
        let lowerResult = lhsMin.UMulOvf(rhsMin)
        let upperResult = lhsMax.UMulOvf(rhsMax)
        if (lowerResult[1] || upperResult[1]) {
            return ConstantRange.Full(Width())
        }
        return ConstantRange.NonEmpty(lowerResult[0], upperResult[0].Add(SInt(Width(), 1)))
    }

    public func SMul(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        let lhsMin = SMinValue()
        let lhsMax = SMaxValue()
        let rhsMin = rhs.SMinValue()
        let rhsMax = rhs.SMaxValue()
        let product1 = lhsMin.SMulOvf(rhsMin)
        let product2 = lhsMin.SMulOvf(rhsMax)
        let product3 = lhsMax.SMulOvf(rhsMin)
        let product4 = lhsMax.SMulOvf(rhsMax)
        if (product1[1] || product2[1] || product3[1] || product4[1]) {
            return ConstantRange.Full(Width())
        }
        var minProduct = product1[0]
        var maxProduct = product1[0]
        if (product2[0].Slt(minProduct)) { minProduct = product2[0] }
        if (product3[0].Slt(minProduct)) { minProduct = product3[0] }
        if (product4[0].Slt(minProduct)) { minProduct = product4[0] }
        if (product2[0].Sgt(maxProduct)) { maxProduct = product2[0] }
        if (product3[0].Sgt(maxProduct)) { maxProduct = product3[0] }
        if (product4[0].Sgt(maxProduct)) { maxProduct = product4[0] }
        return ConstantRange.NonEmpty(minProduct, maxProduct.Add(SInt(Width(), 1)))
    }

    public func UDiv(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet() || rhs.UMaxValue().IsZero()) {
            return ConstantRange.Empty(Width())
        }
        let newLower = UMinValue().UDiv(rhs.UMaxValue())
        var rhsMin = rhs.UMinValue()
        if (rhsMin.IsZero()) {
            rhsMin = if (rhs.upper.IsOne()) { rhs.lower } else { SInt(Width(), 1) }
        }
        let newUpper = UMaxValue().UDiv(rhsMin).Add(SInt(Width(), 1))
        return ConstantRange.NonEmpty(newLower, newUpper)
    }

    public func SDiv(rhs: ConstantRange): ConstantRange {
        return SDivImpl(rhs, false)
    }

    public func SDivSat(rhs: ConstantRange): ConstantRange {
        return SDivImpl(rhs, true)
    }

    public func URem(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet() || rhs.UMaxValue().IsZero()) {
            return ConstantRange.Empty(Width())
        }
        if (rhs.IsSingleElement()) {
            let rhsValue = rhs.GetSingleElement()
            if (rhsValue.IsZero()) {
                return ConstantRange.Empty(Width())
            }
            if (IsSingleElement()) {
                return ConstantRange(GetSingleElement().URem(rhsValue))
            }
        }
        if (UMaxValue().Ult(rhs.UMinValue())) {
            return this
        }
        let zero = SInt.Zero(Width())
        let upperValue = SInt.UMin(UMaxValue(), rhs.UMaxValue().Sub(SInt(Width(), 1))).Add(SInt(Width(), 1))
        return ConstantRange.NonEmpty(zero, upperValue)
    }

    public func SRem(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        if (rhs.IsSingleElement()) {
            let rhsValue = rhs.GetSingleElement()
            if (rhsValue.IsZero()) {
                return ConstantRange.Empty(Width())
            }
            if (IsSingleElement()) {
                return ConstantRange(GetSingleElement().SRem(rhsValue))
            }
        }
        let absRhs = rhs.Abs()
        var minAbsRhs = absRhs.UMinValue()
        let maxAbsRhs = absRhs.UMaxValue()
        if (maxAbsRhs.IsZero()) {
            return ConstantRange.Empty(Width())
        }
        if (minAbsRhs.IsZero()) {
            minAbsRhs = minAbsRhs.Add(SInt(Width(), 1))
        }
        let minLhs = SMinValue()
        let maxLhs = SMaxValue()
        if (minLhs.IsNonNeg()) {
            if (maxLhs.Ult(minAbsRhs)) {
                return this
            }
            let upperValue = SInt.UMin(maxLhs, maxAbsRhs.Sub(SInt(Width(), 1))).Add(SInt(Width(), 1))
            return ConstantRange(SInt.Zero(Width()), upperValue)
        }
        if (maxLhs.IsNeg()) {
            if (minLhs.Ugt(minAbsRhs.Neg())) {
                return this
            }
            let lowerValue = SInt.UMax(minLhs, maxAbsRhs.Neg().Add(SInt(Width(), 1)))
            return ConstantRange(lowerValue, SInt(Width(), 1))
        }
        let lowerValue = SInt.UMax(minLhs, maxAbsRhs.Neg().Add(SInt(Width(), 1)))
        let upperValue = SInt.UMin(maxLhs, maxAbsRhs.Sub(SInt(Width(), 1))).Add(SInt(Width(), 1))
        return ConstantRange(lowerValue, upperValue)
    }

    public func UAddSat(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        let lowerValue = UMinValue().UAddSat(rhs.UMinValue())
        let upperValue = UMaxValue().UAddSat(rhs.UMaxValue()).Add(SInt(Width(), 1))
        return ConstantRange.NonEmpty(lowerValue, upperValue)
    }

    public func SAddSat(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        let lowerValue = SMinValue().SAddSat(rhs.SMinValue())
        let upperValue = SMaxValue().SAddSat(rhs.SMaxValue()).Add(SInt(Width(), 1))
        return ConstantRange.NonEmpty(lowerValue, upperValue)
    }

    public func USubSat(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        let lowerValue = UMinValue().USubSat(rhs.UMaxValue())
        let upperValue = UMaxValue().USubSat(rhs.UMinValue()).Add(SInt(Width(), 1))
        return ConstantRange.NonEmpty(lowerValue, upperValue)
    }

    public func SSubSat(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        let lowerValue = SMinValue().SSubSat(rhs.SMaxValue())
        let upperValue = SMaxValue().SSubSat(rhs.SMinValue()).Add(SInt(Width(), 1))
        return ConstantRange.NonEmpty(lowerValue, upperValue)
    }

    public func UMulSat(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        let lowerValue = UMinValue().UMulSat(rhs.UMinValue())
        let upperValue = UMaxValue().UMulSat(rhs.UMaxValue()).Add(SInt(Width(), 1))
        return ConstantRange.NonEmpty(lowerValue, upperValue)
    }

    public func SMulSat(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        let lhsMin = SMinValue()
        let lhsMax = SMaxValue()
        let rhsMin = rhs.SMinValue()
        let rhsMax = rhs.SMaxValue()
        let product1 = lhsMin.SMulSat(rhsMin)
        let product2 = lhsMin.SMulSat(rhsMax)
        let product3 = lhsMax.SMulSat(rhsMin)
        let product4 = lhsMax.SMulSat(rhsMax)
        var minProduct = product1
        var maxProduct = product1
        if (product2.Slt(minProduct)) { minProduct = product2 }
        if (product3.Slt(minProduct)) { minProduct = product3 }
        if (product4.Slt(minProduct)) { minProduct = product4 }
        if (product2.Sgt(maxProduct)) { maxProduct = product2 }
        if (product3.Sgt(maxProduct)) { maxProduct = product3 }
        if (product4.Sgt(maxProduct)) { maxProduct = product4 }
        return ConstantRange.NonEmpty(minProduct, maxProduct.Add(SInt(Width(), 1)))
    }

    public func Abs(intMinIsPoison!: Bool = false): ConstantRange {
        if (IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        if (IsSignWrappedSet()) {
            var lowerValue = SInt.UMin(lower, upper.Neg().Add(SInt(Width(), 1)))
            if (upper.IsPositive() || !lower.IsPositive()) {
                lowerValue = SInt.Zero(Width())
            }
            let signedMin = SInt.SMinValue(Width())
            return if (intMinIsPoison) {
                ConstantRange(lowerValue, signedMin)
            } else {
                ConstantRange(lowerValue, signedMin.Add(SInt(Width(), 1)))
            }
        }
        var signedMinValue = SMinValue()
        let signedMaxValue = SMaxValue()
        if (intMinIsPoison && signedMinValue.IsSMinValue()) {
            if (signedMaxValue.IsSMinValue()) {
                return ConstantRange.Empty(Width())
            }
            signedMinValue = signedMinValue.Add(SInt(Width(), 1))
        }
        if (signedMinValue.IsNonNeg()) {
            return this
        }
        if (signedMaxValue.IsNeg()) {
            return ConstantRange(signedMaxValue.Neg(), signedMinValue.Neg().Add(SInt(Width(), 1)))
        }
        return ConstantRange(SInt.Zero(Width()), SInt.UMax(signedMinValue.Neg(), signedMaxValue).Add(SInt(Width(), 1)))
    }

    public func Negate(): ConstantRange {
        if (IsEmptySet() || IsFullSet()) {
            return this
        }
        let lowerValue = upper.Sub(SInt(Width(), 1)).Neg()
        let upperValue = if (lower.IsSMinValue()) { lower } else { lower.Neg().Add(SInt(Width(), 1)) }
        return ConstantRange(lowerValue, upperValue)
    }

    private func SDivImpl(rhs: ConstantRange, saturating: Bool): ConstantRange {
        let zero = SInt.Zero(Width())
        let one = SInt(Width(), 1)
        let signedMin = SInt.SMinValue(Width())
        let posFilter = ConstantRange(one, signedMin)
        let negFilter = ConstantRange(signedMin, zero)
        let posL = IntersectWith(posFilter)
        let negL = IntersectWith(negFilter)
        let posR = rhs.IntersectWith(posFilter)
        let negR = rhs.IntersectWith(negFilter)

        var posDivPosRes = ConstantRange.Empty(Width())
        if (!posL.IsEmptySet() && !posR.IsEmptySet()) {
            let lowerValue = SignedDiv(posL.lower, posR.upper.Sub(one), saturating)
            let upperValue = SignedDiv(posL.upper.Sub(one), posR.lower, saturating).Add(one)
            posDivPosRes = ConstantRange(lowerValue, upperValue)
        }

        var negDivNegRes = ConstantRange.Empty(Width())
        if (!negL.IsEmptySet() && !negR.IsEmptySet()) {
            let lowerValue = SignedDiv(negL.upper.Sub(one), negR.lower, saturating)
            var upperValue = SignedDiv(negL.lower, negR.upper.Sub(one), saturating).Add(one)
            if (negL.lower.IsSMinValue() && negR.upper.IsZero()) {
                if (!negR.lower.IsAllOnes()) {
                    var adjustedNegRUpper = negR.upper.Sub(one)
                    if (rhs.lower.IsAllOnes()) {
                        adjustedNegRUpper = rhs.upper
                    }
                    upperValue = SignedDiv(negL.lower, adjustedNegRUpper.Sub(one), saturating).Add(one)
                }
                if (!negL.upper.IsSame(signedMin.Add(one))) {
                    var adjustedNegLLower = negL.lower.Add(one)
                    if (upper.IsSame(signedMin.Add(one))) {
                        adjustedNegLLower = lower
                    }
                    upperValue = SignedDiv(adjustedNegLLower, negR.upper.Sub(one), saturating).Add(one)
                }
            }
            negDivNegRes = ConstantRange(lowerValue, upperValue)
        }
        let posRes = posDivPosRes.UnionWith(negDivNegRes)

        var posDivNegRes = ConstantRange.Empty(Width())
        if (!posL.IsEmptySet() && !negR.IsEmptySet()) {
            let lowerValue = SignedDiv(posL.upper.Sub(one), negR.upper.Sub(one), saturating)
            let upperValue = SignedDiv(posL.lower, negR.lower, saturating).Add(one)
            posDivNegRes = ConstantRange(lowerValue, upperValue)
        }

        var negDivPosRes = ConstantRange.Empty(Width())
        if (!negL.IsEmptySet() && !posR.IsEmptySet()) {
            let lowerValue = SignedDiv(negL.lower, posR.lower, saturating)
            let upperValue = SignedDiv(negL.upper.Sub(one), posR.upper.Sub(one), saturating).Add(one)
            negDivPosRes = ConstantRange(lowerValue, upperValue)
        }
        let negRes = posDivNegRes.UnionWith(negDivPosRes)
        var result = negRes.UnionWith(posRes, preferredType: PreferredRangeType.SIGNED)
        if (Contains(zero) && (!posR.IsEmptySet() || !negR.IsEmptySet())) {
            result = result.UnionWith(ConstantRange(zero))
        }
        return result
    }

    private func IntersectBothWrapped(rhs: ConstantRange, preferredType: PreferredRangeType): ConstantRange {
        if (rhs.upper.Ult(upper)) {
            if (rhs.lower.Ult(upper)) {
                return GetPreferredRange(this, rhs, preferredType)
            }
            if (rhs.lower.Ult(lower)) {
                return ConstantRange(lower, rhs.upper)
            }
            return rhs
        }
        if (rhs.upper.Ule(lower)) {
            if (rhs.lower.Ult(lower)) {
                return this
            }
            return ConstantRange(rhs.lower, upper)
        }
        return GetPreferredRange(this, rhs, preferredType)
    }

    private func IntersectWrappedWithUnwrapped(rhs: ConstantRange,
        preferredType: PreferredRangeType): ConstantRange {
        if (rhs.lower.Ult(upper)) {
            if (rhs.upper.Ult(upper)) {
                return rhs
            }
            if (rhs.upper.Ule(lower)) {
                return ConstantRange(rhs.lower, upper)
            }
            return GetPreferredRange(this, rhs, preferredType)
        }
        if (rhs.lower.Ult(lower)) {
            if (rhs.upper.Ule(lower)) {
                return ConstantRange.Empty(Width())
            }
            return ConstantRange(lower, rhs.upper)
        }
        return rhs
    }

    private func IntersectBothUnwrapped(rhs: ConstantRange): ConstantRange {
        if (lower.Ult(rhs.lower)) {
            if (upper.Ule(rhs.lower)) {
                return ConstantRange.Empty(Width())
            }
            if (upper.Ult(rhs.upper)) {
                return ConstantRange(rhs.lower, upper)
            }
            return rhs
        }
        if (rhs.upper.Ule(lower)) {
            return ConstantRange.Empty(Width())
        }
        if (rhs.upper.Ult(upper)) {
            return ConstantRange(lower, rhs.upper)
        }
        return this
    }

    private func UnionBothWrapped(rhs: ConstantRange): ConstantRange {
        if (rhs.lower.Ule(upper) || lower.Ule(rhs.upper)) {
            return ConstantRange.Full(Width())
        }
        let newLower = if (rhs.lower.Ult(lower)) { rhs.lower } else { lower }
        let newUpper = if (rhs.upper.Ugt(upper)) { rhs.upper } else { upper }
        return ConstantRange(newLower, newUpper)
    }

    private func UnionWrappedWithUnwrapped(rhs: ConstantRange,
        preferredType: PreferredRangeType): ConstantRange {
        if (rhs.lower.Ule(upper)) {
            if (rhs.upper.Ult(upper)) {
                return this
            }
            if (rhs.upper.Ult(lower)) {
                return ConstantRange(lower, rhs.upper)
            }
            return ConstantRange.Full(Width())
        }
        if (rhs.lower.Ult(lower)) {
            if (rhs.upper.Ult(lower)) {
                return GetPreferredRange(ConstantRange(lower, rhs.upper), ConstantRange(rhs.lower, upper), preferredType)
            }
            return ConstantRange(rhs.lower, upper)
        }
        return this
    }

    private func UnionBothUnwrapped(rhs: ConstantRange, preferredType: PreferredRangeType): ConstantRange {
        if (rhs.upper.Ult(lower) || upper.Ult(rhs.lower)) {
            return GetPreferredRange(ConstantRange(lower, rhs.upper), ConstantRange(rhs.lower, upper), preferredType)
        }
        let newLower = if (rhs.lower.Ult(lower)) { rhs.lower } else { lower }
        let one = SInt(Width(), 1)
        let newUpper = if (rhs.upper.Sub(one).Ugt(upper.Sub(one))) { rhs.upper } else { upper }
        if (newLower.IsZero() && newUpper.IsZero()) {
            return ConstantRange.Full(Width())
        }
        return ConstantRange(newLower, newUpper)
    }

    public func ToString(asUnsigned!: Bool = true, radix!: Radix = Radix.R10): String {
        if (IsEmptySet()) {
            return "{}"
        }
        if (IsFullSet()) {
            return "<full " + "${lower.WidthBits()}" + ">"
        }
        return "[" + lower.ToString(asUnsigned: asUnsigned, radix: radix) + ", " +
            upper.ToString(asUnsigned: asUnsigned, radix: radix) + ")"
    }

}

private func GetPreferredRange(left: ConstantRange, right: ConstantRange,
    preferredType: PreferredRangeType): ConstantRange {
    if (preferredType == PreferredRangeType.UNSIGNED) {
        if (!left.IsWrappedSet() && right.IsWrappedSet()) {
            return left
        }
        if (left.IsWrappedSet() && !right.IsWrappedSet()) {
            return right
        }
    } else if (preferredType == PreferredRangeType.SIGNED) {
        if (!left.IsSignWrappedSet() && right.IsSignWrappedSet()) {
            return left
        }
        if (left.IsSignWrappedSet() && !right.IsSignWrappedSet()) {
            return right
        }
    }
    return if (left.IsSizeStrictlySmallerThan(right)) { left } else { right }
}

private func SignedDiv(left: SInt, right: SInt, saturating: Bool): SInt {
    return if (saturating) { left.SDivSat(right) } else { left.SDiv(right) }
}
