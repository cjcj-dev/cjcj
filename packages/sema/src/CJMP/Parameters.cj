package cangjie_compiler::sema.CJMP

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private func HasDefaultArgument(param: FuncParam): Bool {
    return param.isNamedParam && param.TestAttr(Attribute.HAS_INITIAL)
}

private func CloneDefaultArgument(from: FuncParam, to: FuncParam, toFunc: FuncDecl): Unit {
    if (let Some(defaultDecl) <- from.desugarDecl) {
        if (let Some(clonedDecl) <- (ASTCloner.Clone(defaultDecl) as FuncDecl)) {
            clonedDecl.begin = defaultDecl.begin
            clonedDecl.end = defaultDecl.end
            clonedDecl.outerDecl = toFunc.outerDecl
            to.desugarDecl = clonedDecl
        }
    }
    if (let Some(assignment) <- from.assignment) {
        if (let Some(clonedAssignment) <- (ASTCloner.Clone(assignment) as Expr)) {
            to.assignment = clonedAssignment
        }
    }
    to.EnableAttr(Attribute.HAS_INITIAL)
}

private func CompatibleParamListShape(commonFunc: FuncDecl, specificFunc: FuncDecl): Bool {
    if (let Some(commonBody) <- commonFunc.funcBody) {
        if (let Some(specificBody) <- specificFunc.funcBody) {
            return commonBody.paramLists.size == specificBody.paramLists.size
        }
    }
    return false
}

extend MPTypeCheckerImpl {
    public func MatchCJMPFunctionParameters(specificParams: FuncParamList, commonParams: FuncParamList): Bool {
        if (commonParams.params.size != specificParams.params.size) {
            return false
        }
        for (idx in 0..commonParams.params.size) {
            let commonParam = commonParams.params[idx]
            let specificParam = specificParams.params[idx]
            if (commonParam.isNamedParam != specificParam.isNamedParam) {
                return false
            }
            if (commonParam.isNamedParam && specificParam.isNamedParam &&
                commonParam.identifier.GetRawText() != specificParam.identifier.GetRawText()) {
                return false
            }
            if (commonParam.isMemberParam != specificParam.isMemberParam) {
                return false
            }
        }
        return true
    }

    public func MatchCJMPFunctionParameters(specificFunc: FuncDecl, commonFunc: FuncDecl): Bool {
        let commonGenericsCount = commonFunc.GetGenericsCount()
        let specificGenericsCount = specificFunc.GetGenericsCount()
        if (commonGenericsCount != specificGenericsCount) {
            return false
        }
        if (commonGenericsCount > 0) {
            if (!MatchCJMPFunctionGenerics(specificFunc, commonFunc)) {
                return false
            }
        } else if (!typeManager.IsFuncDeclSubType(specificFunc, commonFunc)) {
            return false
        }

        if (!CompatibleParamListShape(commonFunc, specificFunc)) {
            return false
        }
        if (let Some(commonBody) <- commonFunc.funcBody) {
            if (let Some(specificBody) <- specificFunc.funcBody) {
                for (idx in 0..commonBody.paramLists.size) {
                    if (!MatchCJMPFunctionParameters(specificBody.paramLists[idx], commonBody.paramLists[idx])) {
                        return false
                    }
                }
                return true
            }
        }
        return false
    }

    public func MatchCJMPFunctionGenerics(specificFunc: FuncDecl, commonFunc: FuncDecl): Bool {
        let genericTyMap = TypeSubst()
        MapCJMPGenericTypeArgs(genericTyMap, commonFunc, specificFunc)
        if (genericTyMap.IsEmpty()) {
            return true
        }
        if (let Some(commonTy) <- commonFunc.GetTy()) {
            if (let Some(specificTy) <- specificFunc.GetTy()) {
                if (let Some(newCommonFuncTy) <- (typeManager.GetInstantiatedTy(commonTy, genericTyMap) as FuncTy)) {
                    if (let Some(specificFuncTy) <- (specificTy as FuncTy)) {
                        return typeManager.IsFuncTySubType(specificFuncTy, newCommonFuncTy)
                    }
                }
            }
        }
        return false
    }

    public func MapCJMPGenericTypeArgs(genericTyMap: TypeSubst, commonDecl: Decl, specificDecl: Decl): Unit {
        if (!(commonDecl.TestAttr(Attribute.GENERIC) && specificDecl.TestAttr(Attribute.GENERIC))) {
            return
        }
        if (commonDecl.IsNominalDecl()) {
            if (let Some(commonTy) <- commonDecl.GetTy()) {
                if (let Some(specificTy) <- specificDecl.GetTy()) {
                    if (commonTy.typeArgs.size == specificTy.typeArgs.size) {
                        for (idx in 0..commonTy.typeArgs.size) {
                            if (let Some(commonGeneric) <- (commonTy.typeArgs[idx] as GenericsTy)) {
                                genericTyMap.Put(commonGeneric, specificTy.typeArgs[idx])
                            }
                        }
                    }
                }
            }
        }
        if (commonDecl.GetGenericsCount() != specificDecl.GetGenericsCount()) {
            return
        }
        let mapping = typeManager.GenerateGenericMappingFromGeneric(commonDecl, specificDecl)
        for (entry in mapping.entries) {
            if (!genericTyMap.Contains(entry.tyVar)) {
                genericTyMap.Put(entry.tyVar, entry.ty)
            }
        }
    }

    public func PropagateDefaultArguments(commonParams: FuncParamList, specificParams: FuncParamList,
        specificFunc: FuncDecl): Unit {
        if (commonParams.params.size != specificParams.params.size) {
            return
        }
        for (idx in 0..commonParams.params.size) {
            let specificParam = specificParams.params[idx]
            if (!specificParam.isNamedParam) {
                continue
            }
            let commonParam = commonParams.params[idx]
            if (HasDefaultArgument(commonParam) && !HasDefaultArgument(specificParam)) {
                CloneDefaultArgument(commonParam, specificParam, specificFunc)
            }
        }
    }

    public func PropagateDefaultArguments(commonFunc: FuncDecl, specificFunc: FuncDecl): Unit {
        if (!CompatibleParamListShape(commonFunc, specificFunc)) {
            return
        }
        if (let Some(commonBody) <- commonFunc.funcBody) {
            if (let Some(specificBody) <- specificFunc.funcBody) {
                for (idx in 0..commonBody.paramLists.size) {
                    PropagateDefaultArguments(commonBody.paramLists[idx], specificBody.paramLists[idx], specificFunc)
                }
            }
        }
    }
}
