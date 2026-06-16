package cangjie_compiler::chir

import std.collection.*

public class AST2CHIRResult {
    public let pkg: Package

    public init(pkg: Package) {
        this.pkg = pkg
    }
}

public class AST2CHIRGlobalSpec {
    public let name: String
    public let srcCodeIdentifier: String
    public let rawMangledName: String
    public let ty: Type
    public let initialValue: Option<LiteralValue>
    public let attributes: ArrayList<Attribute> = ArrayList<Attribute>()
    public var useRefStorage: Bool = false

    public init(name: String, ty: Type, srcCodeIdentifier!: String = "", rawMangledName!: String = "",
        initialValue!: Option<LiteralValue> = None) {
        this.name = name
        this.srcCodeIdentifier = srcCodeIdentifier
        this.rawMangledName = rawMangledName
        this.ty = ty
        this.initialValue = initialValue
    }

    public func AddAttribute(attr: Attribute): AST2CHIRGlobalSpec {
        AddAttributeUnique(attributes, attr)
        return this
    }

    public func SetUseRefStorage(value: Bool): AST2CHIRGlobalSpec {
        useRefStorage = value
        return this
    }
}

public class AST2CHIRFunctionSpec {
    public let name: String
    public let srcCodeIdentifier: String
    public let rawMangledName: String
    public let paramTypes: ArrayList<Type> = ArrayList<Type>()
    public let returnType: Type
    public let funcKind: FuncKind
    public let emitBody: Bool
    public let paramNames: ArrayList<String> = ArrayList<String>()
    public let attributes: ArrayList<Attribute> = ArrayList<Attribute>()
    public let genericTypeParams: ArrayList<GenericType> = ArrayList<GenericType>()
    public var ownerTypeName: Option<String> = None
    public var isInstanceMember: Bool = false
    public var genericDeclName: Option<String> = None

    public init(name: String, paramTypes: ArrayList<Type>, returnType: Type, srcCodeIdentifier!: String = "",
        rawMangledName!: String = "", funcKind!: FuncKind = FuncKind.DEFAULT, emitBody!: Bool = true) {
        this.name = name
        this.srcCodeIdentifier = srcCodeIdentifier
        this.rawMangledName = rawMangledName
        for (ty in paramTypes) {
            this.paramTypes.add(ty)
        }
        this.returnType = returnType
        this.funcKind = funcKind
        this.emitBody = emitBody
    }

    public func AddParamName(name: String): AST2CHIRFunctionSpec {
        paramNames.add(name)
        return this
    }

    public func AddAttribute(attr: Attribute): AST2CHIRFunctionSpec {
        AddAttributeUnique(attributes, attr)
        return this
    }

    public func AddGenericTypeParam(param: GenericType): AST2CHIRFunctionSpec {
        genericTypeParams.add(param)
        return this
    }

    public func SetOwnerType(name: String, isInstanceMember!: Bool = true): AST2CHIRFunctionSpec {
        ownerTypeName = Some(name)
        this.isInstanceMember = isInstanceMember
        return this
    }

    public func SetGenericDeclName(name: String): AST2CHIRFunctionSpec {
        genericDeclName = Some(name)
        return this
    }
}

public class AST2CHIRPackageSpec {
    public let name: String
    public let types: ArrayList<AST2CHIRNominalSpec> = ArrayList<AST2CHIRNominalSpec>()
    public let globals: ArrayList<AST2CHIRGlobalSpec> = ArrayList<AST2CHIRGlobalSpec>()
    public let functions: ArrayList<AST2CHIRFunctionSpec> = ArrayList<AST2CHIRFunctionSpec>()

    public init(name: String) {
        this.name = name
    }

    public func AddType(spec: AST2CHIRNominalSpec): AST2CHIRPackageSpec {
        types.add(spec)
        return this
    }

    public func AddGlobal(spec: AST2CHIRGlobalSpec): AST2CHIRPackageSpec {
        globals.add(spec)
        return this
    }

    public func AddFunction(spec: AST2CHIRFunctionSpec): AST2CHIRPackageSpec {
        functions.add(spec)
        return this
    }
}

public class AST2CHIR {
    private let builder: CHIRBuilder

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func CreateEmptyPackage(name: String): AST2CHIRResult {
        return AST2CHIRResult(builder.CreatePackage(name))
    }

    public func LowerPackage(spec: AST2CHIRPackageSpec): AST2CHIRResult {
        return AST2CHIRDeclTranslator(builder).LowerPackage(spec)
    }
}

public func ToCHIR(packageName: String, builder: CHIRBuilder): Package {
    return AST2CHIR(builder).CreateEmptyPackage(packageName).pkg
}

public func ToCHIR(spec: AST2CHIRPackageSpec, builder: CHIRBuilder): Package {
    return AST2CHIR(builder).LowerPackage(spec).pkg
}
