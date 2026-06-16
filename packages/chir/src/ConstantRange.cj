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
