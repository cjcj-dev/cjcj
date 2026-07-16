package cjcj::sema.InheritanceChecker

import std.collection.*
import cjcj::ast.*
import cjcj::basic.{DiagArgument, DiagKind, DiagKindRefactor}
import cjcj::sema.*

public class InstantiationTriggerInfo {
    public var node: Node
    public var decl: Decl
    public let instTys: ArrayList<Ty> = ArrayList<Ty>()

    public init(node: Node, decl: Decl, instTys: ArrayList<Ty>) {
        this.node = node
        this.decl = decl
        for (ty in instTys) {
            this.instTys.add(ty)
        }
    }
}

public class InstantiatedMemberDiagnosticPair {
    public var parent: MemberSignature
    public var child: MemberSignature

    public init(parent: MemberSignature, child: MemberSignature) {
        this.parent = parent.Clone()
        this.child = child.Clone()
    }
}

public class InstantiatedMemberDiagnosticRecord {
    public var key: String
    public let pairs: ArrayList<InstantiatedMemberDiagnosticPair> = ArrayList<InstantiatedMemberDiagnosticPair>()

    public init(key: String) {
        this.key = key
    }
}

public class InstantiatedTyCacheEntry {
    public var source: Ty
    public var instantiated: Ty

    public init(source: Ty, instantiated: Ty) {
        this.source = source
        this.instantiated = instantiated
    }
}

public class InstantiatedTyCacheRecord {
    public var key: String
    public let entries: ArrayList<InstantiatedTyCacheEntry> = ArrayList<InstantiatedTyCacheEntry>()

    public init(key: String) {
        this.key = key
    }
}

func InstantiationKey(decl: Decl, instTys: ArrayList<Ty>): String {
    let parts = ArrayList<String>()
    for (ty in instTys) {
        parts.add(ty.String())
    }
    return "${decl.fullPackageName}:${decl.identifier.Val()}:${decl.begin.ToString()}:${JoinStrings(parts, ",")}"
}

private func GetReferenceTyAndTarget(node: Node): (Option<Ty>, Option<Decl>) {
    var target = GetRealTarget(node.GetTarget())
    var baseTy = node.GetTy()
    if (let Some(realTarget) <- target) {
        if (IsClassOrEnumConstructor(realTarget)) {
            target = realTarget.outerDecl
            if (let Some(nodeTy) <- node.GetTy()) {
                if (let Some(funcTy) <- (nodeTy as FuncTy)) {
                    baseTy = Some(funcTy.retTy)
                }
            }
        }
    }
    return (baseTy, target)
}

private func HasExtendForInstantiation(values: ArrayList<ExtendDecl>, extendDecl: ExtendDecl): Bool {
    for (value in values) {
        if (SameDecl(value, extendDecl)) {
            return true
        }
    }
    return false
}

private func IsVisibleGenericExtendForInstantiation(
    checker: StructInheritanceChecker,
    extendDecl: ExtendDecl,
    instTys: ArrayList<Ty>
): Bool {
    if (!checker.IsExtendVisibleInCurpkg(extendDecl)) {
        return false
    }
    return extendDecl.TestAttr(Attribute.GENERIC) && checker.typeManager.CheckGenericDeclInstantiation(extendDecl, instTys)
}

private func AddVisibleExtendForInstantiation(
    checker: StructInheritanceChecker,
    out: ArrayList<ExtendDecl>,
    extendDecl: ExtendDecl,
    instTys: ArrayList<Ty>
): Unit {
    if (HasExtendForInstantiation(out, extendDecl)) {
        return
    }
    if (IsVisibleGenericExtendForInstantiation(checker, extendDecl, instTys)) {
        var idx: Int64 = 0
        while (idx < out.size) {
            if (InheritanceDeclLessByPosition(extendDecl, out[idx])) {
                out.add(extendDecl, at: idx)
                return
            }
            idx++
        }
        out.add(extendDecl)
    }
}

private func GetVisibleExtendsForInstantiation(
    checker: StructInheritanceChecker,
    decl: Decl,
    instTys: ArrayList<Ty>
): ArrayList<ExtendDecl> {
    let out = ArrayList<ExtendDecl>()
    if (decl.astKind == ASTKind.EXTEND_DECL || !Ty.IsTyCorrect(decl.GetTy())) {
        return out
    }
    if (let Some(declTy) <- decl.GetTy()) {
        for (extendDecl in checker.typeManager.GetAllExtendsByTy(declTy)) {
            AddVisibleExtendForInstantiation(checker, out, extendDecl, instTys)
        }
    }
    return out
}

