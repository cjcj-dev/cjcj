package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

public func CheckUpperBound(genericConstraint: GenericConstraint): Bool {
    if (let Some(refType) <- genericConstraint.refType) {
        if (!Ty.IsTyCorrect(refType.GetTy())) {
            return false
        }
    } else {
        return false
    }
    for (upperBound in genericConstraint.upperBounds) {
        if (!Ty.IsTyCorrect(upperBound.GetTy())) {
            return false
        }
    }
    return true
}

public func CheckGenericConstraints(generic: Generic): Bool {
    for (genericConstraint in generic.genericConstraints) {
        if (!CheckUpperBound(genericConstraint)) {
            return false
        }
        if (let Some(refType) <- genericConstraint.refType) {
            var found = false
            for (typeParameter in generic.typeParameters) {
                if (refType.ref.identifier.Val() == typeParameter.identifier.Val()) {
                    found = true
                    break
                }
            }
            if (!found) {
                return false
            }
        }
    }
    return true
}

public func CheckInstTyWithUpperbound(typeManager: TypeManager, typeMapping: TypeSubst): Bool {
    for (entry in typeMapping.entries) {
        let genericTy = entry.tyVar
        for (upperBound in genericTy.upperBounds) {
            let upperBoundTy = typeManager.GetInstantiatedTy(upperBound, typeMapping)
            if ((SameTy(entry.ty, upperBoundTy) && entry.ty.IsCType()) ||
                !typeManager.IsSubtype(entry.ty, upperBoundTy, implicitBoxed: true, allowOptionBox: false)) {
                return false
            }
        }
    }
    return true
}

public func CheckGenericDeclInstantiation(typeManager: TypeManager, decl: Option<Decl>, typeArgs: ArrayList<Ty>): Bool {
    if (let Some(value) <- decl) {
        if (!Ty.IsTyCorrect(value.GetTy())) {
            return false
        }
        let genericParams = GetDeclTypeParams(value)
        if (typeArgs.isEmpty() || genericParams.size != typeArgs.size) {
            return false
        }
        if (!typeManager.CheckGenericDeclInstantiation(Some(value), typeArgs)) {
            return false
        }
        let typeMapping = GenerateTypeMapping(value, typeArgs)
        return CheckInstTyWithUpperbound(typeManager, typeMapping)
    }
    return false
}

public func CheckGenericDeclInstantiation(typeManager: TypeManager, decl: Decl, typeArgs: ArrayList<Ty>): Bool {
    return CheckGenericDeclInstantiation(typeManager, Some(decl), typeArgs)
}

public func CheckGenericDeclInstantiation(typeManager: TypeManager, decl: Decl, typeNodes: ArrayList<Type>): Bool {
    let typeArgs = ArrayList<Ty>()
    for (typeNode in typeNodes) {
        if (let Some(ty) <- typeNode.GetTy()) {
            typeArgs.add(ty)
        } else {
            return false
        }
    }
    return CheckGenericDeclInstantiation(typeManager, decl, typeArgs)
}

public func GetGenericType(typeManager: TypeManager, decl: Decl, typeArgs: ArrayList<Type>): Ty {
    if (let Some(genericParamDecl) <- (decl as GenericParamDecl)) {
        let _ = genericParamDecl
        if (!typeArgs.isEmpty()) {
            if (let Some(ty) <- decl.GetTy()) {
                return ty
            }
            return TypeManager.GetInvalidTy()
        }
    }
    if (let Some(generic) <- decl.GetGeneric()) {
        if (generic.typeParameters.size != typeArgs.size) {
            if (let Some(ty) <- decl.GetTy()) {
                return ty
            }
            return TypeManager.GetInvalidTy()
        }
        let typeMapping = TypeSubst()
        for (idx in 0..typeArgs.size) {
            if (let Some(paramTy) <- generic.typeParameters[idx].GetTy()) {
                if (let Some(genTy) <- (paramTy as GenericsTy)) {
                    if (let Some(argTy) <- typeArgs[idx].GetTy()) {
                        typeMapping.Put(genTy, argTy)
                    }
                }
            }
        }
        if (let Some(declTy) <- decl.GetTy()) {
            return typeManager.GetInstantiatedTy(declTy, typeMapping)
        }
    }
    if (let Some(ty) <- decl.GetTy()) {
        return ty
    }
    return TypeManager.GetInvalidTy()
}

public func GenerateGenericTypeMapping(typeManager: TypeManager, expr: Expr): SubstPack {
    let typeMapping = SubstPack()
    if (let Some(memberAccess) <- (expr as MemberAccess)) {
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            if (let Some(baseTy) <- baseExpr.GetTy()) {
                typeManager.GenerateGenericMapping(typeMapping, baseTy)
            }
        }
    } else if (let Some(refExpr) <- (expr as RefExpr)) {
        if (let Some(target) <- refExpr.GetTarget()) {
            if (let Some(targetTy) <- target.GetTy()) {
                typeManager.GenerateGenericMapping(typeMapping, targetTy)
            }
        }
    }
    return typeMapping
}
