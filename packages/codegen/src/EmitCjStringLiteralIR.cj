package cjcj::codegen

import std.collection.*
import std.sort.*
import cjcj::option.OSType

private let RAW_ARRAY_UINT8_KIND: UInt64 = 130u64

private func NamedGlobalExists(moduleHandle: LLVMModuleHandle, globalName: String): Bool {
    var result = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(globalName) }.asResource()) {
        result = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
    }
    return !result.isNull()
}

private func GetNamedGlobal(moduleHandle: LLVMModuleHandle, globalName: String): LLVMValueRef {
    var result = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(globalName) }.asResource()) {
        result = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
    }
    return result
}

private func GetOrInsertGlobal(moduleHandle: LLVMModuleHandle, globalName: String,
    globalType: LLVMTypeRef): LLVMValueRef {
    var result = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(globalName) }.asResource()) {
        result = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
        if (result.isNull()) {
            result = unsafe { LLVMAddGlobal(moduleHandle.raw, globalType, nameCString.value) }
        }
    }
    return result
}

private func ConstStruct(structType: LLVMTypeRef, values: ArrayList<LLVMValueRef>): LLVMValueRef {
    if (values.isEmpty()) {
        return unsafe { LLVMConstNamedStruct(structType, CPointer<LLVMValueRef>(), 0u32) }
    }
    var result = LLVMNullValue()
    try (valuePtr = LibC.malloc<LLVMValueRef>(count: values.size).asResource()) {
        var valueIdx: Int64 = 0
        while (valueIdx < values.size) {
            unsafe { (valuePtr.value + valueIdx).write(values[valueIdx]) }
            valueIdx++
        }
        result = unsafe { LLVMConstNamedStruct(structType, valuePtr.value, UInt32(values.size)) }
    }
    return result
}

private func StructTypeInContext(context: LLVMContextRef, fieldTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
    if (fieldTypes.isEmpty()) {
        return unsafe { LLVMStructTypeInContext(context, CPointer<LLVMTypeRef>(), 0u32, 0) }
    }
    var result = LLVMNullType()
    try (typePtr = LibC.malloc<LLVMTypeRef>(count: fieldTypes.size).asResource()) {
        var fieldIdx: Int64 = 0
        while (fieldIdx < fieldTypes.size) {
            unsafe { (typePtr.value + fieldIdx).write(fieldTypes[fieldIdx]) }
            fieldIdx++
        }
        result = unsafe { LLVMStructTypeInContext(context, typePtr.value, UInt32(fieldTypes.size), 0) }
    }
    return result
}

private func BuildPackedRawStringData(cjStrings: HashMap<String, String>,
    moduleHandle: LLVMModuleHandle): String {
    let uniqueContents = HashSet<String>()
    for ((cjStringName, cjStringContent) in cjStrings) {
        if (NamedGlobalExists(moduleHandle, cjStringName)) {
            uniqueContents.add(cjStringContent)
        }
    }
    let sortedContents = ArrayList<String>()
    for (content in uniqueContents) {
        sortedContents.add(content)
    }
    sort(sortedContents, by: { left: String, right: String =>
        if (left < right) {
            Ordering.LT
        } else if (left > right) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    }, stable: true)

    var rawData = ""
    var contentIdx = sortedContents.size - 1
    while (contentIdx >= 0) {
        let content = sortedContents[contentIdx]
        if (rawData.indexOf(content).isNone()) {
            rawData += content
        }
        contentIdx--
    }
    return rawData
}

