package cjcj::chir

import std.collection.*
import cjcj::utils.CJC_ABORT

public class ExtendDef <: CustomTypeDef {
    public var extendedType: Option<Type> = None

    public init(packageName: String, identifier: String) {
        super(packageName, identifier, "", CustomDefKind.TYPE_EXTEND)
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
        let out = ArrayList<GenericType>()
        for (param in genericTypeParams) {
            out.add(param)
        }
        return out
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

    protected override func CustomTypeDefTitleToString(): String {
        let extendedTy = extendedType.getOrThrow()
        let extendedTyText = if (let Some(customTy) <- (extendedTy as CustomType)) {
            customTy.GetCustomTypeDef().GetIdentifier() + GenericInsArgsToString(customTy)
        } else {
            extendedTy.ToString()
        }
        return "extend" + TypeVecToString("<", GetGenericTypeParams(), ">") + " " + extendedTyText
    }

    protected override func AddExtraComment(): String {
        let comments = ArrayList<String>()
        if (!GetIdentifier().isEmpty()) {
            comments.add("id: " + GetIdentifier())
        }
        let constraints = GetGenericTypeConstaintsStr(GetGenericTypeParams())
        if (!constraints.isEmpty()) {
            comments.add("genericConstrains: " + constraints)
        }
        return StringJoin(comments, ", ")
    }
}
