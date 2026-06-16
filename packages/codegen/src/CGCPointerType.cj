package cangjie_compiler::codegen

import cangjie_compiler::chir.Type

public class CGCPointerType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let typeArgs = chirType.GetTypeArgs()
        let elementTy = if (!typeArgs.isEmpty()) {
            CGType.GetOrCreate(cgMod, typeArgs[0]).GetLLVMType()
        } else {
            unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        }
        return unsafe { LLVMPointerType(elementTy, 0u32) }
    }

    protected override func GenContainedCGTypes(): Unit {
        let typeArgs = chirType.GetTypeArgs()
        if (!typeArgs.isEmpty()) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, typeArgs[0]))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        size = 8
        align = 8
    }
}
