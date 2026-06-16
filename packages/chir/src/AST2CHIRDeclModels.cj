package cangjie_compiler::chir

import std.collection.*

public enum AST2CHIRNominalKind {
    | CLASS
    | INTERFACE
    | STRUCT
    | ENUM
    | EXTEND
}

public func AST2CHIRNominalKindIndex(kind: AST2CHIRNominalKind): Int64 {
    return match (kind) {
        case AST2CHIRNominalKind.CLASS => 0
        case AST2CHIRNominalKind.INTERFACE => 1
        case AST2CHIRNominalKind.STRUCT => 2
        case AST2CHIRNominalKind.ENUM => 3
        case AST2CHIRNominalKind.EXTEND => 4
    }
}

extend AST2CHIRNominalKind <: Equatable<AST2CHIRNominalKind> {
    public operator func ==(right: AST2CHIRNominalKind): Bool {
        return AST2CHIRNominalKindIndex(this) == AST2CHIRNominalKindIndex(right)
    }

    public operator func !=(right: AST2CHIRNominalKind): Bool {
        return !(this == right)
    }
}

public class AST2CHIRMemberVarSpec {
    public let name: String
    public let ty: Type
    public var rawMangledName: String
    public var isStatic: Bool
    public var isReadOnly: Bool
    public let attributes: ArrayList<Attribute> = ArrayList<Attribute>()

    public init(name: String, ty: Type, rawMangledName!: String = "", isStatic!: Bool = false,
        isReadOnly!: Bool = false) {
        this.name = name
        this.ty = ty
        this.rawMangledName = rawMangledName
        this.isStatic = isStatic
        this.isReadOnly = isReadOnly
    }

    public func AddAttribute(attr: Attribute): AST2CHIRMemberVarSpec {
        AddAttributeUnique(attributes, attr)
        return this
    }
}

public class AST2CHIREnumCtorSpec {
    public let name: String
    public let payloadTypes: ArrayList<Type> = ArrayList<Type>()

    public init(name: String) {
        this.name = name
    }

    public init(name: String, payloadTypes: ArrayList<Type>) {
        this.name = name
        for (payloadType in payloadTypes) {
            this.payloadTypes.add(payloadType)
        }
    }

    public func AddPayload(ty: Type): AST2CHIREnumCtorSpec {
        payloadTypes.add(ty)
        return this
    }
}

public class AST2CHIRNominalSpec {
    public let kind: AST2CHIRNominalKind
    public let name: String
    public let srcCodeIdentifier: String
    public let rawMangledName: String
    public let packageName: String
    public let genericTypeParams: ArrayList<GenericType> = ArrayList<GenericType>()
    public let attributes: ArrayList<Attribute> = ArrayList<Attribute>()
    public let instanceVars: ArrayList<AST2CHIRMemberVarSpec> = ArrayList<AST2CHIRMemberVarSpec>()
    public let methods: ArrayList<AST2CHIRFunctionSpec> = ArrayList<AST2CHIRFunctionSpec>()
    public let enumCtors: ArrayList<AST2CHIREnumCtorSpec> = ArrayList<AST2CHIREnumCtorSpec>()
    public let implementedInterfaces: ArrayList<String> = ArrayList<String>()
    public var superClassName: Option<String> = None
    public var extendedType: Option<Type> = None

    public init(kind: AST2CHIRNominalKind, name: String, packageName!: String = "", srcCodeIdentifier!: String = "",
        rawMangledName!: String = "") {
        this.kind = kind
        this.name = name
        this.packageName = packageName
        this.srcCodeIdentifier = srcCodeIdentifier
        this.rawMangledName = rawMangledName
    }

    public func AddAttribute(attr: Attribute): AST2CHIRNominalSpec {
        AddAttributeUnique(attributes, attr)
        return this
    }

    public func AddGenericTypeParam(param: GenericType): AST2CHIRNominalSpec {
        genericTypeParams.add(param)
        return this
    }

    public func AddInstanceVar(spec: AST2CHIRMemberVarSpec): AST2CHIRNominalSpec {
        instanceVars.add(spec)
        return this
    }

    public func AddMethod(spec: AST2CHIRFunctionSpec): AST2CHIRNominalSpec {
        spec.SetOwnerType(name, isInstanceMember: !spec.attributes.contains(Attribute.STATIC))
        methods.add(spec)
        return this
    }

    public func AddEnumCtor(spec: AST2CHIREnumCtorSpec): AST2CHIRNominalSpec {
        enumCtors.add(spec)
        return this
    }

    public func SetSuperClass(name: String): AST2CHIRNominalSpec {
        superClassName = Some(name)
        return this
    }

    public func AddImplementedInterface(name: String): AST2CHIRNominalSpec {
        if (!implementedInterfaces.contains(name)) {
            implementedInterfaces.add(name)
        }
        return this
    }

    public func SetExtendedType(ty: Type): AST2CHIRNominalSpec {
        extendedType = Some(ty)
        return this
    }
}

public func AddAttributeUnique(attrs: ArrayList<Attribute>, attr: Attribute): Unit {
    if (!attrs.contains(attr)) {
        attrs.add(attr)
    }
}

public func BuildAttributeInfo(attrs: ArrayList<Attribute>): AttributeInfo {
    let info = AttributeInfo()
    for (attr in attrs) {
        info.Enable(attr)
    }
    return info
}
