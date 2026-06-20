package cangjie_compiler::chir

import std.collection.*

public class EnumCtorInfo {
    public let name: String
    public let payloadTypes: ArrayList<Type> = ArrayList<Type>()

    public init(name: String, payloadTypes: ArrayList<Type>) {
        this.name = name
        for (ty in payloadTypes) {
            this.payloadTypes.add(ty)
        }
    }
}

public class EnumDef <: CustomTypeDef {
    private var enumType: Option<EnumType> = None
    private let ctors: ArrayList<EnumCtorInfo> = ArrayList<EnumCtorInfo>()
    private var nonExhaustive: Bool = false

    public init(packageName: String, identifier: String) {
        super(packageName, identifier, identifier, CustomDefKind.TYPE_ENUM)
    }

    public init(packageName: String, identifier: String, srcCodeIdentifier: String) {
        super(packageName, identifier, srcCodeIdentifier, CustomDefKind.TYPE_ENUM)
    }

    public override func GetType(): Option<CustomType> {
        if (let Some(ty) <- enumType) {
            return ty
        }
        return None
    }

    public override func SetType(ty: CustomType): Unit {
        if (let Some(enumTy) <- (ty as EnumType)) {
            enumType = enumTy
            return
        }
        throw IllegalArgumentException("EnumDef requires EnumType")
    }

    public func AddCtor(info: EnumCtorInfo): Unit {
        ctors.add(info)
    }

    public func GetCtors(): ArrayList<EnumCtorInfo> {
        let out = ArrayList<EnumCtorInfo>()
        for (ctor in ctors) {
            out.add(ctor)
        }
        return out
    }

    public func GetConstructorInfos(builder!: Option<CHIRBuilder> = None): ArrayList<EnumCtorInfo> {
        let _ = builder
        return GetCtors()
    }

    public func SetNonExhaustive(value: Bool): Unit {
        nonExhaustive = value
    }

    public func IsExhaustive(): Bool {
        return !nonExhaustive
    }

    public func IsAllCtorsTrivial(): Bool {
        for (ctor in ctors) {
            if (!ctor.payloadTypes.isEmpty()) {
                return false
            }
        }
        return true
    }

    public func IsOptionLike(): Bool {
        if (!IsExhaustive()) {
            return false
        }
        if (ctors.size != 2) {
            return false
        }
        return (ctors[0].payloadTypes.isEmpty() && ctors[1].payloadTypes.size == 1) ||
            (ctors[1].payloadTypes.isEmpty() && ctors[0].payloadTypes.size == 1)
    }

    public func IsAntiOptionLike(): Bool {
        return IsOptionLike() && ctors[0].payloadTypes.isEmpty()
    }

    public func GetOptionLikeAssociatedValueType(): Option<Type> {
        if (!IsOptionLike()) {
            return None
        }
        if (!ctors[0].payloadTypes.isEmpty()) {
            return Some(ctors[0].payloadTypes[0])
        }
        if (!ctors[1].payloadTypes.isEmpty()) {
            return Some(ctors[1].payloadTypes[0])
        }
        return None
    }

    public override func ToString(indent: Int64): String {
        return IndentToString(indent) + "enum " + GetFullName()
    }
}
