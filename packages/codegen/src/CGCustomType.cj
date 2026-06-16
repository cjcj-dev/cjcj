package cangjie_compiler::codegen

import cangjie_compiler::chir.Type

public open class CGCustomType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type, cgTypeKind!: CGTypeKind = CGTypeKind.OTHERS) {
        super(cgMod, cgCtx, chirType, cgTypeKind: cgTypeKind)
    }

    protected open override func GenLLVMType(): LLVMTypeRef {
        let layoutName = STRUCT_TYPE_PREFIX + chirType.ToString()
        let customLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        layoutType = customLayout
        return customLayout
    }

    protected open override func GenContainedCGTypes(): Unit {
        for (argTy in chirType.GetTypeArgs()) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, argTy))
        }
    }

    protected open override func CalculateSizeAndAlign(): Unit {
        size = None
        align = None
    }
}
