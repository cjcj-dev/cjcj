package cjcj::sema

import cjcj::ast.*

public func BeginTyVarScope(typeManager: TypeManager): TyVarScope {
    return TyVarScope(typeManager)
}

public func EndTyVarScope(scope: TyVarScope): Unit {
    scope.Close()
}

public func BeginInstCtxScope(typeManager: TypeManager): InstCtxScope {
    return InstCtxScope(typeManager)
}

public func EndInstCtxScope(scope: InstCtxScope): Unit {
    scope.Close()
}

public func SetInstCtxRefDecl(scope: InstCtxScope, decl: Decl, instTy: Ty): Unit {
    scope.SetRefDecl(decl, instTy)
}
