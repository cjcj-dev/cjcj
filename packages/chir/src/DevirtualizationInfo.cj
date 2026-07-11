package cjcj::chir

import std.collection.*
import cjcj::modules.{GetPackageRelation, PackageRelation}
import cjcj::option.GlobalOptions
import cjcj::utils.StaticCast

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

public class DevirtualizationInfo {
    private let chirPackage: Package
    private let opts: GlobalOptions
    private let subtypeMap: HashMap<Int64, ArrayList<InheritanceInfo>> = HashMap<Int64, ArrayList<InheritanceInfo>>()
    private let realRuntimeRetTyMap: HashMap<Int64, Type> = HashMap<Int64, Type>()
    private let constMemberTypeMap: HashMap<Int64, HashMap<Int64, Type>> = HashMap<Int64, HashMap<Int64, Type>>()
    public let defsMap: HashMap<Int64, ArrayList<CustomTypeDef>> = HashMap<Int64, ArrayList<CustomTypeDef>>()

    public init(chirPackage: Package, opts: GlobalOptions) {
        this.chirPackage = chirPackage
        this.opts = opts
    }

    public func CollectInfo(): Unit {
        for (fn in chirPackage.GetGlobalFuncsWithBody()) {
            CollectReturnTypeMap(fn)
        }
        for (customDef in chirPackage.GetAllCustomTypeDef()) {
            if (customDef.TestAttr(Attribute.SKIP_ANALYSIS)) {
                continue
            }
            if (customDef.IsClassLike() && IsClosureConversionEnvClass(StaticCast<ClassDef>(customDef))) {
                continue
            }

            var thisType = customDef.GetType().getOrThrow()
            if (customDef.IsExtend()) {
                thisType = StaticCast<ExtendDef>(customDef).GetExtendedType().getOrThrow()
                if (let Some(customTy) <- (thisType as CustomType)) {
                    thisType = customTy.GetCustomTypeDef().GetType().getOrThrow()
                }
            }

            if (let Some(values) <- defsMap.get(thisType.objectId)) {
                values.add(customDef)
            } else {
                let values = ArrayList<CustomTypeDef>()
                values.add(customDef)
                defsMap[thisType.objectId] = values
            }

            for (parentTy in customDef.GetSuperTypesInCurDef()) {
                let parentDef = parentTy.GetClassDef()
                if (IsCoreObject(parentDef)) {
                    continue
                }
                if (CheckCustomTypeInternal(parentDef)) {
                    let info = InheritanceInfo(parentTy, thisType)
                    if (let Some(infos) <- subtypeMap.get(parentDef.nodeId)) {
                        infos.add(info)
                    } else {
                        let infos = ArrayList<InheritanceInfo>()
                        infos.add(info)
                        subtypeMap[parentDef.nodeId] = infos
                    }
                }
            }
        }
    }

    public func FreshRetMap(): Unit {
        for (fn in chirPackage.GetGlobalFuncsWithBody()) {
            if (let Some(runtimeTy) <- GetRuntimeTypeFromFunc(fn.GetReturnValue())) {
                realRuntimeRetTyMap[fn.nodeId] = runtimeTy
            }
        }
    }

    public func CheckCustomTypeInternal(def: CustomTypeDef): Bool {
        let relation = GetPackageRelation(def.GetPackageName(), chirPackage.GetName())
        if (def.TestAttr(Attribute.PUBLIC) || def.TestAttr(Attribute.PROTECTED)) {
            return false
        }
        if (def.TestAttr(Attribute.PRIVATE)) {
            return true
        }
        if (def.TestAttr(Attribute.INTERNAL)) {
            if (relation != PackageRelation.CHILD && relation != PackageRelation.SAME_PACKAGE) {
                return true
            }
            if (opts.noSubPkg) {
                return true
            }
            return false
        }
        return false
    }

    public func CollectConstMemberVarType(): Unit {
        let collector = ConstMemberVarCollector(chirPackage)
        let collected = collector.CollectConstMemberVarType()
        for ((defId, memberMap) in collected) {
            if (!constMemberTypeMap.contains(defId)) {
                constMemberTypeMap[defId] = memberMap
            }
        }
    }

    public func GetSubtypeMap(): HashMap<Int64, ArrayList<InheritanceInfo>> {
        return subtypeMap
    }

    public func GetConstMemberMap(): HashMap<Int64, HashMap<Int64, Type>> {
        return constMemberTypeMap
    }

    public func GetReturnTypeMap(): HashMap<Int64, Type> {
        return realRuntimeRetTyMap
    }

    private func CollectReturnTypeMap(fn: Function): Unit {
        if (let Some(runtimeTy) <- GetRuntimeTypeFromFunc(fn.GetReturnValue())) {
            if (!realRuntimeRetTyMap.contains(fn.nodeId)) {
                realRuntimeRetTyMap[fn.nodeId] = runtimeTy
            }
        }
    }
}

private func GetRuntimeTypeFromLambda(apply: Apply, fallbackTy: Type): Option<Type> {
    if (!apply.GetCallee().IsLocalVar()) {
        return Some(fallbackTy)
    }
    let localVar = StaticCast<LocalVar>(apply.GetCallee())
    let expr = localVar.GetExpr().getOrThrow()
    if (expr.GetExprKind() != ExprKind.LAMBDA) {
        return Some(fallbackTy)
    }
    let lambda = StaticCast<Lambda>(expr)
    return GetRuntimeTypeFromFunc(lambda.GetReturnValue(), isInLambda: true)
}

private func GetRuntimeTypeFromFunc(retVal: Option<LocalVar>, isInLambda!: Bool = false): Option<Type> {
    let value = retVal ?? return None
    let rtTy = value.GetType().getOrThrow().StripAllRefs()
    if (!rtTy.IsClass()) {
        return None
    }
    let users = value.GetUsers()
    if (users.size == 1 && users[0].GetExprKind() == ExprKind.STORE) {
        let storedValue = StaticCast<Store>(users[0]).GetValue()
        if (!storedValue.IsLocalVar()) {
            return None
        }
        let expr = StaticCast<LocalVar>(storedValue).GetExpr().getOrThrow()
        var srcTy = storedValue.GetType().getOrThrow()
        if (expr.GetExprKind() == ExprKind.TYPECAST) {
            srcTy = StaticCast<TypeCast>(expr).GetSourceTy().getOrThrow()
        } else if (expr.GetExprKind() == ExprKind.APPLY && !isInLambda) {
            if (let Some(applyResType) <- GetRuntimeTypeFromLambda(StaticCast<Apply>(expr), srcTy)) {
                srcTy = applyResType
            }
        }
        srcTy = srcTy.StripAllRefs()
        if (srcTy == rtTy) {
            return None
        }
        return Some(srcTy)
    }
    return None
}

private func IsClosureConversionEnvClass(classDef: ClassDef): Bool {
    return classDef.GetAnnotation("IsAutoEnvClass").isSome()
}

private func IsCoreObject(classDef: ClassDef): Bool {
    var packageName = classDef.GetPackageName()
    if (let Some(genericDecl) <- classDef.GetGenericDecl()) {
        packageName = genericDecl.GetPackageName()
    }
    return packageName == "std.core" && classDef.GetSrcCodeIdentifier() == "Object"
}
