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
        let layoutName = GetClassObjLayoutName(chirType.ToString())
        let layout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        layoutType = layout
        llvmType = unsafe { LLVMPointerType(layout, 1u32) }
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            cgCtx.AddGeneratedStructType(layoutName)
            let fieldTypes = ArrayList<LLVMTypeRef>()
            if (let Some(customTy) <- (chirType as CustomType)) {
                for (member in customTy.GetCustomTypeDef().GetInstanceVars()) {
                    if (!member.isStatic) {
                        fieldTypes.add(CGType.GetOrCreate(cgMod, member.ty).GetLLVMType())
                    }
                }
            }
            SetStructTypeBody(layout, fieldTypes)
        }
        return unsafe { LLVMPointerType(layout, 1u32) }
    }

    protected override func GenContainedCGTypes(): Unit {
        if (let Some(customTy) <- (chirType as CustomType)) {
            for (member in customTy.GetCustomTypeDef().GetInstanceVars()) {
                if (!member.isStatic) {
                    containedCGTypes.add(CGType.GetOrCreate(cgMod, member.ty))
                }
            }
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        size = 8
        align = 8
    }
}