private func GetReadOnlyArrayKlassInfo(cgMod: CGModule, moduleHandle: LLVMModuleHandle): LLVMValueRef {
    let name = "RawArray<UInt8>.ti"
    let existing = GetNamedGlobal(moduleHandle, name)
    if (!existing.isNull()) {
        return existing
    }
    let contextHandle = cgMod.GetLLVMContext()
    let context = contextHandle.raw
    let i8Type = unsafe { LLVMInt8TypeInContext(context) }
    let i16Type = unsafe { LLVMInt16TypeInContext(context) }
    let i32Type = unsafe { LLVMInt32TypeInContext(context) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let i32PtrType = unsafe { LLVMPointerType(i32Type, 0u32) }
    let typeInfoType = CGType.GetOrCreateTypeInfoType(cgMod.GetLLVMContext())
    let bitMapPtrType = unsafe { LLVMPointerType(CGType.GetBitMapType(contextHandle), 0u32) }
    let extensionDefPtrPtrType = unsafe {
        LLVMPointerType(CGType.GetOrCreateExtensionDefPtrType(contextHandle), 0u32)
    }
    let typeTemplateType = CGType.GetOrCreateTypeTemplateType(contextHandle)
    let rawArrayTypeTemplate = GetOrInsertGlobal(moduleHandle, "RawArray.tt", typeTemplateType)
    let memberTypeInfoName = "UInt8.ti"
    let memberTypeInfoExisted = !GetNamedGlobal(moduleHandle, memberTypeInfoName).isNull()
    let memberTypeInfo = GetOrInsertGlobal(moduleHandle, memberTypeInfoName, typeInfoType)
    if (!memberTypeInfoExisted) {
        LLVMSetGlobalStringMetadata(contextHandle, memberTypeInfo, GC_TYPE_META_NAME, "UInt8.Type")
        addAttribute(memberTypeInfo, GC_KLASS_ATTR)
        addAttribute(memberTypeInfo, NOT_MODIFIABLE_CLASS_ATTR)
    }

    let typeInfoValues = ArrayList<LLVMValueRef>()
    typeInfoValues.add(cgMod.GenerateTypeNameConstantString("RawArray<UInt8>", false))
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, RAW_ARRAY_UINT8_KIND, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i16Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i32Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstNull(bitMapPtrType) })
    typeInfoValues.add(unsafe { LLVMConstInt(i32Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i16Type, INHERITED_CLASS_NUM_FE_FLAG, 0) })
    typeInfoValues.add(unsafe { LLVMConstNull(i32PtrType) })
    typeInfoValues.add(unsafe { LLVMConstBitCast(rawArrayTypeTemplate, i8PtrType) })
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    typeInfoValues.add(memberTypeInfo)
    typeInfoValues.add(unsafe { LLVMConstNull(extensionDefPtrPtrType) })
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })

    let globalValue = GetOrInsertGlobal(moduleHandle, name, typeInfoType)
    unsafe {
        LLVMSetInitializer(globalValue, ConstStruct(typeInfoType, typeInfoValues))
        addAttribute(globalValue, GC_KLASS_ATTR)
        if (cgMod.GetCGContext().GetCompileOptions().target.os != OSType.WINDOWS) {
            LLVMSetLinkage(globalValue, LLVMLinkageValue(LLVMLinkage.LinkOnceODR))
        }
    }
    AddLinkageTypeMetadata(globalValue, LLVMLinkage.Internal, false)
    let layoutType = CGArrayType.GenerateArrayLayoutTypeInfo(cgMod.GetCGContext(), ARRAY_LAYOUT_PREFIX + "UInt8",
        unsafe { LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw) })
    let layoutName = LLVMCStringToString(unsafe { LLVMGetStructName(layoutType) }) ?? ""
    LLVMSetGlobalStringMetadata(contextHandle, globalValue, GC_TYPE_META_NAME, layoutName)
    return globalValue
}

