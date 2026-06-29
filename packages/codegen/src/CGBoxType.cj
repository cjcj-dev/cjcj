package cangjie_compiler::codegen

import cangjie_compiler::chir.BoxType
import cangjie_compiler::chir.Type

public class CGBoxType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType, cgTypeKind: CGTypeKind.CG_REF)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        if (let Some(existingType) <- llvmType) {
            return existingType
        }
        return unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
    }

    protected override func GenContainedCGTypes(): Unit {
        let boxTy = (chirType as BoxType).getOrThrow()
        containedCGTypes.add(CGType.GetOrCreate(cgMod, boxTy.GetBaseType()))
    }

    protected override func CalculateSizeAndAlign(): Unit {
        let rawType = GetLLVMType()
        size = Int64(cgMod.GetTypeSize(rawType))
        align = Int64(cgMod.GetABITypeAlignment(rawType))
    }
}
