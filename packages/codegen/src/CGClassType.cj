package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.Type

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
        let layoutName = GetClassObjLayoutName(chirType.ToString())
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
                for (fieldTy in customTy.GetInstantiatedMemberTys()) {
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
            for (fieldTy in customTy.GetInstantiatedMemberTys()) {
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
}
