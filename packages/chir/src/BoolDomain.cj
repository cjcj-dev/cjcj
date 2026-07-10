package cjcj::chir

public enum BoolDomainKind {
    | BOTTOM | FALSE | TRUE | TOP
}

public func BoolDomainKindIndex(kind: BoolDomainKind): Int64 {
    return match (kind) {
        case BoolDomainKind.BOTTOM => 0
        case BoolDomainKind.FALSE => 1
        case BoolDomainKind.TRUE => 2
        case BoolDomainKind.TOP => 3
    }
}

extend BoolDomainKind <: Equatable<BoolDomainKind> {
    public operator func ==(right: BoolDomainKind): Bool {
        return BoolDomainKindIndex(this) == BoolDomainKindIndex(right)
    }

    public operator func !=(right: BoolDomainKind): Bool {
        return !(this == right)
    }
}

public struct BoolDomain {
    private let value: BoolDomainKind

    public init(kind: BoolDomainKind) {
        value = kind
    }

    public static func True(): BoolDomain { return BoolDomain(BoolDomainKind.TRUE) }
    public static func False(): BoolDomain { return BoolDomain(BoolDomainKind.FALSE) }
    public static func Top(): BoolDomain { return BoolDomain(BoolDomainKind.TOP) }
    public static func Bottom(): BoolDomain { return BoolDomain(BoolDomainKind.BOTTOM) }
    public static func FromBool(v: Bool): BoolDomain {
        return if (v) { BoolDomain.True() } else { BoolDomain.False() }
    }

    public func IsTrue(): Bool { return value == BoolDomainKind.TRUE }
    public func IsFalse(): Bool { return value == BoolDomainKind.FALSE }
    public func IsTop(): Bool { return value == BoolDomainKind.TOP }
    public func IsBottom(): Bool { return value == BoolDomainKind.BOTTOM }
    public func IsNonTrivial(): Bool { return !IsTop() }
    public func IsSingleValue(): Bool { return IsTrue() || IsFalse() }
    public func GetSingleValue(): Bool { return IsTrue() }
    public func GetKind(): BoolDomainKind { return value }

    public func LogicalAnd(other: BoolDomain): BoolDomain {
        if (IsBottom() || other.IsBottom()) {
            return BoolDomain.Bottom()
        }
        if (IsFalse() || other.IsFalse()) {
            return BoolDomain.False()
        }
        if (IsTrue() && other.IsTrue()) {
            return BoolDomain.True()
        }
        return BoolDomain.Top()
    }

    public func LogicalOr(other: BoolDomain): BoolDomain {
        if (IsBottom() || other.IsBottom()) {
            return BoolDomain.Bottom()
        }
        if (IsTrue() || other.IsTrue()) {
            return BoolDomain.True()
        }
        if (IsFalse() && other.IsFalse()) {
            return BoolDomain.False()
        }
        return BoolDomain.Top()
    }

    public func BitAnd(other: BoolDomain): BoolDomain {
        return BoolDomain(BoolDomainKindFromIndex(BoolDomainKindIndex(value) & BoolDomainKindIndex(other.value)))
    }

    public func BitOr(other: BoolDomain): BoolDomain {
        return BoolDomain(BoolDomainKindFromIndex(BoolDomainKindIndex(value) | BoolDomainKindIndex(other.value)))
    }

    public func LogicalNot(): BoolDomain {
        if (IsBottom()) {
            return BoolDomain.Bottom()
        }
        if (IsTrue()) {
            return BoolDomain.False()
        }
        if (IsFalse()) {
            return BoolDomain.True()
        }
        return BoolDomain.Top()
    }

    public static func Union(left: BoolDomain, right: BoolDomain): BoolDomain {
        return left.BitOr(right)
    }

    public func IsSame(other: BoolDomain): Bool {
        return value == other.value
    }

    public func ToString(): String {
        return match (value) {
            case BoolDomainKind.BOTTOM => "<>"
            case BoolDomainKind.FALSE => "false"
            case BoolDomainKind.TRUE => "true"
            case BoolDomainKind.TOP => "<t,f>"
        }
    }
}

private func BoolDomainKindFromIndex(index: Int64): BoolDomainKind {
    return match (index) {
        case 0 => BoolDomainKind.BOTTOM
        case 1 => BoolDomainKind.FALSE
        case 2 => BoolDomainKind.TRUE
        case _ => BoolDomainKind.TOP
    }
}
