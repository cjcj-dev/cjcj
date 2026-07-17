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
        if (let Some(arrayType) <- llvmType) {
            size = Int64(UInt32(cgMod.GetTypeSize(arrayType) & UInt64(UInt32.Max)))
            align = Int64(cgMod.GetABITypeAlignment(arrayType))
        }
    }
}
