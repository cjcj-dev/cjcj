package cangjie_compiler::codegen

import cangjie_compiler::chir.RefType
import cangjie_compiler::chir.Type

public class CGRefType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type, addrspace: UInt32) {
        super(cgMod, cgCtx, chirType, cgTypeKind: CGTypeKind.CG_REF)
        this.addrspace = addrspace
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        if (let Some(refTy) <- (chirType as RefType)) {
            let baseType = refTy.GetBaseType()
            let baseCGType = CGType.GetOrCreate(cgMod, baseType)
            if (baseType.IsClass() || baseType.IsRawArray() || baseType.IsBox()) {
                return CGType.GetRefType(cgCtx.GetLLVMContext())
            }
            return unsafe { LLVMPointerType(baseCGType.GetLLVMType(), addrspace) }
        } else {
            return unsafe {
                LLVMPointerType(LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw), addrspace)
            }
        }
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
