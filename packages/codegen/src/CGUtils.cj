package cangjie_compiler::codegen

import cangjie_compiler::chir.Type
import cangjie_compiler::mangle.MANGLE_NESTED_PREFIX
import cangjie_compiler::mangle.MANGLE_SUFFIX
import cangjie_compiler::utils.HashString64

public func GenNameForBB(name: String, extraInfo!: UInt64 = 0u64): String {
    if (extraInfo != 0u64) {
        return name
    }
    return name
}

public func GetClassObjLayoutName(className: String): String {
    return "ObjLayout." + className
}

public func MangleName(value: String): String {
    return value.size.toString() + value
}

public func GetMangledNameOfCompilerAddedClass(className: String): String {
    return MANGLE_NESTED_PREFIX + MangleName(className) + MANGLE_SUFFIX
}

public func GetCjStringDataLiteralName(cjStr: String): String {
    return CJSTRING_DATA_PREFIX + HashString64(cjStr)
}

public func GetCjStringLiteralName(cjStr: String): String {
    return CJSTRING_LITERAL_PREFIX + HashString64(cjStr)
}

public func GetConstantTupleName(value: String): String {
    return CONST_TUPLE_PREFIX + HashString64(value)
}

public func GetConstantArrayName(value: String): String {
    return CONST_ARRAY_PREFIX + HashString64(value)
}

public func DeRef(chirTy: Type): Type {
    return chirTy.StripAllRefs()
}

public func IsGenericRef(chirTy: Type): Bool {
    let typeArgs = chirTy.GetTypeArgs()
    return chirTy.IsRef() && !typeArgs.isEmpty() && typeArgs[0].IsGeneric()
}

public func IsStructRef(chirTy: Type): Bool {
    let typeArgs = chirTy.GetTypeArgs()
    return chirTy.IsRef() && !typeArgs.isEmpty() && typeArgs[0].IsStruct()
}

public func IsStaticStruct(chirTy: Type): Bool {
    return chirTy.IsStruct() && CGType.GetCGGenericKind(chirTy) == CGGenericKind.STATIC_GI
}

public func IsDynamicStruct(chirTy: Type): Bool {
    return chirTy.IsStruct() && CGType.GetCGGenericKind(chirTy) == CGGenericKind.DYNAMIC_GI
}

public func IsDynamicStructRef(chirTy: Type): Bool {
    let typeArgs = chirTy.GetTypeArgs()
    if (!chirTy.IsRef() || typeArgs.isEmpty()) {
        return false
    }
    let baseTy = typeArgs[0]
    return baseTy.IsStruct() && CGType.GetCGGenericKind(baseTy) == CGGenericKind.DYNAMIC_GI
}

public func IsClassRef(chirTy: Type): Bool {
    let typeArgs = chirTy.GetTypeArgs()
    return chirTy.IsRef() && !typeArgs.isEmpty() && typeArgs[0].IsClass()
}

public func IsStaticClass(chirTy: Type): Bool {
    return chirTy.IsClass() && CGType.GetCGGenericKind(chirTy) == CGGenericKind.STATIC_GI
}

public func IsDynamicClass(chirTy: Type): Bool {
    return chirTy.IsClass() && CGType.GetCGGenericKind(chirTy) == CGGenericKind.DYNAMIC_GI
}

public func IsDynamicClassRef(chirTy: Type): Bool {
    let typeArgs = chirTy.GetTypeArgs()
    if (!chirTy.IsRef() || typeArgs.isEmpty()) {
        return false
    }
    let baseTy = typeArgs[0]
    return baseTy.IsClass() && CGType.GetCGGenericKind(baseTy) == CGGenericKind.DYNAMIC_GI
}

public func IsVArrayRef(chirTy: Type): Bool {
    let typeArgs = chirTy.GetTypeArgs()
    return chirTy.IsRef() && !typeArgs.isEmpty() && typeArgs[0].IsVArray()
}

public func IsUnitOrNothing(chirTy: Type): Bool {
    return chirTy.IsUnit() || chirTy.IsNothing()
}
