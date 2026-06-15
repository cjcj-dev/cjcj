package cangjie_compiler::sema

import cangjie_compiler::ast.*

public func Join(tm: TypeManager, lhs: Ty, rhs: Ty): Ty {
    if (tm.IsSubtype(lhs, rhs)) {
        return rhs
    }
    if (tm.IsSubtype(rhs, lhs)) {
        return lhs
    }
    return tm.GetUnionTy([lhs, rhs])
}

public func Meet(tm: TypeManager, lhs: Ty, rhs: Ty): Ty {
    if (tm.IsSubtype(lhs, rhs)) {
        return lhs
    }
    if (tm.IsSubtype(rhs, lhs)) {
        return rhs
    }
    return tm.GetIntersectionTy([lhs, rhs])
}
