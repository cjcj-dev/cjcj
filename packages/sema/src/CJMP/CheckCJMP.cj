package cangjie_compiler::sema.CJMP

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange

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

private func NodeRange(node: Node): BasicRange {
    return ToBasicRange(node.begin, node.end)
}

private func IsCommon(node: Node): Bool {
    return node.TestAttr(Attribute.COMMON)
}

private func IsEnumConstructor(node: Node): Bool {
    return node.TestAttr(Attribute.ENUM_CONSTRUCTOR)
}

private func NeedToReportMissingBody(common: Decl, specific: Decl): Bool {
    if (let Some(_) <- common.outerDecl) {
        return common.TestAttr(Attribute.COMMON_WITH_DEFAULT) && !common.TestAttr(Attribute.ABSTRACT) &&
            specific.TestAttr(Attribute.ABSTRACT)
    }
    return false
}

private func IsConstructor(funcDecl: FuncDecl): Bool {
    return funcDecl.TestAttr(Attribute.CONSTRUCTOR)
}

private func IsPrimaryConstructor(funcDecl: FuncDecl): Bool {
    return funcDecl.TestAttr(Attribute.PRIMARY_CONSTRUCTOR)
}

private func FunctionReturnTy(funcDecl: FuncDecl): Option<Ty> {
    if (let Some(ty) <- funcDecl.GetTy()) {
        if (let Some(funcTy) <- (ty as FuncTy)) {
            return Some(funcTy.retTy)
        }
    }
    if (let Some(body) <- funcDecl.funcBody) {
        if (let Some(ty) <- body.GetTy()) {
            if (let Some(funcTy) <- (ty as FuncTy)) {
                return Some(funcTy.retTy)
            }
        }
    }
    return None
}

private func DeclInfo(decl: Decl): String {
    if (decl.astKind == ASTKind.FUNC_DECL && decl.TestAttr(Attribute.CONSTRUCTOR)) {
        return "constructor"
    }
    if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
        if (let Some(outer) <- decl.outerDecl) {
            return "enum '" + outer.identifier.GetRawText() + "' constructor '" + decl.identifier.GetRawText() + "'"
        }
    }
    if (decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
        return "variable with pattern"
    }
    return DeclKindToString(decl) + " '" + decl.identifier.GetRawText() + "'"
}

private func DiagNotMatchedDecl(checker: MPTypeCheckerImpl, decl: Decl, left: String, right: String): Unit {
    let builder = checker.diag.DiagnoseRefactor(
        BasicDiagKindRefactor.sema_not_matched,
        NodeRange(decl),
        arguments: [left, DeclInfo(decl), right])
    builder.Emit()
}

private func DiagNotMatchedSpecificDecl(checker: MPTypeCheckerImpl, decl: Decl): Unit {
    DiagNotMatchedDecl(checker, decl, "common", "specific")
}

