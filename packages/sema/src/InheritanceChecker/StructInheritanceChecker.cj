package cangjie_compiler::sema.InheritanceChecker

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.{DiagnosticEngine, DiagArgument, DiagKind, DiagKindRefactor, MakeRange}
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::sema.*

private func DeclRange(decl: Decl): BasicRange {
    return MakeRange(decl.begin, decl.end)
}

private func NodeRange(node: Node): BasicRange {
    return MakeRange(node.begin, node.end)
}

private func DeclKindText(decl: Decl): String {
    return DeclKindToString(decl)
}

private func HasExtend(values: ArrayList<ExtendDecl>, decl: ExtendDecl): Bool {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return true
        }
    }
    return false
}

private func AddExtendUnique(values: ArrayList<ExtendDecl>, decl: ExtendDecl): Unit {
    if (!HasExtend(values, decl)) {
        values.add(decl)
    }
}

private func IsInvisibleMember(member: Decl, currentPkg: String): Bool {
    if (member.TestAttr(Attribute.PRIVATE)) {
        return true
    }
    if (member.TestAttr(Attribute.PUBLIC) || member.TestAttr(Attribute.PROTECTED)) {
        return false
    }
    if (member.fullPackageName.isEmpty()) {
        return false
    }
    return member.fullPackageName != currentPkg && !member.TestAttr(Attribute.INTERNAL)
}

private func RemoveMembersShouldNotInherit(members: MemberMap): Unit {
    var idx: Int64 = 0
    while (idx < members.entries.size) {
        if (let Some(decl) <- members.entries[idx].signature.decl) {
            if (decl.TestAttr(Attribute.PRIVATE)) {
                members.Remove(idx)
                continue
            }
        }
        idx++
    }
}

private func RemoveInvisibleMember(members: MemberMap, currentPkg: String): Unit {
    var idx: Int64 = 0
    while (idx < members.entries.size) {
        if (let Some(decl) <- members.entries[idx].signature.decl) {
            if (IsInvisibleMember(decl, currentPkg)) {
                members.Remove(idx)
                continue
            }
        }
        idx++
    }
}

private func AreFuncParameterNameIdentical(parent: FuncDecl, child: FuncDecl): Bool {
    if (let Some(parentBody) <- parent.funcBody) {
        if (let Some(childBody) <- child.funcBody) {
            if (parentBody.paramLists.isEmpty() || childBody.paramLists.isEmpty()) {
                return true
            }
            let parentParams = parentBody.paramLists[0].params
            let childParams = childBody.paramLists[0].params
            if (parentParams.size != childParams.size) {
                return false
            }
            for (idx in 0..parentParams.size) {
                if (parentParams[idx].isNamedParam != childParams[idx].isNamedParam) {
                    return false
                }
                if (parentParams[idx].isNamedParam && parentParams[idx].identifier != childParams[idx].identifier) {
                    return false
                }
            }
        }
    }
    return true
}

private func DiagnoseParameterName(diag: DiagnosticEngine, parent: FuncDecl, child: FuncDecl): Unit {
    let builder = diag.DiagnoseRefactor(
        DiagKindRefactor.sema_param_named_mismatched,
        DeclRange(child)
    )
    builder.AddNote(DeclRange(parent), "the corresponding function of the supertype is")
}

private func NeedCheck(node: Node): Bool {
    if (!node.IsNominalDecl()) {
        return false
    }
    if (node.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
        return false
    }
    if (node.TestAttr(Attribute.FROM_COMMON_PART) && node.TestAttr(Attribute.COMMON)) {
        return false
    }
    return true
}

private func InheritedDisplayName(decl: Decl): String {
    if (let Some(ty) <- decl.GetTy()) {
        if (ty.IsNominal()) {
            return ty.name
        }
        return ty.String()
    }
    return decl.identifier.Val()
}

private func CountByDecl(members: ArrayList<MemberSignature>, decl: Decl): Int64 {
    var count: Int64 = 0
    for (member in members) {
        if (let Some(memberDecl) <- member.decl) {
            if (SameDecl(memberDecl, decl)) {
                count++
            }
        }
    }
    return count
}

private func UnimplementedIdentifier(member: MemberSignature): String {
    if (let Some(memberDecl) <- member.decl) {
        let name = "'" + memberDecl.identifier.Val() + "'"
        if (let Some(memberTy) <- member.ty) {
            return name + ", of type: " + memberTy.String()
        }
        return name
    }
    return "''"
}

public class StructInheritanceChecker {
    public let diag: DiagnosticEngine
    public let typeManager: TypeManager
    public let pkg: Package

    private let structInheritedMembers: ArrayList<InheritedMemberEntry> = ArrayList<InheritedMemberEntry>()
    private let checkingDecls: ArrayList<InheritableDecl> = ArrayList<InheritableDecl>()
    private let instantiatedKeys: HashSet<String> = HashSet<String>()

    public init(diag: DiagnosticEngine, typeManager: TypeManager, pkg: Package) {
        this.diag = diag
        this.typeManager = typeManager
        this.pkg = pkg
    }

