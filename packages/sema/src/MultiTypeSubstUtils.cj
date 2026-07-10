package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::utils.CJC_NULLPTR_CHECK

private func containsTy(values: ArrayList<Ty>, ty: Ty): Bool {
    for (value in values) {
        if (SameTy(value, ty)) {
            return true
        }
    }
    return false
}

private func containsGeneric(values: ArrayList<GenericsTy>, tyVar: GenericsTy): Bool {
    for (value in values) {
        if (SameTy(value, tyVar)) {
            return true
        }
    }
    return false
}

private func addGenericUnique(values: ArrayList<GenericsTy>, tyVar: GenericsTy): Bool {
    if (containsGeneric(values, tyVar)) {
        return false
    }
    values.add(tyVar)
    return true
}

private func addTyUnique(values: ArrayList<Ty>, ty: Ty): Bool {
    if (containsTy(values, ty)) {
        return false
    }
    values.add(ty)
    return true
}

private func sameDeclOpt(left: Option<Decl>, right: Option<Decl>): Bool {
    if (let Some(leftDecl) <- left) {
        if (let Some(rightDecl) <- right) {
            return SameDecl(leftDecl, rightDecl)
        }
        return false
    }
    if (let Some(_) <- right) {
        return false
    }
    return true
}

private func keySet(mapping: MultiTypeSubst): ArrayList<GenericsTy> {
    let out = ArrayList<GenericsTy>()
    for (entry in mapping.entries) {
        let _ = addGenericUnique(out, entry.tyVar)
    }
    return out
}

private func removeMapping(mapping: MultiTypeSubst, tyVar: GenericsTy): Unit {
    var idx: Int64 = 0
    while (idx < mapping.entries.size) {
        if (SameTy(mapping.entries[idx].tyVar, tyVar)) {
            mapping.entries.remove(at: idx)
            return
        }
        idx++
    }
}

private func copyTypeArgs(args: ArrayList<Ty>): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    for (arg in args) {
        out.add(arg)
    }
    return out
}

private func getDirectMappingTys(tyVar: GenericsTy, mts: MultiTypeSubst): TySet {
    let stack = ArrayList<GenericsTy>()
    let res = TySet()
    let mapping = mts.Clone()
    stack.add(tyVar)
    while (!stack.isEmpty()) {
        let curTy = stack[stack.size - 1]
        stack.remove(at: stack.size - 1)
        if (let Some(targetTys) <- mapping.Get(curTy)) {
            removeMapping(mapping, curTy)
            let candidates = targetTys.Clone()
            let _ = candidates.Remove(curTy)
            if (candidates.IsEmpty()) {
                continue
            }
            for (ty in candidates.values) {
                if (let Some(genTy) <- (ty as GenericsTy)) {
                    stack.add(genTy)
                }
            }
            let _ = res.Remove(curTy)
            res.AddAll(candidates)
        }
    }
    return res
}

private func filterUnusedMapping(mapping: MultiTypeSubst, tys: TySet): MultiTypeSubst {
    let all = keySet(mapping)
    let reachable = ArrayList<GenericsTy>()
    let worklist = ArrayList<GenericsTy>()
    for (ty in tys.values) {
        for (tyVar in ty.GetGenericTyArgs(all)) {
            if (addGenericUnique(reachable, tyVar)) {
                worklist.add(tyVar)
            }
        }
    }
    var workIdx: Int64 = 0
    while (workIdx < worklist.size) {
        let tv = worklist[workIdx]
        workIdx++
        if (let Some(instTys) <- mapping.Get(tv)) {
            for (instTy in instTys.values) {
                for (used in instTy.GetGenericTyArgs(all)) {
                    let _ = addGenericUnique(reachable, used)
                }
            }
        }
    }
    let ret = MultiTypeSubst()
    for (entry in mapping.entries) {
        if (containsGeneric(reachable, entry.tyVar)) {
            ret.PutAll(entry.tyVar, entry.tys)
        }
    }
    return ret
}

