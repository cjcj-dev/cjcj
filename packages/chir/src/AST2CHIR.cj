package cangjie_compiler::chir

import std.collection.*

let AST2CHIR_LITERAL_NONE: Int64 = 0
let AST2CHIR_LITERAL_BOOL: Int64 = 1
let AST2CHIR_LITERAL_INT: Int64 = 2
let AST2CHIR_LITERAL_FLOAT: Int64 = 3
let AST2CHIR_LITERAL_UNIT: Int64 = 4

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
    public let packageName: String
    public let ty: Type
    public let initialValue: Option<LiteralValue>
    public let attributes: ArrayList<Attribute> = ArrayList<Attribute>()
    public let features: ArrayList<String> = ArrayList<String>()
    public var useRefStorage: Bool = false
    public var debugLocation: Option<DebugLocation> = None

    public init(name: String, ty: Type, srcCodeIdentifier!: String = "", rawMangledName!: String = "",
        packageName!: String = "", initialValue!: Option<LiteralValue> = None) {
        this.name = name
        this.srcCodeIdentifier = srcCodeIdentifier
        this.rawMangledName = rawMangledName
        this.packageName = packageName
        this.ty = ty
        this.initialValue = initialValue
    }

    public func AddAttribute(attr: Attribute): AST2CHIRGlobalSpec {
        AddAttributeUnique(attributes, attr)
        return this
    }

    public func AddFeature(name: String): AST2CHIRGlobalSpec {
        AddStringUnique(features, name)
        return this
    }

    public func SetUseRefStorage(value: Bool): AST2CHIRGlobalSpec {
        useRefStorage = value
        return this
    }

    public func SetDebugLocation(loc: DebugLocation): AST2CHIRGlobalSpec {
        debugLocation = Some(loc)
        return this
    }
}

public class AST2CHIRFunctionSpec {
    public let name: String
    public let srcCodeIdentifier: String
    public let rawMangledName: String
    public let packageName: String
    public let paramTypes: ArrayList<Type> = ArrayList<Type>()
    public let returnType: Type
    public let funcKind: FuncKind
    public let emitBody: Bool
    public let paramNames: ArrayList<String> = ArrayList<String>()
    public let attributes: ArrayList<Attribute> = ArrayList<Attribute>()
    public let features: ArrayList<String> = ArrayList<String>()
    public let genericTypeParams: ArrayList<GenericType> = ArrayList<GenericType>()
    public let defaultParamFunctions: ArrayList<AST2CHIRFunctionSpec> = ArrayList<AST2CHIRFunctionSpec>()
    public let genericInstantiations: ArrayList<AST2CHIRFunctionSpec> = ArrayList<AST2CHIRFunctionSpec>()
    public var ownerTypeName: Option<String> = None
    public var isInstanceMember: Bool = false
    public var genericDeclName: Option<String> = None
    public var sourceFileKey: String = ""
    public var isCommonMatchedWithSpecific: Bool = false
    public var debugLocation: Option<DebugLocation> = None
    public var propertyLocation: Option<DebugLocation> = None
    public var hasVariableLenArg: Bool = false
    public var isCFunc: Bool = false
    public var hasLiteralReturn: Bool = false
    public var literalReturnKind: Int64 = AST2CHIR_LITERAL_NONE
    public var literalReturnBoolValue: Bool = false
    public var literalReturnIntValue: Int64 = 0
    public var literalReturnFloatValue: Float64 = 0.0
    // Literal strings to print when the function body runs, in source order. printNewlines is a
    // parallel list: true => println (puts, trailing newline), false => print (fputs, no newline).
    // printIsInt is a parallel list: true => integer print (printStrings holds the decimal text,
    // lowered via printf("%ld[\n]")); false => string print.
    public let printStrings: ArrayList<String> = ArrayList<String>()
    public let printNewlines: ArrayList<Bool> = ArrayList<Bool>()
    public let printIsInt: ArrayList<Bool> = ArrayList<Bool>()

    public init(name: String, paramTypes: ArrayList<Type>, returnType: Type, srcCodeIdentifier!: String = "",
        rawMangledName!: String = "", packageName!: String = "", funcKind!: FuncKind = FuncKind.DEFAULT,
        emitBody!: Bool = true) {
        this.name = name
        this.srcCodeIdentifier = srcCodeIdentifier
        this.rawMangledName = rawMangledName
        this.packageName = packageName
        for (ty in paramTypes) {
            this.paramTypes.add(ty)
        }
        this.returnType = returnType
        this.funcKind = funcKind
        this.emitBody = emitBody
    }