private func MarkUpperBoundIgnored(node: Node, generic: Generic): Unit {
    for (constraint in generic.genericConstraints) {
        for (upperBound in constraint.upperBounds) {
            if (let Some(upperTy) <- upperBound.GetTy()) {
                if (upperTy.HasGeneric()) {
                    upperBound.visitedByWalkerID = node.visitedByWalkerID
                }
            }
        }
    }
}

func CheckInstMemberSignatures(
    checker: StructInheritanceChecker,
    decl: InheritableDecl,
    instTys: ArrayList<Ty>
): Unit {
    if (!checker.HasInstantiationTrigger()) {
        return
    }
    let key = InstantiationKey(decl, instTys)
    if (checker.HasInstantiatedKey(key)) {
        checker.ReplayInstantiatedMemberDiagnostics(key)
        return
    }
    let typeMapping = GenerateTypeMapping(decl, instTys)
    checker.CheckMembersWithInheritedDecls(decl)
    let members = checker.GetStoredMembersForDecl(decl).Clone()
    for (member in decl.GetMemberDecls()) {
        if (!Ty.IsTyCorrect(member.GetTy()) || (let None <- member.outerDecl)) {
            continue
        }
        if (IsInstanceConstructor(member) || member.TestAttr(Attribute.PRIVATE)) {
            let sig = MemberSignature(decl: member, ty: member.GetTy(), structTy: decl.GetTy())
            let _ = checker.UpdateInheritedMemberIfNeeded(members, sig)
        }
    }
    let genericTyMembers = MemberMap()
    var idx: Int64 = 0
    while (idx < members.entries.size) {
        let memberSig = members.entries[idx].signature
        if (let Some(memberDecl) <- memberSig.decl) {
            if (memberDecl.TestAttr(Attribute.GENERIC) || memberDecl.astKind != ASTKind.FUNC_DECL) {
                members.Remove(idx)
                continue
            }
            if (let Some(memberTy) <- memberSig.ty) {
                if (memberTy.HasGeneric()) {
                    genericTyMembers.Add(members.entries[idx].name, memberSig.Clone())
                    members.Remove(idx)
                    continue
                }
            }
        }
        idx++
    }
    for (entry in genericTyMembers.entries) {
        let memberSig = entry.signature.Clone()
        if (let Some(memberTy) <- memberSig.ty) {
            memberSig.ty = checker.GetCachedInstantiatedTy(key, memberTy, typeMapping)
        }
        if (let Some(memberStructTy) <- memberSig.structTy) {
            memberSig.structTy = checker.GetCachedInstantiatedTy(key, memberStructTy, typeMapping)
        }
        for (candidate in members.Get(entry.name)) {
            let parent = candidate.Clone()
            if (let Some(parentStructTy) <- parent.structTy) {
                parent.structTy = checker.GetCachedInstantiatedTy(key, parentStructTy, typeMapping)
            }
            checker.DiagnoseForInstantiatedMember(parent, memberSig)
            checker.RecordInstantiatedMemberDiagnostic(key, parent, memberSig)
        }
        members.Add(entry.name, memberSig)
    }
}

private func InstantiationTriggeredInside(checker: StructInheritanceChecker, decl: Decl): Bool {
    if (let Some(trigger) <- checker.CurrentInstantiationTrigger()) {
        return SameDecl(trigger.decl, decl)
    }
    return false
}

private func ContainsRecursiveInstantiationArg(
    checker: StructInheritanceChecker,
    genericTy: Ty,
    arg: Ty,
    currentMapping: Option<TypeSubst>,
    triggeredInside: Bool
): Bool {
    var substitutedTy = arg
    if (let Some(mapping) <- currentMapping) {
        substitutedTy = checker.typeManager.GetInstantiatedTy(arg, mapping)
    }
    if (arg.Contains(genericTy) || substitutedTy.Contains(genericTy)) {
        return true
    }
    var noRecursion = !triggeredInside
    if (!noRecursion) {
        if (let Some(directGenericArg) <- Ty.GetGenericTyOfInsTy(arg)) {
            noRecursion = directGenericArg.Contains(genericTy)
        }
    }
    if (noRecursion) {
        return false
    }
    if (let Some(substitutedGenericArg) <- Ty.GetGenericTyOfInsTy(substitutedTy)) {
        return substitutedGenericArg.Contains(genericTy)
    }
    return false
}

