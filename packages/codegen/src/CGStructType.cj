package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.Type

public class CGStructType <: CGCustomType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        if (chirType.IsString()) {
            let stringLayout = cgCtx.GetCjStringType()
            layoutType = stringLayout
            llvmType = stringLayout
            return stringLayout
        }
        let layoutName = STRUCT_TYPE_PREFIX + chirType.ToString()
        let structLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        layoutType = structLayout
        llvmType = structLayout
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            cgCtx.AddGeneratedStructType(layoutName)
            let fieldTypes = ArrayList<LLVMTypeRef>()
            if (let Some(customTy) <- (chirType as CustomType)) {
                for (member in customTy.GetCustomTypeDef().GetInstanceVars()) {
                    if (!member.isStatic) {
                        fieldTypes.add(CGType.GetOrCreate(cgMod, member.ty).GetLLVMType())
                    }
                }
            }
            SetStructTypeBody(structLayout, fieldTypes)
        }
        return structLayout
    }

    protected override func GenContainedCGTypes(): Unit {
        if (chirType.IsString()) {
            return
        }
        if (let Some(customTy) <- (chirType as CustomType)) {
            for (member in customTy.GetCustomTypeDef().GetInstanceVars()) {
                if (!member.isStatic) {
                    containedCGTypes.add(CGType.GetOrCreate(cgMod, member.ty))
                }
            }
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        if (chirType.IsString()) {
            if (let Some(rawLayout) <- layoutType) {
                size = Int64(cgMod.GetTypeSize(rawLayout))
                align = Int64(cgMod.GetABITypeAlignment(rawLayout))
            }
            return
        }
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
