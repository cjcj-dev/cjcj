package cangjie_compiler::sema

import cangjie_compiler::ast.*

public func IsInvalidTy(ty: Option<Ty>): Bool {
    if (let Some(value) <- ty) {
        return value.HasInvalidTy()
    }
    return true
}

public func IsInvalidNode(node: Node): Bool {
    return node.IsInvalid() || IsInvalidTy(node.GetTy())
}
