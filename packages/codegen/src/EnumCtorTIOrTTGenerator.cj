package cjcj::codegen

import std.collection.*
import cjcj::basic.Linkage
import cjcj::chir.Attribute
import cjcj::chir.CustomTypeDef
import cjcj::chir.EnumType
import cjcj::chir.GenericType
import cjcj::chir.LinkTypeInfo
import cjcj::chir.Type
import cjcj::option.OSType
import cjcj::utils.CJC_ASSERT

public class EnumCtorLayout {
    public let fieldTypes: ArrayList<Type> = ArrayList<Type>()
    public var size: UInt32 = 0u32
    public var align: UInt32 = 1u32
    public var offsets: LLVMValueRef = LLVMNullValue()

    public init() {}
}

public class EnumCtorTIOrTTGenerator {
    private let cgMod: CGModule
    private let cgCtx: CGContext
    private let chirEnumType: EnumType
    private let ctorIndex: Int64

    public init(cgMod: CGModule, chirEnumType: EnumType, ctorIndex: Int64) {
        this.cgMod = cgMod
        this.cgCtx = cgMod.GetCGContext()
        this.chirEnumType = chirEnumType
        this.ctorIndex = ctorIndex
    }

    public func Emit(): Unit {
        let cgEnumType = CGType.GetOrCreate(cgMod, chirEnumType)
        if (cgEnumType.IsDynamicGI()) {
            EmitForDynamicGI()
        } else if (cgEnumType.IsStaticGI()) {
            EmitForStaticGI()
        } else if (cgEnumType.IsConcrete()) {
            EmitForConcrete()
        } else {
            CJC_ASSERT(false)
        }
    }

    private func EmitForDynamicGI(): Unit {
        let enumDef = chirEnumType.GetEnumDef()
        let tt = cgMod.GetOrCreateEnumCtorTIOrTT(chirEnumType, ctorIndex)
        if (unsafe { LLVMIsDeclaration(tt) } == 0 || enumDef.TestAttr(Attribute.IMPORTED) ||
            enumDef.TestAttr(Attribute.NON_RECOMPILE)) {
            return
        }
        if (!cgMod.OwnsCustomTypeDef(enumDef)) {
            return
        }

        GenerateGenericEnumCtorTypeTemplate(tt)
        var linkageType = LinkageOfCustomTypeDef(enumDef)
        if (LLVMLinkageValue(linkageType) == LLVMLinkageValue(LLVMLinkage.Internal)) {
            linkageType = LLVMLinkage.Private
        }
        AddLinkageTypeMetadata(tt, linkageType, cgCtx.IsCGParallelEnabled())
    }

    private func EmitForStaticGI(): Unit {
        let ti = cgMod.GetOrCreateEnumCtorTIOrTT(chirEnumType, ctorIndex)
        if (unsafe { LLVMIsDeclaration(ti) } == 0) {
            return
        }

        GenerateNonGenericEnumCtorTypeInfo(ti)
        let linkageType = if (cgCtx.GetCompileOptions().target.os != OSType.WINDOWS) {
            LLVMLinkage.LinkOnceODR
        } else {
            LLVMLinkage.Private
        }
        AddLinkageTypeMetadata(ti, linkageType, false)
    }

    private func EmitForConcrete(): Unit {
        let enumDef = chirEnumType.GetEnumDef()
        let ti = cgMod.GetOrCreateEnumCtorTIOrTT(chirEnumType, ctorIndex)
        if (unsafe { LLVMIsDeclaration(ti) } == 0 || enumDef.TestAttr(Attribute.IMPORTED) ||
            enumDef.TestAttr(Attribute.NON_RECOMPILE)) {
            return
        }
        if (!cgMod.OwnsCustomTypeDef(enumDef)) {
            return
        }

        GenerateNonGenericEnumCtorTypeInfo(ti)
        var linkageType = LinkageOfCustomTypeDef(enumDef)
        if (LLVMLinkageValue(linkageType) == LLVMLinkageValue(LLVMLinkage.Internal)) {
            linkageType = LLVMLinkage.Private
        }
        if (cgCtx.GetCompileOptions().target.os != OSType.WINDOWS) {
            linkageType = LLVMLinkage.LinkOnceODR
        }
        AddLinkageTypeMetadata(ti, linkageType, cgCtx.IsCGParallelEnabled())
    }

