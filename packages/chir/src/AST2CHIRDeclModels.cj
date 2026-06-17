package cangjie_compiler::chir

import std.collection.*

public enum AST2CHIRNominalKind {
    | CLASS
    | INTERFACE
    | STRUCT
    | ENUM
    | EXTEND
}

public enum AST2CHIRNominalMemberKind {
    | VAR
    | METHOD
    | PROPERTY
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

public func AST2CHIRNominalMemberKindIndex(kind: AST2CHIRNominalMemberKind): Int64 {
    return match (kind) {
        case AST2CHIRNominalMemberKind.VAR => 0
        case AST2CHIRNominalMemberKind.METHOD => 1
        case AST2CHIRNominalMemberKind.PROPERTY => 2
    }
}

extend AST2CHIRNominalMemberKind <: Equatable<AST2CHIRNominalMemberKind> {
    public operator func ==(right: AST2CHIRNominalMemberKind): Bool {
        return AST2CHIRNominalMemberKindIndex(this) == AST2CHIRNominalMemberKindIndex(right)
    }

    public operator func !=(right: AST2CHIRNominalMemberKind): Bool {
        return !(this == right)
    }
}

public class AST2CHIRMemberVarSpec {
    public let name: String
    public let ty: Type
    public var rawMangledName: String
    public var isStatic: Bool
    public var isReadOnly: Bool
    public var sourceFileKey: String = ""
    public var initializerFunc: Option<AST2CHIRFunctionSpec> = None
    public var isSpecificDecl: Bool = false
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

    public func SetSourceFileKey(key: String): AST2CHIRMemberVarSpec {
        sourceFileKey = key
        return this
    }

    public func SetInitializerFunc(spec: AST2CHIRFunctionSpec): AST2CHIRMemberVarSpec {
        initializerFunc = Some(spec)
        return this
    }

    public func SetSpecificDecl(value: Bool): AST2CHIRMemberVarSpec {
        isSpecificDecl = value
        return this
    }
}

public class AST2CHIREnumCtorSpec {
    public let name: String
    public let mangledName: String
    public let payloadTypes: ArrayList<Type> = ArrayList<Type>()

    public init(name: String) {
        this(name, mangledName: "", payloadTypes: ArrayList<Type>())
    }

    public init(name: String, payloadTypes: ArrayList<Type>) {
        this(name, mangledName: "", payloadTypes: payloadTypes)
    }

    public init(name: String, mangledName!: String = "", payloadTypes!: ArrayList<Type> = ArrayList<Type>()) {
        this.name = name
        this.mangledName = mangledName
        for (payloadType in payloadTypes) {
            this.payloadTypes.add(payloadType)
        }
    }

    public func AddPayload(ty: Type): AST2CHIREnumCtorSpec {
        payloadTypes.add(ty)
        return this
    }
}

public class AST2CHIRPropertySpec {
    public let getters: ArrayList<AST2CHIRFunctionSpec> = ArrayList<AST2CHIRFunctionSpec>()
    public let setters: ArrayList<AST2CHIRFunctionSpec> = ArrayList<AST2CHIRFunctionSpec>()
    public var sourceFileKey: String = ""
    public var isCommonMatchedWithSpecific: Bool = false
    public var propertyLocation: Option<DebugLocation> = None

    public init() {}

    public func AddGetter(spec: AST2CHIRFunctionSpec): AST2CHIRPropertySpec {
        getters.add(spec)
        return this
    }

    public func AddSetter(spec: AST2CHIRFunctionSpec): AST2CHIRPropertySpec {
        setters.add(spec)
        return this
    }

    public func SetSourceFileKey(key: String): AST2CHIRPropertySpec {
        sourceFileKey = key
        return this
    }

    public func SetCommonMatchedWithSpecific(value: Bool): AST2CHIRPropertySpec {
        isCommonMatchedWithSpecific = value
        return this
    }

    public func SetPropertyLocation(loc: DebugLocation): AST2CHIRPropertySpec {
        propertyLocation = Some(loc)
        return this
    }
}

public class AST2CHIRNominalMemberSpec {
    public let kind: AST2CHIRNominalMemberKind
    public let varSpec: Option<AST2CHIRMemberVarSpec>
    public let methodSpec: Option<AST2CHIRFunctionSpec>
    public let propertySpec: Option<AST2CHIRPropertySpec>

    public init(spec: AST2CHIRMemberVarSpec) {
        kind = AST2CHIRNominalMemberKind.VAR
        varSpec = Some(spec)
        methodSpec = None
        propertySpec = None
    }

    public init(spec: AST2CHIRFunctionSpec) {
        kind = AST2CHIRNominalMemberKind.METHOD
        varSpec = None
        methodSpec = Some(spec)
        propertySpec = None
    }

    public init(spec: AST2CHIRPropertySpec) {
        kind = AST2CHIRNominalMemberKind.PROPERTY
        varSpec = None
        methodSpec = None
        propertySpec = Some(spec)
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
    public let properties: ArrayList<AST2CHIRPropertySpec> = ArrayList<AST2CHIRPropertySpec>()
    public let memberDecls: ArrayList<AST2CHIRNominalMemberSpec> = ArrayList<AST2CHIRNominalMemberSpec>()
    public let enumCtors: ArrayList<AST2CHIREnumCtorSpec> = ArrayList<AST2CHIREnumCtorSpec>()
    public let implementedInterfaces: ArrayList<String> = ArrayList<String>()
    public var superClassName: Option<String> = None
    public var extendedType: Option<Type> = None
    public var sourceFileKey: String = ""
    public var isSpecificDecl: Bool = false
    public var debugLocation: Option<DebugLocation> = None

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

    public func SetSourceFileKey(key: String): AST2CHIRNominalSpec {
        sourceFileKey = key
        return this
    }

    public func SetSpecificDecl(value: Bool): AST2CHIRNominalSpec {
        isSpecificDecl = value
        return this
    }

    public func SetDebugLocation(loc: DebugLocation): AST2CHIRNominalSpec {
        debugLocation = Some(loc)
        return this
    }

    public func AddInstanceVar(spec: AST2CHIRMemberVarSpec): AST2CHIRNominalSpec {
        instanceVars.add(spec)
        memberDecls.add(AST2CHIRNominalMemberSpec(spec))
        return this
    }

    public func AddMethod(spec: AST2CHIRFunctionSpec): AST2CHIRNominalSpec {
        spec.SetOwnerType(name, isInstanceMember: !spec.attributes.contains(Attribute.STATIC))
        methods.add(spec)
        memberDecls.add(AST2CHIRNominalMemberSpec(spec))
        return this
    }

    public func AddProperty(spec: AST2CHIRPropertySpec): AST2CHIRNominalSpec {
        properties.add(spec)
        memberDecls.add(AST2CHIRNominalMemberSpec(spec))
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
