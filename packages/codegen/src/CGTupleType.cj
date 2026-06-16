package cangjie_compiler::codegen

import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TupleType

public class CGTupleType <: CGType {
    private let extraInfo: TypeExtraInfo

    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type, extraInfo: TypeExtraInfo) {
        super(cgMod, cgCtx, chirType)
        this.extraInfo = extraInfo
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        try (nameCString = unsafe { LibC.mallocCString(chirType.ToString() + ".Type") }.asResource()) {
            layoutType = unsafe { LLVMStructCreateNamed(cgCtx.GetLLVMContext().raw, nameCString.value) }
        }
        return GetLayoutType()
    }

    protected override func GenContainedCGTypes(): Unit {
        for (fieldTy in chirType.GetTypeArgs()) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, fieldTy, extraInfo: extraInfo))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        var total: Int64 = 0
        var maxAlign: Int64 = 1
        for (fieldCGType in GetContainedTypes()) {
            let fieldAlign = if (let Some(value) <- fieldCGType.GetAlign()) { value } else { 1 }
            let fieldSize = if (let Some(value) <- fieldCGType.GetSize()) { value } else { 0 }
            if (total % fieldAlign != 0) {
                total += fieldAlign - (total % fieldAlign)
            }
            total += fieldSize
            if (fieldAlign > maxAlign) { maxAlign = fieldAlign }
        }
        if (total % maxAlign != 0) {
            total += maxAlign - (total % maxAlign)
        }
        size = total
        align = maxAlign
    }
}
