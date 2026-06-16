package cangjie_compiler::codegen

import cangjie_compiler::chir.RefType
import cangjie_compiler::chir.Type

public class CGRefType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type, addrspace: UInt32) {
        super(cgMod, cgCtx, chirType, cgTypeKind: CGTypeKind.CG_REF)
        this.addrspace = addrspace
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let baseTy = if (let Some(refTy) <- (chirType as RefType)) {
            CGType.GetOrCreate(cgMod, refTy.GetBaseType()).GetLLVMType()
        } else {
            unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        }
        return unsafe { LLVMPointerType(baseTy, addrspace) }
    }

    protected override func GenContainedCGTypes(): Unit {
        if (let Some(refTy) <- (chirType as RefType)) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, refTy.GetBaseType()))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        size = 8
        align = 8
    }
}
