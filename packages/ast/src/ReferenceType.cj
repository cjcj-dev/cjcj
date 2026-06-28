package cangjie_compiler::ast

@When[backend == "cjnative"]
public func IsReferenceType(ty: Ty): Bool {
    var isRefOption = false
    if (ty.IsCoreOptionType()) {
        let enumTy = (ty as EnumTy).getOrThrow()
        let elemTy = enumTy.typeArgs[0]
        isRefOption = IsReferenceType(elemTy) && !elemTy.IsCoreOptionType()
    }
    return ty.IsClassLike() || ty.IsArray() || isRefOption
}
