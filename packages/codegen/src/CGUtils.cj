package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value
import cangjie_compiler::mangle.MANGLE_NESTED_PREFIX
import cangjie_compiler::mangle.MANGLE_SUFFIX
import cangjie_compiler::utils.HashString64

public func GetCodeGenGlobalName(value: Value): String {
    return value.GetIdentifierWithoutPrefix()
}

public func GetCodeGenValueKey(value: Value): String {
    if (value.IsGlobal()) {
        return GetCodeGenGlobalName(value)
    }
    return value.GetIdentifierWithoutPrefix()
}

public func GenNameForBB(name: String, extraInfo!: UInt64 = 0u64): String {
    if (extraInfo != 0u64) {
        return name
    }
    return name
}

public func GetClassObjLayoutName(className: String): String {
    return "ObjLayout." + className
}

public func GetOrCreateNamedStructType(context: LLVMContextHandle, name: String): LLVMTypeRef {
    var result = LLVMNullType()
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = unsafe { LLVMGetTypeByName2(context.raw, nameCString.value) }
        if (result.isNull()) {
            result = unsafe { LLVMStructCreateNamed(context.raw, nameCString.value) }
        }
    }
    return result
}

public func SetStructTypeBody(structType: LLVMTypeRef, body: ArrayList<LLVMTypeRef>): Unit {
    if (structType.isNull()) {
        return
    }
    if (body.isEmpty()) {
        unsafe { LLVMStructSetBody(structType, CPointer<LLVMTypeRef>(), 0u32, 0) }
        return
    }
    try (bodyPtr = LibC.malloc<LLVMTypeRef>(count: body.size).asResource()) {
        var idx: Int64 = 0
        while (idx < body.size) {
            unsafe { (bodyPtr.value + idx).write(body[idx]) }
            idx++
        }
        unsafe { LLVMStructSetBody(structType, bodyPtr.value, UInt32(body.size), 0) }
    }
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

public func IsAutoEnvType(chirTy: Type): Bool {
    if (let Some(customTy) <- (chirTy.StripAllRefs() as CustomType)) {
        return customTy.GetCustomTypeDef().GetAnnotation("IsAutoEnvClass").isSome()
    }
    return false
}

public func IsAutoEnvBaseType(chirTy: Type): Bool {
    if (let Some(customTy) <- (chirTy.StripAllRefs() as CustomType)) {
        return customTy.GetCustomTypeDef().GetAnnotation("IsAutoEnvBase").isSome()
    }
    return false
}

public func IsAutoEnvInstBaseType(chirTy: Type): Bool {
    if (let Some(customTy) <- (chirTy.StripAllRefs() as CustomType)) {
        return customTy.GetCustomTypeDef().GetAnnotation("IsAutoEnvInstBase").isSome()
    }
    return false
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
