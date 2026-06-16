package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

public func SelfhostPortStatus_TypeCheckExpr(): Bool {
    return true
}

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
    let visited = HashSet<String>()
    return GenerateTypeMappingForTypeAliasDeclVisit(typeManager, tad, visited)
}

private func GenerateTypeMappingForTypeAliasDeclVisit(typeManager: TypeManager, tad: TypeAliasDecl,
    visited: HashSet<String>): TypeSubst {
    let mapping = TypeSubst()
    let key = "${tad.fullPackageName}:${tad.identifier.Val()}:${tad.begin.ToString()}:${tad.end.ToString()}"
    if (visited.contains(key)) {
        return mapping
    }
    visited.add(key)
    if (let None <- tad.typeNode) {
        return mapping
    }
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
        for (entry in nested.entries) {
            mapping.Put(entry.tyVar, entry.ty)
        }
        SubstituteTypeForTypeAliasTypeMapping(typeManager, targetAlias, typeNode.GetTypeArgs(), mapping)
        return mapping
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
    typeArgs: ArrayList<Type>, mapping: TypeSubst): Unit {
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
                if (let Some(typeArgTy) <- typeArgs[idx].GetTy()) {
                    aliasParamMapping.Put(genTy, typeArgTy)
                }
            }
        }
    }
    for (entry in mapping.entries) {
        entry.ty = typeManager.GetInstantiatedTy(entry.ty, aliasParamMapping)
    }
}