private func HasSelfRecursiveInstantiation(
    checker: StructInheritanceChecker,
    genericTy: Ty,
    instTy: Ty,
    currentMapping: Option<TypeSubst>,
    triggeredInside: Bool
): Bool {
    for (arg in instTy.typeArgs) {
        if (ContainsRecursiveInstantiationArg(checker, genericTy, arg, currentMapping, triggeredInside)) {
            return true
        }
    }
    return false
}

private func WillCauseInfiniteInstantiation(
    checker: StructInheritanceChecker,
    triggerNode: Node,
    decl: Decl,
    instTys: ArrayList<Ty>,
    typeMapping: TypeSubst
): Bool {
    if (HaveCyclicSubstitution(checker.typeManager, typeMapping)) {
        Diagnose(checker.diag, triggerNode, DiagKind.sema_generic_infinite_instantiation).Emit()
        checker.MarkInfiniteInstantiationOccurred()
        return true
    }
    if (let Some(currentMapping) <- checker.CurrentInstantiationTypeMap()) {
        if (HaveCyclicSubstitution(checker.typeManager, currentMapping)) {
            Diagnose(checker.diag, triggerNode, DiagKind.sema_generic_infinite_instantiation).Emit()
            checker.MarkInfiniteInstantiationOccurred()
            return true
        }
    }
    if (let None <- decl.GetGeneric()) {
        return false
    }
    let generic = decl.GetGeneric().getOrThrow()
    if (generic.typeParameters.size != instTys.size) {
        return false
    }
    let currentMapping = checker.CurrentInstantiationTypeMap()
    let triggeredInside = InstantiationTriggeredInside(checker, decl)
    for (idx in 0..instTys.size) {
        if (let Some(genericTy) <- generic.typeParameters[idx].GetTy()) {
            if (HasSelfRecursiveInstantiation(checker, genericTy, instTys[idx], currentMapping, triggeredInside)) {
                Diagnose(checker.diag, triggerNode, DiagKind.sema_generic_infinite_instantiation).Emit()
                checker.MarkInfiniteInstantiationOccurred()
                return true
            }
        }
    }
    return false
}

private func ApplyCurrentInstantiationMap(checker: StructInheritanceChecker, instTys: ArrayList<Ty>): Unit {
    if (let Some(currentMapping) <- checker.CurrentInstantiationTypeMap()) {
        var idx: Int64 = 0
        while (idx < instTys.size) {
            instTys[idx] = checker.typeManager.GetInstantiatedTy(instTys[idx], currentMapping)
            idx++
        }
    }
}

private func MergeTypeSubstForInstantiation(target: TypeSubst, source: TypeSubst): Unit {
    for ((tyVar, ty) in source.entries) {
        target.Put(tyVar.value, ty)
    }
}

private func BuildInstantiationTypeMap(decl: Decl, instTys: ArrayList<Ty>): TypeSubst {
    if (let Some(extendDecl) <- (decl as ExtendDecl)) {
        if (let Some(extendTy) <- extendDecl.GetTy()) {
            if (extendTy.IsNominal()) {
                if (let Some(targetDecl) <- Ty.GetDeclPtrOfTy(extendTy)) {
                    let typeMapping = GenerateTypeMapping(targetDecl, instTys)
                    MergeTypeSubstForInstantiation(typeMapping, GenerateTypeMapping(decl, extendTy.typeArgs))
                    return typeMapping
                }
            }
        }
    }
    return GenerateTypeMapping(decl, instTys)
}

private func WalkInstDupFuncsInDecl(checker: StructInheritanceChecker, decl: Decl): Unit {
    let walker = Walker(decl, visitPre: { node: Node =>
        CheckInstDupFuncsRecursively(checker, node)
    })
    walker.Walk()
}