extend MPTypeCheckerImpl {
    public func RemoveCommonCandidatesIfHasSpecific(candidates: ArrayList<FuncDecl>): Unit {
        var idx: Int64 = 0
        while (idx < candidates.size) {
            let candidate = candidates[idx]
            var shouldRemove = false
            if (candidate.TestAttr(Attribute.COMMON)) {
                if (let Some(specificImpl) <- candidate.specificImplementation) {
                    for (other in candidates) {
                        if (SameDecl(other, specificImpl)) {
                            shouldRemove = true
                            break
                        }
                    }
                }
            }
            if (shouldRemove) {
                candidates.remove(at: idx)
            } else {
                idx++
            }
        }
    }

    public func IsCJMPDeclMatchable(leftDecl: Decl, rightDecl: Decl): Bool {
        let commonDecl = if (leftDecl.TestAttr(Attribute.COMMON)) { leftDecl } else { rightDecl }
        let specificDecl = if (leftDecl.TestAttr(Attribute.COMMON)) { rightDecl } else { leftDecl }
        if (commonDecl.identifier.GetRawText() != specificDecl.identifier.GetRawText()) {
            return false
        }
        if (specificDecl.IsMemberDecl() != commonDecl.IsMemberDecl()) {
            return false
        }
        if (specificDecl.IsMemberDecl()) {
            if (let Some(specificOuter) <- specificDecl.outerDecl) {
                if (let Some(commonOuter) <- commonDecl.outerDecl) {
                    if (specificOuter.rawMangleName != commonOuter.rawMangleName) {
                        return false
                    }
                } else {
                    return false
                }
            } else {
                return false
            }
        }
        return leftDecl.GetGenericsCount() == rightDecl.GetGenericsCount()
    }

    public func TrySetSpecificImpl(specificDecl: Decl, commonDecl: Decl, kind: String): Bool {
        if (let Some(_) <- commonDecl.specificImplementation) {
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_multiple_common_implementations,
                NodeRange(commonDecl),
                arguments: [kind])
            builder.Emit()
            return false
        }
        if (NeedToReportMissingBody(commonDecl, specificDecl)) {
            var outerName = ""
            if (let Some(outer) <- commonDecl.outerDecl) {
                outerName = outer.identifier.Val()
            }
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_specific_member_must_have_implementation,
                NodeRange(specificDecl),
                arguments: [specificDecl.identifier.Val(), outerName])
            builder.Emit()
            return false
        }
        commonDecl.specificImplementation = specificDecl
        commonDecl.doNotExport = true
        return true
    }

    public func MatchCJMPFunction(specificFunc: FuncDecl, commonFunc: FuncDecl): Bool {
        if (!IsCJMPDeclMatchable(specificFunc, commonFunc)) {
            return false
        }
        if (!MatchCJMPFunctionParameters(specificFunc, commonFunc)) {
            return false
        }
        if ((IsConstructor(specificFunc) || IsConstructor(commonFunc)) &&
            !IsPrimaryConstructor(specificFunc) && IsPrimaryConstructor(commonFunc)) {
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_specific_init_common_primary_constructor,
                NodeRange(commonFunc))
            builder.Emit()
            return false
        }
        return TrySetSpecificImpl(specificFunc, commonFunc, "function")
    }

    public func MatchCJMPProp(specificProp: PropDecl, commonProp: PropDecl): Bool {
        if (!IsCJMPDeclMatchable(specificProp, commonProp)) {
            return false
        }
        if (let Some(specificTy) <- specificProp.GetTy()) {
            if (let Some(commonTy) <- commonProp.GetTy()) {
                if (!typeManager.IsTyEqual(specificTy, commonTy)) {
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_specific_has_different_type,
                        NodeRange(specificProp),
                        arguments: ["property"])
                    builder.Emit()
                }
            }
        }
        var ret = TrySetSpecificImpl(specificProp, commonProp, "property " + specificProp.identifier.Val())
        if (ret && !specificProp.getters.isEmpty() && !commonProp.getters.isEmpty()) {
            ret = TrySetSpecificImpl(
                specificProp.getters[0], commonProp.getters[0], "property getter " + specificProp.identifier.Val()) &&
                ret
        }
        if (ret && !specificProp.setters.isEmpty() && !commonProp.setters.isEmpty()) {
            ret = TrySetSpecificImpl(
                specificProp.setters[0], commonProp.setters[0], "property setter " + specificProp.identifier.Val()) &&
                ret
        }
        return ret
    }

    public func MatchCJMPVar(specificVar: VarDecl, commonVar: VarDecl): Bool {
        if (!IsCJMPDeclMatchable(specificVar, commonVar)) {
            return false
        }
        var commonTy = commonVar.GetTy()
        if (specificVar.IsMemberDecl()) {
            if (let Some(commonOuter) <- commonVar.outerDecl) {
                if (let Some(specificOuter) <- specificVar.outerDecl) {
                    let genericTyMap = TypeSubst()
                    MapCJMPGenericTypeArgs(genericTyMap, commonOuter, specificOuter)
                    if (!genericTyMap.IsEmpty()) {
                        if (let Some(value) <- commonTy) {
                            commonTy = Some(typeManager.GetInstantiatedTy(value, genericTyMap))
                        }
                    }
                }
            }
        }
        if (let Some(specificTy) <- specificVar.GetTy()) {
            if (!Ty.IsInitialTy(Some(specificTy))) {
                if (let Some(value) <- commonTy) {
                    if (!typeManager.IsTyEqual(value, specificTy)) {
                        let specificKind = if (specificVar.isVar) { "var" } else { "let" }
                        let builder = diag.DiagnoseRefactor(
                            BasicDiagKindRefactor.sema_specific_has_different_type,
                            NodeRange(specificVar),
                            arguments: [specificKind])
                        builder.Emit()
                    }
                }
            }
        }
        if (specificVar.isVar != commonVar.isVar) {
            let specificKind = if (specificVar.isVar) { "var" } else { "let" }
            let commonKind = if (commonVar.isVar) { "var" } else { "let" }
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_specific_var_not_match_let,
                NodeRange(specificVar),
                arguments: [specificKind, commonKind])
            builder.Emit()
        }
        commonVar.specificImplementation = specificVar
        if (specificVar.IsStaticOrGlobal() || commonVar.TestAttr(Attribute.STATIC) != specificVar.TestAttr(Attribute.STATIC)) {
            commonVar.doNotExport = true
        }
        return true
    }

    public func CheckMatchedFunctionReturnTypes(specificFunc: FuncDecl, commonFunc: FuncDecl): Unit {
        if (let Some(commonRetTy) <- FunctionReturnTy(commonFunc)) {
            if (let Some(specificRetTy) <- FunctionReturnTy(specificFunc)) {
                var expectedTy = commonRetTy
                let genericTyMap = TypeSubst()
                MapCJMPGenericTypeArgs(genericTyMap, commonFunc, specificFunc)
                if (!genericTyMap.IsEmpty()) {
                    expectedTy = typeManager.GetInstantiatedTy(commonRetTy, genericTyMap)
                }
                if (typeManager.IsTyEqual(specificRetTy, expectedTy) ||
                    typeManager.IsSubtype(specificRetTy, expectedTy)) {
                    return
                }
                let builder = diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.sema_return_type_incompatible,
                    NodeRange(specificFunc),
                    arguments: [specificFunc.identifier.Val()])
                builder.Emit()
            }
        }
    }

    public func CheckMatchedVariableTypes(specificVar: VarDecl, commonVar: VarDecl): Unit {
        if (let Some(specificTy) <- specificVar.GetTy()) {
            if (Ty.IsInitialTy(Some(specificTy))) {
                return
            }
        }
        if (let Some(commonTy) <- commonVar.GetTy()) {
            if (let Some(specificTy) <- specificVar.GetTy()) {
                if (typeManager.IsTyEqual(specificTy, commonTy)) {
                    return
                }
            }
        }
        let _ = MatchCJMPVar(specificVar, commonVar)
    }

    public func CheckReturnAndVariableTypes(pkg: Package): Unit {
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (node.astKind == ASTKind.FUNC_DECL) {
                if (!IsCommon(node) || IsEnumConstructor(node)) {
                    return VisitAction.SKIP_CHILDREN
                }
                if (let Some(commonFunc) <- (node as FuncDecl)) {
                    if (let Some(specific) <- commonFunc.specificImplementation) {
                        if (let Some(specificFunc) <- (specific as FuncDecl)) {
                            CheckMatchedFunctionReturnTypes(specificFunc, commonFunc)
                        }
                    }
                }
                return VisitAction.SKIP_CHILDREN
            }
            if (node.astKind == ASTKind.VAR_DECL) {
                if (!IsCommon(node) || IsEnumConstructor(node)) {
                    return VisitAction.SKIP_CHILDREN
                }
                if (let Some(commonVar) <- (node as VarDecl)) {
                    if (let Some(specific) <- commonVar.specificImplementation) {
                        if (let Some(specificVar) <- (specific as VarDecl)) {
                            CheckMatchedVariableTypes(specificVar, commonVar)
                        }
                    } else if (!commonVar.TestAttr(Attribute.INITIALIZED) &&
                        commonVar.TestAttr(Attribute.FROM_COMMON_PART)) {
                        DiagNotMatchedSpecificDecl(this, commonVar)
                    }
                }
                return VisitAction.SKIP_CHILDREN
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    public func ValidateMatchedAnnotationsAndModifiers(pkg: Package): Unit {
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (node.IsDecl() && IsCommon(node)) {
                if (let Some(commonDecl) <- (node as Decl)) {
                    if (let Some(specificDecl) <- commonDecl.specificImplementation) {
                        let _ = MatchCJMPDeclAnnotations(commonDecl, specificDecl)
                    }
                }
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }
}

public func SelfhostPortStatus_CJMP_CheckCJMP(): Bool {
    return true
}
