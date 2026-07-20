package cjcj::chir

public class StructDef <: CustomTypeDef {
    private var structType: Option<StructType> = None
    private var isC: Bool = false
    private var alignment: Option<Int64> = None
    private var isPacked: Bool = false

    public init(packageName: String, identifier: String) {
        super(packageName, identifier, identifier, CustomDefKind.TYPE_STRUCT)
    }

    public init(packageName: String, identifier: String, srcCodeIdentifier: String) {
        super(packageName, identifier, srcCodeIdentifier, CustomDefKind.TYPE_STRUCT)
    }

    public override func GetType(): Option<Type> {
        if (let Some(ty) <- structType) {
            return ty
        }
        return None
    }

    public override func SetType(ty: CustomType): Unit {
        if (let Some(structTy) <- (ty as StructType)) {
            structType = structTy
            return
        }
        throw IllegalArgumentException("StructDef requires StructType")
    }

    public func IsCStruct(): Bool {
        return isC
    }

    public func SetCStruct(value: Bool): Unit {
        isC = value
    }

    public func GetAlignment(): Option<Int64> { return alignment }

    public func SetAlignment(value: Option<Int64>): Unit { alignment = value }

    public func IsPacked(): Bool { return isPacked }

    public func SetPacked(value: Bool): Unit { isPacked = value }

}
