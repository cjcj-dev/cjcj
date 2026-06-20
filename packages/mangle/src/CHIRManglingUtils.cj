package cangjie_compiler::mangle

import std.collection.*
import std.sort.*
import cangjie_compiler::ast.OverflowStrategy
import cangjie_compiler::chir.*

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

private func ReplaceManglePrefixWith(mangledName: String, newPrefix: String): String {
    if (StartsWith(mangledName, MANGLE_CANGJIE_PREFIX)) {
        return newPrefix + mangledName[MANGLE_PREFIX_LEN..]
    }
    throw IllegalArgumentException("Mangle name has no _C prefix to be replaced: " + mangledName)
}

private func FunctionIdentifierForPrefix(function: Function): String {
    let identifier = function.GetIdentifier()
    if (StartsWith(identifier, MANGLE_CANGJIE_PREFIX)) {
        return identifier
    }
    let withoutPrefix = function.GetIdentifierWithoutPrefix()
    if (StartsWith(withoutPrefix, MANGLE_CANGJIE_PREFIX)) {
        return withoutPrefix
    }
    return identifier
}

private func CustomTypeDefIdentifierWithoutPrefix(def: CustomTypeDef): String {
    let identifier = def.GetIdentifier()
    if (identifier.isEmpty()) {
        throw IllegalArgumentException("Custom type identifier has no prefix to strip.")
    }
    if (StartsWith(identifier, MANGLE_AT_PREFIX)) {
        return identifier[MANGLE_CHAR_LEN..]
    }
    return identifier
}

private func sortedMangledClassTypes(types: ArrayList<ClassType>, genericsTypeStack: ArrayList<String>): ArrayList<String> {
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

public func GenerateVirtualFuncMangleName(rawFunc: Function, customTypeDef: CustomTypeDef,
    parentTy: ClassType, isVirtual: Bool): String {
    let prefix = if (isVirtual) { MANGLE_VIRTUAL_PREFIX } else { MANGLE_MUTABLE_PREFIX }
    var out = ReplaceManglePrefixWith(FunctionIdentifierForPrefix(rawFunc), prefix)
    let customTyGenericTypeStack = ArrayList<String>()
    for (genericType in customTypeDef.genericTypeParams) {
        customTyGenericTypeStack.add(genericType.GetSrcCodeIdentifier())
    }
    if (let Some(extendDef) <- (customTypeDef as ExtendDef)) {
        if (let Some(extendedType) <- extendDef.extendedType) {
            out += MANGLE_CHIR_EXTEND_PREFIX + MangleCHIRType(extendedType, customTyGenericTypeStack)
        }
        for (implementType in sortedMangledClassTypes(customTypeDef.GetImplementedInterfaceTys(),
            customTyGenericTypeStack)) {
            out += implementType
        }
        out += "${customTypeDef.GetPackageName().size}" + customTypeDef.GetPackageName()
    } else {
        out += MANGLE_DOLLAR_PREFIX + ReplaceManglePrefixWith(CustomTypeDefIdentifierWithoutPrefix(customTypeDef), "")
    }
    out += MANGLE_DOLLAR_PREFIX + MangleCHIRType(parentTy, customTyGenericTypeStack)
    return out
}

public func GenerateInstantiateFuncMangleName(baseName: String, instTysInFunc: ArrayList<Type>): String {
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

public func GenerateLambdaFuncMangleName(baseFunc: Function, counter: Int64): String {
    return ReplaceManglePrefixWith(baseFunc.GetIdentifierWithoutPrefix(), MANGLE_CHIR_LAMBDA_PREFIX) +
        MANGLE_DOLLAR_PREFIX + "${counter}" + MANGLE_WILDCARD_PREFIX
}

public func OverflowStrategyToString(ovf: OverflowStrategy): String {
    return match (ovf) {
        case OverflowStrategy.WRAPPING => "&"
        case OverflowStrategy.THROWING => "~"
        case _ => "%"
    }
}

private func OverflowOperatorMangleCode(name: String): String {
    if (let Some(op) <- OperatorTypeMangle(name)) {
        return op
    }
    throw IllegalArgumentException("Unsupported name for overflow operator mangling: " + name)
}

public func GenerateOverflowOperatorFuncMangleName(name: String, ovf: OverflowStrategy, isBinary: Bool,
    typeInfo: BuiltinType): String {
    var out = MANGLE_OPERATOR_PREFIX + OverflowStrategyToString(ovf) + OverflowOperatorMangleCode(name)
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

public func GenerateInstantiatedBaseClassMangleName(funcType: FuncType): String {
    return MANGLE_CLOSURE_INSTANTIATE_PREFIX + MangleCHIRType(funcType)
}

public func GenerateGlobalImplClassMangleName(function: Function): String {
    return ReplaceManglePrefixWith(FunctionIdentifierForPrefix(function), MANGLE_CLOSURE_FUNC_PREFIX)
}

public func GenerateLambdaImplClassMangleName(function: Lambda, count: Int64): String {
    return ReplaceManglePrefixWith(function.GetIdentifier(), MANGLE_CLOSURE_LAMBDA_PREFIX) +
        MANGLE_DOLLAR_PREFIX + "${count}"
}

public func GenerateWrapperClassMangleName(def: ClassDef): String {
    return MANGLE_CLOSURE_WRAPPER_PREFIX + CustomTypeDefIdentifierWithoutPrefix(def)
}

public func GenerateGenericAbstractFuncMangleName(def: ClassDef): String {
    return MANGLE_CHIR_FUNC_PREFIX + def.GetIdentifier() + MANGLE_ABSTRACT_GENERIC_PREFIX
}

public func GenerateInstantiatedAbstractFuncMangleName(def: ClassDef): String {
    return MANGLE_CHIR_FUNC_PREFIX + def.GetIdentifier() + MANGLE_ABSTRACT_INSTANTIATED_PREFIX
}

public func GenerateGenericOverrideFuncMangleName(function: Function): String {
    return ReplaceManglePrefixWith(FunctionIdentifierForPrefix(function), MANGLE_CHIR_FUNC_PREFIX) +
        MANGLE_CHIR_GENERIC_SUFFIX
}

public func GenerateInstOverrideFuncMangleName(function: Function): String {
    return ReplaceManglePrefixWith(FunctionIdentifierForPrefix(function), MANGLE_CHIR_FUNC_PREFIX) +
        MANGLE_ABSTRACT_INST_PREFIX
}

public func GenerateWrapperClassGenericOverrideFuncMangleName(def: ClassDef): String {
    return MANGLE_CHIR_FUNC_PREFIX + CustomTypeDefIdentifierWithoutPrefix(def) + MANGLE_CHIR_GENERIC_SUFFIX
}

public func GenerateWrapperClassInstOverrideFuncMangleName(def: ClassDef): String {
    return MANGLE_CHIR_FUNC_PREFIX + CustomTypeDefIdentifierWithoutPrefix(def) + MANGLE_ABSTRACT_INST_PREFIX
}
