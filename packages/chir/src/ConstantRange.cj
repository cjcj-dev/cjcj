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
        if (rel == RelationalOperation.EQ) {
            return ConstantRange(value)
        }
        if (rel == RelationalOperation.NE) {
            if (value.IsZero()) {
                return ConstantRange.NonEmpty(value.Add(SInt(width, 1)), value)
            }
            return ConstantRange.NonEmpty(value.Add(SInt(width, 1)), value)
        }
        if (isSigned) {
            return SignedConstraint(rel, value)
        }
        return UnsignedConstraint(rel, value)
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
        if (IsEmptySet() || IsFullSet()) {
            return false
        }
        return lower.UVal() > upper.UVal() && !upper.IsZero()
    }

    public func IsUpperWrapped(): Bool {
        if (IsEmptySet() || IsFullSet()) {
            return false
        }
        return lower.UVal() > upper.UVal() || upper.IsZero()
    }

    public func IsSignWrappedSet(): Bool {
        if (IsEmptySet() || IsFullSet()) {
            return false
        }
        return lower.SVal() > upper.SVal() && !upper.IsSMinValue()
    }

    public func IsUpperSignWrapped(): Bool {
        if (IsEmptySet() || IsFullSet()) {
            return false
        }
        return lower.SVal() > upper.SVal() || upper.IsSMinValue()
    }

    public func Contains(value: SInt): Bool {
        if (IsFullSet()) {
            return true
        }
        if (IsEmptySet() || value.Width() != Width()) {
            return false
        }
        let candidate = value.UVal()
        let low = lower.UVal()
        let high = upper.UVal()
        if (low < high) {
            return candidate >= low && candidate < high
        }
        return candidate >= low || candidate < high
    }

    public func GetSingleElement(): SInt {
        return lower
    }

    public func IsSingleElement(): Bool {
        if (IsEmptySet() || IsFullSet()) {
            return false
        }
        return lower.Add(SInt(Width(), 1)).IsSame(upper)
    }

    public func IsSizeStrictlySmallerThan(rhs: ConstantRange): Bool {
        return Size() < rhs.Size()
    }

    public func UMaxValue(): SInt {
        if (IsFullSet() || IsWrappedSet()) {
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
        if (IsFullSet() || IsSignWrappedSet()) {
            return SInt.SMaxValue(Width())
        }
        return MaxBySignedScan()
    }

    public func SMinValue(): SInt {
        if (IsFullSet() || IsSignWrappedSet()) {
            return SInt.SMinValue(Width())
        }
        return MinBySignedScan()
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

    public func Difference(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return this
        }
        if (rhs.IsFullSet()) {
            return ConstantRange.Empty(Width())
        }
        if (!rhs.Contains(lower)) {
            return this
        }
        var candidate = lower
        while (Contains(candidate) && rhs.Contains(candidate)) {
            candidate = candidate.Add(SInt(Width(), 1))
            if (candidate.IsSame(upper)) {
                return ConstantRange.Empty(Width())
            }
        }
        return ConstantRange(candidate, upper)
    }

    public func IntersectWith(rhs: ConstantRange,
        preferredType!: PreferredRangeType = PreferredRangeType.SMALLEST): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        if (IsFullSet()) {
            return rhs
        }
        if (rhs.IsFullSet()) {
            return this
        }
        var found = false
        var newLower = SInt.Zero(Width())
        var newUpper = SInt.Zero(Width())
        var current = if (preferredType == PreferredRangeType.SIGNED) {
            SInt.SMinValue(Width())
        } else {
            SInt.Zero(Width())
        }
        var visited: Int64 = 0
        while (visited < DomainSize(Width())) {
            if (Contains(current) && rhs.Contains(current)) {
                if (!found) {
                    newLower = current
                    found = true
                }
                newUpper = current.Add(SInt(Width(), 1))
            } else if (found) {
                break
            }
            current = current.Add(SInt(Width(), 1))
            visited++
        }
        if (!found) {
            return ConstantRange.Empty(Width())
        }
        return ConstantRange(newLower, newUpper)
    }

    public func UnionWith(rhs: ConstantRange,
        preferredType!: PreferredRangeType = PreferredRangeType.SMALLEST): ConstantRange {
        if (IsFullSet() || rhs.IsEmptySet()) {
            return this
        }
        if (rhs.IsFullSet() || IsEmptySet()) {
            return rhs
        }
        let useSigned = preferredType == PreferredRangeType.SIGNED
        let low = if (RangeLessOrEqual(lower, rhs.lower, useSigned)) { lower } else { rhs.lower }
        let high = if (RangeGreaterOrEqual(upper, rhs.upper, useSigned)) { upper } else { rhs.upper }
        return ConstantRange.NonEmpty(low, high)
    }

    public func Add(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        if (IsSingleElement() && rhs.IsSingleElement()) {
            return ConstantRange(lower.Add(rhs.lower))
        }
        return ConstantRange.Full(Width())
    }

    public func Sub(rhs: ConstantRange): ConstantRange {
        if (IsEmptySet() || rhs.IsEmptySet()) {
            return ConstantRange.Empty(Width())
        }
        if (IsSingleElement() && rhs.IsSingleElement()) {
            return ConstantRange(lower.Sub(rhs.lower))
        }
        return ConstantRange.Full(Width())
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

    private func Size(): Int64 {
        if (IsEmptySet()) {
            return 0
        }
        if (IsFullSet()) {
            return DomainSize(Width())
        }
        let low = lower.UVal()
        let high = upper.UVal()
        if (low < high) {
            return high - low
        }
        return DomainSize(Width()) - low + high
    }

    private func MaxBySignedScan(): SInt {
        var current = lower
        var best = lower
        var visited: Int64 = 0
        while (visited < Size()) {
            if (Contains(current) && current.SVal() > best.SVal()) {
                best = current
            }
            current = current.Add(SInt(Width(), 1))
            visited++
        }
        return best
    }

    private func MinBySignedScan(): SInt {
        var current = lower
        var best = lower
        var visited: Int64 = 0
        while (visited < Size()) {
            if (Contains(current) && current.SVal() < best.SVal()) {
                best = current
            }
            current = current.Add(SInt(Width(), 1))
            visited++
        }
        return best
    }
}

