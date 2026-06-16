package cangjie_compiler::codegen

import cangjie_compiler::chir.IntType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind

public class CGCStringType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let int8Ty = unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        return unsafe { LLVMPointerType(int8Ty, 0u32) }
    }

    protected override func GenContainedCGTypes(): Unit {
        containedCGTypes.add(CGType.GetOrCreate(cgMod, IntType(TypeKind.TYPE_INT8)))
    }

    protected override func CalculateSizeAndAlign(): Unit {
        size = 8
        align = 8
    }
}
