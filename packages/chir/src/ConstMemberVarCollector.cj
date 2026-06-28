package cangjie_compiler::chir

import std.collection.*

public class MemberInfo {
    public let oriType: Type
    public var derivedType: Option<Type> = None

    public init(oriType: Type) {
        this.oriType = oriType
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
                    if (let Some(derivedTy) <- info.derivedType) {
                        result[index] = derivedTy
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

    public func JudgeIfOnlyDerivedType(def: CustomTypeDef, index2Type: HashMap<Int64, MemberInfo>): Unit {
        for (method in def.GetMethods()) {
            if (!method.IsConstructor()) {
                continue
            }
            let firstParam = method.GetParam(0)
            if (let Some(body) <- method.GetBody()) {
                VisitBodyForStores(body, firstParam, index2Type)
            }
        }
    }

    public func HandleStoreElementRef(storeRef: StoreElementRef, firstParam: Value,
        index2Type: HashMap<Int64, MemberInfo>): Unit {
        let path = storeRef.GetPath()
        if (path.size != 1) {
            return
        }
        let index = Int64(path[0])
        if (!index2Type.contains(index)) {
            return
        }
        if (storeRef.GetLocation() != firstParam) {
            return
        }
        let sourceValue = GetSourceTargetRecursively(storeRef.GetValue())
        let sourceType = sourceValue.GetType().getOrThrow().StripAllRefs()
        if (let Some(customTy) <- (sourceType as CustomType)) {
            if (customTy.GetCustomTypeDef().CanBeInherited()) {
                index2Type.remove(index)
                return
            }
        }
        if (let Some(info) <- index2Type.get(index)) {
            if (let Some(oldTy) <- info.derivedType) {
                if (!oldTy.IsEqual(sourceType)) {
                    index2Type.remove(index)
                }
            } else {
                info.derivedType = sourceType
            }
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

    private func BuildCandidateMap(def: CustomTypeDef): HashMap<Int64, MemberInfo> {
        let out = HashMap<Int64, MemberInfo>()
        let members = def.GetDirectInstanceVars()
        let indexBase = def.GetAllInstanceVarNum() - def.GetDirectInstanceVarNum()
        var idx: Int64 = 0
        for (member in members) {
            if (!member.IsImmutable()) {
                idx++
                continue
            }
            let memberTy = member.ty.StripAllRefs()
            if (let Some(customTy) <- (memberTy as CustomType)) {
                let customDef = customTy.GetCustomTypeDef()
                if (customDef.IsClassLike() && customDef.CanBeInherited()) {
                    out[indexBase + idx] = MemberInfo(customTy)
                }
            }
            idx++
        }
        return out
    }

    private func VisitBodyForStores(body: BlockGroup, firstParam: Value,
        index2Type: HashMap<Int64, MemberInfo>): Unit {
        for (block in body.GetBlocksRef()) {
            for (expr in block.GetExpressionsRef()) {
                if (expr.GetExprKind() == ExprKind.STORE_ELEMENT_REF) {
                    let storeRef = (expr as StoreElementRef).getOrThrow()
                    HandleStoreElementRef(storeRef, firstParam, index2Type)
                    if (index2Type.isEmpty()) {
                        return
                    }
                }
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        VisitBodyForStores(lambdaBody, firstParam, index2Type)
                        if (index2Type.isEmpty()) {
                            return
                        }
                    }
                }
            }
        }
    }
}

private func IsForwardingExpression(expr: Expression): Bool {
    let kind = expr.GetExprKind()
    return kind == ExprKind.TYPECAST || kind == ExprKind.TYPECAST_WITH_EXCEPTION ||
        kind == ExprKind.BOX || kind == ExprKind.UNBOX || kind == ExprKind.TRANSFORM_TO_GENERIC ||
        kind == ExprKind.TRANSFORM_TO_CONCRETE || kind == ExprKind.UNBOX_TO_REF ||
        kind == ExprKind.GET_INSTANTIATE_VALUE
}
