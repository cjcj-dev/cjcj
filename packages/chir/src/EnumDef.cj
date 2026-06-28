package cangjie_compiler::chir

import std.collection.*

public class EnumCtorInfo {
    public let name: String
    public let mangledName: String
    public let funcType: Option<FuncType>
    public let annoInfo: AnnoInfo
    public let payloadTypes: ArrayList<Type> = ArrayList<Type>()

    public init(name: String, payloadTypes: ArrayList<Type>, mangledName!: String = "",
        funcType!: Option<FuncType> = None, annoInfo!: AnnoInfo = AnnoInfo()) {
        this.name = name
        this.mangledName = mangledName
        this.funcType = funcType
        this.annoInfo = annoInfo
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

    public override func GetType(): Option<Type> {
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

    public func GetCtor(index: Int64): EnumCtorInfo {
        return ctors[index]
    }

    public func GetCtors(): ArrayList<EnumCtorInfo> {
        let out = ArrayList<EnumCtorInfo>()
        for (ctor in ctors) {
            out.add(ctor)
        }
        return out
    }

    public func SetCtors(items: ArrayList<EnumCtorInfo>): Unit {
        ctors.clear()
        for (item in items) {
            ctors.add(item)
        }
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
            let funcType = ctor.funcType ?? throw IllegalStateException("EnumCtorInfo requires FuncType")
            if (funcType.GetParamTypes().size != 0) {
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
