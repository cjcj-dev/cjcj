package cjcj::chir

import std.collection.*

public class InheritanceInfo {
    public let parentType: ClassType
    public let subType: Type
    public init(parentType: ClassType, subType: Type) {
        this.parentType = parentType
        this.subType = subType
    }
}

// Upstream 6e125215 src/CHIR/Analysis/InheritanceInfoCollector.cpp:16-37.
public class InheritanceInfoCollector {
    private let chirPackage: Package
    public init(chirPackage: Package) { this.chirPackage = chirPackage }
    public func Collect(subtypeMap: HashMap<CustomTypeDef, ArrayList<InheritanceInfo>>,
        defsMap: HashMap<Type, ArrayList<CustomTypeDef>>): Unit {
        for (def in chirPackage.GetAllCustomTypeDef()) {
            var thisType = def.GetType().getOrThrow()
            if (let Some(exDef) <- (def as ExtendDef)) {
                thisType = exDef.GetExtendedType().getOrThrow()
                if (let Some(customTy) <- (thisType as CustomType)) {
                    thisType = customTy.GetCustomTypeDef().GetType().getOrThrow()
                }
            }
            if (!defsMap.contains(thisType)) { defsMap[thisType] = ArrayList<CustomTypeDef>() }
            defsMap[thisType].add(def)
            for (parentTy in def.GetSuperTypesInCurDef()) {
                let parentDef = parentTy.GetClassDef()
                if (IsCoreObject(parentDef)) { continue }
                if (!subtypeMap.contains(parentDef)) { subtypeMap[parentDef] = ArrayList<InheritanceInfo>() }
                subtypeMap[parentDef].add(InheritanceInfo(parentTy, thisType))
            }
        }
    }
}
