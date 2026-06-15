package cangjie_compiler::sema

import cangjie_compiler::ast.*

public func Promote(tm: TypeManager, ty: Ty, target: Ty): Ty {
    if (tm.IsSubtype(ty, target)) {
        return target
    }
    return ty
}
