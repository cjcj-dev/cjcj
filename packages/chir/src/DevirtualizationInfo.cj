package cangjie_compiler::chir

import std.collection.*

public enum DevirtualTyKind {
    | SUBTYPE_OF | EXACTLY
}

public func DevirtualTyKindIndex(kind: DevirtualTyKind): Int64 {
    return match (kind) {
        case DevirtualTyKind.SUBTYPE_OF => 0
        case DevirtualTyKind.EXACTLY => 1
    }
}

extend DevirtualTyKind <: Equatable<DevirtualTyKind> {
    public operator func ==(right: DevirtualTyKind): Bool {
        return DevirtualTyKindIndex(this) == DevirtualTyKindIndex(right)
    }

    public operator func !=(right: DevirtualTyKind): Bool {
        return !(this == right)
    }
}

public class InheritanceInfo {
    public let parentType: ClassType
    public let subType: Type

    public init(parentType: ClassType, subType: Type) {
        this.parentType = parentType
        this.subType = subType
    }
}

private enum PackageRelationForAnalysis {
    | NONE | CHILD | SAME_PACKAGE
}

private func PackageRelationForAnalysisIndex(relation: PackageRelationForAnalysis): Int64 {
    return match (relation) {
        case PackageRelationForAnalysis.NONE => 0
        case PackageRelationForAnalysis.CHILD => 1
        case PackageRelationForAnalysis.SAME_PACKAGE => 2
    }
}

extend PackageRelationForAnalysis <: Equatable<PackageRelationForAnalysis> {
    public operator func ==(right: PackageRelationForAnalysis): Bool {
        return PackageRelationForAnalysisIndex(this) == PackageRelationForAnalysisIndex(right)
    }

    public operator func !=(right: PackageRelationForAnalysis): Bool {
        return !(this == right)
    }
}

public class DevirtualizationInfo {
    private let chirPackage: Package
    private let noSubPkg: Bool
    private let subtypeMap: HashMap<Int64, ArrayList<InheritanceInfo>> = HashMap<Int64, ArrayList<InheritanceInfo>>()
    private let realRuntimeRetTyMap: HashMap<Int64, Type> = HashMap<Int64, Type>()
    private let constMemberTypeMap: HashMap<Int64, HashMap<Int64, Type>> = HashMap<Int64, HashMap<Int64, Type>>()
    public let defsMap: HashMap<String, ArrayList<CustomTypeDef>> = HashMap<String, ArrayList<CustomTypeDef>>()

    public init(chirPackage: Package, noSubPkg!: Bool = false) {
        this.chirPackage = chirPackage
        this.noSubPkg = noSubPkg
    }

    public func CollectInfo(): Unit {
        realRuntimeRetTyMap.clear()
        subtypeMap.clear()
        defsMap.clear()
        for (fn in chirPackage.GetGlobalFuncsWithBody()) {
            CollectReturnTypeMap(fn)
        }
        for (customDef in chirPackage.GetAllCustomTypeDef()) {
            if (ShouldSkipCustomTypeDef(customDef)) {
                continue
            }
            let thisType = GetCanonicalTypeForDef(customDef)
            if (let Some(defType) <- thisType) {
                AddDefForType(defType, customDef)
                CollectInheritance(customDef, defType)
            }
        }
    }

    public func FreshRetMap(): Unit {
        realRuntimeRetTyMap.clear()
        for (fn in chirPackage.GetGlobalFuncsWithBody()) {
            CollectReturnTypeMap(fn)
        }
    }

    public func CheckCustomTypeInternal(def: CustomTypeDef): Bool {
        if (def.TestAttr(Attribute.PUBLIC) || def.TestAttr(Attribute.PROTECTED)) {
            return false
        }
        if (def.TestAttr(Attribute.PRIVATE)) {
            return true
        }
        let relation = GetPackageRelationForAnalysis(def.GetPackageName(), chirPackage.GetName())
        if (relation != PackageRelationForAnalysis.CHILD && relation != PackageRelationForAnalysis.SAME_PACKAGE) {
            return true
        }
        if (noSubPkg) {
            return true
        }
        return false
    }

    public func CollectConstMemberVarType(): Unit {
        constMemberTypeMap.clear()
        let collector = ConstMemberVarCollector(chirPackage)
        let collected = collector.CollectConstMemberVarType()
        for (defId in collected.keys()) {
            if (let Some(memberMap) <- collected.get(defId)) {
                let copied = HashMap<Int64, Type>()
                for (index in memberMap.keys()) {
                    if (let Some(memberTy) <- memberMap.get(index)) {
                        copied[index] = memberTy
                    }
                }
                constMemberTypeMap[defId] = copied
            }
        }
    }

