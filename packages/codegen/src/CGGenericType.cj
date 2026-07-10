package cjcj::codegen

import cjcj::chir.Type

public class CGGenericType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        return CGType.GetRefType(cgMod.GetLLVMContext())
    }

    protected override func CalculateSizeAndAlign(): Unit {
        size = None
        align = None
    }
}