private func filterUnusedMapping(mapping: SubstPack, tys: TySet): SubstPack {
    let allUniversal = ArrayList<GenericsTy>()
    let allInst = ArrayList<GenericsTy>()
    for (entry in mapping.u2i.entries) {
        let _ = addGenericUnique(allUniversal, entry.tyVar)
        if (let Some(instTyVar) <- (entry.ty as GenericsTy)) {
            let _ = addGenericUnique(allInst, instTyVar)
        }
    }

    let reachable = ArrayList<GenericsTy>()
    let worklist = ArrayList<GenericsTy>()
    for (ty in tys.values) {
        for (universalTyVar in ty.GetGenericTyArgs(allUniversal)) {
            if (let Some(instTy) <- mapping.u2i.Get(universalTyVar)) {
                if (let Some(instTyVar) <- (instTy as GenericsTy)) {
                    if (addGenericUnique(reachable, instTyVar)) {
                        worklist.add(instTyVar)
                    }
                }
            }
        }
    }

    var workIdx: Int64 = 0
    while (workIdx < worklist.size) {
        let instTyVar = worklist[workIdx]
        workIdx++
        if (let Some(instTys) <- mapping.inst.Get(instTyVar)) {
            for (instTy in instTys.values) {
                for (used in instTy.GetGenericTyArgs(allInst)) {
                    let _ = addGenericUnique(reachable, used)
                }
            }
        }
    }

    let ret = SubstPack()
    for (entry in mapping.u2i.entries) {
        if (let Some(instTyVar) <- (entry.ty as GenericsTy)) {
            if (containsGeneric(reachable, instTyVar)) {
                ret.u2i.Put(entry.tyVar, entry.ty)
            }
        }
    }
    for (entry in mapping.inst.entries) {
        if (containsGeneric(reachable, entry.tyVar)) {
            ret.inst.PutAll(entry.tyVar, entry.tys)
        }
    }
    return ret
}

private func expandFilteredMultiTypeSubst(mts: MultiTypeSubst): ArrayList<TypeSubst> {
    let res = ArrayList<TypeSubst>()
    res.add(TypeSubst())
    for (entry in mts.entries) {
        let next = ArrayList<TypeSubst>()
        for (mapping in res) {
            for (ty in entry.tys.values) {
                let cloned = mapping.Clone()
                cloned.Put(entry.tyVar, ty)
                next.add(cloned)
            }
        }
        res.clear()
        for (mapping in next) {
            res.add(mapping)
        }
    }
    return res
}

private func insertInstMapping(typeManager: TypeManager, maps: SubstPack, genTy: GenericsTy, instTy: Ty): Unit {
    if (!maps.u2i.Contains(genTy)) {
        maps.u2i.Put(genTy, typeManager.AllocTyVar())
    }
    if (let Some(mappedTy) <- maps.u2i.Get(genTy)) {
        if (let Some(instTyVar) <- (mappedTy as GenericsTy)) {
            maps.inst.Put(instTyVar, instTy)
        }
    }
}

private func generateTypeMappingByArgs(srcArgs: ArrayList<Ty>, instantiateArgs: ArrayList<Ty>): TypeSubst {
    let typeMapping = TypeSubst()
    if (srcArgs.size != instantiateArgs.size) {
        return typeMapping
    }
    for (idx in 0..srcArgs.size) {
        let srcTy = srcArgs[idx]
        let instantiateTy = instantiateArgs[idx]
        if (let Some(genTy) <- (srcTy as GenericsTy)) {
            typeMapping.Put(genTy, instantiateTy)
        } else {
            if (srcTy.kind != instantiateTy.kind || !sameDeclOpt(Ty.GetDeclPtrOfTy(srcTy), Ty.GetDeclPtrOfTy(instantiateTy))) {
                continue
            }
            let nested = generateTypeMappingByArgs(srcTy.typeArgs, instantiateTy.typeArgs)
            for (entry in nested.entries) {
                typeMapping.Put(entry.tyVar, entry.ty)
            }
        }
    }
    return typeMapping
}

private func generateTypeMappingByArgs(typeManager: TypeManager, maps: SubstPack,
    srcArgs: ArrayList<Ty>, instantiateArgs: ArrayList<Ty>): Unit {
    if (srcArgs.size != instantiateArgs.size) {
        return
    }
    for (idx in 0..srcArgs.size) {
        let srcTy = srcArgs[idx]
        let instantiateTy = instantiateArgs[idx]
        if (let Some(genTy) <- (srcTy as GenericsTy)) {
            insertInstMapping(typeManager, maps, genTy, instantiateTy)
        } else {
            if (srcTy.kind != instantiateTy.kind || !sameDeclOpt(Ty.GetDeclPtrOfTy(srcTy), Ty.GetDeclPtrOfTy(instantiateTy))) {
                continue
            }
            generateTypeMappingByArgs(typeManager, maps, srcTy.typeArgs, instantiateTy.typeArgs)
        }
    }
}

private func genericParamType(param: GenericParamDecl): Option<GenericsTy> {
    if (let Some(paramTy) <- param.GetTy()) {
        return paramTy as GenericsTy
    }
    return None
}

public func MultiTypeSubstToTypeSubst(mts: MultiTypeSubst): TypeSubst {
    let out = TypeSubst()
    for (entry in mts.entries) {
        var chosen = entry.tys.values[0]
        if (entry.tys.values.size > 1) {
            let candidates = entry.tys.Clone()
            let _ = candidates.Remove(entry.tyVar)
            chosen = candidates.values[0]
        }
        out.Put(entry.tyVar, chosen)
    }
    return out
}