    private func GenerateNonGenericEnumCtorTypeInfo(ti: LLVMValueRef): Unit {
        let llvmCtx = cgMod.GetLLVMContext()
        let i8Ty = unsafe { LLVMInt8TypeInContext(llvmCtx.raw) }
        let i16Ty = unsafe { LLVMInt16TypeInContext(llvmCtx.raw) }
        let i32Ty = unsafe { LLVMInt32TypeInContext(llvmCtx.raw) }
        let i8PtrTy = unsafe { LLVMPointerType(i8Ty, 0u32) }
        let i8PtrNull = unsafe { LLVMConstNull(i8PtrTy) }

        let className = cgMod.GetEnumCaseClassName(chirEnumType, ctorIndex)
        let tiName = className + ".ti"
        let ctors = chirEnumType.GetEnumDef().GetConstructorInfos(builder: Some(cgCtx.GetCHIRBuilder()))
        CJC_ASSERT(ctorIndex >= 0 && ctorIndex < ctors.size)
        let paramTypes = ctors[ctorIndex].funcType.getOrThrow().GetParamTypes()
        let cgEnumType = (CGType.GetOrCreate(cgMod, chirEnumType) as CGEnumType).getOrThrow()
        var layout = EnumCtorLayout()
        if (cgEnumType.IsOptionLikeRef() || cgEnumType.IsOptionLikeT()) {
            layout = GenLayoutForReferenceType(tiName, className)
        } else if (cgEnumType.IsZeroSizeEnum()) {
            layout = GenLayoutForZeroSize()
        } else if (cgEnumType.IsTrivial()) {
            layout = GenLayoutForTrivial(tiName)
        } else {
            layout = GenLayoutForStructure(cgEnumType, paramTypes, tiName, className)
        }

        let fieldsTypes = layout.fieldTypes
        let fieldConstants = CGCustomType.GenTypeInfoConstantVectorForTypes(cgMod, fieldsTypes)
        let layoutType = GetLLVMStructType(cgMod, fieldsTypes, GetClassObjLayoutName(className))
        let typeInfoVec = ArrayList<LLVMValueRef>()
        typeInfoVec.add(cgMod.GenerateTypeNameConstantString(className, false))
        typeInfoVec.add(unsafe { LLVMConstInt(i8Ty, 132u64, 0) })
        typeInfoVec.add(unsafe { LLVMConstInt(i8Ty, 0u64, 0) })
        typeInfoVec.add(unsafe { LLVMConstInt(i16Ty, UInt64(fieldsTypes.size), 0) })
        typeInfoVec.add(unsafe { LLVMConstInt(i32Ty, UInt64(layout.size), 0) })
        typeInfoVec.add(unsafe { LLVMConstNull(LLVMPointerType(CGType.GetBitMapType(llvmCtx), 0u32)) })
        typeInfoVec.add(unsafe { LLVMConstNull(i32Ty) })
        typeInfoVec.add(unsafe { LLVMConstInt(i8Ty, UInt64(layout.align), 0) })
        typeInfoVec.add(GenTypeArgsNumOfTypeInfo())
        typeInfoVec.add(unsafe { LLVMConstInt(i16Ty, INHERITED_CLASS_NUM_FE_FLAG, 0) })
        typeInfoVec.add(layout.offsets)
        typeInfoVec.add(GenSourceGenericOfTypeInfo())
        typeInfoVec.add(GenTypeArgsOfTypeInfo())
        typeInfoVec.add(CGCustomType.GenTypeInfoArray(cgMod, tiName + ".fields", fieldConstants, CJTI_FIELDS_ATTR))
        typeInfoVec.add(CGType.GetOrCreate(cgMod, chirEnumType).GetOrCreateTypeInfo())
        typeInfoVec.add(unsafe { LLVMConstNull(LLVMPointerType(CGType.GetOrCreateExtensionDefPtrType(llvmCtx), 0u32)) })
        typeInfoVec.add(i8PtrNull)
        typeInfoVec.add(i8PtrNull)

        unsafe {
            LLVMSetInitializer(ti, ConstNamedStruct(CGType.GetOrCreateTypeInfoType(llvmCtx), typeInfoVec))
        }
        addAttribute(ti, GC_KLASS_ATTR)
        if (cgCtx.GetCompileOptions().target.os != OSType.WINDOWS) {
            unsafe { LLVMSetLinkage(ti, LLVMLinkageValue(LLVMLinkage.LinkOnceODR)) }
        }
        let layoutName = LLVMCStringToString(unsafe { LLVMGetStructName(layoutType) }) ?? ""
        LLVMSetGlobalStringMetadata(llvmCtx, ti, GC_TYPE_META_NAME, layoutName)
        if (!cgCtx.GetCompileOptions().disableReflection) {
            let mangledName = ctors[ctorIndex].annoInfo.GetAnnoFactoryFuncMangledName()
            LLVMSetGlobalMetadata(llvmCtx, ti, "Reflection", CreateReflectionMetadata(llvmCtx, mangledName))
        }
        cgCtx.AddGeneratedStructType(layoutName)
        cgCtx.RegisterStaticGIName(tiName)
    }

