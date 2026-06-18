package cangjie_compiler::chir

public enum ExpressionFlatSetKind {
    | BOTTOM | ELEM | TOP
}

public func ExpressionFlatSetKindIndex(kind: ExpressionFlatSetKind): Int64 {
    return match (kind) {
        case ExpressionFlatSetKind.BOTTOM => 0
        case ExpressionFlatSetKind.ELEM => 1
        case ExpressionFlatSetKind.TOP => 2
    }
}

extend ExpressionFlatSetKind <: Equatable<ExpressionFlatSetKind> {
    public operator func ==(right: ExpressionFlatSetKind): Bool {
        return ExpressionFlatSetKindIndex(this) == ExpressionFlatSetKindIndex(right)
    }

    public operator func !=(right: ExpressionFlatSetKind): Bool {
        return !(this == right)
    }
}

public class ExpressionFlatSet {
    private var kind: ExpressionFlatSetKind = ExpressionFlatSetKind.BOTTOM
    private var elem: Option<Expression> = None

    public init(isTop!: Bool = false) {
        if (isTop) {
            kind = ExpressionFlatSetKind.TOP
        }
    }

    public init(kind: ExpressionFlatSetKind, elem: Option<Expression>) {
        this.kind = kind
        this.elem = elem
    }

    public func Clone(): ExpressionFlatSet {
        return ExpressionFlatSet(kind, elem)
    }

    public func IsTop(): Bool {
        return kind == ExpressionFlatSetKind.TOP
    }

    public func IsBottom(): Bool {
        return kind == ExpressionFlatSetKind.BOTTOM
    }

    public func HasElem(): Bool {
        return kind == ExpressionFlatSetKind.ELEM && elem.isSome()
    }

    public func GetElem(): Option<Expression> {
        if (HasElem()) {
            return elem
        }
        return None
    }

    public func SetToBound(isTop!: Bool): Unit {
        kind = if (isTop) { ExpressionFlatSetKind.TOP } else { ExpressionFlatSetKind.BOTTOM }
        elem = None
    }

    public func UpdateElem(value: Expression): Unit {
        kind = ExpressionFlatSetKind.ELEM
        elem = value
    }

    public func Join(rhs: ExpressionFlatSet): Bool {
        if (kind == ExpressionFlatSetKind.TOP || rhs.kind == ExpressionFlatSetKind.BOTTOM) {
            return false
        }
        if (rhs.kind == ExpressionFlatSetKind.TOP) {
            SetToBound(isTop: true)
            return true
        }
        if (kind == ExpressionFlatSetKind.BOTTOM) {
            kind = rhs.kind
            elem = rhs.elem
            return rhs.kind != ExpressionFlatSetKind.BOTTOM
        }
        if (let Some(leftExpr) <- elem) {
            if (let Some(rightExpr) <- rhs.elem) {
                if (leftExpr.nodeId == rightExpr.nodeId) {
                    return false
                }
            }
        }
        SetToBound(isTop: true)
        return true
    }

    public func ToString(): String {
        if (kind == ExpressionFlatSetKind.TOP) {
            return "top"
        }
        if (kind == ExpressionFlatSetKind.BOTTOM) {
            return "bottom"
        }
        if (let Some(value) <- elem) {
            return value.ToString(0)
        }
        return "bottom"
    }
}
