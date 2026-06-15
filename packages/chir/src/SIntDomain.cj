package cangjie_compiler::chir

import std.collection.*

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
        if (!numeric.IsSame(domain.numeric) || unsignedFlag != domain.unsignedFlag ||
            symbolics.size != domain.symbolics.size) {
            return false
        }
        for (bound in symbolics) {
            if (let Some(otherBound) <- domain.FindSymbolicBound(bound.symbol)) {
                if (!bound.bound.IsSame(otherBound)) {
                    return false
                }
            } else {
                return false
            }
        }
        return true
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

    public func ToString(asUnsigned!: Bool = unsignedFlag, radix!: Radix = Radix.R10): String {
        if (symbolics.isEmpty()) {
            return numeric.ToString(asUnsigned: asUnsigned, radix: radix)
        }
        var out = "|" + numeric.ToString(asUnsigned: asUnsigned, radix: radix)
        for (bound in symbolics) {
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
    public let isUnsigned: Bool

    public init(left: SIntDomain, right: SIntDomain, isUnsigned: Bool) {
        this.left = left
        this.right = right
        this.isUnsigned = isUnsigned
    }
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

private func IsUnsignedSymbol(symbol: Value): Bool {
    if (let Some(ty) <- symbol.GetType()) {
        return ty.IsUnsignedInteger()
    }
    return false
}
