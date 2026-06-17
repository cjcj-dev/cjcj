package cangjie_compiler::chir

public class ExtendDef <: CustomTypeDef {
    public var extendedType: Option<Type> = None

    public init(packageName: String, identifier: String) {
        super(packageName, identifier, identifier, CustomDefKind.TYPE_EXTEND)
    }

    public init(packageName: String, identifier: String, extendedType: Type) {
        super(packageName, identifier, identifier, CustomDefKind.TYPE_EXTEND)
        this.extendedType = extendedType
    }

    public init(packageName: String, identifier: String, srcCodeIdentifier: String, extendedType: Type) {
        super(packageName, identifier, srcCodeIdentifier, CustomDefKind.TYPE_EXTEND)
        this.extendedType = extendedType
    }

    public func GetExtendedType(): Option<Type> {
        return extendedType
    }

    public func SetExtendedType(ty: Type): Unit {
        extendedType = ty
    }

    public override func ToString(indent: Int64): String {
        let target = if (let Some(ty) <- extendedType) { ty.ToString() } else { "<unknown>" }
        return IndentToString(indent) + "extend " + target
    }
}
