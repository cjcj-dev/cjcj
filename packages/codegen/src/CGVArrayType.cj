package cangjie_compiler::codegen

import cangjie_compiler::chir.Type
import cangjie_compiler::chir.VArrayType

public class CGVArrayType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let elementTy = if (let Some(vArrayTy) <- (chirType as VArrayType)) {
            CGType.GetOrCreate(cgMod, vArrayTy.GetElementType()).GetLLVMType()
        } else {
            unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        }
        let elementCount = if (let Some(vArrayTy) <- (chirType as VArrayType)) {
            UInt32(vArrayTy.size)
        } else {
            0u32
        }
        return unsafe { LLVMArrayType(elementTy, elementCount) }
    }

    protected override func GenContainedCGTypes(): Unit {
        if (let Some(vArrayTy) <- (chirType as VArrayType)) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, vArrayTy.GetElementType()))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        if (let Some(vArrayTy) <- (chirType as VArrayType)) {
            let elementType = CGType.GetOrCreate(cgMod, vArrayTy.GetElementType())
            let elementSize = if (let Some(value) <- elementType.GetSize()) { value } else { 0 }
            let elementAlign = if (let Some(value) <- elementType.GetAlign()) { value } else { 1 }
            size = elementSize * Int64(vArrayTy.size)
            align = elementAlign
        } else {
            size = 0
            align = 1
        }
    }
}
