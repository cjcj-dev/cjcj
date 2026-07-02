package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.CheckCustomTypeDefIsExpected
import cangjie_compiler::chir.ClassDef
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.Parameter
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value
import cangjie_compiler::mangle.MANGLE_NESTED_PREFIX
import cangjie_compiler::mangle.MANGLE_SUFFIX
import cangjie_compiler::option.OSType
import cangjie_compiler::utils.{CJC_ASSERT, CORE_PACKAGE_NAME, HashString64, STD_LIB_FUTURE, STD_LIB_MONITOR,
    STD_LIB_MUTEX, STD_LIB_WAIT_QUEUE, SYNC_PACKAGE_NAME}

public func GetCodeGenGlobalName(value: Value): String {
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

public func GetPointerElementType(llvmType: LLVMTypeRef): LLVMTypeRef {
    return unsafe { LLVMGetElementType(llvmType) }
}

public func IsStructPtrType(llvmType: LLVMTypeRef): Bool {
    if (llvmType.isNull() || unsafe { LLVMGetTypeKind(llvmType) } != 12) {
        return false
    }
    let elementType = GetPointerElementType(llvmType)
    return !elementType.isNull() && unsafe { LLVMGetTypeKind(elementType) } == 10
}

public func IsLitStructPtrType(llvmType: LLVMTypeRef): Bool {
    if (llvmType.isNull() || unsafe { LLVMGetTypeKind(llvmType) } != 12) {
        return false
    }
    let elementType = GetPointerElementType(llvmType)
    return !elementType.isNull() && unsafe { LLVMGetTypeKind(elementType) } == 10 &&
        unsafe { LLVMIsLiteralStruct(elementType) } != 0
}

public func IsCommonStruct(chirTy: Type): Bool {
    return chirTy.IsStruct() && !chirTy.IsCPointer() && !chirTy.IsCString()
}

public func AlignedUpTo(offset: UInt64, align: UInt64): UInt64 {
    CJC_ASSERT(align != 0u64)
    return ((offset + align - 1u64) / align) * align
}

public func AlignedUpTo(cgMod: CGModule, offset: UInt64, llvmType: LLVMTypeRef): UInt64 {
    return AlignedUpTo(offset, UInt64(cgMod.GetABITypeAlignment(llvmType)))
}

public func GetTypeSize(cgMod: CGModule, llvmType: LLVMTypeRef): UInt64 {
    return cgMod.GetTypeSize(llvmType)
}

public func GetTypeSize(cgMod: CGModule, chirTy: Type): UInt64 {
    if (chirTy.IsUnit() || chirTy.IsNothing()) {
        return 0u64
    }
    return GetTypeSize(cgMod, CGType.GetOrCreate(cgMod, chirTy).GetLLVMType())
}

public func GetTypeAlignment(cgMod: CGModule, llvmType: LLVMTypeRef): UInt64 {
    return UInt64(cgMod.GetABITypeAlignment(llvmType))
}

public func GetTypeAlignment(cgMod: CGModule, chirTy: Type): UInt64 {
    if (chirTy.IsUnit() || chirTy.IsNothing()) {
        return 1u64
    }
    return GetTypeAlignment(cgMod, CGType.GetOrCreate(cgMod, chirTy).GetLLVMType())
}

public func IsZeroSizedTypeInC(cgMod: CGModule, chirTy: Type): Bool {
    if (chirTy.IsRef()) {
        let typeArgs = chirTy.GetTypeArgs()
        if (!typeArgs.isEmpty()) {
            return IsZeroSizedTypeInC(cgMod, typeArgs[0])
        }
    }
    return chirTy.IsUnit() || chirTy.IsNothing() ||
        (cgMod.GetCGContext().GetCompileOptions().target.os != OSType.WINDOWS &&
            GetTypeSize(cgMod, chirTy) == 0u64)
}

public func FixedCGTypeOfFuncArg(cgMod: CGModule, chirFuncArg: Value, llvmValue: LLVMValueRef): CGType {
    let chirFuncArgType = chirFuncArg.GetType().getOrThrow()
    var cgType = CGType.GetOrCreate(cgMod, chirFuncArgType)
    let byRef = chirFuncArgType.IsStruct() || chirFuncArgType.IsTuple() || chirFuncArgType.IsVArray() ||
        chirFuncArgType.IsUnit() || chirFuncArgType.IsNothing() ||
        (chirFuncArgType.IsEnum() && (CGType.GetOrCreate(cgMod, chirFuncArgType) as CGEnumType).getOrThrow().PassByReference())
    if (byRef) {
        let rawType = unsafe { LLVMTypeOf(llvmValue) }
        let addrspace = if (!rawType.isNull() && unsafe { LLVMGetTypeKind(rawType) } == 12) {
            unsafe { LLVMGetPointerAddressSpace(rawType) }
        } else {
            0u32
        }
        let refType = cgMod.GetCGContext().GetCHIRBuilder().context.GetRefTy(chirFuncArgType)
        cgType = CGType.GetOrCreate(cgMod, refType, extraInfo: TypeExtraInfo(addrspace))
    }
    cgMod.SetOrUpdateMappedCGValue(chirFuncArg, CGValue(llvmValue, cgType))
    return cgType
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

public func IsThisArgOfStructMethod(chirValue: Value): Bool {
    if (!chirValue.IsParameter()) {
        return false
    }
    let chirParam = (chirValue as Parameter) ?? return false
    let chirFunc = chirParam.GetTopLevelFunc() ?? return false
    if (chirFunc.GetNumOfParams() == 0 || chirFunc.GetParam(0) != chirParam) {
        return false
    }
    if (chirFunc.TestAttr(Attribute.STATIC) || !chirFunc.IsStructMethod()) {
        return false
    }
    return true
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

public func IsModifiableClass(chirTy: Type): Bool {
    if (!chirTy.IsClass()) {
        return false
    }
    let classDef = (chirTy as ClassType).getOrThrow().GetClassDef()
    return classDef.IsClass() && !classDef.TestAttr(Attribute.COMPILER_ADD) && !classDef.TestAttr(Attribute.VIRTUAL)
}

public func IsCoreFutureClass(classDef: ClassDef): Bool {
    return CheckCustomTypeDefIsExpected(classDef, CORE_PACKAGE_NAME, STD_LIB_FUTURE)
}

public func IsSyncRelatedClass(classDef: ClassDef): Bool {
    return CheckCustomTypeDefIsExpected(classDef, SYNC_PACKAGE_NAME, STD_LIB_MONITOR) ||
        CheckCustomTypeDefIsExpected(classDef, SYNC_PACKAGE_NAME, STD_LIB_MUTEX) ||
        CheckCustomTypeDefIsExpected(classDef, SYNC_PACKAGE_NAME, STD_LIB_WAIT_QUEUE)
}

public func IsVArrayRef(chirTy: Type): Bool {
    let typeArgs = chirTy.GetTypeArgs()
    return chirTy.IsRef() && !typeArgs.isEmpty() && typeArgs[0].IsVArray()
}

public func IsUnitOrNothing(chirTy: Type): Bool {
    return chirTy.IsUnit() || chirTy.IsNothing()
}
