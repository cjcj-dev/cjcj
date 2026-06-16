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
        if (storeExpr.GetExprKind() != ExprKind.STORE_ELEMENT_REF &&
            storeExpr.GetExprKind() != ExprKind.STORE_ELEMENT_BY_NAME) {
            return
        }
        let memberIndex = ResolveMemberIndexFromStore(storeExpr, ownerDef)
        if (memberIndex.isNone()) {
            return
        }
        if (let Some(index) <- memberIndex) {
            if (!index2Type.contains(index)) {
                return
            }
            let maybeLocation = GetStoreElementLocation(storeExpr, firstParam)
            if (maybeLocation.isNone()) {
                return
            }
            let maybeSource = GetStoreElementValue(storeExpr, firstParam, ownerDef)
            if (maybeSource.isNone()) {
                InvalidateCandidate(index2Type, index)
                return
            }
            if (let Some(sourceValue) <- maybeSource) {
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
        let members = def.GetInstanceVars()
        var idx: Int64 = 0
        for (member in members) {
            if (member.isStatic || !member.isReadOnly) {
                idx++
                continue
            }
            let memberTy = member.ty.StripAllRefs()
            if (IsOpenClassLikeType(memberTy)) {
                out[idx] = ConstMemberVarInfo(memberTy)
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

private func ResolveMemberIndexFromStore(storeExpr: Expression, ownerDef: CustomTypeDef): Option<Int64> {
    var idx: Int64 = 0
    for (member in ownerDef.GetInstanceVars()) {
        var operandIdx: Int64 = 0
        while (operandIdx < storeExpr.GetNumOfOperands()) {
            let operand = storeExpr.GetOperand(operandIdx)
            if (operand.GetSrcCodeIdentifier() == member.name || operand.GetIdentifierWithoutPrefix() == member.name) {
                return idx
            }
            operandIdx++
        }
        idx++
    }
    if (storeExpr.GetNumOfOperands() >= 3) {
        if (let Some(intLiteral) <- ExtractIntLiteral(storeExpr.GetOperand(2))) {
            if (intLiteral >= 0 && intLiteral < ownerDef.GetInstanceVars().size) {
                return intLiteral
            }
        }
    }
    return None
}

private func GetStoreElementLocation(storeExpr: Expression, firstParam: Value): Option<Value> {
    var idx: Int64 = 0
    while (idx < storeExpr.GetNumOfOperands()) {
        let operand = storeExpr.GetOperand(idx)
        if (operand.nodeId == firstParam.nodeId) {
            return operand
        }
        idx++
    }
    return None
}

private func GetStoreElementValue(storeExpr: Expression, firstParam: Value, ownerDef: CustomTypeDef): Option<Value> {
    var idx: Int64 = 0
    while (idx < storeExpr.GetNumOfOperands()) {
        let operand = storeExpr.GetOperand(idx)
        if (operand.nodeId == firstParam.nodeId || IsMemberPathMarker(operand, ownerDef)) {
            idx++
            continue
        }
        return operand
    }
    return None
}

private func IsMemberPathMarker(value: Value, ownerDef: CustomTypeDef): Bool {
    let srcName = value.GetSrcCodeIdentifier()
    let identifier = value.GetIdentifierWithoutPrefix()
    for (member in ownerDef.GetInstanceVars()) {
        if ((!srcName.isEmpty() && srcName == member.name) || (!identifier.isEmpty() && identifier == member.name)) {
            return true
        }
    }
    if (ExtractIntLiteral(value).isSome()) {
        return true
    }
    return false
}

private func ExtractIntLiteral(value: Value): Option<Int64> {
    if (let Some(local) <- value.AsLocalVar()) {
        if (let Some(expr) <- local.GetExpr()) {
            if (let Some(constant) <- (expr as Constant)) {
                if (let Some(intLiteral) <- (constant.literal as IntLiteral)) {
                    return intLiteral.value
                }
            }
        }
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
        return (customTy.GetCustomTypeDef() as ClassDef).isSome()
    }
    return false
}

private func InvalidateCandidate(index2Type: HashMap<Int64, ConstMemberVarInfo>, index: Int64): Unit {
    if (let Some(info) <- index2Type.get(index)) {
        info.invalidated = true
    }
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