func CheckInstDupFuncsRecursively(checker: StructInheritanceChecker, node: Node): VisitAction {
    if (checker.HasInfiniteInstantiationOccurred()) {
        return VisitAction.STOP_NOW
    }
    if (let Some(generic) <- (node as Generic)) {
        MarkUpperBoundIgnored(node, generic)
    }
    if (!Ty.IsTyCorrect(node.GetTy()) || node.TestAttr(Attribute.HAS_BROKEN)) {
        return VisitAction.WALK_CHILDREN
    }
    let refInfo = GetReferenceTyAndTarget(node)
    if (let Some(target) <- refInfo[1]) {
        if (target.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
            return VisitAction.WALK_CHILDREN
        }
            if (let Some(baseTy) <- refInfo[0]) {
                if (target.IsNominalDecl() && target.TestAttr(Attribute.GENERIC)) {
                    let emptyInstTys = ArrayList<Ty>()
                    let emptyKey = InstantiationKey(target, emptyInstTys)
                    if (!checker.HasInstantiatedKey(emptyKey)) {
                        checker.AddInstantiatedKey(emptyKey)
                        WalkInstDupFuncsInDecl(checker, target)
                    }
            }
            checker.CheckInstWithCStructTypeArg(node)
            var instTys = checker.typeManager.GetTypeArgs(baseTy)
            if (let Some(nameRef) <- (node as NameReferenceExpr)) {
                instTys = ArrayList<Ty>()
                for (ty in nameRef.instTys) {
                    instTys.add(ty)
                }
            }
            let typeMapping = GenerateTypeMapping(target, instTys)
            if (typeMapping.IsEmpty()) {
                return VisitAction.WALK_CHILDREN
            }
            if (WillCauseInfiniteInstantiation(checker, node, target, instTys, typeMapping)) {
                return VisitAction.STOP_NOW
            }
            ApplyCurrentInstantiationMap(checker, instTys)
            let shouldUpdateTrigger = !baseTy.HasGeneric() || !checker.HasInstantiationTypeMap()
            if (shouldUpdateTrigger) {
                checker.PushInstantiationTrigger(node, target, instTys)
            }
            if (let Some(inheritable) <- (target as InheritableDecl)) {
                CheckInstMemberSignatures(checker, inheritable, instTys)
            }
            let targetKey = InstantiationKey(target, instTys)
            for (extendDecl in GetVisibleExtendsForInstantiation(checker, target, instTys)) {
                CheckInstMemberSignatures(checker, extendDecl, instTys)
                if (!checker.HasInstantiatedKey(targetKey)) {
                    checker.AddInstantiatedKey(targetKey)
                }
            }
            if (!checker.HasInstantiatedKey(targetKey)) {
                checker.AddInstantiatedKey(targetKey)
                CheckInstantiatedDecl(checker, target, instTys)
            }
            if (shouldUpdateTrigger) {
                checker.PopInstantiationTrigger()
            }
        }
    }
    return VisitAction.WALK_CHILDREN
}

func CheckInstantiatedDecl(checker: StructInheritanceChecker, decl: Decl, instTys: ArrayList<Ty>): Unit {
    if (decl.IsBuiltIn()) {
        return
    }
    let typeMapping = BuildInstantiationTypeMap(decl, instTys)
    checker.PushInstantiationTypeMap(typeMapping)
    let walker = Walker(decl, visitPre: { node: Node =>
        CheckInstDupFuncsRecursively(checker, node)
    })
    walker.Walk()
    checker.PopInstantiationTypeMap()
}

func CheckInstDupFuncsInNominalDecls(checker: StructInheritanceChecker): Unit {
    for (file in checker.pkg.files) {
        for (decl in file.decls) {
            let empty = ArrayList<Ty>()
            let emptyKey = InstantiationKey(decl, empty)
            if (!checker.HasInstantiatedKey(emptyKey)) {
                checker.AddInstantiatedKey(emptyKey)
                WalkInstDupFuncsInDecl(checker, decl)
            }
        }
    }
}

func CheckInstWithCStructTypeArgImpl(checker: StructInheritanceChecker, node: Node): Unit {
    if (node.astKind != ASTKind.REF_TYPE && node.astKind != ASTKind.REF_EXPR && node.astKind != ASTKind.MEMBER_ACCESS) {
        return
    }
    if (let Some(refType) <- (node as RefType)) {
        if (!refType.typeArguments.isEmpty()) {
            if (let Some(refTy) <- refType.GetTy()) {
                CheckCStructArguments(checker, refType, refTy, refType.leftAnglePos, refType.GetTypeArgs())
            }
        }
        return
    }
    if (let Some(nameRef) <- (node as NameReferenceExpr)) {
        if (nameRef.instTys.isEmpty()) {
            return
        }
        if (let Some(target) <- node.GetTarget()) {
            if (node.astKind == ASTKind.MEMBER_ACCESS && target.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                return
            }
            if (let Some(refTy) <- nameRef.GetTy()) {
                var checkTy = refTy
                if (node.astKind == ASTKind.REF_EXPR && target.TestAttr(Attribute.CONSTRUCTOR)) {
                    if (let Some(outer) <- target.outerDecl) {
                        if (let Some(outerTy) <- outer.GetTy()) {
                            checkTy = outerTy
                        }
                    }
                }
                if (nameRef.instTys.size == nameRef.GetTypeArgs().size) {
                    CheckCStructArguments(checker, nameRef, checkTy, nameRef.leftAnglePos, nameRef.GetTypeArgs())
                }
            }
        }
    }
}

