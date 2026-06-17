package cangjie_compiler::chir

public class StructDef <: CustomTypeDef {
    private var structType: Option<StructType> = None
    private var isC: Bool = false

    public init(packageName: String, identifier: String) {
        super(packageName, identifier, identifier, CustomDefKind.TYPE_STRUCT)
    }

    public init(packageName: String, identifier: String, srcCodeIdentifier: String) {
        super(packageName, identifier, srcCodeIdentifier, CustomDefKind.TYPE_STRUCT)
    }

    public override func GetType(): Option<CustomType> {
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
        return isC || TestAttr(Attribute.C)
    }

    public func SetCStruct(value: Bool): Unit {
        isC = value
        if (value) {
            EnableAttr(Attribute.C)
        } else {
            DisableAttr(Attribute.C)
        }
    }

    public override func ToString(indent: Int64): String {
        return IndentToString(indent) + "struct " + GetFullName()
    }
}
