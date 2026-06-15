package cangjie_compiler::mangle

import std.collection.*
import std.sort.*

public let MANGLE_VIRTUAL_PREFIX: String = "_CV"
public let MANGLE_MUTABLE_PREFIX: String = "_CM"
public let MANGLE_CHIR_FUNC_PREFIX: String = "_CC"
public let MANGLE_CHIR_EXTEND_PREFIX: String = "$X"
public let MANGLE_INSTANTIATE_PREFIX: String = "_CI"
public let MANGLE_CHIR_LAMBDA_PREFIX: String = "_CL"
public let MANGLE_OPERATOR_PREFIX: String = "_CO"
public let MANGLE_ANNOTATION_LAMBDA_PREFIX: String = "_CA"
public let MANGLE_CLOSURE_GENERIC_PREFIX: String = "$Cg"
public let MANGLE_CLOSURE_INSTANTIATE_PREFIX: String = "$Ci"
public let MANGLE_CLOSURE_FUNC_PREFIX: String = "$Cf"
public let MANGLE_CLOSURE_LAMBDA_PREFIX: String = "$Cl"
public let MANGLE_CLOSURE_WRAPPER_PREFIX: String = "$Cw"
public let MANGLE_ABSTRACT_INST_PREFIX: String = "$i"
public let MANGLE_ABSTRACT_GENERIC_PREFIX: String = "$vg"
public let MANGLE_ABSTRACT_INSTANTIATED_PREFIX: String = "$vi"
public let MANGLE_CHIR_GENERIC_SUFFIX: String = "$g"

public enum MangleOverflowStrategy {
    | NA
    | CHECKED
    | WRAPPING
    | THROWING
    | SATURATING
}

public class CHIRFunction {
    public var identifier: String = ""
    public var identifierWithoutPrefix: String = ""

    public init() {}

    public init(identifierWithoutPrefix: String, identifier!: String = "") {
        this.identifierWithoutPrefix = identifierWithoutPrefix
        this.identifier = if (identifier.isEmpty()) { identifierWithoutPrefix } else { identifier }
    }
}

public class CHIRCustomTypeDef {
    public var identifier: String = ""
    public var identifierWithoutPrefix: String = ""
    public var packageName: String = ""
    public var typeInfo: Option<CHIRType> = None
    public var isExtend: Bool = false
    public let genericTypeParams: ArrayList<CHIRType> = ArrayList<CHIRType>()
    public let implementedInterfaceTys: ArrayList<CHIRType> = ArrayList<CHIRType>()

    public init() {}
}

private func ReplaceManglePrefixWith(mangledName: String, newPrefix: String): String {
    if (StartsWith(mangledName, MANGLE_CANGJIE_PREFIX)) {
        return newPrefix + mangledName[MANGLE_PREFIX_LEN..]
    }
    return mangledName
}

private func sortedMangledTypes(types: ArrayList<CHIRType>, genericsTypeStack: ArrayList<String>): ArrayList<String> {
    let values = ArrayList<String>()
    for (ty in types) {
        values.add(MangleCHIRType(ty, genericsTypeStack))
    }
    sort(values, by: { left: String, right: String =>
        if (left < right) {
            Ordering.LT
        } else if (left > right) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }, stable: true)
    return values
}

public func GenerateVirtualFuncMangleName(rawFunc: CHIRFunction, customTypeDef: CHIRCustomTypeDef,
    parentTy: CHIRType, isVirtual: Bool): String {
    let prefix = if (isVirtual) { MANGLE_VIRTUAL_PREFIX } else { MANGLE_MUTABLE_PREFIX }
    var out = ReplaceManglePrefixWith(rawFunc.identifierWithoutPrefix, prefix)
    let customTyGenericTypeStack = ArrayList<String>()
    for (genericType in customTypeDef.genericTypeParams) {
        customTyGenericTypeStack.add(genericType.srcCodeIdentifier)
    }
    if (customTypeDef.isExtend) {
        if (let Some(typeInfo) <- customTypeDef.typeInfo) {
            out += MANGLE_CHIR_EXTEND_PREFIX + MangleCHIRType(typeInfo, customTyGenericTypeStack)
        }
        for (implementType in sortedMangledTypes(customTypeDef.implementedInterfaceTys, customTyGenericTypeStack)) {
            out += implementType
        }
        out += "${customTypeDef.packageName.size}" + customTypeDef.packageName
    } else {
        out += MANGLE_DOLLAR_PREFIX + ReplaceManglePrefixWith(customTypeDef.identifierWithoutPrefix, "")
    }
    out += MANGLE_DOLLAR_PREFIX + MangleCHIRType(parentTy, customTyGenericTypeStack)
    return out
}