public func GetDeclTypeParams(decl: Decl): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    if (let Some(_) <- (decl as ExtendDecl)) {
        CJC_NULLPTR_CHECK(decl.GetTy())
        for (typeArg in decl.GetTy().getOrThrow().typeArgs) {
            out.add(typeArg)
        }
        return out
    }
    if (let Some(generic) <- decl.GetGeneric()) {
        for (param in generic.typeParameters) {
            CJC_NULLPTR_CHECK(param.GetTy())
            out.add(param.GetTy().getOrThrow())
        }
    }
    return out
}

public func GetAllGenericTys(ty: Ty): ArrayList<GenericsTy> {
    let res = ArrayList<GenericsTy>()
    let visited = ArrayList<Ty>()
    let queue = ArrayList<Ty>()
    queue.add(ty)
    var idx: Int64 = 0
    while (idx < queue.size) {
        let curTy = queue[idx]
        idx++
        if (!addTyUnique(visited, curTy)) {
            continue
        }
        if (let Some(genTy) <- (curTy as GenericsTy)) {
            let _ = addGenericUnique(res, genTy)
            continue
        }
        for (arg in curTy.typeArgs) {
            queue.add(arg)
        }
    }
    return res
}

public func ReduceMultiTypeSubst(typeManager: TypeManager, tyVars: ArrayList<GenericsTy>,
    mts: MultiTypeSubst): MultiTypeSubst {
    if (tyVars.isEmpty()) {
        return MultiTypeSubst()
    }
    let mapping = mts.Clone()
    let visited = ArrayList<Ty>()
    for (entry in mts.entries) {
        for (ty in entry.tys.values) {
            if (!addTyUnique(visited, ty)) {
                continue
            }
            for (genTy in GetAllGenericTys(ty)) {
                if (SameTy(genTy, entry.tyVar)) {
                    removeMapping(mapping, entry.tyVar)
                    break
                }
            }
        }
    }

    let res = MultiTypeSubst()
    for (tyVar in tyVars) {
        let targetTys = getDirectMappingTys(tyVar, mts)
        removeMapping(mapping, tyVar)
        if (!targetTys.IsEmpty()) {
            res.PutAll(tyVar, targetTys)
        }
    }
    for (entry in res.entries) {
        let targetRes = TySet()
        for (ty in entry.tys.values) {
            targetRes.AddAll(typeManager.GetInstantiatedTys(ty, mapping))
        }
        entry.tys = targetRes
    }
    return res
}

public func ExpandMultiTypeSubst(maps: SubstPack, usefulTys: TySet): ArrayList<SubstPack> {
    let ret = ArrayList<SubstPack>()
    let filtered = filterUnusedMapping(maps, usefulTys)
    for (mapping in expandFilteredMultiTypeSubst(filtered.inst)) {
        let substPack = SubstPack()
        substPack.u2i = filtered.u2i.Clone()
        MergeTypeSubstToMultiTypeSubst(substPack.inst, mapping)
        ret.add(substPack)
    }
    return ret
}

public func ExpandMultiTypeSubst(mts: MultiTypeSubst, usefulTys: TySet): ArrayList<TypeSubst> {
    return expandFilteredMultiTypeSubst(filterUnusedMapping(mts, usefulTys))
}

public func GetMappedTy(mts: MultiTypeSubst, tyVar: GenericsTy): Ty {
    if (let Some(tys) <- mts.Get(tyVar)) {
        for (ty in tys.values) {
            if (!SameTy(ty, tyVar)) {
                return ty
            }
        }
    }
    return tyVar
}

public func GetMappedTy(typeMapping: TypeSubst, tyVar: GenericsTy): Ty {
    if (let Some(ty) <- typeMapping.Get(tyVar)) {
        return ty
    }
    return tyVar
}

public func GenerateTypeMappingByTy(genericTy: Option<Ty>, instantTy: Option<Ty>): TypeSubst {
    let out = TypeSubst()
    if (let Some(gTy) <- genericTy) {
        if (let Some(iTy) <- instantTy) {
            if (!gTy.IsGeneric() && (gTy.kind != iTy.kind || !sameDeclOpt(Ty.GetDeclPtrOfTy(gTy), Ty.GetDeclPtrOfTy(iTy)))) {
                return out
            }
            let srcArgs = ArrayList<Ty>()
            let dstArgs = ArrayList<Ty>()
            srcArgs.add(gTy)
            dstArgs.add(iTy)
            return generateTypeMappingByArgs(srcArgs, dstArgs)
        }
    }
    return out
}

