package cangjie_compiler::sema

import cangjie_compiler::ast.*

public func CheckTypeCompatible(tm: TypeManager, lvalue: Ty, rvalue: Ty): TypeCompatibility {
    return tm.CheckTypeCompatibility(lvalue, rvalue)
}
