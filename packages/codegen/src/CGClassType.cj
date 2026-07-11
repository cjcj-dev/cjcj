package cjcj::codegen

import std.collection.*
import cjcj::chir.Attribute
import cjcj::chir.ClassType
import cjcj::chir.CustomType
import cjcj::chir.Type
import cjcj::chir.GetTypeQualifiedName

public class CGClassType <: CGCustomType {
    private var numOfAllFields: Int64 = 0

    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType, cgTypeKind: CGTypeKind.CG_CLASS)
    }

    public func GetNumOfAllFields(): Int64 { return numOfAllFields }

    protected override func GenLLVMType(): LLVMTypeRef {
        let i8Type = unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        if (!IsSized()) {
            return i8Type
        }
        let classType = (chirType as ClassType).getOrThrow()
        let layoutName = if (let Some(defTy) <- classType.GetClassDef().GetType()) {
            if (chirType != defTy && CGType.GetOrCreate(cgMod, defTy).GetSize().isSome()) {
                GetClassObjLayoutName(GetTypeQualifiedName(defTy))
            } else {
                GetClassObjLayoutName(GetTypeQualifiedName(classType))
            }
        } else {
            GetClassObjLayoutName(GetTypeQualifiedName(classType))
        }
        let layout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        layoutType = layout
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            cgCtx.AddGeneratedStructType(layoutName)
            let fieldTypes = ArrayList<LLVMTypeRef>()
            if (IsAutoEnvType(chirType)) {
                let i8PtrTy = unsafe { LLVMPointerType(i8Type, 0u32) }
                fieldTypes.add(i8PtrTy)
                fieldTypes.add(i8PtrTy)
            }
            if (let Some(customTy) <- (chirType as CustomType)) {
                for (fieldTy in customTy.GetInstantiatedMemberTys(cgMod.GetCGContext().GetCHIRBuilder())) {
                    fieldTypes.add(CGType.GetOrCreate(cgMod, fieldTy).GetLLVMType())
                }
            }
            SetStructTypeBody(layout, fieldTypes)
        }
        return i8Type
    }

    protected override func GenContainedCGTypes(): Unit {
        if (IsAutoEnvType(chirType)) {
            let pointerTy = cgMod.GetCGContext().GetCHIRBuilder().context.GetCPointerTy(
                cgMod.GetCGContext().GetCHIRBuilder().context.GetInt8Ty())
            containedCGTypes.add(CGType.GetOrCreate(cgMod, pointerTy))
            containedCGTypes.add(CGType.GetOrCreate(cgMod, pointerTy))
        }
        if (let Some(customTy) <- (chirType as CustomType)) {
            for (fieldTy in customTy.GetInstantiatedMemberTys(cgMod.GetCGContext().GetCHIRBuilder())) {
                containedCGTypes.add(CGType.GetOrCreate(cgMod, fieldTy))
            }
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        if (let Some(rawLayout) <- layoutType) {
            size = Int64(cgMod.GetTypeSize(rawLayout))
            align = Int64(cgMod.GetABITypeAlignment(rawLayout))
            return
        }
        size = None
        align = None
    }

    protected override func PreActionOfGenTypeTemplate(): Unit {
        let classDef = (chirType as ClassType).getOrThrow().GetClassDef()
        if (let Some(rawTypeTemplate) <- typeTemplate) {
            if (IsCoreFutureClass(classDef)) {
                addAttribute(rawTypeTemplate, classDef.GetSrcCodeIdentifier())
            }
            if (classDef.GetFinalizer().isSome()) {
                addAttribute(rawTypeTemplate, GC_FINALIZER_ATTR)
            }
        }
    }

    protected override func PreActionOfGenTypeInfo(): Unit {
        let classDef = (chirType as ClassType).getOrThrow().GetClassDef()
        if (let Some(rawTypeInfo) <- typeInfo) {
            if (IsCoreFutureClass(classDef) || IsSyncRelatedClass(classDef)) {
                addAttribute(rawTypeInfo, classDef.GetSrcCodeIdentifier())
            }
            if (classDef.GetFinalizer().isSome()) {
                addAttribute(rawTypeInfo, GC_FINALIZER_ATTR)
            }
        }
    }

    protected override func PostActionOfGenTypeInfo(): Unit {
        let classDef = (chirType as ClassType).getOrThrow().GetClassDef()
        if (!(classDef.TestAttr(Attribute.COMPILER_ADD) || !IsModifiableClass(chirType) || !IsStaticGI())) {
            return
        }
        if (let Some(rawTypeInfo) <- typeInfo) {
            addAttribute(rawTypeInfo, HAS_EXT_PART)
            let llvmCtx = cgCtx.GetLLVMContext()
            let extPartType = CGType.GetClassTTExtTypeVer1(llvmCtx)
            let typeInfoName = LLVMCStringToString(unsafe { LLVMGetValueName(rawTypeInfo) }) ?? ""
            let extPart = GetOrInsertCodeGenGlobal(cgMod, "ext_" + typeInfoName, extPartType)
            let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(llvmCtx.raw), 0u32) }
            let i16Type = unsafe { LLVMInt16TypeInContext(llvmCtx.raw) }
            let i32Type = unsafe { LLVMInt32TypeInContext(llvmCtx.raw) }
            let i8Type = unsafe { LLVMInt8TypeInContext(llvmCtx.raw) }
            let values = ArrayList<LLVMValueRef>()
            values.add(unsafe { LLVMConstBitCast(rawTypeInfo, i8PtrType) })
            values.add(unsafe { LLVMConstInt(i16Type, 1u64, 0) })
            values.add(unsafe { LLVMConstInt(i32Type, cgMod.GetTypeSize(extPartType), 0) })
            values.add(unsafe { LLVMConstInt(i8Type, 1u64, 0) })
            try (valuePtr = LibC.malloc<LLVMValueRef>(count: values.size).asResource()) {
                var idx: Int64 = 0
                while (idx < values.size) {
                    unsafe { (valuePtr.value + idx).write(values[idx]) }
                    idx++
                }
                unsafe {
                    LLVMSetGlobalConstant(extPart, 1)
                    LLVMSetUnnamedAddress(extPart, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr))
                    LLVMSetInitializer(extPart, LLVMConstNamedStruct(extPartType, valuePtr.value, UInt32(values.size)))
                    LLVMSetLinkage(extPart, LLVMLinkageValue(LLVMLinkage.Private))
                }
            }
            addAttribute(extPart, GC_TI_EXT_ATTR)
            cgCtx.AddLLVMUsedVars("ext_" + typeInfoName)
        }
    }
}
