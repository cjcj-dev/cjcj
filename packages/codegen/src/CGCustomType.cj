package cjcj::codegen

import std.collection.*
import cjcj::basic.Linkage
import cjcj::chir.{CustomType, LinkTypeInfo, Type}
import cjcj::utils.{CJC_ASSERT_WITH_MSG, StaticCast}

public open class CGCustomType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type, cgTypeKind!: CGTypeKind = CGTypeKind.OTHERS) {
        super(cgMod, cgCtx, chirType, cgTypeKind: cgTypeKind)
    }

    protected open override func GenLLVMType(): LLVMTypeRef {
        let layoutName = STRUCT_TYPE_PREFIX + chirType.ToString()
        let customLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        layoutType = customLayout
        return customLayout
    }

    protected open override func GenContainedCGTypes(): Unit {
        for (argTy in chirType.GetTypeArgs()) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, argTy))
        }
    }

    protected open override func CalculateSizeAndAlign(): Unit {
        if (!IsSized()) {
            size = None
            align = None
            return
        }
        if (let Some(rawLayout) <- layoutType) {
            if (!rawLayout.isNull() && unsafe { LLVMGetTypeKind(rawLayout) } == 10) {
                size = Int64(cgMod.GetTypeSize(rawLayout))
                align = Int64(cgMod.GetABITypeAlignment(rawLayout))
                return
            }
        }
        size = None
        align = None
    }

    protected func IsSized(): Bool {
        let customType = StaticCast<CustomType>(chirType)
        let memberVars = customType.GetInstantiatedMemberTys(cgMod.GetCGContext().GetCHIRBuilder())
        for (memberVar in memberVars) {
            if (memberVar.IsRef() || memberVar.IsCPointer() || memberVar.IsCFunc()) {
                continue
            }
            if (CGType.GetOrCreate(cgMod, memberVar).GetSize().isNone()) {
                return false
            }
        }
        return true
    }

    public static func GenTypeInfoConstantVectorForTypes(cgMod: CGModule, chirTypes: ArrayList<Type>):
        ArrayList<LLVMValueRef> {
        let fieldConstants = ArrayList<LLVMValueRef>()
        for (chirTy in chirTypes) {
            let derefType = DeRef(chirTy)
            fieldConstants.add(CGType.GetOrCreate(cgMod, derefType).GetOrCreateTypeInfo())
        }
        return fieldConstants
    }

    public static func GenTypeInfoArray(cgMod: CGModule, name: String, constants: ArrayList<LLVMValueRef>,
        attr: String): LLVMValueRef {
        let llvmContext = cgMod.GetLLVMContext()
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(llvmContext.raw), 0u32) }
        if (constants.isEmpty()) {
            return unsafe { LLVMConstNull(i8PtrType) }
        }
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(llvmContext)
        let typeOfFieldsGV = unsafe { LLVMArrayType(typeInfoPtrType, UInt32(constants.size)) }
        let typeInfoOfFields = GetOrInsertCodeGenGlobal(cgMod, name, typeOfFieldsGV)
        var initializer = LLVMNullValue()
        try (valuePtr = LibC.malloc<LLVMValueRef>(count: constants.size).asResource()) {
            var idx: Int64 = 0
            while (idx < constants.size) {
                unsafe { (valuePtr.value + idx).write(constants[idx]) }
                idx++
            }
            initializer = unsafe { LLVMConstArray(typeInfoPtrType, valuePtr.value, UInt32(constants.size)) }
        }
        unsafe {
            LLVMSetInitializer(typeInfoOfFields, initializer)
            LLVMSetLinkage(typeInfoOfFields, LLVMLinkageValue(LLVMLinkage.Private))
            LLVMSetGlobalConstant(typeInfoOfFields, 1)
            LLVMSetUnnamedAddress(typeInfoOfFields, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr))
        }
        addAttribute(typeInfoOfFields, attr)
        return unsafe { LLVMConstBitCast(typeInfoOfFields, i8PtrType) }
    }

    public static func GenOffsetsArray(cgMod: CGModule, name: String, layoutType: LLVMTypeRef): LLVMValueRef {
        let llvmContext = cgMod.GetLLVMContext()
        let i32Type = unsafe { LLVMInt32TypeInContext(llvmContext.raw) }
        let i32PtrType = unsafe { LLVMPointerType(i32Type, 0u32) }
        let arrLength = unsafe { LLVMCountStructElementTypes(layoutType) }
        if (arrLength == 0u32) {
            return unsafe { LLVMConstNull(i32PtrType) }
        }
        let i32ArrType = unsafe { LLVMArrayType(i32Type, arrLength) }
        let offsets = ArrayList<LLVMValueRef>()
        var idx: UInt32 = 0u32
        while (idx < arrLength) {
            offsets.add(unsafe { LLVMConstInt(i32Type, cgMod.GetOffsetOfElement(layoutType, idx), 0) })
            idx++
        }
        let typeInfoOfFields = GetOrInsertCodeGenGlobal(cgMod, name, i32ArrType)
        var initializer = LLVMNullValue()
        try (valuePtr = LibC.malloc<LLVMValueRef>(count: offsets.size).asResource()) {
            var valueIdx: Int64 = 0
            while (valueIdx < offsets.size) {
                unsafe { (valuePtr.value + valueIdx).write(offsets[valueIdx]) }
                valueIdx++
            }
            initializer = unsafe { LLVMConstArray(i32Type, valuePtr.value, UInt32(offsets.size)) }
        }
        unsafe {
            LLVMSetInitializer(typeInfoOfFields, initializer)
            LLVMSetLinkage(typeInfoOfFields, LLVMLinkageValue(LLVMLinkage.Private))
            LLVMSetGlobalConstant(typeInfoOfFields, 1)
            LLVMSetUnnamedAddress(typeInfoOfFields, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr))
        }
        addAttribute(typeInfoOfFields, CJTI_OFFSETS_ATTR)
        return unsafe { LLVMConstBitCast(typeInfoOfFields, i32PtrType) }
    }

    protected open func PreActionOfGenTypeTemplate(): Unit {}
    protected open func PostActionOfGenTypeTemplate(): Unit {}

    public override func GenTypeTemplate(): Unit {
        let customType = StaticCast<CustomType>(chirType)
        let customTypeDef = customType.GetCustomTypeDef()
        CJC_ASSERT_WITH_MSG(customTypeDef.IsGenericDef(), "Should be a generic type here.")
        CJC_ASSERT_WITH_MSG(typeTemplate.isSome(), "This type does not have a type-template GV, please check the caller.")
        if (let Some(rawTypeTemplate) <- typeTemplate) {
            PreActionOfGenTypeTemplate()
            if (unsafe { LLVMIsDeclaration(rawTypeTemplate) } == 0) {
                return
            }
            // C++ CGCustomType::GenTypeTemplate (CGCustomType.cpp:284-289) returns before
            // creating anonymous debug types for imported/other-module and auto-env-base types.
            if (cgMod.GetCGContext().IsCustomTypeOfOtherLLVMModule(customType) ||
                IsAutoEnvBaseType(chirType)) {
                if (customTypeDef.Get<LinkTypeInfo, Linkage>() == Linkage.EXTERNAL_WEAK) {
                    unsafe { LLVMSetLinkage(rawTypeTemplate, LLVMLinkageValue(LLVMLinkage.ExternalWeak)) }
                }
                return
            }
            DefineCustomTypeTemplateIfNeeded(cgMod, customType, rawTypeTemplate)
            if (let Some(diBuilder) <- cgMod.GetDIBuilder()) {
                diBuilder.CreateAnonymousTypeForGenericType(rawTypeTemplate, chirType)
            }
            PostActionOfGenTypeTemplate()
        }
    }
}
