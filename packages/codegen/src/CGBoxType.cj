package cangjie_compiler::codegen

import cangjie_compiler::chir.BoxType
import cangjie_compiler::chir.Type

public class CGBoxType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let payloadTy = if (let Some(boxTy) <- (chirType as BoxType)) {
            CGType.GetOrCreate(cgMod, boxTy.GetBaseType()).GetLLVMType()
        } else {
            unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        }
        return unsafe { LLVMPointerType(payloadTy, 1u32) }
    }

    protected override func GenContainedCGTypes(): Unit {
        if (let Some(boxTy) <- (chirType as BoxType)) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, boxTy.GetBaseType()))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        size = 8
        align = 8
    }
}
