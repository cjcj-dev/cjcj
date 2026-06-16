package cangjie_compiler::codegen

import cangjie_compiler::chir.Type

public class CGThisType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        return LLVMNullType()
    }

    protected override func CalculateSizeAndAlign(): Unit {
        size = None
        align = None
    }
}
