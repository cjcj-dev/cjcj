package cangjie_compiler::sema.CJMP

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*
import cangjie_compiler::sema.InheritanceChecker.*
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::utils.CJC_ASSERT_WITH_MSG

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

private func CheckFuncReturnType(ty: Option<Ty>): Ty {
    CJC_ASSERT_WITH_MSG(ty.isSome(), "Function should be already resolved")
    let value = ty.getOrThrow()
    CJC_ASSERT_WITH_MSG(value.IsFunc(), "Function's type should be a FuncTy")
    let funcTy = (value as FuncTy).getOrThrow()
    CJC_ASSERT_WITH_MSG(!Ty.IsInitialTy(funcTy.retTy), "Function's return type should be already resolved")
    return funcTy.retTy
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
    if (let Some(extendDecl) <- (decl as ExtendDecl)) {
        if (let Some(extendedType) <- extendDecl.extendedType) {
            return DeclKindToString(decl) + " '" + extendedType.ToString() + "'"
        }
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

private func DiagNotMatchedCommonDecl(checker: MPTypeCheckerImpl, decl: Decl): Unit {
    DiagNotMatchedDecl(checker, decl, "specific", "common")
}

private func DiagNotMatchedSuperType(checker: MPTypeCheckerImpl, decl: Decl): Unit {
    let builder = checker.diag.DiagnoseRefactor(
        BasicDiagKindRefactor.sema_specific_has_different_super_type,
        NodeRange(decl),
        arguments: [DeclKindToString(decl)])
    builder.Emit()
}

private func HasGeneralSubClass(cls: ClassDecl): Bool {
    var current = cls
    while (!current.subDecls.isEmpty()) {
        if (let Some(child) <- (current.subDecls[0] as ClassDecl)) {
            if (!child.TestAttr(Attribute.COMMON)) {
                return true
            }
            current = child
        } else {
            return true
        }
    }
    return false
}

private func MatchNominativeDecl(checker: MPTypeCheckerImpl, commonDecl: Decl, specificDecl: Decl): Bool {
    if (commonDecl.astKind != specificDecl.astKind) {
        let builder = checker.diag.DiagnoseRefactor(
            BasicDiagKindRefactor.specific_has_different_kind,
            NodeRange(specificDecl),
            arguments: [DeclKindToString(specificDecl), DeclKindToString(commonDecl)])
        builder.Emit()
        return false
    }
    if (let Some(commonEnum) <- (commonDecl as EnumDecl)) {
        if (let Some(specificEnum) <- (specificDecl as EnumDecl)) {
            if (commonEnum.hasEllipsis) {
                specificDecl.EnableAttr(Attribute.COMMON_NON_EXHAUSTIVE)
            } else if (specificEnum.hasEllipsis) {
                let builder = checker.diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.common_non_exaustive_platfrom_exaustive_mismatch,
                    NodeRange(specificDecl),
                    arguments: [DeclKindToString(commonDecl), DeclKindToString(specificDecl)])
                builder.Emit()
            }
        }
    }
    return true
}

private func IsInstanceVar(decl: Decl): Bool {
    return decl.astKind == ASTKind.VAR_DECL && !decl.IsStaticOrGlobal()
}

private func UpdateVarDependencies(decl: Decl): Unit {
    for (idx in 0..decl.dependencies.size) {
        if (let Some(specificImpl) <- decl.dependencies[idx].specificImplementation) {
            decl.dependencies[idx] = specificImpl
        }
    }
}

private func CheckCommonInstanceVars(checker: MPTypeCheckerImpl, specificDecl: Decl): Unit {
    for (member in specificDecl.GetMemberDeclPtrs()) {
        if (IsInstanceVar(member) && member.TestAttr(Attribute.COMMON) &&
            !member.TestAttr(Attribute.COMMON_WITH_DEFAULT) && (let None <- member.specificImplementation)) {
            DiagNotMatchedSpecificDecl(checker, member)
        }
    }
}

private func ReplaceDecls(target: ArrayList<Decl>, source: ArrayList<Decl>): Unit {
    target.clear()
    for (decl in source) {
        target.add(decl)
    }
}

private func MergeCommonIntoSpecific(checker: MPTypeCheckerImpl, commonDecl: Decl, specificDecl: Decl): Unit {
    if (!MatchNominativeDecl(checker, commonDecl, specificDecl)) {
        return
    }

    let commonMembers = commonDecl.GetMemberDecls()
    let specificMembers = specificDecl.GetMemberDecls()
    let mergedSpecific = ArrayList<Decl>()
    let remainingCommon = ArrayList<Decl>()
    let commonVariablesIds = HashMap<String, Int64>()
    let memberParamIds = HashMap<String, Int64>()

    for (commonMember in commonMembers) {
        commonMember.outerDecl = specificDecl
        commonMember.doNotExport = false
        let id = mergedSpecific.size
        if (IsInstanceVar(commonMember)) {
            if (let Some(varDecl) <- (commonMember as VarDecl)) {
                if (varDecl.TestAttr(Attribute.COMMON)) {
                    commonVariablesIds[varDecl.identifier.Val()] = id
                } else if (varDecl.isMemberParam) {
                    memberParamIds[varDecl.identifier.Val()] = id
                }
            }
        }
        mergedSpecific.add(commonMember)
    }

    for (specificMember in specificMembers) {
        var consumed = false
        if (IsInstanceVar(specificMember)) {
            if (let Some(varDecl) <- (specificMember as VarDecl)) {
                let id = varDecl.identifier.Val()
                if (specificMember.TestAttr(Attribute.SPECIFIC)) {
                    if (let Some(commonIdx) <- commonVariablesIds.get(id)) {
                        let commonMember = mergedSpecific[commonIdx]
                        commonMember.specificImplementation = specificMember
                        mergedSpecific[commonIdx] = specificMember
                        remainingCommon.add(commonMember)
                        consumed = true
                    } else {
                        DiagNotMatchedCommonDecl(checker, varDecl)
                    }
                } else if (varDecl.isMemberParam && memberParamIds.contains(id)) {
                    remainingCommon.add(specificMember)
                    consumed = true
                }
            }
        }
        if (!consumed) {
            mergedSpecific.add(specificMember)
        }
    }

    ReplaceDecls(specificMembers, mergedSpecific)
    ReplaceDecls(commonMembers, remainingCommon)
    for (member in specificMembers) {
        UpdateVarDependencies(member)
    }
    CheckCommonInstanceVars(checker, specificDecl)
    commonDecl.doNotExport = true
    commonDecl.specificImplementation = specificDecl
}

private func MergeCJMPNominalsExceptExtension(checker: MPTypeCheckerImpl, pkg: Package): Unit {
    let matchedDecls = HashMap<String, Decl>()
    let walker = Walker(pkg, visitPre: { node: Node =>
        if (!node.IsDecl()) {
            return VisitAction.WALK_CHILDREN
        }
        if (let Some(decl) <- (node as Decl)) {
            if (decl.IsNominalDecl() && decl.astKind != ASTKind.EXTEND_DECL) {
                let id = decl.identifier.Val()
                if (let Some(matchedDecl) <- matchedDecls.get(id)) {
                    let hasGenericMismatch = (decl.generic.isSome() && matchedDecl.generic.isNone()) ||
                        (decl.generic.isNone() && matchedDecl.generic.isSome())
                    if (!hasGenericMismatch) {
                        if (decl.TestAttr(Attribute.SPECIFIC) && matchedDecl.TestAttr(Attribute.COMMON)) {
                            MergeCommonIntoSpecific(checker, matchedDecl, decl)
                        } else if (decl.TestAttr(Attribute.COMMON) && matchedDecl.TestAttr(Attribute.SPECIFIC)) {
                            MergeCommonIntoSpecific(checker, decl, matchedDecl)
                        }
                    }
                } else if (decl.TestAnyAttr(Attribute.COMMON, Attribute.SPECIFIC)) {
                    matchedDecls[id] = decl
                }
            }
        }
        return VisitAction.SKIP_CHILDREN
    })
    let _ = walker.Walk()
}

private func CollectDecl(decl: Decl, commonDecls: ArrayList<Decl>, specificDecls: ArrayList<Decl>): Unit {
    if (decl.TestAttr(Attribute.COMMON)) {
        commonDecls.add(decl)
    } else if (decl.TestAttr(Attribute.SPECIFIC)) {
        specificDecls.add(decl)
    }
}

private func CollectCJMPDecls(pkg: Package, commonDecls: ArrayList<Decl>, specificDecls: ArrayList<Decl>): Unit {
    let walker = Walker(pkg, visitPre: { node: Node =>
        if (node.IsDecl() && node.astKind != ASTKind.PRIMARY_CTOR_DECL) {
            if (let Some(decl) <- (node as Decl)) {
                CollectDecl(decl, commonDecls, specificDecls)
            }
        }
        if (node.astKind == ASTKind.PACKAGE || node.astKind == ASTKind.FILE ||
            node.IsNominalDecl() || node.IsNominalDeclBody()) {
            return VisitAction.WALK_CHILDREN
        }
        return VisitAction.SKIP_CHILDREN
    })
    let _ = walker.Walk()
}

private func MustMatchWithPlatform(decl: Decl, compilingCommon: Bool): Bool {
    if (compilingCommon) {
        return false
    }
    if (let Some(_) <- decl.specificImplementation) {
        return false
    }
    if (decl.TestAttr(Attribute.COMMON_WITH_DEFAULT)) {
        return false
    }
    if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
        if (let Some(outer) <- decl.outerDecl) {
            if (outer.TestAttr(Attribute.COMMON_WITH_DEFAULT) && (let None <- outer.specificImplementation)) {
                return false
            }
        }
    }
    if (let Some(outer) <- decl.outerDecl) {
        if (outer.astKind == ASTKind.INTERFACE_DECL) {
            return false
        }
    }
    if (decl.astKind == ASTKind.VAR_DECL && decl.TestAttr(Attribute.INITIALIZED)) {
        return false
    }
    if (let Some(varDecl) <- (decl as VarDecl)) {
        if (!varDecl.IsStaticOrGlobal()) {
            if (let Some(outer) <- varDecl.outerDecl) {
                return outer.astKind == ASTKind.ENUM_DECL
            }
            return false
        }
    }
    return true
}

