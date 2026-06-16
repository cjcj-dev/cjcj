package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Type

public class CGTupleType <: CGType {
    private let extraInfo: TypeExtraInfo

    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type, extraInfo: TypeExtraInfo) {
        super(cgMod, cgCtx, chirType)
        this.extraInfo = extraInfo
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let typeName = chirType.ToString() + ".Type"
        let tupleLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), typeName)
        layoutType = tupleLayout
        if (!cgCtx.IsGeneratedStructType(typeName)) {
            let fieldTypes = ArrayList<LLVMTypeRef>()
            for (fieldTy in chirType.GetTypeArgs()) {
                fieldTypes.add(CGType.GetOrCreate(cgMod, fieldTy, extraInfo: extraInfo).GetLLVMType())
            }
            SetStructTypeBody(tupleLayout, fieldTypes)
            cgCtx.AddGeneratedStructType(typeName)
        }
        return tupleLayout
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
