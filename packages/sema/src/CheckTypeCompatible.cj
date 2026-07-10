package cjcj::sema

import cjcj::ast.*

public enum ComparisonRes {
    | LT
    | GT
    | EQ
}

private func ComparisonResIndex(value: ComparisonRes): Int64 {
    return match (value) {
        case ComparisonRes.LT => 0
        case ComparisonRes.GT => 1
        case ComparisonRes.EQ => 2
    }
}

extend ComparisonRes <: Equatable<ComparisonRes> {
    public operator func ==(right: ComparisonRes): Bool {
        return ComparisonResIndex(this) == ComparisonResIndex(right)
    }

    public operator func !=(right: ComparisonRes): Bool {
        return !(this == right)
    }
}

public func CheckTypeCompatible(tm: TypeManager, lvalue: Ty, rvalue: Ty): TypeCompatibility {
    return tm.CheckTypeCompatibility(lvalue, rvalue)
}

public func CompareIntAndFloat(left: Ty, right: Ty): ComparisonRes {
    if (left.kind == right.kind) {
        return ComparisonRes.EQ
    }
    if (left.IsInteger()) {
        if (right.IsInteger()) {
            if (left.kind == TypeKind.TYPE_INT64) {
                return ComparisonRes.LT
            }
            if (right.kind == TypeKind.TYPE_INT64) {
                return ComparisonRes.GT
            }
        } else {
            return ComparisonRes.LT
        }
    } else {
        if (right.IsInteger()) {
            return ComparisonRes.GT
        }
        if (left.kind == TypeKind.TYPE_FLOAT64) {
            return ComparisonRes.LT
        }
        if (right.kind == TypeKind.TYPE_FLOAT64) {
            return ComparisonRes.GT
        }
    }
    return ComparisonRes.EQ
}