private func ContainsDecl(decls: ArrayList<Decl>, target: Decl): Bool {
    for (decl in decls) {
        if (SameDecl(decl, target)) {
            return true
        }
    }
    return false
}

private func SameTyList(left: ArrayList<InterfaceTy>, right: ArrayList<InterfaceTy>, checker: MPTypeCheckerImpl): Bool {
    if (left.size != right.size) {
        return false
    }
    for (leftTy in left) {
        var found = false
        for (rightTy in right) {
            if (checker.typeManager.IsTyEqual(leftTy, rightTy)) {
                found = true
                break
            }
        }
        if (!found) {
            return false
        }
    }
    return true
}

private class DirectExtensionPrivateFunctions {
    public var extendedTypeName: String
    public let rawNames: ArrayList<String> = ArrayList<String>()

    public init(extendedTypeName: String) {
        this.extendedTypeName = extendedTypeName
    }
}

private func FindPrivateFunctionBucket(
    buckets: ArrayList<DirectExtensionPrivateFunctions>, extendedTypeName: String): DirectExtensionPrivateFunctions {
    for (bucket in buckets) {
        if (bucket.extendedTypeName == extendedTypeName) {
            return bucket
        }
    }
    let created = DirectExtensionPrivateFunctions(extendedTypeName)
    buckets.add(created)
    return created
}

