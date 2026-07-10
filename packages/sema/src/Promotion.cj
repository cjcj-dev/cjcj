package cjcj::sema

import std.collection.*
import cjcj::ast.*

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

private func sameInheritableDeclOpt(left: Option<InheritableDecl>, right: Option<InheritableDecl>): Bool {
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

public class Promotion {
    private var tyMgr: TypeManager

    public init(typeManager: TypeManager) {
        tyMgr = typeManager
    }

    public func GetPromoteTypeMapping(from: Ty, target: Ty): MultiTypeSubst {
        let mts = MultiTypeSubst()
        if (!Ty.IsTyCorrect(from) || !Ty.IsTyCorrect(target)) {
            return mts
        }
        let promotedTys = Promote(from, target)
        for (promoted in promotedTys.values) {
            if (promoted.typeArgs.size != target.typeArgs.size) {
                continue
            }
            for (idx in 0..target.typeArgs.size) {
                if (let Some(targetGenParam) <- (target.typeArgs[idx] as GenericsTy)) {
                    mts.Put(targetGenParam, promoted.typeArgs[idx])
                }
            }
        }
        return mts
    }

    public func GetDowngradeTypeMapping(target: Ty, upfrom: Ty): MultiTypeSubst {
        let mts = MultiTypeSubst()
        if (!Ty.IsTyCorrect(target) || !Ty.IsTyCorrect(upfrom)) {
            return mts
        }
        let promotedTys = Promote(target, upfrom)
        for (promoted in promotedTys.values) {
            if (promoted.typeArgs.size != upfrom.typeArgs.size) {
                continue
            }
            for (idx in 0..promoted.typeArgs.size) {
                if (let Some(tv) <- (promoted.typeArgs[idx] as GenericsTy)) {
                    mts.Put(tv, upfrom.typeArgs[idx])
                }
            }
        }
        return mts
    }

    public func Promote(from: Ty, target: Ty): TySet {
        let out = TySet()
        if (!Ty.IsTyCorrect(from) || !Ty.IsTyCorrect(target)) {
            return out
        }
        if (from.IsNothing() || target.IsAny() || (target.IsCType() && Ty.IsMetCType(from))) {
            out.Add(target)
            return out
        }
        if (from.IsPrimitive() && target.IsPrimitive()) {
            return PromoteHandleIdealTys(from, target)
        }
        if (from.IsFunc() && target.IsFunc()) {
            return PromoteHandleFunc(from, target)
        }
        if (from.IsTuple() && target.IsTuple()) {
            return PromoteHandleTuple(from, target)
        }
        let tyVarResult = PromoteHandleTyVar(from, target)
        if (!tyVarResult.IsEmpty()) {
            return tyVarResult
        }
        return PromoteHandleNominal(from, target)
    }

    public func Downgrade(target: Ty, upfrom: Ty): TySet {
        let downgradeMapping = GetDowngradeTypeMapping(target, upfrom)
        if (downgradeMapping.entries.size < target.typeArgs.size) {
            return TySet()
        }
        return tyMgr.GetInstantiatedTys(target, downgradeMapping)
    }

    private func PromoteHandleTyVar(from: Ty, target: Ty): TySet {
        let out = TySet()
        if (let Some(genericTy) <- (from as GenericsTy)) {
            for (upper in genericTy.upperBounds) {
                let promoted = Promote(upper, target)
                if (!promoted.IsEmpty()) {
                    return promoted
                }
            }
        }
        return out
    }

    private func PromoteHandleIdealTys(from: Ty, target: Ty): TySet {
        let out = TySet()
        if (from.kind == target.kind) {
            out.Add(from)
            return out
        }
        if (from.kind == TypeKind.TYPE_IDEAL_INT && target.IsInteger()) {
            out.Add(target)
        } else if (from.kind == TypeKind.TYPE_IDEAL_FLOAT && target.IsFloating()) {
            out.Add(target)
        }
        return out
    }

    private func PromoteHandleFunc(from: Ty, target: Ty): TySet {
        let out = TySet()
        if (tyMgr.IsTyEqual(from, target)) {
            out.Add(from)
        }
        return out
    }

    private func PromoteHandleTuple(from: Ty, target: Ty): TySet {
        let out = TySet()
        if (tyMgr.IsTyEqual(from, target)) {
            out.Add(from)
        }
        return out
    }

    private func PromoteHandleNominal(from: Ty, target: Ty): TySet {
        let out = TySet()
        if (sameInheritableDeclOpt(Ty.GetInheritableDeclPtrOfTy(from), Ty.GetInheritableDeclPtrOfTy(target))) {
            out.Add(from)
            return out
        }

        let typeMapping = TypeSubst()
        addNominalTypeMapping(from, typeMapping)
        let superTys = tyMgr.GetAllSuperTys(from, typeMapping: typeMapping)
        for (ty in superTys.values) {
            if (let Some(classLikeTy) <- (ty as ClassLikeTy)) {
                if (sameDeclOpt(Ty.GetDeclPtrOfTy(classLikeTy), Ty.GetDeclPtrOfTy(target))) {
                    out.Add(classLikeTy)
                }
            }
        }
        return out
    }

    private func addNominalTypeMapping(from: Ty, typeMapping: TypeSubst): Unit {
        let genericTyArgs = getGenericTyArgsForNominal(from)
        if (genericTyArgs.size != from.typeArgs.size) {
            return
        }
        for (idx in 0..genericTyArgs.size) {
            if (let Some(genTy) <- (genericTyArgs[idx] as GenericsTy)) {
                typeMapping.Put(genTy, from.typeArgs[idx])
            }
        }
    }

    private func getGenericTyArgsForNominal(from: Ty): ArrayList<Ty> {
        let out = ArrayList<Ty>()
        if (let Some(classTy) <- (from as ClassTy)) {
            if (let Some(decl) <- classTy.declPtr) {
                if (let Some(genericTy) <- decl.GetTy()) {
                    for (arg in genericTy.typeArgs) { out.add(arg) }
                }
            }
        } else if (let Some(interfaceTy) <- (from as InterfaceTy)) {
            if (let Some(decl) <- interfaceTy.declPtr) {
                if (let Some(genericTy) <- decl.GetTy()) {
                    for (arg in genericTy.typeArgs) { out.add(arg) }
                }
            }
        } else if (let Some(structTy) <- (from as StructTy)) {
            if (let Some(decl) <- structTy.declPtr) {
                if (let Some(genericTy) <- decl.GetTy()) {
                    for (arg in genericTy.typeArgs) { out.add(arg) }
                }
            }
        } else if (let Some(enumTy) <- (from as EnumTy)) {
            if (let Some(decl) <- enumTy.declPtr) {
                if (let Some(genericTy) <- decl.GetTy()) {
                    for (arg in genericTy.typeArgs) { out.add(arg) }
                }
            }
        }
        return out
    }
}

public func Promote(tm: TypeManager, ty: Ty, target: Ty): Ty {
    let promotedTys = Promotion(tm).Promote(ty, target)
    if (!promotedTys.values.isEmpty()) {
        return promotedTys.values[0]
    }
    return ty
}
