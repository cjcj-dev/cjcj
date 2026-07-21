package cjcj::sema.CJMP

import cjcj::ast.*
import cjcj::sema.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.Position as BasicPosition
import cjcj::basic.Range as BasicRange
import cjcj::utils.CJC_ASSERT_WITH_MSG

private func ToBasicPosition(pos: Position): BasicPosition {
    return BasicPosition(pos.fileID, pos.line, pos.column)
}

private func ToBasicRange(begin: Position, end: Position): BasicRange {
    var fixedEnd = end
    if (begin.fileID != end.fileID) {
        fixedEnd = begin + 1
    }
    return BasicRange(ToBasicPosition(begin), ToBasicPosition(fixedEnd))
}

private func IdentifierRange(identifier: SrcIdentifier): BasicRange {
    return ToBasicRange(identifier.GetRawPos(), identifier.GetRawEndPos())
}

private func HasDefaultArgument(param: FuncParam): Bool {
    return param.isNamedParam && param.TestAttr(Attribute.HAS_INITIAL)
}

private func CloneDefaultArgument(from: FuncParam, to: FuncParam, toFunc: FuncDecl): Unit {
    CJC_ASSERT_WITH_MSG(to.desugarDecl.isNone(), "The specific decl shouldn't have desugarDecl")
    CJC_ASSERT_WITH_MSG(to.assignment.isNone(), "The specific decl shouldn't have assignment expression")
    CJC_ASSERT_WITH_MSG(from.desugarDecl.isSome(), "The common decl must have desugarDecl")
    let defaultDecl = from.desugarDecl.getOrThrow()
    let clonedDecl = (ASTCloner.Clone(defaultDecl) as FuncDecl).getOrThrow()
    clonedDecl.begin = defaultDecl.begin
    clonedDecl.end = defaultDecl.end
    clonedDecl.outerDecl = toFunc.outerDecl
    to.desugarDecl = clonedDecl
    if (let Some(assignment) <- from.assignment) {
        let clonedAssignment = (ASTCloner.Clone(assignment) as Expr).getOrThrow()
        to.assignment = clonedAssignment
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
                let builder = DiagnoseRefactor(
                    diag, BasicDiagKindRefactor.sema_specific_has_different_parameter, specificParam)
                builder.Emit()
                return false
            }
            if (commonParam.isNamedParam && specificParam.isNamedParam &&
                commonParam.identifier.GetRawText() != specificParam.identifier.GetRawText()) {
                let builder = DiagnoseRefactor(
                    diag, BasicDiagKindRefactor.sema_specific_has_different_parameter, specificParam)
                builder.Emit()
                return false
            }
            if (commonParam.isMemberParam != specificParam.isMemberParam) {
                let builder = DiagnoseRefactor(
                    diag, BasicDiagKindRefactor.sema_specific_primary_unmatched_var_decl, specificParam)
                builder.Emit()
                return false
            }
        }
        return true
    }

    public func MatchCJMPFunctionParameters(specificFunc: FuncDecl, commonFunc: FuncDecl): Bool {
        let commonGenericsCount = commonFunc.GetGenericsCount()
        let specificGenericsCount = specificFunc.GetGenericsCount()
        if (commonGenericsCount != specificGenericsCount) {
            let builder = Diagnose(
                diag,
                specificFunc,
                BasicDiagKind.sema_generic_member_type_argument_different,
                args: [BasicDiagArgument(specificFunc.identifier.Val())])
            builder.Emit()
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
        CheckCommonSpecificGenericMatch(specificDecl, commonDecl)
        if (commonDecl.GetGenericsCount() != specificDecl.GetGenericsCount()) {
            return
        }
        let mapping = typeManager.GenerateGenericMappingFromGeneric(commonDecl, specificDecl)
        var mapIdx: Int64 = 0
        while (mapIdx < mapping.entries.size) {
            let tyVar = mapping.entries.KeyAt(mapIdx)
            let ty = mapping.entries.ValueAt(mapIdx)
            if (!genericTyMap.Contains(tyVar.value)) {
                genericTyMap.Put(tyVar.value, ty)
            }
            mapIdx++
        }
    }

    public func PropagateDefaultArguments(commonParams: FuncParamList, specificParams: FuncParamList,
        specificFunc: FuncDecl): Unit {
        CJC_ASSERT_WITH_MSG(commonParams.params.size == specificParams.params.size,
            "Matched param lists must have the same size")
        for (idx in 0..commonParams.params.size) {
            let specificParam = specificParams.params[idx]
            if (!specificParam.isNamedParam) {
                continue
            }
            let commonParam = commonParams.params[idx]
            if (HasDefaultArgument(commonParam) && HasDefaultArgument(specificParam)) {
                let builder = diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.sema_cjmp_parameter_default_value_both_sides,
                    IdentifierRange(specificParam.identifier))
                builder.Emit()
                continue
            }
            if (HasDefaultArgument(commonParam)) {
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