private func HasRawName(names: ArrayList<String>, name: String): Bool {
    for (value in names) {
        if (value == name) {
            return true
        }
    }
    return false
}

private func HasSpecificCandidate(funcs: ArrayList<FuncDecl>): Bool {
    for (funcDecl in funcs) {
        if (funcDecl.TestAttr(Attribute.SPECIFIC)) {
            return true
        }
    }
    return false
}

private func IsCommonCandidateFromCommonPart(funcDecl: FuncDecl): Bool {
    return funcDecl.TestAttr(Attribute.COMMON) && funcDecl.TestAttr(Attribute.FROM_COMMON_PART)
}

private func AppendSyms(target: ArrayList<Symbol>, source: ArrayList<Symbol>): Unit {
    for (sym in source) {
        target.add(sym)
    }
}

extend MPTypeCheckerImpl {
    public func PrepareTypeCheck4CJMP(pkg: Package): Unit {
        if (!compilePlatform) {
            return
        }
        MergeCJMPNominalsExceptExtension(this, pkg)
    }

    public func PreCheck4CJMP(pkg: Package): Unit {
        if (!compileCommon) {
            return
        }
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (let Some(classDecl) <- (node as ClassDecl)) {
                PreCheckCJMPClass(classDecl)
                return VisitAction.SKIP_CHILDREN
            }
            if (node.IsDecl()) {
                return VisitAction.SKIP_CHILDREN
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    public func PreCheckCJMPClass(cls: ClassDecl): Unit {
        if (!(cls.TestAttr(Attribute.COMMON) && cls.TestAnyAttr(Attribute.OPEN, Attribute.ABSTRACT))) {
            return
        }
        var hasInit = false
        for (member in cls.GetMemberDeclPtrs()) {
            if (member.TestAttr(Attribute.CONSTRUCTOR)) {
                hasInit = true
                break
            }
        }
        if (!hasInit && HasGeneralSubClass(cls)) {
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_common_open_class_no_init,
                NodeRange(cls),
                arguments: [cls.identifier.Val()])
            builder.Emit()
        }
    }

    public func FilterOutCommonCandidatesIfSpecificExist(candidates: HashMap<Names, ArrayList<FuncDecl>>): Unit {
        for ((_, funcs) in candidates) {
            if (!HasSpecificCandidate(funcs)) {
                continue
            }
            var idx: Int64 = 0
            while (idx < funcs.size) {
                if (IsCommonCandidateFromCommonPart(funcs[idx])) {
                    funcs.remove(at: idx)
                } else {
                    idx++
                }
            }
        }
    }

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

    public func MatchCJMPDeclAttrs(attrs: ArrayList<Attribute>, common: Decl, specific: Decl): Bool {
        for (attr in attrs) {
            if (common.TestAttr(attr) == specific.TestAttr(attr)) {
                continue
            }
            if (attr == Attribute.ABSTRACT || attr == Attribute.OPEN) {
                if (NeedToReportMissingBody(common, specific)) {
                    continue
                }
                if (specific.TestAttr(Attribute.ABSTRACT) && common.TestAttr(Attribute.OPEN) &&
                    common.IsFuncOrProp()) {
                    let kindStr = if (common.astKind == ASTKind.FUNC_DECL) { "function" } else { "property" }
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_open_abstract_specific_can_not_replace_open_common,
                        NodeRange(specific),
                        arguments: [kindStr, kindStr])
                    builder.Emit()
                }
                let funcOrProp = common.astKind == ASTKind.FUNC_DECL || common.astKind == ASTKind.PROP_DECL
                if (funcOrProp && common.TestAttr(Attribute.ABSTRACT) && specific.TestAttr(Attribute.OPEN)) {
                    continue
                }
                if (common.TestAttr(Attribute.ABSTRACT) &&
                    common.TestAttr(Attribute.STATIC) && specific.TestAttr(Attribute.STATIC)) {
                    continue
                }
            }
            if (common.astKind == ASTKind.PROP_DECL && attr == Attribute.MUT) {
                let kind = if (common.TestAttr(attr)) {
                    BasicDiagKindRefactor.sema_property_have_same_declaration_in_inherit_mut
                } else {
                    BasicDiagKindRefactor.sema_property_have_same_declaration_in_inherit_immut
                }
                let target = if (common.TestAttr(attr)) { specific } else { common }
                let builder = diag.DiagnoseRefactor(kind, NodeRange(target), arguments: [target.identifier.Val()])
                builder.Emit()
            } else if (common.astKind == ASTKind.CLASS_DECL &&
                (attr == Attribute.SEALED || attr == Attribute.OPEN) &&
                specific.TestAttr(Attribute.SEALED) && common.TestAttr(Attribute.ABSTRACT)) {
                continue
            } else {
                let builder = diag.DiagnoseRefactor(
                    BasicDiagKindRefactor.sema_specific_has_different_modifier,
                    NodeRange(specific),
                    arguments: [DeclKindToString(specific)])
                builder.Emit()
            }
            return false
        }
        return true
    }

    public func CheckCommonSpecificGenericMatch(specificDecl: Decl, commonDecl: Decl): Unit {
        let parentBounds = GetAllGenericUpperBounds(typeManager, commonDecl)
        let childBounds = GetAllGenericUpperBounds(typeManager, specificDecl)
        CheckGenericTypeBoundsMapped(commonDecl, specificDecl, parentBounds, childBounds, diag, typeManager)
    }

    public func MatchCommonNominalDeclWithSpecific(commonDecl: InheritableDecl): Bool {
        if (let None <- commonDecl.specificImplementation) {
            return true
        }
        let specificDecl = commonDecl.specificImplementation.getOrThrow()
        if (!MatchNominativeDecl(this, commonDecl, specificDecl)) {
            return false
        }
        let matchedAttr = ArrayList<Attribute>()
        matchedAttr.add(Attribute.ABSTRACT)
        matchedAttr.add(Attribute.PUBLIC)
        matchedAttr.add(Attribute.OPEN)
        matchedAttr.add(Attribute.PROTECTED)
        matchedAttr.add(Attribute.C)
        matchedAttr.add(Attribute.SEALED)
        if (!MatchCJMPDeclAttrs(matchedAttr, commonDecl, specificDecl)) {
            return false
        }
        let specificInheritable = specificDecl as InheritableDecl
        if (let Some(platformDecl) <- specificInheritable) {
            let commonSupInterfaces = ArrayList<InterfaceTy>()
            let genericTyMap = TypeSubst()
            MapCJMPGenericTypeArgs(genericTyMap, commonDecl, specificDecl)
            for (superInterface in commonDecl.GetSuperInterfaceTys()) {
                if (genericTyMap.IsEmpty()) {
                    commonSupInterfaces.add(superInterface)
                } else if (let Some(updated) <- (typeManager.GetInstantiatedTy(superInterface, genericTyMap) as InterfaceTy)) {
                    commonSupInterfaces.add(updated)
                }
            }
            if (!SameTyList(commonSupInterfaces, platformDecl.GetSuperInterfaceTys(), this)) {
                DiagNotMatchedSuperType(this, specificDecl)
                return false
            }
            if (let Some(commonClass) <- (commonDecl as ClassDecl)) {
                if (let Some(specificClass) <- (specificDecl as ClassDecl)) {
                    let commonSuper = commonClass.GetSuperClassDecl()
                    let specificSuper = specificClass.GetSuperClassDecl()
                    var bothHaveSuper = false
                    var neitherHasSuper = false
                    if ((let Some(_) <- commonSuper) && (let Some(_) <- specificSuper)) {
                        bothHaveSuper = true
                    }
                    if ((let None <- commonSuper) && (let None <- specificSuper)) {
                        neitherHasSuper = true
                    }
                    if (bothHaveSuper) {
                        let commonSuperDecl = commonSuper.getOrThrow()
                        let specificSuperDecl = specificSuper.getOrThrow()
                        if (let Some(commonSuperTy) <- commonSuperDecl.GetTy()) {
                            if (let Some(specificSuperTy) <- specificSuperDecl.GetTy()) {
                                if (!typeManager.IsTyEqual(commonSuperTy, specificSuperTy)) {
                                    DiagNotMatchedSuperType(this, specificDecl)
                                    return false
                                }
                            }
                        }
                    } else if (!neitherHasSuper) {
                        DiagNotMatchedSuperType(this, specificDecl)
                        return false
                    }
                }
            }
        }
        CheckCommonSpecificGenericMatch(specificDecl, commonDecl)
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

    public func MatchEnumFuncTypes(specific: FuncDecl, common: FuncDecl): Bool {
        if (typeManager.IsFuncDeclEqualType(specific, common)) {
            return true
        }
        if (let Some(commonOuter) <- common.outerDecl) {
            if (let Some(specificOuter) <- specific.outerDecl) {
                let genericTyMap = TypeSubst()
                MapCJMPGenericTypeArgs(genericTyMap, commonOuter, specificOuter)
                if (genericTyMap.IsEmpty()) {
                    return false
                }
                if (let Some(commonTy) <- common.GetTy()) {
                    if (let Some(specificTy) <- specific.GetTy()) {
                        return typeManager.IsTyEqual(typeManager.GetInstantiatedTy(commonTy, genericTyMap), specificTy)
                    }
                }
            }
        }
        return false
    }

    public func MatchCJMPEnumConstructor(specificDecl: Decl, commonDecl: Decl): Bool {
        if (!IsCJMPDeclMatchable(specificDecl, commonDecl)) {
            return false
        }
        if (specificDecl.astKind == ASTKind.FUNC_DECL) {
            if (let Some(specificFunc) <- (specificDecl as FuncDecl)) {
                if (let Some(commonFunc) <- (commonDecl as FuncDecl)) {
                    if (!MatchEnumFuncTypes(specificFunc, commonFunc)) {
                        return false
                    }
                }
            }
        }
        let enumName = if (let Some(outer) <- specificDecl.outerDecl) { outer.identifier.GetRawText() } else { "" }
        return TrySetSpecificImpl(specificDecl, commonDecl, "enum '" + enumName + "' constructor")
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

    public func TryMatchVarWithPatternWithVarDecls(specificDecl: VarWithPatternDecl,
        commonDecls: ArrayList<Decl>): Bool {
        if (let Some(pattern) <- specificDecl.irrefutablePattern) {
            if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
                var matchedAll = true
                for (child in tuplePattern.patterns) {
                    if (let Some(varPattern) <- (child as VarPattern)) {
                        if (let Some(varDecl) <- varPattern.varDecl) {
                            if (!MatchSpecificDeclWithCommonDecls(varDecl, commonDecls)) {
                                matchedAll = false
                            }
                        } else {
                            matchedAll = false
                        }
                    } else {
                        matchedAll = false
                    }
                }
                return matchedAll
            }
        }
        return false
    }

    public func MatchSpecificDeclWithCommonDecls(specificDecl: Decl, commonDecls: ArrayList<Decl>): Bool {
        var matched = false
        let isEnumCtor = specificDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)
        let kind = specificDecl.astKind
        for (commonDecl in commonDecls) {
            if (matched && !severalParents) {
                break
            }
            if (commonDecl.astKind != kind) {
                continue
            }
            if (isEnumCtor && commonDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                matched = MatchCJMPEnumConstructor(specificDecl, commonDecl) || matched
            } else if (kind == ASTKind.FUNC_DECL) {
                if (let Some(specificFunc) <- (specificDecl as FuncDecl)) {
                    if (let Some(commonFunc) <- (commonDecl as FuncDecl)) {
                        matched = MatchCJMPFunction(specificFunc, commonFunc) || matched
                    }
                }
            } else if (kind == ASTKind.PROP_DECL) {
                if (let Some(specificProp) <- (specificDecl as PropDecl)) {
                    if (let Some(commonProp) <- (commonDecl as PropDecl)) {
                        matched = MatchCJMPProp(specificProp, commonProp) || matched
                    }
                }
            } else if (kind == ASTKind.VAR_DECL) {
                if (let Some(specificVar) <- (specificDecl as VarDecl)) {
                    if (let Some(commonVar) <- (commonDecl as VarDecl)) {
                        matched = MatchCJMPVar(specificVar, commonVar) || matched
                    }
                }
            }
        }
        if (kind == ASTKind.VAR_WITH_PATTERN_DECL) {
            if (let Some(varWithPattern) <- (specificDecl as VarWithPatternDecl)) {
                matched = TryMatchVarWithPatternWithVarDecls(varWithPattern, commonDecls)
            }
        }
        if (!matched) {
            if (let Some(outer) <- specificDecl.outerDecl) {
                if (outer.TestAttr(Attribute.COMMON_NON_EXHAUSTIVE)) {
                    return false
                }
            }
            DiagNotMatchedCommonDecl(this, specificDecl)
        }
        return matched
    }

    public func CheckCommonExtensions(commonDecls: ArrayList<Decl>): Unit {
        let buckets = ArrayList<DirectExtensionPrivateFunctions>()
        for (decl in commonDecls) {
            if (let Some(extendDecl) <- (decl as ExtendDecl)) {
                if (!extendDecl.GetSuperInterfaceTys().isEmpty()) {
                    continue
                }
                if (let Some(extendedType) <- extendDecl.extendedType) {
                    let bucket = FindPrivateFunctionBucket(buckets, extendedType.ToString())
                    for (memberDecl in extendDecl.GetMemberDecls()) {
                        if (!memberDecl.IsFuncOrProp() || !memberDecl.TestAttr(Attribute.PRIVATE)) {
                            continue
                        }
                        let rawName = memberDecl.rawMangleName
                        if (HasRawName(bucket.rawNames, rawName)) {
                            let kind = if (memberDecl.IsFunc()) { "function" } else { "property" }
                            let builder = diag.DiagnoseRefactor(
                                BasicDiagKindRefactor.sema_common_direct_extension_has_duplicate_private_members,
                                NodeRange(memberDecl),
                                arguments: [extendedType.ToString(), kind, memberDecl.identifier.GetRawText()])
                            builder.Emit()
                        } else if (memberDecl.TestAttr(Attribute.COMMON)) {
                            let kind = if (memberDecl.IsFunc()) { "function" } else { "property" }
                            let builder = diag.DiagnoseRefactor(
                                BasicDiagKindRefactor.sema_common_direct_extension_has_common_private_members,
                                NodeRange(memberDecl),
                                arguments: [kind, memberDecl.identifier.GetRawText()])
                            builder.Emit()
                        } else {
                            bucket.rawNames.add(rawName)
                        }
                    }
                }
            }
        }
    }

    public func CheckAbstractClassMembers(specificDecl: InheritableDecl): Unit {
        if (!specificDecl.TestAttr(Attribute.SPECIFIC) || !specificDecl.TestAttr(Attribute.ABSTRACT) ||
            specificDecl.astKind != ASTKind.CLASS_DECL) {
            return
        }
        if (let Some(classDecl) <- (specificDecl as ClassDecl)) {
            for (memberDecl in classDecl.GetMemberDeclPtrs()) {
                if (memberDecl.TestAttr(Attribute.ABSTRACT) && !memberDecl.TestAttr(Attribute.SPECIFIC) &&
                    !memberDecl.TestAttr(Attribute.FROM_COMMON_PART) &&
                    (memberDecl.astKind == ASTKind.FUNC_DECL || memberDecl.astKind == ASTKind.PROP_DECL)) {
                    let memberKind = if (memberDecl.astKind == ASTKind.FUNC_DECL) { "function" } else { "property" }
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_cjmp_non_specific_abstract_member_in_specific_class,
                        NodeRange(memberDecl),
                        arguments: [specificDecl.identifier.Val(), memberKind])
                    builder.Emit()
                }
            }
        }
    }

    public func MatchCJMPDecls(commonDecls: ArrayList<Decl>, specificDecls: ArrayList<Decl>): Unit {
        for (specificDecl in specificDecls) {
            if (specificDecl.TestAttr(Attribute.IS_BROKEN) || specificDecl.IsNominalDecl()) {
                continue
            }
            MatchSpecificDeclWithCommonDecls(specificDecl, commonDecls)
        }
        let matchedIds = ArrayList<Decl>()
        for (commonDecl in commonDecls) {
            if (let Some(commonInheritable) <- (commonDecl as InheritableDecl)) {
                if (commonDecl.IsNominalDecl() && MatchCommonNominalDeclWithSpecific(commonInheritable)) {
                    if (let Some(specific) <- commonDecl.specificImplementation) {
                        matchedIds.add(specific)
                    }
                }
            }
            if (!MustMatchWithPlatform(commonDecl, compileCommon)) {
                continue
            }
            if (commonDecl.astKind == ASTKind.VAR_DECL && !commonDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                continue
            }
            DiagNotMatchedSpecificDecl(this, commonDecl)
        }
        for (specificDecl in specificDecls) {
            if (specificDecl.IsNominalDecl() && !ContainsDecl(matchedIds, specificDecl)) {
                DiagNotMatchedCommonDecl(this, specificDecl)
            }
            if (let Some(inheritable) <- (specificDecl as InheritableDecl)) {
                CheckAbstractClassMembers(inheritable)
            }
        }
        for (commonDecl in commonDecls) {
            if (commonDecl.IsNominalDecl()) {
                continue
            }
            if (let Some(specificDecl) <- commonDecl.specificImplementation) {
                let matchedAttrs = ArrayList<Attribute>()
                matchedAttrs.add(Attribute.STATIC)
                matchedAttrs.add(Attribute.MUT)
                matchedAttrs.add(Attribute.PRIVATE)
                matchedAttrs.add(Attribute.PUBLIC)
                matchedAttrs.add(Attribute.PROTECTED)
                matchedAttrs.add(Attribute.FOREIGN)
                matchedAttrs.add(Attribute.UNSAFE)
                matchedAttrs.add(Attribute.OPEN)
                matchedAttrs.add(Attribute.ABSTRACT)
                let _ = MatchCJMPDeclAttrs(matchedAttrs, commonDecl, specificDecl)
            }
        }
    }

    public func MatchSpecificWithCommon(pkg: Package): Unit {
        let commonDecls = ArrayList<Decl>()
        let specificDecls = ArrayList<Decl>()
        CollectCJMPDecls(pkg, commonDecls, specificDecls)
        if (compileCommon) {
            CheckCommonExtensions(commonDecls)
        }
        if (compilePlatform) {
            MatchCJMPDecls(commonDecls, specificDecls)
        }
        for (commonDecl in commonDecls) {
            if (let Some(specificDecl) <- commonDecl.specificImplementation) {
                PropagateCJMPDeclAnnotations(commonDecl, specificDecl)
                if (let Some(commonFunc) <- (commonDecl as FuncDecl)) {
                    if (let Some(specificFunc) <- (specificDecl as FuncDecl)) {
                        PropagateDefaultArguments(commonFunc, specificFunc)
                    }
                }
            }
        }
    }

    public func UpdateGenericTyInMemberFromCommon(genericTyMap: TypeSubst, member: Decl): Unit {
        if (genericTyMap.IsEmpty()) {
            return
        }
        let walker = Walker(member, visitPre: { node: Node =>
            if (let Some(ty) <- node.GetTy()) {
                node.SetTy(typeManager.GetInstantiatedTy(ty, genericTyMap))
            }
            if (let Some(refExpr) <- (node as NameReferenceExpr)) {
                for (idx in 0..refExpr.instTys.size) {
                    refExpr.instTys[idx] = typeManager.GetInstantiatedTy(refExpr.instTys[idx], genericTyMap)
                }
            }
            return VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }

    public func UpdateSpecificMemberGenericTy(
        ctx: ASTContext,
        getSymsFunc: (ASTContext, ASTKind) -> ArrayList<Symbol>
    ): Unit {
        let syms = getSymsFunc(ctx, ASTKind.CLASS_DECL)
        AppendSyms(syms, getSymsFunc(ctx, ASTKind.INTERFACE_DECL))
        AppendSyms(syms, getSymsFunc(ctx, ASTKind.STRUCT_DECL))
        AppendSyms(syms, getSymsFunc(ctx, ASTKind.ENUM_DECL))
        AppendSyms(syms, getSymsFunc(ctx, ASTKind.EXTEND_DECL))

        for (sym in syms) {
            if (let Some(node) <- sym.node) {
                if (let Some(decl) <- (node as Decl)) {
                    if (!decl.TestAttr(Attribute.COMMON) || !decl.TestAttr(Attribute.GENERIC)) {
                        continue
                    }
                    if (let Some(specificDecl) <- decl.specificImplementation) {
                        let genericTyMap = TypeSubst()
                        MapCJMPGenericTypeArgs(genericTyMap, decl, specificDecl)
                        for (member in specificDecl.GetMemberDecls()) {
                            if (member.TestAttr(Attribute.FROM_COMMON_PART)) {
                                UpdateGenericTyInMemberFromCommon(genericTyMap, member)
                            }
                        }
                    }
                }
            }
        }
    }

    public func GetInheritedTypesWithSpecificImpl(inheritedTypes: ArrayList<Type>, hasSpecificImpl: Bool): Unit {
        GetInheritedTypesWithSpecificImpl(inheritedTypes, hasSpecificImpl, compilePlatform)
    }

    public func GetInheritedTypesWithSpecificImpl(
        inheritedTypes: ArrayList<Type>, hasSpecificImpl: Bool, compilePlatformFlag: Bool): Unit {
        if (!compilePlatformFlag || hasSpecificImpl) {
            return
        }
        for (inheritedType in inheritedTypes) {
            if (let Some(decl) <- Ty.GetDeclOfTy(inheritedType.GetTy())) {
                if (let Some(specificDecl) <- decl.specificImplementation) {
                    if (let Some(specificTy) <- specificDecl.GetTy()) {
                        inheritedType.SetTy(specificTy)
                    }
                }
            }
        }
    }

    public func CheckMatchedFunctionReturnTypes(specificFunc: FuncDecl, commonFunc: FuncDecl): Unit {
        let commonType = commonFunc.funcBody.getOrThrow().GetTy()
        let specificType = specificFunc.funcBody.getOrThrow().GetTy()
        let commonRetTy = CheckFuncReturnType(commonType)
        let specificRetTy = CheckFuncReturnType(specificType)
        if (commonRetTy == specificRetTy) {
            return
        }
        if (typeManager.IsSubtype(specificRetTy, commonRetTy)) {
            return
        }
        commonFunc.specificImplementation = None
        if (!MatchCJMPFunction(specificFunc, commonFunc)) {
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_return_type_incompatible,
                NodeRange(specificFunc),
                arguments: [specificFunc.identifier.Val()])
            builder.Emit()
        }
        commonFunc.specificImplementation = specificFunc
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