func CheckCStructArguments(
    checker: StructInheritanceChecker,
    node: Node,
    ty: Ty,
    leftAnglePos: Position,
    typeArgs: ArrayList<Type>
): Unit {
    if (typeArgs.isEmpty()) {
        return
    }
    if (Ty.IsCStructType(ty)) {
        Diagnose(
            checker.diag,
            node,
            leftAnglePos,
            DiagKind.sema_cffi_cannot_have_type_param,
            args: [DiagArgument("struct with @C")]
        ).Emit()
    }
    let _ = node
    for (typeArg in typeArgs) {
        CheckCStructArgument(checker, ty, typeArg)
    }
}

func CheckCStructArgument(checker: StructInheritanceChecker, ty: Ty, typeArg: Type): Unit {
    if (!Ty.IsTyCorrect(typeArg.GetTy())) {
        return
    }
    if (let Some(typeArgTy) <- typeArg.GetTy()) {
        if (ty.IsPointer()) {
            if (!typeArgTy.IsGeneric() && !Ty.IsMetCType(typeArgTy)) {
                Diagnose(checker.diag, typeArg, DiagKind.sema_illegal_cpointer_generic_type).Emit()
            }
            return
        }
        if (ty.IsStructArray() && (typeArgTy.IsCString() || typeArgTy.IsPointer())) {
            return
        }
        CheckCStruct(checker, typeArgTy, typeArg)
    }
}

func CheckCStruct(checker: StructInheritanceChecker, ty: Ty, typeArg: Type): Unit {
    if (!Ty.IsTyCorrect(ty)) {
        return
    }
    if (ty.IsPointer()) {
        if (!ty.typeArgs.isEmpty() && !ty.typeArgs[0].IsGeneric() && !Ty.IsMetCType(ty.typeArgs[0])) {
            Diagnose(checker.diag, typeArg, DiagKind.sema_illegal_cpointer_generic_type).Emit()
        }
        return
    }
    if (let Some(funcTy) <- (ty as FuncTy)) {
        for (arg in funcTy.typeArgs) {
            CheckCStruct(checker, arg, typeArg)
        }
        return
    }
    for (arg in ty.typeArgs) {
        if (arg.IsStruct()) {
            CheckCStruct(checker, arg, typeArg)
        }
    }
}

func DiagnoseForInstantiatedMemberImpl(
    checker: StructInheritanceChecker,
    parent: MemberSignature,
    child: MemberSignature
): Unit {
    if (let None <- checker.CurrentInstantiationTrigger()) {
        return
    }
    let trigger = checker.CurrentInstantiationTrigger().getOrThrow()
    if (let Some(parentDecl) <- parent.decl) {
        if (let Some(childDecl) <- child.decl) {
            if (let Some(parentFuncTy) <- FuncTyFromOption(parent.ty)) {
                if (let Some(childFuncTy) <- FuncTyFromOption(child.ty)) {
                    let sameStatic = parentDecl.TestAttr(Attribute.STATIC) == childDecl.TestAttr(Attribute.STATIC)
                    if (sameStatic && checker.typeManager.IsFuncParameterTypesIdentical(parentFuncTy, childFuncTy)) {
                        let triggeredDeclType = trigger.decl.identifier.Val() + "<" +
                            Ty.GetTypesToStr(trigger.instTys, ", ") + ">"
                        let builder = DiagnoseRefactor(checker.diag,
                            DiagKindRefactor.sema_generic_instantiation_causes_ambiguous_functions,
                            trigger.node,
                            arguments: [triggeredDeclType, childDecl.identifier.Val()]
                        )
                        let candidates = ArrayList<Decl>()
                        AddInheritanceDeclUniqueByPosition(candidates, parentDecl)
                        AddInheritanceDeclUniqueByPosition(candidates, childDecl)
                        for (candidate in candidates) {
                            AddNote(builder, candidate, MakeRangeForDeclIdentifier(candidate), "found candidate")
                        }
                        builder.Emit()
                    }
                }
            }
        }
    }
}
