package cangjie_compiler::codegen

import cangjie_compiler::chir.RawArrayType
import cangjie_compiler::chir.Type

public class CGArrayType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    public func GetElementCGType(): Option<CGType> {
        return GetPointerElementType()
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let elementTy = if (let Some(rawArrayTy) <- (chirType as RawArrayType)) {
            CGType.GetOrCreate(cgMod, rawArrayTy.GetElementType()).GetLLVMType()
        } else {
            unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        }
        let layoutName = ARRAY_LAYOUT_PREFIX + chirType.ToString()
        try (nameCString = unsafe { LibC.mallocCString(layoutName) }.asResource()) {
            layoutType = unsafe { LLVMStructCreateNamed(cgCtx.GetLLVMContext().raw, nameCString.value) }
        }
        return unsafe { LLVMPointerType(elementTy, 1u32) }
    }

    protected override func GenContainedCGTypes(): Unit {
        if (let Some(rawArrayTy) <- (chirType as RawArrayType)) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, rawArrayTy.GetElementType()))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        size = 8
        align = 8
    }
}