private func UnsignedConstraint(rel: RelationalOperation, value: SInt): ConstantRange {
    let width = value.Width()
    return match (rel) {
        case RelationalOperation.LT => ConstantRange.NonEmpty(SInt.UMinValue(width), value)
        case RelationalOperation.LE => ConstantRange.NonEmpty(SInt.UMinValue(width), value.Add(SInt(width, 1)))
        case RelationalOperation.GT => ConstantRange.NonEmpty(value.Add(SInt(width, 1)), SInt.Zero(width))
        case RelationalOperation.GE => ConstantRange.NonEmpty(value, SInt.Zero(width))
        case _ => ConstantRange.Full(width)
    }
}

private func SignedConstraint(rel: RelationalOperation, value: SInt): ConstantRange {
    let width = value.Width()
    return match (rel) {
        case RelationalOperation.LT => ConstantRange.NonEmpty(SInt.SMinValue(width), value)
        case RelationalOperation.LE => ConstantRange.NonEmpty(SInt.SMinValue(width), value.Add(SInt(width, 1)))
        case RelationalOperation.GT => ConstantRange.NonEmpty(value.Add(SInt(width, 1)), SInt.SMinValue(width))
        case RelationalOperation.GE => ConstantRange.NonEmpty(value, SInt.SMinValue(width))
        case _ => ConstantRange.Full(width)
    }
}

private func DomainSize(width: IntWidth): Int64 {
    if (width == IntWidth.I64) {
        return 9223372036854775807
    }
    var out: Int64 = 1
    var idx: Int64 = 0
    while (idx < IntWidthBits(width)) {
        out *= 2
        idx++
    }
    return out
}

private func RangeLessOrEqual(left: SInt, right: SInt, useSigned: Bool): Bool {
    return if (useSigned) { left.SVal() <= right.SVal() } else { left.UVal() <= right.UVal() }
}

private func RangeGreaterOrEqual(left: SInt, right: SInt, useSigned: Bool): Bool {
    return if (useSigned) { left.SVal() >= right.SVal() } else { left.UVal() >= right.UVal() }
}