    private func GenTypeArgsNumOfTypeInfo(): LLVMValueRef {
        return unsafe {
            LLVMConstInt(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), UInt64(chirEnumType.GetGenericArgs().size),
                0)
        }
    }

    private func GenTypeArgsOfTypeInfo(): LLVMValueRef {
        let llvmCtx = cgMod.GetLLVMContext()
        let i8Ty = unsafe { LLVMInt8TypeInContext(llvmCtx.raw) }
        let i8PtrTy = unsafe { LLVMPointerType(i8Ty, 0u32) }
        let typeArgsNum = chirEnumType.GetGenericArgs().size
        if (typeArgsNum == 0) {
            return unsafe { LLVMConstNull(i8PtrTy) }
        }
        let typeInfoPtrTy = CGType.GetOrCreateTypeInfoPtrType(llvmCtx)
        let typeOfGenericArgsGV = unsafe { LLVMArrayType(typeInfoPtrTy, UInt32(typeArgsNum)) }
        let typeInfoOfGenericArgs = GetOrInsertCodeGenGlobal(cgMod,
            CGType.GetNameOfTypeInfoGV(chirEnumType) + ".typeArgs", typeOfGenericArgsGV)
        addAttribute(typeInfoOfGenericArgs, CJTI_TYPE_ARGS_ATTR)
        unsafe {
            LLVMSetGlobalConstant(typeInfoOfGenericArgs, 1)
            LLVMSetUnnamedAddress(typeInfoOfGenericArgs, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr))
        }
        AddLinkageTypeMetadata(typeInfoOfGenericArgs, LLVMLinkage.Private, cgCtx.IsCGParallelEnabled())
        return unsafe { LLVMConstBitCast(typeInfoOfGenericArgs, i8PtrTy) }
    }

    private func GenSourceGenericOfTypeInfo(): LLVMValueRef {
        let p0i8 = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 0u32) }
        if (chirEnumType.GetCustomTypeDef().IsGenericDef()) {
            let genericDecl = chirEnumType.GetCustomTypeDef()
            let genericEnumType = (genericDecl.GetType().getOrThrow() as EnumType) ??
                throw IllegalStateException("generic enum decl requires EnumType")
            return unsafe { LLVMConstBitCast(cgMod.GetOrCreateEnumCtorTIOrTT(genericEnumType, ctorIndex), p0i8) }
        }
        return unsafe { LLVMConstNull(p0i8) }
    }

    private func GenerateGenericEnumCtorTypeTemplate(tt: LLVMValueRef): Unit {
        let llvmCtx = cgMod.GetLLVMContext()
        let i8Ty = unsafe { LLVMInt8TypeInContext(llvmCtx.raw) }
        let i8PtrTy = unsafe { LLVMPointerType(i8Ty, 0u32) }
        let i16Ty = unsafe { LLVMInt16TypeInContext(llvmCtx.raw) }
        let i8PtrNull = unsafe { LLVMConstNull(i8PtrTy) }

        let className = cgMod.GetEnumCaseClassName(chirEnumType, ctorIndex)
        let ttName = className + ".tt"
        let ctors = chirEnumType.GetEnumDef().GetConstructorInfos(builder: Some(cgCtx.GetCHIRBuilder()))
        CJC_ASSERT(ctorIndex >= 0 && ctorIndex < ctors.size)
        let paramTypes = ctors[ctorIndex].funcType.getOrThrow().GetParamTypes()
        let cgEnumType = (CGType.GetOrCreate(cgMod, chirEnumType) as CGEnumType).getOrThrow()
        var layout = EnumCtorLayout()
        if (cgEnumType.IsOptionLikeRef() || cgEnumType.IsOptionLikeT()) {
            layout = GenLayoutForReferenceType(ttName, className)
        } else if (cgEnumType.IsZeroSizeEnum()) {
            layout = GenLayoutForZeroSize()
        } else if (cgEnumType.IsTrivial()) {
            layout = GenLayoutForTrivial(ttName)
        } else {
            layout = GenLayoutForStructure(cgEnumType, paramTypes, ttName, className)
        }

        let genericParamIndicesMap = ArrayList<GenericType>()
        for (typeArg in GetGenericArgsFromCHIRType(chirEnumType)) {
            genericParamIndicesMap.add(typeArg.genericType)
        }
        let fieldsFns = if (cgEnumType.IsOptionLikeT()) {
            cgEnumType.GenFieldsFnsOfTypeTemplateForOptionLikeT(cgMod, ttName)
        } else {
            GenFieldsFnsOfTypeTemplate(cgMod, ttName, layout.fieldTypes, genericParamIndicesMap)
        }

        let typeTemplateVec = ArrayList<LLVMValueRef>()
        typeTemplateVec.add(cgMod.GenerateTypeNameConstantString(className, false))
        typeTemplateVec.add(unsafe { LLVMConstInt(i8Ty, 132u64, 0) })
        typeTemplateVec.add(unsafe { LLVMConstInt(i8Ty, 0u64, 0) })
        typeTemplateVec.add(unsafe { LLVMConstInt(i16Ty, UInt64(layout.fieldTypes.size), 0) })
        typeTemplateVec.add(GenTypeArgsNumOfTypeTemplate())
        typeTemplateVec.add(fieldsFns)
        typeTemplateVec.add(GenSuperFnOfTypeTemplate(ttName + ".superTiFn"))
        typeTemplateVec.add(i8PtrNull)
        typeTemplateVec.add(unsafe { LLVMConstNull(i8PtrTy) })
        typeTemplateVec.add(unsafe { LLVMConstNull(LLVMPointerType(CGType.GetOrCreateExtensionDefPtrType(llvmCtx), 0u32)) })
        typeTemplateVec.add(unsafe { LLVMConstInt(i16Ty, 0u64, 0) })
        if (!cgCtx.GetCompileOptions().disableReflection) {
            let mangledName = ctors[ctorIndex].annoInfo.GetAnnoFactoryFuncMangledName()
            LLVMSetGlobalMetadata(llvmCtx, tt, "Reflection", CreateReflectionMetadata(llvmCtx, mangledName))
        }
        unsafe {
            LLVMSetInitializer(tt, ConstNamedStruct(CGType.GetOrCreateTypeTemplateType(llvmCtx), typeTemplateVec))
        }
        addAttribute(tt, TYPE_TEMPLATE_ATTR)
    }

    private func GenTypeArgsNumOfTypeTemplate(): LLVMValueRef {
        return unsafe {
            LLVMConstInt(LLVMInt16TypeInContext(cgMod.GetLLVMContext().raw),
                UInt64(chirEnumType.GetGenericArgs().size), 0)
        }
    }

    private func GenSuperFnOfTypeTemplate(funcName: String): LLVMValueRef {
        let moduleHandle = cgMod.GetLLVMModule().getOrThrow()
        let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 0u32) }
        let argTypes = ArrayList<LLVMTypeRef>()
        argTypes.add(unsafe { LLVMInt32TypeInContext(cgMod.GetLLVMContext().raw) })
        argTypes.add(unsafe { LLVMPointerType(CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext()), 0u32) })
        let superTiFnType = BuildFunctionType(i8PtrTy, argTypes)
        var superTiFn = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(funcName) }.asResource()) {
            superTiFn = unsafe { LLVMAddFunction(moduleHandle.raw, nameCString.value, superTiFnType) }
        }
        unsafe {
            LLVMSetLinkage(superTiFn, LLVMLinkageValue(LLVMLinkage.Private))
            LLVMSetUnnamedAddress(superTiFn, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr))
        }
        AddFnAttr(superTiFn, "native-interface-fn")
        try (irBuilder = IRBuilder2(cgMod)) {
            let entryBB = irBuilder.CreateEntryBasicBlock(superTiFn, "entry")
            irBuilder.SetInsertPoint(entryBB)
            let tt = CGType.GetOrCreate(cgMod, chirEnumType).GetOrCreateTypeTemplate()
            let ti = irBuilder.CallGetTypeInfoIntrinsic(ArrayList<LLVMValueRef>(
                [tt, unsafe { LLVMGetParam(superTiFn, 0u32) }, unsafe { LLVMGetParam(superTiFn, 1u32) }]))
            irBuilder.CreateRet(irBuilder.CreateBitCast(ti, i8PtrTy))
        }
        return unsafe { LLVMConstBitCast(superTiFn, i8PtrTy) }
    }

    private func ComputeLLVMLayout(fields: ArrayList<Type>, tiName: String, className: String): EnumCtorLayout {
        let layout = EnumCtorLayout()
        for (field in fields) {
            layout.fieldTypes.add(field)
        }
        let layoutType = GetLLVMStructType(cgMod, layout.fieldTypes, GetClassObjLayoutName(className))
        layout.size = UInt32(cgMod.GetTypeSize(layoutType))
        layout.align = UInt32(cgMod.GetABITypeAlignment(layoutType))
        layout.offsets = CGCustomType.GenOffsetsArray(cgMod, tiName + ".offsets", layoutType)
        return layout
    }

    private func GenLayoutForReferenceType(tiName: String, className: String): EnumCtorLayout {
        let layout = EnumCtorLayout()
        layout.size = 8u32
        layout.align = 8u32
        let cgEnumType = (CGType.GetOrCreate(cgMod, chirEnumType) as CGEnumType).getOrThrow()
        layout.fieldTypes.add(cgCtx.GetCHIRBuilder().context.GetUnitTy())
        if (cgEnumType.IsOptionLikeT()) {
            layout.fieldTypes.add(CGType.GetRefTypeOfCHIRInt8(cgCtx.GetCHIRBuilder()))
        } else {
            let ctors = chirEnumType.GetEnumDef().GetConstructorInfos(builder: Some(cgCtx.GetCHIRBuilder()))
            let associatedValueType = if (cgEnumType.IsAntiOptionLike()) {
                ctors[1].funcType.getOrThrow().GetParamTypes()[0]
            } else {
                ctors[0].funcType.getOrThrow().GetParamTypes()[0]
            }
            layout.fieldTypes.add(associatedValueType)
        }
        let layoutType = GetLLVMStructType(cgMod, layout.fieldTypes, GetClassObjLayoutName(className))
        layout.offsets = CGCustomType.GenOffsetsArray(cgMod, tiName + ".offsets", layoutType)
        return layout
    }

    private func GenLayoutForZeroSize(): EnumCtorLayout {
        let layout = EnumCtorLayout()
        layout.size = 0u32
        layout.align = 1u32
        let i32Ty = unsafe { LLVMInt32TypeInContext(cgMod.GetLLVMContext().raw) }
        layout.offsets = unsafe { LLVMConstNull(LLVMPointerType(i32Ty, 0u32)) }
        return layout
    }

    private func GenLayoutForTrivial(tiName: String): EnumCtorLayout {
        let layout = EnumCtorLayout()
        let llvmCtx = cgMod.GetLLVMContext()
        let i32Ty = unsafe { LLVMInt32TypeInContext(llvmCtx.raw) }
        let i32ArrType = unsafe { LLVMArrayType(i32Ty, 1u32) }
        layout.size = 4u32
        layout.align = 4u32
        let typeInfoOfFields = GetOrInsertCodeGenGlobal(cgMod, tiName + ".offsets", i32ArrType)
        let offsetValues = ArrayList<LLVMValueRef>()
        offsetValues.add(unsafe { LLVMConstInt(i32Ty, 0u64, 0) })
        unsafe {
            LLVMSetInitializer(typeInfoOfFields, ConstArray(i32Ty, offsetValues))
            LLVMSetLinkage(typeInfoOfFields, LLVMLinkageValue(LLVMLinkage.Private))
            LLVMSetUnnamedAddress(typeInfoOfFields, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr))
            LLVMSetGlobalConstant(typeInfoOfFields, 1)
        }
        addAttribute(typeInfoOfFields, CJTI_OFFSETS_ATTR)
        layout.fieldTypes.add(cgCtx.GetCHIRBuilder().context.GetInt32Ty())
        layout.offsets = unsafe { LLVMConstBitCast(typeInfoOfFields, LLVMPointerType(i32Ty, 0u32)) }
        return layout
    }

    private func GenLayoutForStructure(cgEnumType: CGEnumType, paramTypes: ArrayList<Type>, tiName: String,
        className: String): EnumCtorLayout {
        let layout = EnumCtorLayout()
        let i32Ty = unsafe { LLVMInt32TypeInContext(cgMod.GetLLVMContext().raw) }
        let fields = ArrayList<Type>()
        if (cgEnumType.IsOptionLikeNonRef()) {
            fields.add(cgCtx.GetCHIRBuilder().context.GetBoolTy())
            fields.add(cgEnumType.GetAssociatedValueTypeOfOptionLike().getOrThrow())
        } else {
            if (cgEnumType.IsOptionLike()) {
                fields.add(cgCtx.GetCHIRBuilder().context.GetBoolTy())
            } else {
                fields.add(cgCtx.GetCHIRBuilder().context.GetInt32Ty())
            }
            for (paramType in paramTypes) {
                fields.add(paramType)
            }
        }
        if (!cgEnumType.IsAllAssociatedValuesAreNonRef()) {
            return ComputeLLVMLayout(fields, tiName, className)
        }
        for (field in fields) {
            layout.fieldTypes.add(field)
        }
        let nonRefLayout = CGEnumType.ComputeAssociatedNonRefLayout(cgMod, layout.fieldTypes)
        if (CGEnumType.NeedAndroidArm32AlignedEnumLayout(cgCtx.GetCompileOptions().target)) {
            layout.size = nonRefLayout.size
        }
        layout.align = nonRefLayout.align
        let offsets = ArrayList<LLVMValueRef>()
        var idx: Int64 = 0
        while (idx < layout.fieldTypes.size) {
            offsets.add(unsafe { LLVMConstInt(i32Ty, UInt64(nonRefLayout.offsets[idx]), 0) })
            idx++
        }
        let layoutType = GetLLVMStructType(cgMod, layout.fieldTypes, GetClassObjLayoutName(className))
        if (unsafe { LLVMCountStructElementTypes(layoutType) } == 0u32) {
            layout.offsets = unsafe { LLVMConstNull(LLVMPointerType(i32Ty, 0u32)) }
        } else {
            let i32ArrType = unsafe { LLVMArrayType(i32Ty, UInt32(layout.fieldTypes.size)) }
            let typeInfoOfFields = GetOrInsertCodeGenGlobal(cgMod, tiName + ".offsets", i32ArrType)
            unsafe {
                LLVMSetInitializer(typeInfoOfFields, ConstArray(i32Ty, offsets))
                LLVMSetLinkage(typeInfoOfFields, LLVMLinkageValue(LLVMLinkage.Private))
                LLVMSetUnnamedAddress(typeInfoOfFields, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr))
                LLVMSetGlobalConstant(typeInfoOfFields, 1)
            }
            addAttribute(typeInfoOfFields, CJTI_OFFSETS_ATTR)
            layout.offsets = unsafe { LLVMConstBitCast(typeInfoOfFields, LLVMPointerType(i32Ty, 0u32)) }
        }
        return layout
    }
}

