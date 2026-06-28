package cangjie_compiler::chir

import std.collection.*
import cangjie_compiler::utils.CJC_ABORT

public class ExtendDef <: CustomTypeDef {
    public var extendedType: Option<Type> = None

    public init(packageName: String, identifier: String) {
        super(packageName, identifier, identifier, CustomDefKind.TYPE_EXTEND)
    }

    public func GetExtendedType(): Option<Type> {
        return extendedType
    }

    public func SetExtendedType(ty: Type): Unit {
        extendedType = ty
    }

    public override func GetType(): Option<Type> {
        return GetExtendedType()
    }

    public override func SetType(ty: CustomType): Unit {
        let _ = ty
        CJC_ABORT()
        throw IllegalStateException("extend decl doesn't have type")
    }

    public func GetExtendedCustomTypeDef(): Option<CustomTypeDef> {
        if (let Some(ty) <- extendedType) {
            if (let Some(customTy) <- (ty as CustomType)) {
                return customTy.GetCustomTypeDef()
            }
        }
        return None
    }

    public override func GetGenericTypeParams(): ArrayList<GenericType> {
        return super.GetGenericTypeParams()
    }

    public func RemoveParent(parent: ClassType): Unit {
        var idx: Int64 = 0
        while (idx < implementedInterfaceTys.size) {
            if (refEq(implementedInterfaceTys[idx], parent)) {
                implementedInterfaceTys.remove(at: idx)
            } else {
                idx++
            }
        }
    }

    public override func ToString(indent: Int64): String {
        let target = if (let Some(ty) <- extendedType) { ty.ToString() } else { "<unknown>" }
        return IndentToString(indent) + "extend " + target
    }
}