    public func AddPrintString(value: String, newline!: Bool = true, isInt!: Bool = false): AST2CHIRFunctionSpec {
        printStrings.add(value)
        printNewlines.add(newline)
        printIsInt.add(isInt)
        return this
    }

    public func AddParamName(name: String): AST2CHIRFunctionSpec {
        paramNames.add(name)
        return this
    }

    public func AddAttribute(attr: Attribute): AST2CHIRFunctionSpec {
        AddAttributeUnique(attributes, attr)
        return this
    }

    public func AddFeature(name: String): AST2CHIRFunctionSpec {
        AddStringUnique(features, name)
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

    public func AddDefaultParamFunction(spec: AST2CHIRFunctionSpec): AST2CHIRFunctionSpec {
        defaultParamFunctions.add(spec)
        return this
    }

    public func AddGenericInstantiation(spec: AST2CHIRFunctionSpec): AST2CHIRFunctionSpec {
        genericInstantiations.add(spec)
        return this
    }

    public func SetSourceFileKey(key: String): AST2CHIRFunctionSpec {
        sourceFileKey = key
        return this
    }

    public func SetCommonMatchedWithSpecific(value: Bool): AST2CHIRFunctionSpec {
        isCommonMatchedWithSpecific = value
        return this
    }

    public func SetDebugLocation(loc: DebugLocation): AST2CHIRFunctionSpec {
        debugLocation = Some(loc)
        return this
    }

    public func SetPropertyLocation(loc: DebugLocation): AST2CHIRFunctionSpec {
        propertyLocation = Some(loc)
        return this
    }

    public func SetHasVariableLenArg(value: Bool): AST2CHIRFunctionSpec {
        hasVariableLenArg = value
        if (value) {
            isCFunc = true
        }
        return this
    }

    public func SetCFunc(value: Bool): AST2CHIRFunctionSpec {
        isCFunc = value
        return this
    }

    public func SetBoolLiteralReturn(value: Bool): AST2CHIRFunctionSpec {
        hasLiteralReturn = true
        literalReturnKind = AST2CHIR_LITERAL_BOOL
        literalReturnBoolValue = value
        return this
    }

    public func SetIntLiteralReturn(value: Int64): AST2CHIRFunctionSpec {
        hasLiteralReturn = true
        literalReturnKind = AST2CHIR_LITERAL_INT
        literalReturnIntValue = value
        return this
    }

    public func SetFloatLiteralReturn(value: Float64): AST2CHIRFunctionSpec {
        hasLiteralReturn = true
        literalReturnKind = AST2CHIR_LITERAL_FLOAT
        literalReturnFloatValue = value
        return this
    }

    public func SetUnitLiteralReturn(): AST2CHIRFunctionSpec {
        hasLiteralReturn = true
        literalReturnKind = AST2CHIR_LITERAL_UNIT
        return this
    }
}

public class AST2CHIRPackageSpec {
    public let name: String
    public let types: ArrayList<AST2CHIRNominalSpec> = ArrayList<AST2CHIRNominalSpec>()
    public let globals: ArrayList<AST2CHIRGlobalSpec> = ArrayList<AST2CHIRGlobalSpec>()
    public let functions: ArrayList<AST2CHIRFunctionSpec> = ArrayList<AST2CHIRFunctionSpec>()
    public let sourceFileIds: ArrayList<UInt32> = ArrayList<UInt32>()
    public let sourceFileNames: ArrayList<String> = ArrayList<String>()
    public var accessLevel: AccessLevel = AccessLevel.INVALID
    public var mergingSpecific: Bool = false
    public var packageInitFunction: Option<AST2CHIRFunctionSpec> = None
    public var packageLiteralInitFunction: Option<AST2CHIRFunctionSpec> = None

    public init(name: String) {
        this.name = name
    }

    public func SetMergingSpecific(value: Bool): AST2CHIRPackageSpec {
        mergingSpecific = value
        return this
    }

    public func SetAccessLevel(level: AccessLevel): AST2CHIRPackageSpec {
        accessLevel = level
        return this
    }

    public func RegisterSourceFile(fileId: UInt32, fileName: String): AST2CHIRPackageSpec {
        sourceFileIds.add(fileId)
        sourceFileNames.add(fileName)
        return this
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

    public func SetPackageInitFunction(spec: AST2CHIRFunctionSpec): AST2CHIRPackageSpec {
        packageInitFunction = Some(spec)
        return this
    }

    public func SetPackageLiteralInitFunction(spec: AST2CHIRFunctionSpec): AST2CHIRPackageSpec {
        packageLiteralInitFunction = Some(spec)
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