private func CreateReflectionMetadata(context: LLVMContextHandle, mangledName: String): LLVMMetadataRef {
    let inner = ArrayList<LLVMMetadataRef>()
    inner.add(LLVMCreateMDString(context, "enumCtor"))
    inner.add(LLVMCreateMDString(context, mangledName))
    let outer = ArrayList<LLVMMetadataRef>()
    outer.add(LLVMCreateMDTuple(context, inner))
    return LLVMCreateMDTuple(context, outer)
}

private func LinkageOfCustomTypeDef(def: CustomTypeDef): LLVMLinkage {
    return CHIRLinkage2LLVMLinkage(def.Get<LinkTypeInfo, Linkage>())
}

private func BuildFunctionType(returnType: LLVMTypeRef, paramTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
    if (paramTypes.isEmpty()) {
        return unsafe { LLVMFunctionType(returnType, CPointer<LLVMTypeRef>(), 0u32, 0) }
    }
    var result = LLVMNullType()
    try (paramPtr = LibC.malloc<LLVMTypeRef>(count: paramTypes.size).asResource()) {
        var idx: Int64 = 0
        while (idx < paramTypes.size) {
            unsafe { (paramPtr.value + idx).write(paramTypes[idx]) }
            idx++
        }
        result = unsafe { LLVMFunctionType(returnType, paramPtr.value, UInt32(paramTypes.size), 0) }
    }
    return result
}

