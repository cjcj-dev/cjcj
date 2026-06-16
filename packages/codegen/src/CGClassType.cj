package cangjie_compiler::codegen

import cangjie_compiler::chir.Type

public class CGClassType <: CGCustomType {
    private var numOfAllFields: Int64 = 0

    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType, cgTypeKind: CGTypeKind.CG_CLASS)
    }

    public func GetNumOfAllFields(): Int64 { return numOfAllFields }

    protected override func GenLLVMType(): LLVMTypeRef {
        let layout = super.GenLLVMType()
        return unsafe { LLVMPointerType(layout, 1u32) }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        size = 8
        align = 8
    }
}