    public func GetSubtypeMap(): HashMap<Int64, ArrayList<InheritanceInfo>> {
        let out = HashMap<Int64, ArrayList<InheritanceInfo>>()
        for (defId in subtypeMap.keys()) {
            if (let Some(values) <- subtypeMap.get(defId)) {
                let copied = ArrayList<InheritanceInfo>()
                for (value in values) {
                    copied.add(value)
                }
                out[defId] = copied
            }
        }
        return out
    }

    public func GetSubtypeInfos(parentDef: ClassDef): ArrayList<InheritanceInfo> {
        if (let Some(values) <- subtypeMap.get(parentDef.nodeId)) {
            let out = ArrayList<InheritanceInfo>()
            for (value in values) {
                out.add(value)
            }
            return out
        }
        return ArrayList<InheritanceInfo>()
    }

    public func GetConstMemberMap(): HashMap<Int64, HashMap<Int64, Type>> {
        let out = HashMap<Int64, HashMap<Int64, Type>>()
        for (defId in constMemberTypeMap.keys()) {
            if (let Some(values) <- constMemberTypeMap.get(defId)) {
                let copied = HashMap<Int64, Type>()
                for (index in values.keys()) {
                    if (let Some(memberTy) <- values.get(index)) {
                        copied[index] = memberTy
                    }
                }
                out[defId] = copied
            }
        }
        return out
    }

    public func GetReturnTypeMap(): HashMap<Int64, Type> {
        let out = HashMap<Int64, Type>()
        for (funcId in realRuntimeRetTyMap.keys()) {
            if (let Some(ty) <- realRuntimeRetTyMap.get(funcId)) {
                out[funcId] = ty
            }
        }
        return out
    }

    public func GetReturnType(fn: Function): Option<Type> {
        return realRuntimeRetTyMap.get(fn.nodeId)
    }

    public func GetDefsForType(ty: Type): ArrayList<CustomTypeDef> {
        if (let Some(values) <- defsMap.get(TypeKey(ty))) {
            let out = ArrayList<CustomTypeDef>()
            for (value in values) {
                out.add(value)
            }
            return out
        }
        return ArrayList<CustomTypeDef>()
    }

    private func CollectReturnTypeMap(fn: Function): Unit {
        if (let Some(returnValue) <- fn.GetReturnValue()) {
            if (let Some(runtimeTy) <- GetRuntimeTypeFromFunc(returnValue, isInLambda: false)) {
                realRuntimeRetTyMap[fn.nodeId] = runtimeTy
            }
        }
    }

    private func CollectInheritance(customDef: CustomTypeDef, thisType: Type): Unit {
        if (let Some(classDef) <- (customDef as ClassDef)) {
            if (let Some(superTy) <- classDef.GetSuperClassTy()) {
                AddSubtypeInfo(superTy, thisType)
            } else if (let Some(superDef) <- classDef.GetSuperClassDef()) {
                AddSubtypeInfo(ClassType(superDef, ArrayList<Type>()), thisType)
            }
            for (interfaceTy in classDef.GetImplementedInterfaceTys()) {
                AddSubtypeInfo(interfaceTy, thisType)
            }
        }
    }

    private func AddSubtypeInfo(parentType: ClassType, subType: Type): Unit {
        let parentDef = parentType.GetClassDef()
        if (IsCoreObject(parentDef) || !CheckCustomTypeInternal(parentDef)) {
            return
        }
        let info = InheritanceInfo(parentType, subType)
        if (let Some(values) <- subtypeMap.get(parentDef.nodeId)) {
            if (!ContainsInheritanceInfo(values, info)) {
                values.add(info)
            }
        } else {
            let values = ArrayList<InheritanceInfo>()
            values.add(info)
            subtypeMap[parentDef.nodeId] = values
        }
    }

    private func AddDefForType(ty: Type, customDef: CustomTypeDef): Unit {
        let key = TypeKey(ty)
        if (let Some(values) <- defsMap.get(key)) {
            values.add(customDef)
        } else {
            let values = ArrayList<CustomTypeDef>()
            values.add(customDef)
            defsMap[key] = values
        }
    }
}

private func GetRuntimeTypeFromFunc(retVal: Value, isInLambda!: Bool): Option<Type> {
    let retTy = if (let Some(ty) <- retVal.GetType()) { ty.StripAllRefs() } else { return None }
    if (!retTy.IsClass()) {
        return None
    }
    let users = retVal.GetUsers()
    if (users.size != 1 || users[0].GetExprKind() != ExprKind.STORE || users[0].GetNumOfOperands() < 2) {
        return None
    }
    let storedValue = users[0].GetOperand(0)
    if (!storedValue.IsLocalVar()) {
        return None
    }
    let storedTy = InferStoredRuntimeType(storedValue, isInLambda: isInLambda)
    if (let Some(srcTy) <- storedTy) {
        let strippedSrcTy = srcTy.StripAllRefs()
        if (!strippedSrcTy.IsEqual(retTy)) {
            return strippedSrcTy
        }
    }
    return None
}