private func CreateRawArrayGlobal(cgMod: CGModule, moduleHandle: LLVMModuleHandle, rawData: String): LLVMValueRef {
    let context = cgMod.GetLLVMContext().raw
    let i8Type = unsafe { LLVMInt8TypeInContext(context) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let i64Type = unsafe { LLVMInt64TypeInContext(context) }

    var strContent = LLVMNullValue()
    try (rawCString = unsafe { LibC.mallocCString(rawData) }.asResource()) {
        strContent = unsafe { LLVMConstStringInContext(context, rawCString.value, UInt32(rawData.size), 1) }
    }

    let rawArrayFieldTypes = ArrayList<LLVMTypeRef>()
    rawArrayFieldTypes.add(i8PtrType)
    rawArrayFieldTypes.add(i64Type)
    rawArrayFieldTypes.add(unsafe { LLVMTypeOf(strContent) })
    let rawArrayType = StructTypeInContext(context, rawArrayFieldTypes)

    let arrayKlassInfo = GetReadOnlyArrayKlassInfo(cgMod, moduleHandle)
    let rawArrayValues = ArrayList<LLVMValueRef>()
    rawArrayValues.add(unsafe { LLVMConstBitCast(arrayKlassInfo, i8PtrType) })
    rawArrayValues.add(unsafe { LLVMConstInt(i64Type, UInt64(rawData.size), 1) })
    rawArrayValues.add(strContent)
    let rawArrayData = ConstStruct(rawArrayType, rawArrayValues)

    let rawDataName = GetCjStringDataLiteralName(rawData)
    let rawDataGlobal = GetOrInsertGlobal(moduleHandle, rawDataName, rawArrayType)
    unsafe {
        LLVMSetInitializer(rawDataGlobal, rawArrayData)
        LLVMSetGlobalConstant(rawDataGlobal, 1)
        addAttribute(rawDataGlobal, CJSTRING_DATA_ATTR)
        LLVMSetLinkage(rawDataGlobal, LLVMLinkageValue(LLVMLinkage.Private))
    }
    return rawDataGlobal
}

private func InitializeOneCjStringLiteral(cgMod: CGModule, moduleHandle: LLVMModuleHandle,
    rawDataGlobal: LLVMValueRef, rawData: String, cjStringName: String, cjStringContent: String): Unit {
    let cjStringGlobal = GetNamedGlobal(moduleHandle, cjStringName)
    if (cjStringGlobal.isNull()) {
        return
    }
    if (let Some(pos) <- rawData.indexOf(cjStringContent)) {
        let context = cgMod.GetLLVMContext().raw
        let i8Type = unsafe { LLVMInt8TypeInContext(context) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let i8PtrAddr1Type = unsafe { LLVMPointerType(i8Type, 1u32) }
        let i32Type = unsafe { LLVMInt32TypeInContext(context) }
        let cjStringType = cgMod.GetCGContext().GetCjStringType()
        let i8Ptr = unsafe { LLVMConstBitCast(rawDataGlobal, i8PtrType) }
        let i8PtrAddr1 = unsafe { LLVMConstAddrSpaceCast(i8Ptr, i8PtrAddr1Type) }

        let cjStringValues = ArrayList<LLVMValueRef>()
        cjStringValues.add(i8PtrAddr1)
        cjStringValues.add(unsafe { LLVMConstInt(i32Type, UInt64(pos), 1) })
        cjStringValues.add(unsafe { LLVMConstInt(i32Type, UInt64(cjStringContent.size), 1) })
        let cjStringInitializer = ConstStruct(cjStringType, cjStringValues)
        unsafe { LLVMSetInitializer(cjStringGlobal, cjStringInitializer) }
    }
}

public func InitializeCjStringLiteral(cgMod: CGModule): Unit {
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let cjStrings = cgMod.GetCGContext().GetCJStrings()
        if (cjStrings.isEmpty()) {
            return
        }
        let rawData = BuildPackedRawStringData(cjStrings, moduleHandle)
        let rawDataGlobal = CreateRawArrayGlobal(cgMod, moduleHandle, rawData)
        for ((cjStringName, cjStringContent) in cjStrings) {
            InitializeOneCjStringLiteral(cgMod, moduleHandle, rawDataGlobal, rawData, cjStringName, cjStringContent)
        }
    }
}
