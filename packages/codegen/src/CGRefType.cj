package cangjie_compiler::codegen

import cangjie_compiler::chir.RefType
import cangjie_compiler::chir.Type
import cangjie_compiler::utils.StaticCast

public class CGRefType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type, addrspace: UInt32) {
        super(cgMod, cgCtx, chirType, cgTypeKind: CGTypeKind.CG_REF)
        this.addrspace = addrspace
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        if (let Some(rawType) <- llvmType) {
            return rawType
        }
        let baseType = StaticCast<RefType>(chirType).GetBaseType()
        if (baseType.IsClass() || baseType.IsRawArray() || baseType.IsBox()) {
            return CGType.GetRefType(cgCtx.GetLLVMContext())
        }
        let baseCGType = CGType.GetOrCreate(cgMod, baseType)
        if (baseCGType.GetSize().isNone() && !baseType.IsGeneric() && addrspace == 1u32) {
            return unsafe {
                LLVMPointerType(LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw), 1u32)
            }
        }
        return unsafe { LLVMPointerType(baseCGType.GetLLVMType(), addrspace) }
    }

    protected override func GenContainedCGTypes(): Unit {
        let refTy = StaticCast<RefType>(chirType)
        containedCGTypes.add(CGType.GetOrCreate(cgMod, refTy.GetBaseType()))
    }

    protected override func CalculateSizeAndAlign(): Unit {
        let rawType = llvmType.getOrThrow()
        size = Int64(cgMod.GetTypeSize(rawType))
        align = Int64(cgMod.GetABITypeAlignment(rawType))
    }
}