public func GenerateTypeMapping(typeManager: TypeManager, maps: SubstPack, decl: Decl, typeArgs: ArrayList<Ty>): Unit {
    if (let None <- decl.GetGeneric()) {
        return
    }
    if (let Some(extendDecl) <- (decl as ExtendDecl)) {
        if (let Some(extendedType) <- extendDecl.extendedType) {
            if (let Some(extendedTy) <- extendedType.GetTy()) {
                generateTypeMappingByArgs(typeManager, maps, extendedTy.typeArgs, typeArgs)
            }
        }
        return
    }
    if (let Some(generic) <- decl.GetGeneric()) {
        if (generic.typeParameters.size != typeArgs.size) {
            return
        }
        for (idx in 0..typeArgs.size) {
            if (Ty.IsTyCorrect(typeArgs[idx])) {
                if (let Some(genTy) <- genericParamType(generic.typeParameters[idx])) {
                    insertInstMapping(typeManager, maps, genTy, typeArgs[idx])
                }
            }
        }
    }
}

public func RelayMappingFromExtendToExtended(typeManager: TypeManager, maps: SubstPack, decl: ExtendDecl): Unit {
    if (let Some(extendedType) <- decl.extendedType) {
        if (let Some(target) <- extendedType.GetTarget()) {
            if (let Some(originalTy) <- GetRealTarget(target).GetTy()) {
                let originalTypeArgs = copyTypeArgs(originalTy.typeArgs)
                if (let Some(extendedTy) <- extendedType.GetTy()) {
                    let extendedTypeArgsInst = ArrayList<Ty>()
                    for (ty in extendedTy.typeArgs) {
                        extendedTypeArgsInst.add(typeManager.GetInstantiatedTy(ty, maps.u2i))
                    }
                    generateTypeMappingByArgs(typeManager, maps, originalTypeArgs, extendedTypeArgsInst)
                }
            }
        }
    }
}

public func GenerateTypeMapping(decl: Decl, typeArgs: ArrayList<Ty>): TypeSubst {
    let substituteMapping = TypeSubst()
    if (let Some(extendDecl) <- (decl as ExtendDecl)) {
        if (let None <- decl.GetGeneric()) {
            return substituteMapping
        }
        if (let Some(extendedType) <- extendDecl.extendedType) {
            if (let Some(extendedTy) <- extendedType.GetTy()) {
                return generateTypeMappingByArgs(extendedTy.typeArgs, typeArgs)
            }
        }
        return substituteMapping
    }
    if (let Some(generic) <- decl.GetGeneric()) {
        if (generic.typeParameters.size != typeArgs.size) {
            return substituteMapping
        }
        for (idx in 0..typeArgs.size) {
            if (Ty.IsTyCorrect(typeArgs[idx])) {
                if (let Some(genTy) <- genericParamType(generic.typeParameters[idx])) {
                    substituteMapping.Put(genTy, typeArgs[idx])
                }
            }
        }
    }
    return substituteMapping
}

public func InverseMapping(typeMapping: TypeSubst): TypeSubst {
    let inversed = TypeSubst()
    for (entry in typeMapping.entries) {
        if (let Some(genTo) <- (entry.ty as GenericsTy)) {
            inversed.Put(genTo, entry.tyVar)
        }
    }
    return inversed
}

public func MergeTypeSubstToMultiTypeSubst(mts: MultiTypeSubst, typeMapping: TypeSubst): Unit {
    for (entry in typeMapping.entries) {
        mts.Put(entry.tyVar, entry.ty)
    }
}

public func MergeMultiTypeSubsts(target: MultiTypeSubst, src: MultiTypeSubst): Unit {
    for (entry in src.entries) {
        if (!entry.tys.IsEmpty()) {
            target.PutAll(entry.tyVar, entry.tys)
        }
    }
}

public func MergeMultiTypeSubst(lhs: MultiTypeSubst, rhs: MultiTypeSubst): MultiTypeSubst {
    let out = lhs.Clone()
    MergeMultiTypeSubsts(out, rhs)
    return out
}

public func HaveCyclicSubstitution(typeManager: TypeManager, typeMapping: TypeSubst): Bool {
    for (entry in typeMapping.entries) {
        let mapping = typeMapping.Clone()
        removeTypeSubst(mapping, entry.tyVar)
        let substitutedTy = typeManager.GetInstantiatedTy(entry.ty, mapping)
        if (!SameTy(substitutedTy, entry.tyVar) && substitutedTy.Contains(entry.tyVar)) {
            return true
        }
    }
    return false
}

private func removeTypeSubst(mapping: TypeSubst, tyVar: GenericsTy): Unit {
    var idx: Int64 = 0
    while (idx < mapping.entries.size) {
        if (SameTy(mapping.entries[idx].tyVar, tyVar)) {
            mapping.entries.remove(at: idx)
            return
        }
        idx++
    }
}