    public func Check(): Unit {
        if (pkg.TestAnyAttr(Attribute.IMPORTED, Attribute.TOOL_ADD)) {
            return
        }
        let nominalDecls = ArrayList<InheritableDecl>()
        let extendDecls = ArrayList<ExtendDecl>()
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (!NeedCheck(node)) {
                return VisitAction.WALK_CHILDREN
            }
            if (node.TestAttr(Attribute.IS_BROKEN) || !Ty.IsTyCorrect(node.GetTy())) {
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(inheritable) <- (node as InheritableDecl)) {
                if (let Some(extendDecl) <- (node as ExtendDecl)) {
                    extendDecls.add(extendDecl)
                } else {
                    nominalDecls.add(inheritable)
                }
            }
            return VisitAction.SKIP_CHILDREN
        })
        walker.Walk()
        for (decl in nominalDecls) {
            CheckMembersWithInheritedDecls(decl)
        }
        for (decl in extendDecls) {
            CheckMembersWithInheritedDecls(decl)
        }
        CheckAllUpperBoundsConfliction()
        CheckInstDupFuncsInNominalDecls(this)
    }

    public func MoveStructInheritedMembers(): ArrayList<InheritedMemberEntry> {
        let out = ArrayList<InheritedMemberEntry>()
        for (entry in structInheritedMembers) {
            out.add(InheritedMemberEntry(entry.decl, entry.members.Clone()))
        }
        structInheritedMembers.clear()
        return out
    }

    public func HasInstantiatedKey(key: String): Bool {
        return instantiatedKeys.contains(key)
    }

    public func AddInstantiatedKey(key: String): Unit {
        instantiatedKeys.add(key)
    }

    public func CheckInstWithCStructTypeArg(node: Node): Unit {
        CheckInstWithCStructTypeArgImpl(this, node)
    }

    public func DiagnoseForInstantiatedMember(parent: MemberSignature, child: MemberSignature): Unit {
        DiagnoseForInstantiatedMemberImpl(this, parent, child)
    }

    public func GetStoredMembersForDecl(decl: InheritableDecl): MemberMap {
        if (let Some(entry) <- FindStoredEntry(decl)) {
            return entry.members
        }
        return MemberMap()
    }

    public func CheckMembersWithInheritedDecls(decl: InheritableDecl): Unit {
        if (let Some(_) <- FindStoredEntry(decl)) {
            return
        }
        checkingDecls.add(decl)
        let interfaceMembers = GetAndCheckInheritedInterfaces(decl)
        let instanceMembers = GetAndCheckInheritedMembers(decl)
        let visiblePair = GetVisibleExtendMembersForExtend(decl)
        let visibleExtendMembers = visiblePair[0]
        let invisibleMembers = visiblePair[1]
        if (let Some(declTy) <- decl.GetTy()) {
            MergeInheritedMembers(visibleExtendMembers, instanceMembers, declTy)
        }
        for (entry in interfaceMembers.entries) {
            CheckExtendExportDependence(decl, entry.signature, visibleExtendMembers)
        }
        for (member in decl.GetMemberDecls()) {
            if (!Ty.IsTyCorrect(member.GetTy()) || (let None <- member.outerDecl) ||
                member.TestAttr(Attribute.CONSTRUCTOR)) {
                continue
            }
            let memberSig = MemberSignature(
                decl: member,
                ty: member.GetTy(),
                structTy: decl.GetTy(),
                extendDecl: None
            )
            for (bounds in GetAllGenericUpperBounds(typeManager, member)) {
                memberSig.upperBounds.add(bounds)
            }
            for (parent in visibleExtendMembers.Get(member.identifier.Val())) {
                DiagnoseForInheritedMember(parent, memberSig)
            }
            for (parent in invisibleMembers.Get(member.identifier.Val())) {
                DiagnoseForInheritedMember(parent, memberSig)
            }
            let updatedSig = UpdateInheritedMemberIfNeeded(visibleExtendMembers, memberSig)
            let _ = updatedSig
        }
        for (entry in interfaceMembers.entries) {
            entry.signature.isInheritedInterface = true
            DiagnoseForInheritedInterfaces(entry.signature, visibleExtendMembers)
        }
        if (let Some(declTy) <- decl.GetTy()) {
            MergeInheritedMembers(interfaceMembers, visibleExtendMembers, declTy)
        }
        for (entry in interfaceMembers.entries) {
            DiagnoseForOverriddenMember(entry.signature)
        }
        DiagnoseForUnimplementedInterfaces(interfaceMembers, decl)
        RemoveMembersShouldNotInherit(interfaceMembers)
        checkingDecls.remove(at: checkingDecls.size - 1)
        for (entry in interfaceMembers.entries) {
            entry.signature.isInheritedInterface = false
            entry.signature.extendDecl = None
        }
        structInheritedMembers.add(InheritedMemberEntry(decl, interfaceMembers))
    }

    private func FindStoredEntry(decl: InheritableDecl): Option<InheritedMemberEntry> {
        for (entry in structInheritedMembers) {
            if (SameDecl(entry.decl, decl)) {
                return entry
            }
        }
        return None
    }

    private func GetAndCheckInheritedInterfaces(decl: InheritableDecl): MemberMap {
        let interfaceTys = ArrayList<Ty>()
        for (typeNode in decl.inheritedTypes) {
            if (let Some(inheritedTy) <- typeNode.GetTy()) {
                if (let Some(baseDecl) <- Ty.GetInheritableDeclPtrOfTy(inheritedTy)) {
                    if (baseDecl.astKind == ASTKind.INTERFACE_DECL && !baseDecl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                        CheckMembersWithInheritedDecls(baseDecl)
                        var found = false
                        for (value in interfaceTys) {
                            if (SameTy(value, inheritedTy)) {
                                found = true
                                break
                            }
                        }
                        if (!found) {
                            interfaceTys.add(inheritedTy)
                        }
                    }
                }
            }
        }
        let members = MemberMap()
        for (interfaceTy in interfaceTys) {
            if (let Some(interfaceDecl) <- Ty.GetInheritableDeclPtrOfTy(interfaceTy)) {
                MergeInheritedMembers(members, GetStoredMembersForDecl(interfaceDecl), interfaceTy, inheritedInterfaces: true)
            }
        }
        DiagnoseForConflictInheritance(decl, members)
        return members
    }

    private func GetInheritedSuperMembers(
        decl: InheritableDecl,
        baseTy: Ty,
        curFile: File,
        ignoreExtends!: Bool = false
    ): MemberMap {
        let members = MemberMap()
        MergeInheritedMembers(members, GetStoredMembersForDecl(decl), baseTy)
        if (let Some(currentPkg) <- curFile.curPackage) {
            RemoveInvisibleMember(members, currentPkg.fullPackageName)
        }
        if (ignoreExtends) {
            return members
        }
        for (extendDecl in CollectExtendsForDecl(decl, baseTy)) {
            if (!Ty.IsTyCorrect(extendDecl.GetTy())) {
                continue
            }
            CheckMembersWithInheritedDecls(extendDecl)
            let extendMembers = GetStoredMembersForDecl(extendDecl)
            if (let Some(currentPkg) <- curFile.curPackage) {
                RemoveInvisibleMember(members, currentPkg.fullPackageName)
            }
            MergeInheritedMembers(members, extendMembers, baseTy)
        }
        return members
    }

    private func GetAndCheckInheritedMembers(decl: InheritableDecl): MemberMap {
        if (!Ty.IsTyCorrect(decl.GetTy())) {
            return MemberMap()
        }
        var baseDecl: Option<InheritableDecl> = None
        var baseTy: Option<Ty> = None
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            for (typeNode in classDecl.inheritedTypes) {
                if (let Some(ty) <- typeNode.GetTy()) {
                    if (let Some(classTy) <- (ty as ClassTy)) {
                        if (let Some(superDecl) <- classTy.declPtr) {
                            baseDecl = superDecl
                            baseTy = ty
                        }
                    }
                }
            }
        } else if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(extendedTy) <- extendedType.GetTy()) {
                    baseDecl = Ty.GetInheritableDeclPtrOfTy(extendedTy)
                    baseTy = extendedTy
                }
            }
        }
        if (let Some(realBaseDecl) <- baseDecl) {
            if (let Some(realBaseTy) <- baseTy) {
                if (!realBaseDecl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                    CheckMembersWithInheritedDecls(realBaseDecl)
                    if (let Some(curFile) <- decl.curFile) {
                        return GetInheritedSuperMembers(
                            realBaseDecl,
                            realBaseTy,
                            curFile,
                            ignoreExtends: decl.astKind == ASTKind.EXTEND_DECL
                        )
                    }
                }
            }
        }
        return MemberMap()
    }

    private func CollectExtendsForDecl(decl: InheritableDecl, baseTy: Ty): ArrayList<ExtendDecl> {
        let out = ArrayList<ExtendDecl>()
        for (extendDecl in typeManager.GetDeclExtends(decl)) {
            AddExtendUnique(out, extendDecl)
        }
        for (extendDecl in typeManager.GetAllExtendsByTy(baseTy)) {
            AddExtendUnique(out, extendDecl)
        }
        return out
    }

    private func GetVisibleExtendMembersForExtend(decl: InheritableDecl): (MemberMap, MemberMap) {
        let interfaceMembers = MemberMap()
        let extendMembers = MemberMap()
        let invisibleInterfaceMembers = MemberMap()
        let invisibleExtendMembers = MemberMap()
        if (let Some(ed) <- (decl as ExtendDecl)) {
            if (let Some(extendedType) <- ed.extendedType) {
                if (let Some(extendedTy) <- extendedType.GetTy()) {
                    let allExtends = CollectExtendsForTy(extendedTy)
                    let mts = MultiTypeSubst()
                    typeManager.GenerateGenericMapping(mts, extendedTy)
                    for (otherExtend in allExtends) {
                        if (SameDecl(otherExtend, ed) || (let None <- otherExtend.extendedType)) {
                            continue
                        }
                        if (decl.fullPackageName != otherExtend.fullPackageName && !otherExtend.TestAttr(Attribute.PUBLIC)) {
                            continue
                        }
                        let visible = typeManager.CheckGenericDeclInstantiation(otherExtend, extendedTy.typeArgs)
                        if (!visible) {
                            typeManager.GenerateStructDeclGenericMapping(mts, otherExtend, extendedTy)
                        }
                        let targetInterfaceMap = if (visible) { interfaceMembers } else { invisibleInterfaceMembers }
                        let targetExtendMap = if (visible) { extendMembers } else { invisibleExtendMembers }
                        let curInterfaceMap = GetAndCheckInheritedInterfaces(otherExtend)
                        for (entry in curInterfaceMap.entries) {
                            entry.signature.extendDecl = otherExtend
                        }
                        MergeInheritedMembers(targetInterfaceMap, curInterfaceMap, extendedTy)
                        let typeMapping = MultiTypeSubstToTypeSubstForInheritance(mts)
                        for (edMember in otherExtend.GetMemberDecls()) {
                            if (!Ty.IsTyCorrect(edMember.GetTy()) || IsInvisibleMember(edMember, decl.fullPackageName)) {
                                continue
                            }
                            let memberTy: Option<Ty> = if (let Some(ty) <- edMember.GetTy()) {
                                Some(typeManager.GetInstantiatedTy(ty, typeMapping))
                            } else {
                                None
                            }
                            let structTy: Option<Ty> = if (let Some(ty) <- otherExtend.GetTy()) {
                                Some(typeManager.GetInstantiatedTy(ty, typeMapping))
                            } else {
                                None
                            }
                            let sig = MemberSignature(
                                decl: edMember,
                                ty: memberTy,
                                structTy: structTy,
                                extendDecl: otherExtend
                            )
                            for (bounds in GetAllGenericUpperBounds(typeManager, edMember)) {
                                sig.upperBounds.add(bounds)
                            }
                            let _ = UpdateInheritedMemberIfNeeded(targetExtendMap, sig)
                        }
                    }
                    MergeInheritedMembers(interfaceMembers, extendMembers, extendedTy)
                    MergeInheritedMembers(invisibleInterfaceMembers, invisibleExtendMembers, extendedTy)
                    RemoveAbstractMembers(interfaceMembers)
                    RemoveAbstractMembers(invisibleInterfaceMembers)
                }
            }
        }
        return (interfaceMembers, invisibleInterfaceMembers)
    }

    private func CheckExtendExportDependence(
        curDecl: InheritableDecl,
        interfaceSig: MemberSignature,
        implDecls: MemberMap
    ): Unit {
        if ((let None <- (curDecl as ExtendDecl)) || !curDecl.IsExportedDecl()) {
            return
        }
        if (let None <- interfaceSig.decl) {
            return
        }
        let interfaceDecl = interfaceSig.decl.getOrThrow()
        for (child in implDecls.Get(interfaceDecl.identifier.Val())) {
            if (let None <- child.decl) {
                continue
            }
            let childDecl = child.decl.getOrThrow()
            if (childDecl.astKind != interfaceDecl.astKind) {
                continue
            }
            var implemented = interfaceDecl.astKind == ASTKind.PROP_DECL
            if (!implemented && interfaceDecl.IsFunc()) {
                implemented = CheckImplementationRelation(interfaceSig, child)
            }
            if (!implemented) {
                continue
            }
            if (let Some(parentOuter) <- interfaceDecl.outerDecl) {
                if (let Some(childOuter) <- childDecl.outerDecl) {
                    if (parentOuter.IsExportedDecl() && !childOuter.IsExportedDecl()) {
                        let builder = diag.DiagnoseRefactor(
                            DiagKindRefactor.sema_export_extend_depend_non_export_extend,
                            DeclRange(curDecl),
                            arguments: [interfaceDecl.identifier.Val()]
                        )
                        builder.AddNote(DeclRange(childOuter), "following extension cannot be exported")
                    }
                }
            }
        }
    }

    private func CollectExtendsForTy(ty: Ty): ArrayList<ExtendDecl> {
        let out = ArrayList<ExtendDecl>()
        for (extendDecl in typeManager.GetAllExtendsByTy(ty)) {
            AddExtendUnique(out, extendDecl)
        }
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(ty)) {
            for (extendDecl in typeManager.GetDeclExtends(decl)) {
                AddExtendUnique(out, extendDecl)
            }
        }
        return out
    }

    private func RemoveAbstractMembers(members: MemberMap): Unit {
        var idx: Int64 = 0
        while (idx < members.entries.size) {
            if (let Some(decl) <- members.entries[idx].signature.decl) {
                if (decl.TestAttr(Attribute.ABSTRACT)) {
                    members.Remove(idx)
                    continue
                }
            }
            idx++
        }
    }

    public func ComputeInconsistentTypes(
        child: MemberSignature,
        parent: MemberSignature,
        updated: MemberSignature,
        status: (Bool, Bool),
        inconsistentTypes: TySet
    ): Bool {
        let parentTy = FuncTyFromOption(parent.ty)
        let childTy = FuncTyFromOption(child.ty)
        if (let Some(parentFuncTy) <- parentTy) {
            if (let Some(childFuncTy) <- childTy) {
                var hasConsistentReturnTy = true
                if (status[0]) {
                    var parentAbstract = false
                    if (let Some(parentDecl) <- parent.decl) {
                        parentAbstract = parentDecl.TestAttr(Attribute.ABSTRACT)
                    }
                    var childAbstract = false
                    if (let Some(childDecl) <- child.decl) {
                        childAbstract = childDecl.TestAttr(Attribute.ABSTRACT)
                    }
                    let isValidOverride = parentAbstract || !childAbstract
                    hasConsistentReturnTy = isValidOverride && AreReturnTypesCompatible(parentFuncTy, childFuncTy)
                    var bothInterfaceMember = false
                    if (status[1]) {
                        if (let Some(childDecl) <- child.decl) {
                            if (let Some(parentDecl) <- parent.decl) {
                                if (let Some(childOuter) <- childDecl.outerDecl) {
                                    if (let Some(parentOuter) <- parentDecl.outerDecl) {
                                        bothInterfaceMember = childOuter.astKind == ASTKind.INTERFACE_DECL &&
                                            parentOuter.astKind == ASTKind.INTERFACE_DECL
                                    }
                                }
                            }
                        }
                    }
                    let needUpdateTy = bothInterfaceMember && AreReturnTypesCompatible(childFuncTy, parentFuncTy)
                    hasConsistentReturnTy = hasConsistentReturnTy || needUpdateTy
                    if (needUpdateTy) {
                        updated.ty = parentFuncTy
                    }
                }
                if (!hasConsistentReturnTy) {
                    AddPossibleInconsistentTypes(parent, child, inconsistentTypes)
                }
                return hasConsistentReturnTy
            }
        }
        return true
    }

    public func UpdateInheritedMemberIfNeeded(
        inheritedMembers: MemberMap,
        child: MemberSignature,
        inheritedInterfaces!: Bool = false
    ): MemberSignature {
        if (let None <- child.decl) {
            return child
        }
        let childDecl = child.decl.getOrThrow()
        let updated = child.Clone()
        var needImplement = inheritedInterfaces
        if (let Some(outer) <- childDecl.outerDecl) {
            needImplement = needImplement || outer.astKind == ASTKind.INTERFACE_DECL
        }
        let inconsistentTypes = TySet()
        for (entry in inheritedMembers.entries) {
            if (entry.name != childDecl.identifier.Val()) {
                continue
            }
            let parent = entry.signature.Clone()
            if (let None <- parent.decl) {
                continue
            }
            let parentDecl = parent.decl.getOrThrow()
            if (parentDecl.astKind != childDecl.astKind) {
                continue
            }
            var shouldUpdate = true
            var inconsistentType = needImplement && TyOptionsDiffer(parent.ty, child.ty)
            if (parentDecl.IsFunc()) {
                if (childDecl.TestAttr(Attribute.GENERIC) && parentDecl.TestAttr(Attribute.GENERIC)) {
                    let typeMapping = typeManager.GenerateGenericMappingFromGeneric(parentDecl, childDecl)
                    if (let Some(parentTy) <- parent.ty) {
                        parent.ty = typeManager.GetInstantiatedTy(parentTy, typeMapping)
                    }
                }
                let parentFuncTy = FuncTyFromOption(parent.ty)
                let childFuncTy = FuncTyFromOption(child.ty)
                let sameStatus = parentDecl.TestAttr(Attribute.STATIC) == childDecl.TestAttr(Attribute.STATIC) &&
                    childDecl.TestAttr(Attribute.GENERIC) == parentDecl.TestAttr(Attribute.GENERIC)
                shouldUpdate = false
                if (let Some(parentFt) <- parentFuncTy) {
                    if (let Some(childFt) <- childFuncTy) {
                        shouldUpdate = sameStatus && typeManager.IsFuncParameterTypesIdentical(parentFt, childFt)
                    }
                }
                let consistent = ComputeInconsistentTypes(
                    child,
                    parent,
                    updated,
                    (shouldUpdate, inheritedInterfaces),
                    inconsistentTypes
                )
                inconsistentType = inconsistentType && !consistent
            } else if (inconsistentType) {
                AddPossibleInconsistentTypes(parent, child, inconsistentTypes)
            }
            if (shouldUpdate) {
                if (parentDecl.TestAttr(Attribute.ABSTRACT) || !childDecl.TestAttr(Attribute.ABSTRACT)) {
                    UpdateOverriddenFuncDeclCache(childDecl, parentDecl)
                    entry.signature = updated.Clone()
                }
                entry.signature.replaceOther = true
                if (needImplement && (!parent.inconsistentTypes.IsEmpty() || inconsistentType)) {
                    UpdateInconsistentTypesForInheritance(entry.signature, parent, inconsistentTypes)
                }
                MergeUpperBoundsForInheritance(typeManager, entry.signature, parent, inheritedInterfaces)
                MergeUpperBoundsForInheritance(typeManager, entry.signature, child, inheritedInterfaces)
                if ((let None <- parent.extendDecl) || (let None <- child.extendDecl)) {
                    entry.signature.extendDecl = None
                }
                entry.signature.isInheritedInterface = child.isInheritedInterface && inheritedInterfaces
                let relationExtend = IsRelationExtend(child)
                entry.signature.shouldBeImplemented = (entry.signature.isInheritedInterface || !relationExtend) &&
                    childDecl.TestAttr(Attribute.DEFAULT) && parentDecl.TestAttr(Attribute.DEFAULT)
                return entry.signature
            }
        }
        inheritedMembers.Add(childDecl.identifier.Val(), updated)
        return updated
    }

    private func IsRelationExtend(child: MemberSignature): Bool {
        if (checkingDecls.isEmpty()) {
            return true
        }
        if (checkingDecls[0].astKind != ASTKind.EXTEND_DECL) {
            return true
        }
        if (let Some(childExtend) <- child.extendDecl) {
            if (let Some(curExtend) <- (checkingDecls[0] as ExtendDecl)) {
                return typeManager.IsExtendInheritRelation(curExtend, childExtend)[0]
            }
        }
        return true
    }

    public func MergeInheritedMembers(
        members: MemberMap,
        otherMembers: MemberMap,
        structTy: Ty,
        inheritedInterfaces!: Bool = false
    ): Unit {
        if (otherMembers.IsEmpty()) {
            return
        }
        let mts = MultiTypeSubst()
        typeManager.GenerateGenericMapping(mts, structTy)
        let typeMapping = MultiTypeSubstToTypeSubstForInheritance(mts)
        for (entry in otherMembers.entries) {
            if (typeMapping.IsEmpty() && !inheritedInterfaces) {
                let _ = UpdateInheritedMemberIfNeeded(members, entry.signature, inheritedInterfaces: false)
                continue
            }
            let memberSig = entry.signature.Clone()
            if (inheritedInterfaces) {
                memberSig.isInheritedInterface = true
            }
            if (!typeMapping.IsEmpty()) {
                if (let Some(ty) <- memberSig.ty) {
                    memberSig.ty = typeManager.GetInstantiatedTy(ty, typeMapping)
                }
                if (let Some(sigStructTy) <- memberSig.structTy) {
                    memberSig.structTy = typeManager.GetInstantiatedTy(sigStructTy, typeMapping)
                }
                UpdateUpperBoundsSetForInheritance(typeManager, memberSig.upperBounds, typeMapping)
            }
            let _ = UpdateInheritedMemberIfNeeded(members, memberSig, inheritedInterfaces: inheritedInterfaces)
        }
    }

    private func UpdateOverriddenFuncDeclCache(child: Decl, parent: Decl): Unit {
        if (checkingDecls.isEmpty()) {
            return
        }
        if (let Some(outer) <- child.outerDecl) {
            if (SameDecl(outer, checkingDecls[checkingDecls.size - 1])) {
                typeManager.UpdateTopOverriddenFuncDeclMap(child, parent)
            }
        }
    }

    private func AreReturnTypesCompatible(parentTy: FuncTy, childTy: FuncTy, inconsistentTypes!: TySet = TySet()): Bool {
        for (ty in inconsistentTypes.values) {
            if (!typeManager.IsSubtype(childTy.retTy, ty, implicitBoxed: false)) {
                return false
            }
        }
        if (!CheckReturnOverrideByGeneric(parentTy, childTy)) {
            return false
        }
        return typeManager.IsSubtype(childTy.retTy, parentTy.retTy, implicitBoxed: false)
    }

    private func CheckReturnOverrideByGeneric(parentTy: FuncTy, childTy: FuncTy): Bool {
        if (!Ty.IsTyCorrect(childTy.retTy) || !Ty.IsTyCorrect(parentTy.retTy)) {
            return true
        }
        if (!childTy.retTy.IsGeneric() || SameTy(parentTy.retTy, childTy.retTy)) {
            return true
        }
        if (let Some(genericTy) <- (childTy.retTy as GenericsTy)) {
            if (genericTy.upperBounds.isEmpty()) {
                return false
            }
            for (upper in genericTy.upperBounds) {
                if (!upper.IsInterface() && !upper.IsGeneric()) {
                    return true
                }
            }
        }
        return false
    }

    private func DiagnoseForInheritedMember(parent: MemberSignature, child: MemberSignature): Unit {
        if (let Some(parentDecl) <- parent.decl) {
            if (let Some(childDecl) <- child.decl) {
                if (parentDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR) && childDecl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                    return
                }
                if (let Some(parentOuter) <- parentDecl.outerDecl) {
                    if (let Some(childOuter) <- childDecl.outerDecl) {
                        if (SameDecl(parentOuter, childOuter)) {
                            return
                        }
                    }
                }
                CheckSameNameInheritanceInfo(parent, childDecl)
                if (childDecl.astKind != parentDecl.astKind) {
                    return
                }
                if (parentDecl.astKind == ASTKind.PROP_DECL) {
                    CheckInheritanceAttributes(parent, childDecl)
                    CheckPropertyInheritance(parent, childDecl)
                } else if (parentDecl.IsFunc()) {
                    if (CheckImplementationRelation(parent, child)) {
                        CheckInheritanceAttributes(parent, childDecl)
                    }
                }
            }
        }
    }

    private func DiagnoseForInheritedInterfaces(interfaceSig: MemberSignature, implDecls: MemberMap): Unit {
        if (let Some(interfaceDecl) <- interfaceSig.decl) {
            for (child in implDecls.Get(interfaceDecl.identifier.Val())) {
                if (let Some(childDecl) <- child.decl) {
                    CheckSameNameInheritanceInfo(interfaceSig, childDecl)
                    if (childDecl.astKind != interfaceDecl.astKind) {
                        continue
                    }
                    if (interfaceDecl.astKind == ASTKind.PROP_DECL) {
                        CheckInheritanceForInterface(interfaceSig, child)
                        CheckPropertyInheritance(interfaceSig, childDecl)
                    } else if (interfaceDecl.IsFunc()) {
                        if (CheckImplementationRelation(interfaceSig, child)) {
                            CheckInheritanceForInterface(interfaceSig, child)
                            CheckMutModifierCompatible(interfaceSig, childDecl)
                        }
                    }
                }
            }
            if (interfaceDecl.TestAttr(Attribute.DEFAULT)) {
                interfaceDecl.EnableAttr(Attribute.INTERFACE_IMPL)
            }
        }
    }

    private func DiagnoseForUnimplementedInterfaces(members: MemberMap, structDecl: Decl): Unit {
        if (structDecl.TestAnyAttr(Attribute.FOREIGN, Attribute.OBJ_C_MIRROR, Attribute.OBJ_C_MIRROR_SYNTHETIC_WRAPPER)) {
            return
        }
        let prefix = if (structDecl.astKind == ASTKind.EXTEND_DECL) { "extend " } else { "" }
        let structName = prefix + InheritedDisplayName(structDecl)
        let unimplementedMembers = ArrayList<MemberSignature>()
        for (entry in members.entries) {
            let member = entry.signature
            if (let None <- member.decl) {
                continue
            }
            let memberDecl = member.decl.getOrThrow()
            let notInheritable = memberDecl.astKind != ASTKind.PROP_DECL && !memberDecl.IsFunc()
            if (notInheritable || (let Some(_) <- member.extendDecl)) {
                continue
            }
            if (IsBuiltInOperatorFuncInExtend(diag, typeManager, member, structDecl)) {
                continue
            }
            if (structDecl.TestAttr(Attribute.COMMON) && member.isInheritedInterface &&
                IsCommonWithoutDefault(memberDecl) && (if (let Some(outer) <- memberDecl.outerDecl) { SameDecl(outer, structDecl) } else { false })) {
                continue
            }
            var skip = false
            if (let Some(outer) <- memberDecl.outerDecl) {
                skip = outer.TestAttr(Attribute.FOREIGN)
                skip = skip || (outer.TestAttr(Attribute.ABSTRACT) && memberDecl.TestAttr(Attribute.ABSTRACT) &&
                    structDecl.astKind == ASTKind.EXTEND_DECL)
            }
            skip = skip || (structDecl.astKind == ASTKind.EXTEND_DECL &&
                memberDecl.TestAttr(Attribute.ABSTRACT) && !member.isInheritedInterface)
            if (skip) {
                continue
            }
            let isAbstractClass = structDecl.TestAttr(Attribute.ABSTRACT) && structDecl.astKind == ASTKind.CLASS_DECL
            let isAbstractDecl = isAbstractClass || structDecl.astKind == ASTKind.INTERFACE_DECL
            let isStaticAbsMember = memberDecl.TestAttr(Attribute.STATIC) && memberDecl.TestAttr(Attribute.ABSTRACT)
            if (memberDecl.TestAttr(Attribute.ABSTRACT) && !isAbstractDecl) {
                unimplementedMembers.add(member.Clone())
            } else if (member.shouldBeImplemented) {
                diag.Diagnose(
                    structDecl.begin,
                    structDecl.end,
                    DiagKind.sema_interface_member_must_be_implemented,
                    args: [DiagArgument(DeclKindText(memberDecl)), DiagArgument(entry.name), DiagArgument(structName)]
                )
            } else if (isStaticAbsMember && isAbstractClass) {
                if (let Some(outer) <- memberDecl.outerDecl) {
                    if (!SameDecl(outer, structDecl)) {
                        diag.DiagnoseRefactor(
                            DiagKindRefactor.sema_inherit_abstract_class_static_unimplement_func,
                            DeclRange(structDecl),
                            arguments: [structName, DeclKindText(memberDecl), entry.name]
                        )
                    }
                }
            } else if (!member.inconsistentTypes.IsEmpty()) {
                if (let Some(outer) <- memberDecl.outerDecl) {
                    if (!SameDecl(outer, structDecl)) {
                        DiagnoseInheritedInsconsistType(member, structDecl)
                    }
                }
            }
        }
        if (!unimplementedMembers.isEmpty()) {
            let kind = if (structDecl.IsClassLikeDecl()) {
                DiagKindRefactor.sema_class_need_abstract_modifier_or_func_need_impl
            } else {
                DiagKindRefactor.sema_need_member_implementation
            }
            let builder = diag.DiagnoseRefactor(kind, DeclRange(structDecl), arguments: [structName])
            for (member in unimplementedMembers) {
                if (let Some(memberDecl) <- member.decl) {
                    let abstractType = if (if (let Some(outer) <- memberDecl.outerDecl) {
                        outer.astKind == ASTKind.CLASS_DECL
                    } else { false }) { "abstract" } else { "interface" }
                    let identifierName = if (CountByDecl(unimplementedMembers, memberDecl) > 1) {
                        UnimplementedIdentifier(member)
                    } else {
                        "'" + memberDecl.identifier.Val() + "'"
                    }
                    builder.AddNote(
                        DeclRange(memberDecl),
                        "unimplemented ${abstractType} ${DeclKindText(memberDecl)} ${identifierName}"
                    )
                }
            }
        }
    }

    private func DiagnoseForConflictInheritance(decl: InheritableDecl, members: MemberMap): Unit {
        for (name in members.Names()) {
            let found = members.Get(name)
            var allFunc = true
            for (member in found) {
                if (!member.IsFunc()) {
                    allFunc = false
                    break
                }
            }
            if (found.size > 1 && !allFunc) {
                let builder = diag.DiagnoseRefactor(
                    DiagKindRefactor.sema_inherit_super_member_kind_inconsistent,
                    DeclRange(decl),
                    arguments: [name]
                )
                for (member in found) {
                    if (let Some(memberDecl) <- member.decl) {
                        builder.AddNote(DeclRange(memberDecl), DeclKindText(memberDecl) + " member")
                    }
                }
            } else {
                for (member in found) {
                    if (!member.inconsistentTypes.IsEmpty() && member.IsProp()) {
                        DiagnoseInheritedInsconsistType(member, decl)
                    }
                }
            }
        }
    }

    private func DiagnoseInheritedInsconsistType(member: MemberSignature, node: Node): Unit {
        if (let Some(memberDecl) <- member.decl) {
            let typeName = if (memberDecl.astKind == ASTKind.PROP_DECL) { "type" } else { "return type" }
            let builder = diag.DiagnoseRefactor(
                DiagKindRefactor.sema_inherit_member_type_inconsistent,
                NodeRange(node),
                arguments: [typeName, DeclKindText(memberDecl), memberDecl.identifier.Val()]
            )
            builder.AddNote("conflict types are " + member.inconsistentTypes.ToString())
        }
    }

    private func CheckSameNameInheritanceInfo(parent: MemberSignature, child: Decl): Unit {
        if (let None <- parent.decl) {
            return
        }
        let parentDecl = parent.decl.getOrThrow()
        let name = child.identifier.Val()
        let childStatic = if (child.TestAttr(Attribute.STATIC)) { "static" } else { "non-static" }
        let parentStatic = if (parentDecl.TestAttr(Attribute.STATIC)) { "static" } else { "non-static" }
        let inheritance = if (!checkingDecls.isEmpty() && checkingDecls[0].astKind == ASTKind.EXTEND_DECL) {
            "extended type"
        } else {
            "parent class or interfaces"
        }
        if (child.TestAttr(Attribute.STATIC) != parentDecl.TestAttr(Attribute.STATIC)) {
            diag.Diagnose(
                child.begin,
                child.end,
                DiagKind.sema_static_and_non_static_member_cannot_have_same_name,
                args: [DiagArgument(childStatic), DiagArgument(name), DiagArgument(parentStatic), DiagArgument(inheritance)]
            )
            return
        }
        if (child.astKind != parentDecl.astKind) {
            if ((let Some(_) <- parent.extendDecl) || parent.isInheritedInterface || CheckExtendMemberValid(parent, child)) {
                let builder = diag.DiagnoseRefactor(
                    DiagKindRefactor.sema_inherit_member_kind_inconsistent,
                    DeclRange(child),
                    arguments: [DeclKindText(child), name, DeclKindText(parentDecl), inheritance]
                )
                builder.AddNote(DeclRange(parentDecl), "found conflict here")
            }
        } else if (parentDecl.astKind == ASTKind.VAR_DECL) {
            diag.Diagnose(
                child.begin,
                child.end,
                DiagKind.sema_member_variable_can_not_shadow,
                args: [DiagArgument(name)]
            )
        }
    }

    private func CheckInheritanceAttributes(parent: MemberSignature, child: Decl): Unit {
        if (let None <- parent.decl) {
            return
        }
        let parentDecl = parent.decl.getOrThrow()
        if (child.astKind != parentDecl.astKind || (parentDecl.astKind != ASTKind.PROP_DECL && !parentDecl.IsFunc())) {
            return
        }
        let typeText = DeclKindText(parentDecl)
        let name = child.identifier.Val()
        if (!CheckExtendMemberValid(parent, child) || (!checkingDecls.isEmpty() && checkingDecls[0].astKind == ASTKind.EXTEND_DECL)) {
            return
        }
        if (!parentDecl.TestAttr(Attribute.STATIC) && child.TestAttr(Attribute.REDEF)) {
            diag.Diagnose(
                child.begin,
                child.end,
                DiagKind.sema_func_no_override_or_redefine_modifier,
                args: [DiagArgument("redef"), DiagArgument(typeText), DiagArgument(name)]
            )
        } else if (!parentDecl.TestAttr(Attribute.ABSTRACT) && !parentDecl.TestAttr(Attribute.STATIC)) {
            let notInInterface = if (let Some(parentOuter) <- parentDecl.outerDecl) {
                parentOuter.astKind != ASTKind.INTERFACE_DECL
            } else {
                true
            }
            if (!parentDecl.TestAttr(Attribute.OPEN) && notInInterface) {
                let builder = diag.DiagnoseRefactor(
                    DiagKindRefactor.sema_cannot_override,
                    DeclRange(child),
                    arguments: [typeText, name]
                )
                builder.AddNote(DeclRange(parentDecl), "overridden definition is here")
            } else if (child.TestAttr(Attribute.ABSTRACT) && notInInterface) {
                diag.Diagnose(
                    child.begin,
                    child.end,
                    DiagKind.sema_invalid_override_member_in_class,
                    args: [DiagArgument(typeText), DiagArgument(name), DiagArgument(typeText)]
                )
            }
        }
    }

    private func CheckPropertyInheritance(parent: MemberSignature, child: Decl): Unit {
        if (let None <- parent.decl) {
            return
        }
        let parentDecl = parent.decl.getOrThrow()
        if (parentDecl.astKind != ASTKind.PROP_DECL) {
            return
        }
        if (TyOptionsDiffer(parent.ty, child.GetTy()) || !parent.inconsistentTypes.IsEmpty()) {
            diag.Diagnose(child.begin, child.end, DiagKind.sema_property_override_implement_type_diff)
        }
        if (let Some(parentProp) <- (parentDecl as PropDecl)) {
            if (let Some(childProp) <- (child as PropDecl)) {
                if (childProp.isVar != parentProp.isVar) {
                    let kind = if (parentProp.isVar) {
                        DiagKindRefactor.sema_property_have_same_declaration_in_inherit_mut
                    } else {
                        DiagKindRefactor.sema_property_have_same_declaration_in_inherit_immut
                    }
                    diag.DiagnoseRefactor(kind, DeclRange(child), arguments: [child.identifier.Val()])
                } else if (childProp.isVar && (childProp.getters.isEmpty() || childProp.setters.isEmpty()) &&
                    parentProp.TestAnyAttr(Attribute.DEFAULT, Attribute.ABSTRACT)) {
                    diag.DiagnoseRefactor(
                        DiagKindRefactor.sema_property_must_implement_both,
                        DeclRange(child),
                        arguments: [child.identifier.Val()]
                    )
                }
            }
        }
        CheckAccessVisibility(parentDecl, child, child)
    }

    private func CheckGenericTypeArgInfo(parent: MemberSignature, child: MemberSignature): Unit {
        if (let Some(parentDecl) <- parent.decl) {
            if (let Some(childDecl) <- child.decl) {
                let diffStatus = parentDecl.TestAttr(Attribute.STATIC) != childDecl.TestAttr(Attribute.STATIC)
                if ((let Some(_) <- parentDecl.GetGeneric()) && (let Some(_) <- childDecl.GetGeneric()) && !diffStatus) {
                    CheckGenericTypeBoundsMapped(parentDecl, childDecl, parent.upperBounds, child.upperBounds, diag, typeManager)
                }
            }
        }
    }

    private func CheckInheritanceForInterface(interfaceSig: MemberSignature, child: MemberSignature): Unit {
        if (let Some(interfaceMember) <- interfaceSig.decl) {
            if (let Some(childDecl) <- child.decl) {
                if (childDecl.astKind != interfaceMember.astKind ||
                    (interfaceMember.astKind != ASTKind.PROP_DECL && !interfaceMember.IsFunc())) {
                    return
                }
                let typeText = DeclKindText(interfaceMember)
                if (childDecl.TestAttr(Attribute.ABSTRACT) && !interfaceMember.TestAttr(Attribute.ABSTRACT)) {
                    diag.Diagnose(
                        childDecl.begin,
                        childDecl.end,
                        DiagKind.sema_invalid_override_or_redefine_member_in_interface,
                        args: [DiagArgument(typeText), DiagArgument(childDecl.identifier.Val()), DiagArgument(typeText)]
                    )
                }
                childDecl.EnableAttr(Attribute.INTERFACE_IMPL)
                if (let Some(propDecl) <- (childDecl as PropDecl)) {
                    for (getter in propDecl.getters) {
                        getter.EnableAttr(Attribute.INTERFACE_IMPL)
                    }
                    for (setter in propDecl.setters) {
                        setter.EnableAttr(Attribute.INTERFACE_IMPL)
                    }
                }
            }
        }
    }

    private func CheckImplementationRelation(parent: MemberSignature, child: MemberSignature): Bool {
        if (let None <- parent.decl) {
            return false
        }
        if (let None <- child.decl) {
            return false
        }
        let parentDecl = parent.decl.getOrThrow()
        let childDecl = child.decl.getOrThrow()
        if (!parentDecl.IsFunc()) {
            return false
        }
        var parentTy = parent.ty
        if (let Some(parentFunc) <- (parentDecl as FuncDecl)) {
            if (let Some(childFunc) <- (childDecl as FuncDecl)) {
                if (childFunc.TestAttr(Attribute.GENERIC) && parentDecl.TestAttr(Attribute.GENERIC)) {
                    let typeMapping = typeManager.GenerateGenericMappingFromGeneric(parentDecl, childDecl)
                    if (let Some(parentTyValue) <- parentTy) {
                        parentTy = typeManager.GetInstantiatedTy(parentTyValue, typeMapping)
                    }
                }
                if (let Some(parentFuncTy) <- FuncTyFromOption(parentTy)) {
                    if (let Some(childFuncTy) <- FuncTyFromOption(child.ty)) {
                        let sameSignature = typeManager.IsFuncParameterTypesIdentical(parentFuncTy, childFuncTy)
                        if (sameSignature) {
                            if (!AreFuncParameterNameIdentical(parentFunc, childFunc)) {
                                DiagnoseParameterName(diag, parentFunc, childFunc)
                            } else if (!CheckThisTypeCompatibility(parentFunc, childFunc)) {
                                let builder = diag.DiagnoseRefactor(
                                    DiagKindRefactor.sema_inherit_not_return_this,
                                    DeclRange(childFunc)
                                )
                                builder.AddNote(DeclRange(parentFunc), "the overridden function")
                            } else if (AreReturnTypesCompatible(parentFuncTy, childFuncTy, inconsistentTypes: parent.inconsistentTypes)) {
                                var diagNode: Decl = childFunc
                                if (!checkingDecls.isEmpty()) {
                                    if (let Some(childOuter) <- childFunc.outerDecl) {
                                        if (!SameDecl(childOuter, checkingDecls[0])) {
                                            diagNode = checkingDecls[0]
                                        }
                                    }
                                }
                                CheckAccessVisibility(parentFunc, childFunc, diagNode)
                                CheckGenericTypeArgInfo(parent, child)
                            } else if (!CheckReturnOverrideByGeneric(parentFuncTy, childFuncTy)) {
                                let builder = diag.Diagnose(
                                    childFunc.begin,
                                    childFunc.end,
                                    DiagKind.sema_return_type_invariance,
                                    args: [DiagArgument(childFunc.identifier.Val()), DiagArgument(parentFuncTy.retTy.String())]
                                )
                                builder.AddNote(DeclRange(parentFunc), "cannot override/implement the following function")
                            } else {
                                let builder = diag.DiagnoseRefactor(
                                    DiagKindRefactor.sema_return_type_incompatible,
                                    DeclRange(childFunc),
                                    arguments: [childFunc.identifier.Val()]
                                )
                                builder.AddNote(
                                    DeclRange(parentFunc),
                                    "'" + childFuncTy.retTy.String() + "' is not a subtype of '" + parentFuncTy.retTy.String() + "'"
                                )
                            }
                            if (!childFunc.IsConst() && parentDecl.IsConst()) {
                                let inheritance = if (!checkingDecls.isEmpty() && checkingDecls[0].astKind == ASTKind.EXTEND_DECL) {
                                    "extended type"
                                } else {
                                    "parent class or interfaces"
                                }
                                let builder = diag.DiagnoseRefactor(
                                    DiagKindRefactor.sema_inherit_member_kind_inconsistent,
                                    DeclRange(childFunc),
                                    arguments: ["non-constant function", childFunc.identifier.Val(), "'const' function", inheritance]
                                )
                                builder.AddNote(DeclRange(parentDecl), "found 'const' function here")
                            }
                        }
                        return sameSignature
                    }
                }
            }
        }
        return false
    }

    private func CheckMutModifierCompatible(parent: MemberSignature, child: Decl): Unit {
        if (let None <- parent.decl) {
            return
        }
        let parentDecl = parent.decl.getOrThrow()
        if (!parentDecl.IsFunc()) {
            return
        }
        if (let Some(parentOuter) <- parentDecl.outerDecl) {
            if (parentOuter.astKind != ASTKind.INTERFACE_DECL) {
                return
            }
        } else {
            return
        }
        var needsCheck = false
        if (let Some(outer) <- child.outerDecl) {
            if (let Some(extendDecl) <- (outer as ExtendDecl)) {
                if (let Some(ty) <- extendDecl.GetTy()) {
                    needsCheck = ty.IsStruct()
                }
            } else {
                needsCheck = outer.astKind == ASTKind.STRUCT_DECL
            }
        }
        if (!needsCheck) {
            return
        }
        if (parentDecl.TestAttr(Attribute.MUT) != child.TestAttr(Attribute.MUT)) {
            var diagDecl: Decl = child
            if (!checkingDecls.isEmpty()) {
                if (let Some(childOuter) <- child.outerDecl) {
                    if (!SameDecl(childOuter, checkingDecls[0])) {
                        diagDecl = checkingDecls[0]
                    }
                }
            }
            let interfaceName = if (let Some(outer) <- parentDecl.outerDecl) { outer.identifier.Val() } else { "" }
            diag.Diagnose(
                diagDecl.begin,
                diagDecl.end,
                DiagKind.sema_incompatible_mut_modifier_between_struct_and_interface,
                args: [DiagArgument(child.identifier.Val()), DiagArgument(interfaceName)]
            )
        }
    }

    private func CheckAccessVisibility(parent: Decl, child: Decl, diagNode: Decl): Unit {
        var canBeImplemented = parent.TestAnyAttr(Attribute.ABSTRACT, Attribute.OPEN, Attribute.STATIC)
        if (let Some(parentOuter) <- parent.outerDecl) {
            canBeImplemented = canBeImplemented || parentOuter.astKind == ASTKind.INTERFACE_DECL
        }
        if (!canBeImplemented) {
            return
        }
        let weakVisibility =
            (parent.TestAttr(Attribute.PUBLIC) && !child.TestAttr(Attribute.PUBLIC)) ||
            (parent.TestAttr(Attribute.PROTECTED) && !child.TestAnyAttr(Attribute.PUBLIC, Attribute.PROTECTED)) ||
            (!parent.TestAnyAttr(Attribute.PUBLIC, Attribute.PROTECTED, Attribute.PRIVATE) && child.TestAttr(Attribute.PRIVATE))
        if (weakVisibility) {
            let builder = diag.DiagnoseRefactor(DiagKindRefactor.sema_weak_visibility, DeclRange(diagNode))
            builder.AddNote(DeclRange(parent), "base visibility is stronger")
            builder.AddNote(DeclRange(child), "deriving visibility is weaker")
        }
    }

    private func IsExtendedDefaultImpl(parent: MemberSignature, child: Decl): Bool {
        if (let Some(parentDecl) <- parent.decl) {
            if ((parentDecl.astKind != ASTKind.FUNC_DECL && parentDecl.astKind != ASTKind.PROP_DECL) ||
                !parentDecl.TestAttr(Attribute.DEFAULT)) {
                return false
            }
            if (let Some(parentOuter) <- parentDecl.outerDecl) {
                if (parentOuter.astKind != ASTKind.INTERFACE_DECL) {
                    return false
                }
                if (let Some(childOuter) <- child.outerDecl) {
                    if (childOuter.astKind == ASTKind.EXTEND_DECL) {
                        return false
                    }
                    if (let Some(childTy) <- childOuter.GetTy()) {
                        if (let Some(parentTy) <- parentOuter.GetTy()) {
                            return typeManager.HasExtensionRelation(childTy, parentTy)
                        }
                    }
                }
            }
        }
        return false
    }

    private func CheckExtendMemberValid(parent: MemberSignature, child: Decl): Bool {
        if (let Some(parentDecl) <- parent.decl) {
            if (let Some(_) <- parent.extendDecl) {
                if (!parentDecl.TestAnyAttr(Attribute.DEFAULT, Attribute.IN_EXTEND) && child.TestAttr(Attribute.IN_EXTEND)) {
                    return true
                }
                let typeName = if (let Some(outer) <- child.outerDecl) {
                    "extend " + InheritedDisplayName(outer)
                } else {
                    "extend"
                }
                diag.DiagnoseRefactor(
                    DiagKindRefactor.sema_extend_member_cannot_shadow,
                    DeclRange(child),
                    arguments: [child.identifier.Val(), typeName]
                )
            } else if (IsExtendedDefaultImpl(parent, child) || (if (let Some(outer) <- parentDecl.outerDecl) {
                outer.astKind == ASTKind.EXTEND_DECL
            } else { false })) {
                let builder = diag.DiagnoseRefactor(
                    DiagKindRefactor.sema_extend_function_cannot_overridden,
                    DeclRange(child),
                    arguments: [DeclKindText(parentDecl), child.identifier.Val()]
                )
                builder.AddNote(DeclRange(parentDecl), "overridden definition of '" + child.identifier.Val() + "' is here")
            } else if (if (let Some(outer) <- child.outerDecl) { outer.astKind == ASTKind.EXTEND_DECL } else { false }) {
                let builder = diag.DiagnoseRefactor(
                    DiagKindRefactor.sema_extend_member_cannot_shadow,
                    DeclRange(child),
                    arguments: [child.identifier.Val(), InheritedDisplayName(child.outerDecl.getOrThrow())]
                )
                builder.AddNote(DeclRange(parentDecl), "shadowed definition of '" + child.identifier.Val() + "' is here")
            } else {
                return true
            }
            return false
        }
        return true
    }

    private func DiagnoseForOverriddenMember(child: MemberSignature): Unit {
        if (child.replaceOther) {
            return
        }
        if (let Some(childDecl) <- child.decl) {
            let typeText = DeclKindText(childDecl)
            if (childDecl.TestAttr(Attribute.OVERRIDE)) {
                diag.Diagnose(
                    childDecl.begin,
                    childDecl.end,
                    DiagKind.sema_missing_overridden_func,
                    args: [DiagArgument(typeText), DiagArgument(childDecl.identifier.Val()), DiagArgument(typeText)]
                )
            } else if (childDecl.TestAttr(Attribute.REDEF) && childDecl.TestAttr(Attribute.STATIC)) {
                diag.Diagnose(
                    childDecl.begin,
                    childDecl.end,
                    DiagKind.sema_missing_redefined_func,
                    args: [DiagArgument(typeText), DiagArgument(childDecl.identifier.Val()), DiagArgument(typeText)]
                )
            }
        }
    }

    private func CheckAllUpperBoundsConfliction(): Unit {
        let genericsWithConstraint = ArrayList<Generic>()
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (node.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(generic) <- (node as Generic)) {
                if (!generic.genericConstraints.isEmpty()) {
                    genericsWithConstraint.add(generic)
                    return VisitAction.SKIP_CHILDREN
                }
            }
            return VisitAction.WALK_CHILDREN
        })
        walker.Walk()
        for (generic in genericsWithConstraint) {
            CheckUpperBoundsConfliction(generic)
        }
    }

    private func CheckUpperBoundsConfliction(generic: Generic): Unit {
        for (gc in generic.genericConstraints) {
            if (let None <- gc.refType) {
                continue
            }
            if (let Some(typeNode) <- gc.refType) {
                if (let Some(gTy) <- typeNode.GetTy()) {
                if (let Some(genericTy) <- (gTy as GenericsTy)) {
                    if (genericTy.upperBounds.isEmpty()) {
                        continue
                    }
                    var classTy: Option<Ty> = None
                    for (upper in genericTy.upperBounds) {
                        if (upper.IsClass()) {
                            if (let Some(existing) <- classTy) {
                                if (typeManager.IsSubtype(upper, existing)) {
                                    classTy = upper
                                }
                            } else {
                                classTy = upper
                            }
                        }
                    }
                    let inheritedMembers = MemberMap()
                    for (upper in genericTy.upperBounds) {
                        if (!upper.IsInterface()) {
                            continue
                        }
                        if (let Some(interfaceDecl) <- Ty.GetInheritableDeclPtrOfTy(upper)) {
                            if (let Some(_) <- FindStoredEntry(interfaceDecl)) {
                                MergeInheritedMembers(inheritedMembers, GetStoredMembersForDecl(interfaceDecl), upper, inheritedInterfaces: true)
                            }
                        }
                    }
                    if (let Some(realClassTy) <- classTy) {
                        if (let Some(classDecl) <- Ty.GetInheritableDeclPtrOfTy(realClassTy)) {
                            if (let Some(curFile) <- generic.curFile) {
                                let classMembers = GetInheritedSuperMembers(classDecl, realClassTy, curFile)
                                MergeInheritedMembers(inheritedMembers, classMembers, realClassTy, inheritedInterfaces: true)
                            }
                        }
                    }
                    for (entry in inheritedMembers.entries) {
                        if (!entry.signature.inconsistentTypes.IsEmpty()) {
                            DiagnoseInheritedInsconsistType(entry.signature, gc)
                        }
                    }
                }
                }
            }
        }
    }
}

public func SelfhostPortStatus_InheritanceChecker_StructInheritanceChecker(): Bool {
    return true
}
