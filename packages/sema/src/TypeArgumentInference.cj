package cangjie_compiler::sema

import cangjie_compiler::ast.*

public func InferIdentityTypeArguments(decl: Decl): TypeSubst {
    let out = TypeSubst()
    if (let Some(generic) <- decl.GetGeneric()) {
        for (param in generic.typeParameters) {
            if (let Some(paramTy) <- param.GetTy()) {
                if (let Some(genTy) <- (paramTy as GenericsTy)) {
                    out.Put(genTy, genTy)
                }
            }
        }
    }
    return out
}
