package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.Type

public class CGStructType <: CGCustomType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let layoutName = STRUCT_TYPE_PREFIX + chirType.ToString()
        let structLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        layoutType = structLayout
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            let fieldTypes = ArrayList<LLVMTypeRef>()
            if (let Some(customTy) <- (chirType as CustomType)) {
                for (member in customTy.GetCustomTypeDef().GetInstanceVars()) {
                    if (!member.isStatic) {
                        fieldTypes.add(CGType.GetOrCreate(cgMod, member.ty).GetLLVMType())
                    }
                }
            }
            SetStructTypeBody(structLayout, fieldTypes)
            cgCtx.AddGeneratedStructType(layoutName)
        }
        return structLayout
    }

    protected override func GenContainedCGTypes(): Unit {
        if (let Some(customTy) <- (chirType as CustomType)) {
            for (member in customTy.GetCustomTypeDef().GetInstanceVars()) {
                if (!member.isStatic) {
                    containedCGTypes.add(CGType.GetOrCreate(cgMod, member.ty))
                }
            }
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
