package cangjie_compiler::chir

import std.collection.*

public class ConstMemberVarInfo {
    public let originalType: Type
    public var derivedType: Option<Type> = None
    public var invalidated: Bool = false

    public init(originalType: Type) {
        this.originalType = originalType
    }
}

public class ConstMemberVarCollector {
    private let chirPackage: Package
    private let constMemberMap: HashMap<Int64, HashMap<Int64, Type>> = HashMap<Int64, HashMap<Int64, Type>>()

    public init(chirPackage: Package) {
        this.chirPackage = chirPackage
    }

    public func CollectConstMemberVarType(): HashMap<Int64, HashMap<Int64, Type>> {
        constMemberMap.clear()
        for (def in chirPackage.GetCurPkgCustomTypeDef()) {
            if ((def as ExtendDef).isSome()) {
                continue
            }
            let index2Type = BuildCandidateMap(def)
            if (index2Type.isEmpty()) {
                continue
            }
            JudgeIfOnlyDerivedType(def, index2Type)
            let result = HashMap<Int64, Type>()
            for (index in index2Type.keys()) {
                if (let Some(info) <- index2Type.get(index)) {
                    if (!info.invalidated) {
                        if (let Some(derivedTy) <- info.derivedType) {
                            result[index] = derivedTy
                        }
                    }
                }
            }
            if (!result.isEmpty()) {
                constMemberMap[def.nodeId] = result
            }
        }
        return GetConstMemberMap()
    }

    public func GetConstMemberMap(): HashMap<Int64, HashMap<Int64, Type>> {
        let out = HashMap<Int64, HashMap<Int64, Type>>()
        for (defId in constMemberMap.keys()) {
            if (let Some(memberMap) <- constMemberMap.get(defId)) {
                let copied = HashMap<Int64, Type>()
                for (index in memberMap.keys()) {
                    if (let Some(ty) <- memberMap.get(index)) {
                        copied[index] = ty
                    }
                }
                out[defId] = copied
            }
        }
        return out
    }

    public func GetConstMemberType(def: CustomTypeDef, memberIndex: Int64): Option<Type> {
        if (let Some(memberMap) <- constMemberMap.get(def.nodeId)) {
            return memberMap.get(memberIndex)
        }
        return None
    }

    public func JudgeIfOnlyDerivedType(def: CustomTypeDef, index2Type: HashMap<Int64, ConstMemberVarInfo>): Unit {
        for (method in def.GetMethods()) {
            if (!method.IsConstructor() || method.GetNumOfParams() == 0) {
                continue
            }
            let firstParam = method.GetParam(0)
            if (let Some(body) <- method.GetBody()) {
                VisitBodyForStores(body, def, firstParam, index2Type)
            }
            RemoveInvalidated(index2Type)
            if (index2Type.isEmpty()) {
                return
            }
        }
    }

    public func HandleStoreElementRef(storeExpr: Expression, firstParam: Value,
        index2Type: HashMap<Int64, ConstMemberVarInfo>, ownerDef: CustomTypeDef): Unit {
        if (let Some(storeRef) <- (storeExpr as StoreElementRef)) {
            HandleStoreElementRefByPath(storeRef, firstParam, index2Type)
            return
        }
        if (let Some(storeByName) <- (storeExpr as StoreElementByName)) {
            HandleStoreElementByName(storeByName, firstParam, index2Type, ownerDef)
        }
    }

    private func HandleStoreElementRefByPath(storeRef: StoreElementRef, firstParam: Value,
        index2Type: HashMap<Int64, ConstMemberVarInfo>): Unit {
        let path = storeRef.GetPath()
        if (path.size != 1) {
            return
        }
        let rawIndex = path[0]
        if (rawIndex > 9223372036854775807u64) {
            return
        }
        let index = Int64(rawIndex)
        if (!index2Type.contains(index)) {
            return
        }
        if (storeRef.GetLocation().nodeId != firstParam.nodeId) {
            return
        }
        UpdateCandidateFromSource(index2Type, index, storeRef.GetValue())
    }

    private func HandleStoreElementByName(storeByName: StoreElementByName, firstParam: Value,
        index2Type: HashMap<Int64, ConstMemberVarInfo>, ownerDef: CustomTypeDef): Unit {
        let memberIndex = ResolveMemberIndexFromStoreByName(storeByName, ownerDef)
        if (memberIndex.isNone() || storeByName.GetLocation().nodeId != firstParam.nodeId) {
            return
        }
        if (let Some(index) <- memberIndex) {
            if (!index2Type.contains(index)) {
                return
            }
            UpdateCandidateFromSource(index2Type, index, storeByName.GetValue())
        }
    }

