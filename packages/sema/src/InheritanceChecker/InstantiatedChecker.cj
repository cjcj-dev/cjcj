package cangjie_compiler::sema.InheritanceChecker

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.{DiagArgument, DiagKind, DiagKindRefactor, MakeRange}
import cangjie_compiler::sema.*

func InstantiationKey(decl: Decl, instTys: ArrayList<Ty>): String {
    let parts = ArrayList<String>()
    for (ty in instTys) {
        parts.add(ty.String())
    }
    return "${decl.fullPackageName}:${decl.identifier.Val()}:${decl.begin.ToString()}:${JoinStrings(parts, ",")}"
}

func TypeArgsFromTy(ty: Ty): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    for (arg in ty.typeArgs) {
        out.add(arg)
    }
    return out
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

func GenerateTypeMappingForInheritance(decl: Decl, instTys: ArrayList<Ty>): TypeSubst {
    let out = TypeSubst()
    if (let Some(generic) <- decl.GetGeneric()) {
        if (generic.typeParameters.size != instTys.size) {
            return out
        }
        for (idx in 0..generic.typeParameters.size) {
            if (let Some(paramTy) <- generic.typeParameters[idx].GetTy()) {
                if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                    out.Put(genericTy, instTys[idx])
                }
            }
        }
    }
    return out
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
    contextDecl: Decl,
    extendDecl: ExtendDecl,
    instTys: ArrayList<Ty>
): Bool {
    let samePkg = extendDecl.fullPackageName == checker.pkg.fullPackageName ||
        extendDecl.fullPackageName == contextDecl.fullPackageName
    if (!samePkg && !extendDecl.TestAttr(Attribute.PUBLIC)) {
        return false
    }
    return extendDecl.TestAttr(Attribute.GENERIC) && checker.typeManager.CheckGenericDeclInstantiation(extendDecl, instTys)
}

private func AddVisibleExtendForInstantiation(
    checker: StructInheritanceChecker,
    out: ArrayList<ExtendDecl>,
    contextDecl: Decl,
    extendDecl: ExtendDecl,
    instTys: ArrayList<Ty>
): Unit {
    if (HasExtendForInstantiation(out, extendDecl)) {
        return
    }
    if (IsVisibleGenericExtendForInstantiation(checker, contextDecl, extendDecl, instTys)) {
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
            AddVisibleExtendForInstantiation(checker, out, decl, extendDecl, instTys)
        }
    }
    if (let Some(inheritable) <- (decl as InheritableDecl)) {
        for (extendDecl in checker.typeManager.GetDeclExtends(inheritable)) {
            AddVisibleExtendForInstantiation(checker, out, decl, extendDecl, instTys)
        }
    }
    return out
}

func CheckInstMemberSignatures(
    checker: StructInheritanceChecker,
    decl: InheritableDecl,
    instTys: ArrayList<Ty>
): Unit {
    if (instTys.isEmpty()) {
        return
    }
    let key = InstantiationKey(decl, instTys)
    if (checker.HasInstantiatedKey(key)) {
        return
    }
    checker.AddInstantiatedKey(key)
    let typeMapping = GenerateTypeMappingForInheritance(decl, instTys)
    if (typeMapping.IsEmpty()) {
        return
    }
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
            memberSig.ty = checker.typeManager.GetInstantiatedTy(memberTy, typeMapping)
        }
        if (let Some(memberStructTy) <- memberSig.structTy) {
            memberSig.structTy = checker.typeManager.GetInstantiatedTy(memberStructTy, typeMapping)
        }
        for (candidate in members.Get(entry.name)) {
            let parent = candidate.Clone()
            if (let Some(parentStructTy) <- parent.structTy) {
                parent.structTy = checker.typeManager.GetInstantiatedTy(parentStructTy, typeMapping)
            }
            checker.DiagnoseForInstantiatedMember(parent, memberSig)
        }
        members.Add(entry.name, memberSig)
    }
}

func CheckInstDupFuncsRecursively(checker: StructInheritanceChecker, node: Node): VisitAction {
    if (!Ty.IsTyCorrect(node.GetTy()) || node.TestAttr(Attribute.HAS_BROKEN)) {
        return VisitAction.WALK_CHILDREN
    }
    let refInfo = GetReferenceTyAndTarget(node)
    if (let Some(target) <- refInfo[1]) {
        if (target.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
            return VisitAction.WALK_CHILDREN
        }
        if (let Some(baseTy) <- refInfo[0]) {
            var instTys = TypeArgsFromTy(baseTy)
            if (let Some(nameRef) <- (node as NameReferenceExpr)) {
                if (!nameRef.instTys.isEmpty()) {
                    instTys = nameRef.instTys
                }
            }
            if (!instTys.isEmpty()) {
                if (let Some(inheritable) <- (target as InheritableDecl)) {
                    CheckInstMemberSignatures(checker, inheritable, instTys)
                }
                for (extendDecl in GetVisibleExtendsForInstantiation(checker, target, instTys)) {
                    CheckInstMemberSignatures(checker, extendDecl, instTys)
                }
            }
            checker.CheckInstWithCStructTypeArg(node)
        }
    }
    return VisitAction.WALK_CHILDREN
}

func CheckInstantiatedDecl(checker: StructInheritanceChecker, decl: Decl, instTys: ArrayList<Ty>): Unit {
    if (decl.IsBuiltIn()) {
        return
    }
    let _ = instTys
    let walker = Walker(decl, visitPre: { node: Node =>
        CheckInstDupFuncsRecursively(checker, node)
    })
    walker.Walk()
}

func CheckInstDupFuncsInNominalDecls(checker: StructInheritanceChecker): Unit {
    for (file in checker.pkg.files) {
        for (decl in file.decls) {
            let empty = ArrayList<Ty>()
            CheckInstantiatedDecl(checker, decl, empty)
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
        checker.diag.Diagnose(
            leftAnglePos,
            DiagKind.sema_cffi_cannot_have_type_param,
            args: [DiagArgument("struct with @C")]
        )
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
                checker.diag.Diagnose(typeArg.begin, DiagKind.sema_illegal_cpointer_generic_type)
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
            checker.diag.Diagnose(typeArg.begin, DiagKind.sema_illegal_cpointer_generic_type)
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
    if (let Some(parentDecl) <- parent.decl) {
        if (let Some(childDecl) <- child.decl) {
            if (let Some(parentFuncTy) <- FuncTyFromOption(parent.ty)) {
                if (let Some(childFuncTy) <- FuncTyFromOption(child.ty)) {
                    let sameStatic = parentDecl.TestAttr(Attribute.STATIC) == childDecl.TestAttr(Attribute.STATIC)
                    if (sameStatic && checker.typeManager.IsFuncParameterTypesIdentical(parentFuncTy, childFuncTy)) {
                        let builder = checker.diag.DiagnoseRefactor(
                            DiagKindRefactor.sema_generic_instantiation_causes_ambiguous_functions,
                            MakeRange(childDecl.begin, childDecl.end),
                            arguments: [childDecl.identifier.Val(), childDecl.identifier.Val()]
                        )
                        builder.AddNote(MakeRange(parentDecl.begin, parentDecl.end), "found candidate")
                        builder.AddNote(MakeRange(childDecl.begin, childDecl.end), "found candidate")
                    }
                }
            }
        }
    }
}

public func SelfhostPortStatus_InheritanceChecker_InstantiatedChecker(): Bool {
    return true
}