public func GenerateInstantiateFuncMangleName(baseName: String, instTysInFunc: ArrayList<CHIRType>): String {
    var out = ReplaceManglePrefixWith(baseName, MANGLE_INSTANTIATE_PREFIX) + MANGLE_DOLLAR_PREFIX
    if (instTysInFunc.isEmpty()) {
        out += MANGLE_VOID_TY_SUFFIX
    } else {
        for (paramTy in instTysInFunc) {
            out += MangleCHIRType(paramTy)
        }
    }
    return out
}

public func GenerateLambdaFuncMangleName(baseFunc: CHIRFunction, counter: Int64): String {
    return ReplaceManglePrefixWith(baseFunc.identifierWithoutPrefix, MANGLE_CHIR_LAMBDA_PREFIX) +
        MANGLE_DOLLAR_PREFIX + "${counter}" + MANGLE_WILDCARD_PREFIX
}

public func OverflowStrategyToString(ovf: MangleOverflowStrategy): String {
    return match (ovf) {
        case MangleOverflowStrategy.WRAPPING => "&"
        case MangleOverflowStrategy.THROWING => "~"
        case _ => "%"
    }
}

public func GenerateOverflowOperatorFuncMangleName(name: String, ovf: MangleOverflowStrategy, isBinary: Bool,
    typeInfo: CHIRType): String {
    var out = MANGLE_OPERATOR_PREFIX + OverflowStrategyToString(ovf)
    if (let Some(op) <- OperatorTypeMangle(name)) {
        out += op
    }
    out += MANGLE_FUNC_PARAM_TYPE_PREFIX + MangleCHIRType(typeInfo)
    if (isBinary) {
        out += MangleCHIRType(typeInfo)
    }
    return out
}

public func GenerateAnnotationFuncMangleName(name: String): String {
    return MANGLE_CANGJIE_PREFIX + "AF" + name[MANGLE_PREFIX_LEN + 1..]
}

public func GenerateGenericBaseClassMangleName(paramNum: Int64): String {
    return MANGLE_CLOSURE_GENERIC_PREFIX + "${paramNum}" + MANGLE_WILDCARD_PREFIX
}

public func GenerateInstantiatedBaseClassMangleName(funcType: CHIRType): String {
    return MANGLE_CLOSURE_INSTANTIATE_PREFIX + MangleCHIRType(funcType)
}

public func GenerateGlobalImplClassMangleName(function: CHIRFunction): String {
    return ReplaceManglePrefixWith(function.identifierWithoutPrefix, MANGLE_CLOSURE_FUNC_PREFIX)
}

public func GenerateLambdaImplClassMangleName(function: CHIRFunction, count: Int64): String {
    return ReplaceManglePrefixWith(function.identifier, MANGLE_CLOSURE_LAMBDA_PREFIX) + MANGLE_DOLLAR_PREFIX + "${count}"
}

public func GenerateWrapperClassMangleName(def: CHIRCustomTypeDef): String {
    return MANGLE_CLOSURE_WRAPPER_PREFIX + def.identifierWithoutPrefix
}

public func GenerateGenericAbstractFuncMangleName(def: CHIRCustomTypeDef): String {
    return MANGLE_CHIR_FUNC_PREFIX + def.identifier + MANGLE_ABSTRACT_GENERIC_PREFIX
}

public func GenerateInstantiatedAbstractFuncMangleName(def: CHIRCustomTypeDef): String {
    return MANGLE_CHIR_FUNC_PREFIX + def.identifier + MANGLE_ABSTRACT_INSTANTIATED_PREFIX
}

public func GenerateGenericOverrideFuncMangleName(function: CHIRFunction): String {
    return ReplaceManglePrefixWith(function.identifierWithoutPrefix, MANGLE_CHIR_FUNC_PREFIX) + MANGLE_CHIR_GENERIC_SUFFIX
}

public func GenerateInstOverrideFuncMangleName(function: CHIRFunction): String {
    return ReplaceManglePrefixWith(function.identifierWithoutPrefix, MANGLE_CHIR_FUNC_PREFIX) + MANGLE_ABSTRACT_INST_PREFIX
}

public func GenerateWrapperClassGenericOverrideFuncMangleName(def: CHIRCustomTypeDef): String {
    return MANGLE_CHIR_FUNC_PREFIX + def.identifierWithoutPrefix + MANGLE_CHIR_GENERIC_SUFFIX
}

public func GenerateWrapperClassInstOverrideFuncMangleName(def: CHIRCustomTypeDef): String {
    return MANGLE_CHIR_FUNC_PREFIX + def.identifierWithoutPrefix + MANGLE_ABSTRACT_INST_PREFIX
}