    private func UpdateCandidateFromSource(index2Type: HashMap<Int64, ConstMemberVarInfo>, index: Int64,
        sourceValue: Value): Unit {
        let sourceTarget = GetSourceTargetRecursively(sourceValue)
        if (let Some(sourceTy) <- sourceTarget.GetType()) {
            let stripped = sourceTy.StripAllRefs()
            if (IsOpenClassLikeType(stripped)) {
                InvalidateCandidate(index2Type, index)
                return
            }
            if (let Some(info) <- index2Type.get(index)) {
                if (let Some(oldTy) <- info.derivedType) {
                    if (!oldTy.IsEqual(stripped)) {
                        InvalidateCandidate(index2Type, index)
                    }
                } else {
                    info.derivedType = stripped
                }
            }
        } else {
            InvalidateCandidate(index2Type, index)
        }
    }

    public static func GetSourceTargetRecursively(value: Value): Value {
        var current = value
        var guard: Int64 = 0
        while (guard < 256) {
            guard++
            if (let Some(local) <- current.AsLocalVar()) {
                if (let Some(expr) <- local.GetExpr()) {
                    if (IsForwardingExpression(expr) && expr.GetNumOfOperands() > 0) {
                        current = expr.GetOperand(0)
                        continue
                    }
                }
            }
            return current
        }
        return current
    }

    private func BuildCandidateMap(def: CustomTypeDef): HashMap<Int64, ConstMemberVarInfo> {
        let out = HashMap<Int64, ConstMemberVarInfo>()
        let members = def.GetDirectInstanceVars()
        let indexBase = def.GetAllInstanceVarNum() - def.GetDirectInstanceVarNum()
        var idx: Int64 = 0
        for (member in members) {
            if (member.isStatic || !member.IsImmutable()) {
                idx++
                continue
            }
            let memberTy = member.ty.StripAllRefs()
            if (IsOpenClassLikeType(memberTy)) {
                out[indexBase + idx] = ConstMemberVarInfo(memberTy)
            }
            idx++
        }
        return out
    }

    private func VisitBodyForStores(body: BlockGroup, ownerDef: CustomTypeDef, firstParam: Value,
        index2Type: HashMap<Int64, ConstMemberVarInfo>): Unit {
        for (block in body.GetBlocksRef()) {
            for (expr in block.GetExpressionsRef()) {
                if (expr.GetExprKind() == ExprKind.STORE_ELEMENT_REF ||
                    expr.GetExprKind() == ExprKind.STORE_ELEMENT_BY_NAME) {
                    HandleStoreElementRef(expr, firstParam, index2Type, ownerDef)
                    if (index2Type.isEmpty()) {
                        return
                    }
                }
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        VisitBodyForStores(lambdaBody, ownerDef, firstParam, index2Type)
                    }
                }
            }
        }
    }
}

private func ResolveMemberIndexFromStoreByName(storeExpr: StoreElementByName, ownerDef: CustomTypeDef): Option<Int64> {
    let names = storeExpr.GetNames()
    if (names.size != 1) {
        return None
    }
    var idx: Int64 = 0
    for (member in ownerDef.GetInstanceVars()) {
        if (names[0] == member.name || names[0] == member.rawMangledName) {
            return idx
        }
        idx++
    }
    return None
}

private func IsForwardingExpression(expr: Expression): Bool {
    let kind = expr.GetExprKind()
    return kind == ExprKind.TYPECAST || kind == ExprKind.TYPECAST_WITH_EXCEPTION ||
        kind == ExprKind.BOX || kind == ExprKind.UNBOX || kind == ExprKind.TRANSFORM_TO_GENERIC ||
        kind == ExprKind.TRANSFORM_TO_CONCRETE || kind == ExprKind.UNBOX_TO_REF ||
        kind == ExprKind.GET_INSTANTIATE_VALUE
}

private func IsOpenClassLikeType(ty: Type): Bool {
    if (let Some(customTy) <- (ty as CustomType)) {
        let def = customTy.GetCustomTypeDef()
        return def.IsClassLike() && def.CanBeInherited()
    }
    return false
}

private func InvalidateCandidate(index2Type: HashMap<Int64, ConstMemberVarInfo>, index: Int64): Unit {
    if (let Some(info) <- index2Type.get(index)) {
        info.invalidated = true
    }
    index2Type.remove(index)
}

private func RemoveInvalidated(index2Type: HashMap<Int64, ConstMemberVarInfo>): Unit {
    let removeKeys = ArrayList<Int64>()
    for (index in index2Type.keys()) {
        if (let Some(info) <- index2Type.get(index)) {
            if (info.invalidated) {
                removeKeys.add(index)
            }
        }
    }
    for (index in removeKeys) {
        index2Type.remove(index)
    }
}