private func ConstNamedStruct(structType: LLVMTypeRef, values: ArrayList<LLVMValueRef>): LLVMValueRef {
    if (values.isEmpty()) {
        return unsafe { LLVMConstNamedStruct(structType, CPointer<LLVMValueRef>(), 0u32) }
    }
    var result = LLVMNullValue()
    try (valuePtr = LibC.malloc<LLVMValueRef>(count: values.size).asResource()) {
        var idx: Int64 = 0
        while (idx < values.size) {
            unsafe { (valuePtr.value + idx).write(values[idx]) }
            idx++
        }
        result = unsafe { LLVMConstNamedStruct(structType, valuePtr.value, UInt32(values.size)) }
    }
    return result
}

private func ConstArray(elementType: LLVMTypeRef, values: ArrayList<LLVMValueRef>): LLVMValueRef {
    if (values.isEmpty()) {
        return unsafe { LLVMConstArray(elementType, CPointer<LLVMValueRef>(), 0u32) }
    }
    var result = LLVMNullValue()
    try (valuePtr = LibC.malloc<LLVMValueRef>(count: values.size).asResource()) {
        var idx: Int64 = 0
        while (idx < values.size) {
            unsafe { (valuePtr.value + idx).write(values[idx]) }
            idx++
        }
        result = unsafe { LLVMConstArray(elementType, valuePtr.value, UInt32(values.size)) }
    }
    return result
}
