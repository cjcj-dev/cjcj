package cangjie_compiler::mangle

import std.collection.*
import cangjie_compiler::ast.OverflowStrategy
import cangjie_compiler::chir.BuiltinType
import cangjie_compiler::chir.ClassDef
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.CustomTypeDef
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.Lambda
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.GenerateVirtualFuncMangleName as ChirGenerateVirtualFuncMangleName
import cangjie_compiler::chir.GenerateInstantiateFuncMangleName as ChirGenerateInstantiateFuncMangleName
import cangjie_compiler::chir.GenerateLambdaFuncMangleName as ChirGenerateLambdaFuncMangleName
import cangjie_compiler::chir.OverflowStrategyToString as ChirOverflowStrategyToString
import cangjie_compiler::chir.GenerateOverflowOperatorFuncMangleName as ChirGenerateOverflowOperatorFuncMangleName
import cangjie_compiler::chir.GenerateAnnotationFuncMangleName as ChirGenerateAnnotationFuncMangleName
import cangjie_compiler::chir.GenerateGenericBaseClassMangleName as ChirGenerateGenericBaseClassMangleName
import cangjie_compiler::chir.GenerateInstantiatedBaseClassMangleName as ChirGenerateInstantiatedBaseClassMangleName
import cangjie_compiler::chir.GenerateGlobalImplClassMangleName as ChirGenerateGlobalImplClassMangleName
import cangjie_compiler::chir.GenerateLambdaImplClassMangleName as ChirGenerateLambdaImplClassMangleName
import cangjie_compiler::chir.GenerateWrapperClassMangleName as ChirGenerateWrapperClassMangleName
import cangjie_compiler::chir.GenerateGenericAbstractFuncMangleName as ChirGenerateGenericAbstractFuncMangleName
import cangjie_compiler::chir.GenerateInstantiatedAbstractFuncMangleName as ChirGenerateInstantiatedAbstractFuncMangleName
import cangjie_compiler::chir.GenerateGenericOverrideFuncMangleName as ChirGenerateGenericOverrideFuncMangleName
import cangjie_compiler::chir.GenerateInstOverrideFuncMangleName as ChirGenerateInstOverrideFuncMangleName
import cangjie_compiler::chir.GenerateWrapperClassGenericOverrideFuncMangleName as ChirGenerateWrapperClassGenericOverrideFuncMangleName
import cangjie_compiler::chir.GenerateWrapperClassInstOverrideFuncMangleName as ChirGenerateWrapperClassInstOverrideFuncMangleName

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

public func GenerateVirtualFuncMangleName(rawFunc: Function, customTypeDef: CustomTypeDef,
    parentTy: ClassType, isVirtual: Bool): String {
    return ChirGenerateVirtualFuncMangleName(rawFunc, customTypeDef, parentTy, isVirtual)
}

public func GenerateInstantiateFuncMangleName(baseName: String, instTysInFunc: ArrayList<Type>): String {
    return ChirGenerateInstantiateFuncMangleName(baseName, instTysInFunc)
}

public func GenerateLambdaFuncMangleName(baseFunc: Function, counter: Int64): String {
    return ChirGenerateLambdaFuncMangleName(baseFunc, counter)
}

public func OverflowStrategyToString(ovf: OverflowStrategy): String {
    return ChirOverflowStrategyToString(ovf)
}

public func GenerateOverflowOperatorFuncMangleName(name: String, ovf: OverflowStrategy, isBinary: Bool,
    typeInfo: BuiltinType): String {
    return ChirGenerateOverflowOperatorFuncMangleName(name, ovf, isBinary, typeInfo)
}

public func GenerateAnnotationFuncMangleName(name: String): String {
    return ChirGenerateAnnotationFuncMangleName(name)
}

public func GenerateGenericBaseClassMangleName(paramNum: Int64): String {
    return ChirGenerateGenericBaseClassMangleName(paramNum)
}

public func GenerateInstantiatedBaseClassMangleName(funcType: FuncType): String {
    return ChirGenerateInstantiatedBaseClassMangleName(funcType)
}

public func GenerateGlobalImplClassMangleName(function: Function): String {
    return ChirGenerateGlobalImplClassMangleName(function)
}

public func GenerateLambdaImplClassMangleName(function: Lambda, count: Int64): String {
    return ChirGenerateLambdaImplClassMangleName(function, count)
}

public func GenerateWrapperClassMangleName(def: ClassDef): String {
    return ChirGenerateWrapperClassMangleName(def)
}

public func GenerateGenericAbstractFuncMangleName(def: ClassDef): String {
    return ChirGenerateGenericAbstractFuncMangleName(def)
}

public func GenerateInstantiatedAbstractFuncMangleName(def: ClassDef): String {
    return ChirGenerateInstantiatedAbstractFuncMangleName(def)
}

public func GenerateGenericOverrideFuncMangleName(function: Function): String {
    return ChirGenerateGenericOverrideFuncMangleName(function)
}

public func GenerateInstOverrideFuncMangleName(function: Function): String {
    return ChirGenerateInstOverrideFuncMangleName(function)
}

public func GenerateWrapperClassGenericOverrideFuncMangleName(def: ClassDef): String {
    return ChirGenerateWrapperClassGenericOverrideFuncMangleName(def)
}

public func GenerateWrapperClassInstOverrideFuncMangleName(def: ClassDef): String {
    return ChirGenerateWrapperClassInstOverrideFuncMangleName(def)
}
