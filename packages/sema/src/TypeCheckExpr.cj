package cjcj::sema

import std.collection.*
import cjcj::ast.*

public func CheckOptionBox(typeManager: TypeManager, target: Ty, ty: Ty): Bool {
    if (typeManager.IsSubtype(ty, target)) {
        return true
    }
    if (!Ty.IsTyCorrect(target) || !target.IsCoreOptionType()) {
        return false
    }
    if (typeManager.IsTyEqual(ty, target)) {
        return true
    }
    var currentTarget = target
    var keepGoing = true
    while (keepGoing) {
        if (Ty.IsTyCorrect(currentTarget) && currentTarget.IsCoreOptionType() && currentTarget.typeArgs.size == 1) {
            currentTarget = currentTarget.typeArgs[0]
            if (typeManager.IsTyEqual(ty, currentTarget)) {
                return true
            }
        } else {
            keepGoing = false
        }
    }
    return false
}

public func GenerateTypeMappingForTypeAliasDecl(typeManager: TypeManager, tad: TypeAliasDecl): TypeSubst {
    let visited = HashSet<Decl>()
    return GenerateTypeMappingForTypeAliasDeclVisit(typeManager, tad, visited)
}

private func GenerateTypeMappingForTypeAliasDeclVisit(typeManager: TypeManager, tad: TypeAliasDecl,
    visited: HashSet<Decl>): TypeSubst {
    let mapping = TypeSubst()
    if (let None <- tad.typeNode) {
        return mapping
    }
    if (visited.contains(tad)) {
        return mapping
    }
    visited.add(tad)
    let typeNode = tad.typeNode.getOrThrow()
    if (!Ty.IsTyCorrect(typeNode.GetTy())) {
        return mapping
    }
    let targetOpt = typeNode.GetTarget()
    if (let None <- targetOpt) {
        return mapping
    }
    let target = targetOpt.getOrThrow()
    if (let Some(targetAlias) <- (target as TypeAliasDecl)) {
        let nested = GenerateTypeMappingForTypeAliasDeclVisit(typeManager, targetAlias, visited)
        let typeArgs = ArrayList<Ty>()
        for (typeArg in typeNode.GetTypeArgs()) {
            typeArgs.add(typeArg.GetTy().getOrThrow())
        }
        SubstituteTypeForTypeAliasTypeMapping(typeManager, targetAlias, typeArgs, nested)
        return nested
    }
    if (let Some(ty) <- typeNode.GetTy()) {
        for (arg in ty.typeArgs) {
            if (let Some(genTy) <- (arg as GenericsTy)) {
                mapping.Put(genTy, genTy)
            }
        }
    }
    return mapping
}

private func SubstituteTypeForTypeAliasTypeMapping(typeManager: TypeManager, tad: TypeAliasDecl,
    typeArgs: ArrayList<Ty>, mapping: TypeSubst): Unit {
    if (let None <- tad.generic) {
        return
    }
    let generic = tad.generic.getOrThrow()
    if (generic.typeParameters.size != typeArgs.size) {
        return
    }
    let aliasParamMapping = TypeSubst()
    for (idx in 0..generic.typeParameters.size) {
        let genericParam = generic.typeParameters[idx]
        if (let Some(paramTy) <- genericParam.GetTy()) {
            if (let Some(genTy) <- (paramTy as GenericsTy)) {
                aliasParamMapping.Put(genTy, typeArgs[idx])
            }
        }
    }
    for ((tyVar, ty) in mapping.entries) {
        mapping.entries[tyVar] = typeManager.SubstituteTypeAliasInTy(ty, needSubstituteGeneric: true,
            typeMapping: aliasParamMapping)
    }
}

// C++ src/Sema/TypeCheckerImpl.h:1548-1572 GenerateTypeMappingForTypeAliasUse<Type>.
public func GenerateTypeMappingForTypeAliasUse(typeManager: TypeManager, tad: TypeAliasDecl,
    usage: Type): TypeSubst {
    if (let None <- tad.typeNode) {
        return TypeSubst()
    }
    let typeArgs = ArrayList<Ty>()
    for (typeArg in usage.GetTypeArgs()) {
        typeArgs.add(typeArg.GetTy().getOrThrow())
    }
    let target = tad.typeNode.getOrThrow().GetTarget()
    if ((let None <- target) || target.getOrThrow().astKind != ASTKind.TYPE_ALIAS_DECL) {
        return GenerateTypeMapping(tad, typeArgs)
    }
    let mapping = GenerateTypeMappingForTypeAliasDecl(typeManager, tad)
    SubstituteTypeForTypeAliasTypeMapping(typeManager, tad, typeArgs, mapping)
    let directMapping = GenerateTypeMapping(tad, typeArgs)
    for ((tyVar, ty) in directMapping.entries) {
        mapping.Put(tyVar.value, ty)
    }
    return mapping
}

// C++ src/Sema/TypeCheckerImpl.h:1548-1572 GenerateTypeMappingForTypeAliasUse<NameReferenceExpr>.
public func GenerateTypeMappingForTypeAliasUse(typeManager: TypeManager, tad: TypeAliasDecl,
    usage: NameReferenceExpr): TypeSubst {
    if (let None <- tad.typeNode) {
        return TypeSubst()
    }
    let typeArgs = ArrayList<Ty>()
    for (typeArg in usage.GetTypeArgs()) {
        typeArgs.add(typeArg.GetTy().getOrThrow())
    }
    let target = tad.typeNode.getOrThrow().GetTarget()
    if ((let None <- target) || target.getOrThrow().astKind != ASTKind.TYPE_ALIAS_DECL) {
        return GenerateTypeMapping(tad, typeArgs)
    }
    let mapping = GenerateTypeMappingForTypeAliasDecl(typeManager, tad)
    SubstituteTypeForTypeAliasTypeMapping(typeManager, tad, typeArgs, mapping)
    let directMapping = GenerateTypeMapping(tad, typeArgs)
    for ((tyVar, ty) in directMapping.entries) {
        mapping.Put(tyVar.value, ty)
    }
    return mapping
}

// C++ src/Sema/TypeCheckUtil.cpp:894-917 GetLastTypeAliasTarget.
public func GetLastTypeAliasTarget(decl: TypeAliasDecl): TypeAliasDecl {
    return GetLastTypeAliasTargetVisit(decl, HashSet<Decl>())
}

private func GetLastTypeAliasTargetVisit(decl: TypeAliasDecl, visited: HashSet<Decl>): TypeAliasDecl {
    if (visited.contains(decl)) {
        return decl
    }
    visited.add(decl)
    if (let Some(typeNode) <- decl.typeNode) {
        if (let Some(realTarget) <- typeNode.GetTarget()) {
            if (let Some(innerAlias) <- (realTarget as TypeAliasDecl)) {
                if (innerAlias.typeNode.isSome()) {
                    return GetLastTypeAliasTargetVisit(innerAlias, visited)
                }
            }
        }
    }
    return decl
}