private func InferStoredRuntimeType(value: Value, isInLambda!: Bool): Option<Type> {
    var srcTy: Option<Type> = value.GetType()
    if (let Some(local) <- value.AsLocalVar()) {
        if (let Some(expr) <- local.GetExpr()) {
            if (expr.GetExprKind() == ExprKind.TYPECAST && expr.GetNumOfOperands() > 0) {
                srcTy = expr.GetOperand(0).GetType()
            } else if (expr.GetExprKind() == ExprKind.APPLY && !isInLambda) {
                if (let Some(applyTy) <- GetRuntimeTypeFromLambdaApply(expr, srcTy)) {
                    srcTy = applyTy
                }
            }
        }
    }
    return srcTy
}

private func GetRuntimeTypeFromLambdaApply(apply: Expression, fallback: Option<Type>): Option<Type> {
    if (apply.GetNumOfOperands() == 0) {
        return fallback
    }
    let callee = apply.GetOperand(0)
    if (let Some(local) <- callee.AsLocalVar()) {
        if (let Some(lambdaExpr) <- local.GetExpr()) {
            if (let Some(lambda) <- (lambdaExpr as Lambda)) {
                if (let Some(lambdaBody) <- lambda.GetBody()) {
                    if (let Some(resultValue) <- FindStoredReturnValue(lambdaBody)) {
                        return GetRuntimeTypeFromFunc(resultValue, isInLambda: true)
                    }
                }
            }
        }
    }
    return fallback
}

private func FindStoredReturnValue(body: BlockGroup): Option<Value> {
    for (block in body.GetBlocksRef()) {
        for (expr in block.GetExpressionsRef()) {
            if (expr.GetExprKind() == ExprKind.STORE && expr.GetNumOfOperands() >= 2) {
                let location = expr.GetOperand(1)
                if (let Some(local) <- location.AsLocalVar()) {
                    if (local.IsRetValue()) {
                        return location
                    }
                }
            }
            if (let Some(lambda) <- (expr as Lambda)) {
                if (let Some(lambdaBody) <- lambda.GetBody()) {
                    if (let Some(value) <- FindStoredReturnValue(lambdaBody)) {
                        return value
                    }
                }
            }
        }
    }
    return None
}

private func GetCanonicalTypeForDef(customDef: CustomTypeDef): Option<Type> {
    if (let Some(ty) <- customDef.GetType()) {
        return ty
    }
    if (let Some(classDef) <- (customDef as ClassDef)) {
        return ClassType(classDef, ArrayList<Type>())
    }
    if (let Some(structDef) <- (customDef as StructDef)) {
        return StructType(structDef, ArrayList<Type>())
    }
    if (let Some(enumDef) <- (customDef as EnumDef)) {
        return EnumType(enumDef, ArrayList<Type>())
    }
    if (let Some(extendDef) <- (customDef as ExtendDef)) {
        if (let Some(extendedTy) <- extendDef.extendedType) {
            if (let Some(customTy) <- (extendedTy as CustomType)) {
                return GetCanonicalTypeForDef(customTy.GetCustomTypeDef())
            }
            return extendedTy
        }
    }
    return None
}

private func ShouldSkipCustomTypeDef(customDef: CustomTypeDef): Bool {
    if (let Some(classDef) <- (customDef as ClassDef)) {
        return IsClosureConversionEnvClass(classDef)
    }
    return false
}

private func IsClosureConversionEnvClass(classDef: ClassDef): Bool {
    if (classDef.GetAnnotation("IsAutoEnvClass").isSome()) {
        return true
    }
    let name = classDef.GetIdentifier()
    return name.contains("AutoEnv") || name.contains("ClosureEnv") || name.contains("$env")
}

private func IsCoreObject(classDef: ClassDef): Bool {
    if (classDef.GetPackageName() != "std.core") {
        return false
    }
    let name = classDef.GetIdentifier()
    return name == "Any" || name == "Object"
}

private func TypeKey(ty: Type): String {
    return ty.ToString()
}

private func ContainsInheritanceInfo(values: ArrayList<InheritanceInfo>, target: InheritanceInfo): Bool {
    for (value in values) {
        if (value.parentType.GetClassDef().nodeId == target.parentType.GetClassDef().nodeId &&
            value.parentType.IsEqual(target.parentType) && value.subType.IsEqual(target.subType)) {
            return true
        }
    }
    return false
}

private func GetPackageRelationForAnalysis(srcFullPkgName: String, targetFullPkgName: String):
    PackageRelationForAnalysis {
    if (srcFullPkgName == targetFullPkgName) {
        return PackageRelationForAnalysis.SAME_PACKAGE
    }
    if (srcFullPkgName.isEmpty() || targetFullPkgName.isEmpty()) {
        return PackageRelationForAnalysis.NONE
    }
    if (srcFullPkgName.startsWith(targetFullPkgName + ".")) {
        return PackageRelationForAnalysis.CHILD
    }
    return PackageRelationForAnalysis.NONE
}
