package cjcj::codegen

import std.collection.*
import cjcj::chir.MangleType
import cjcj::chir.Type
import cjcj::chir.VArrayType

public class CGVArrayType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let elementTy = if (let Some(vArrayTy) <- (chirType as VArrayType)) {
            CGType.GetOrCreate(cgMod, vArrayTy.GetElementType()).GetLLVMType()
        } else {
            unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        }
        let elementCount = if (let Some(vArrayTy) <- (chirType as VArrayType)) {
            UInt64(vArrayTy.size)
        } else {
            0u64
        }
        let arrayType = unsafe { LLVMSelfhostArrayType64(elementTy, elementCount) }
        let layoutName = if (let Some(vArrayTy) <- (chirType as VArrayType)) {
            "VArray.${vArrayTy.size}" + MangleType(vArrayTy.GetElementType())
        } else {
            "VArray.0Invalid"
        }
        let varrayLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        layoutType = varrayLayout
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            let body = ArrayList<LLVMTypeRef>()
            body.add(arrayType)
            SetStructTypeBody(varrayLayout, body)
            cgCtx.AddGeneratedStructType(layoutName)
        }
        return arrayType
    }

    protected override func GenContainedCGTypes(): Unit {
        if (let Some(vArrayTy) <- (chirType as VArrayType)) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, vArrayTy.GetElementType()))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        if (let Some(vArrayTy) <- (chirType as VArrayType)) {
            let elementType = CGType.GetOrCreate(cgMod, vArrayTy.GetElementType())
            let elementSize = if (let Some(value) <- elementType.GetSize()) { value } else { 0 }
            let elementAlign = if (let Some(value) <- elementType.GetAlign()) { value } else { 1 }
            size = elementSize * Int64(vArrayTy.size)
            align = elementAlign
        } else {
            size = 0
            align = 1
        }
    }
}
