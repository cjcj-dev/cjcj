package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.RawArrayType
import cangjie_compiler::chir.Type

public class CGArrayType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    public func GetElementCGType(): Option<CGType> {
        return GetPointerElementType()
    }

    public static func GenerateArrayLayoutTypeInfo(cgCtx: CGContext, layoutName: String,
        elementType: LLVMTypeRef): LLVMTypeRef {
        let result = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            let body = ArrayList<LLVMTypeRef>()
            body.add(CGType.GetArrayBaseType(cgCtx))
            body.add(unsafe { LLVMArrayType(elementType, 0u32) })
            SetStructTypeBody(result, body)
            cgCtx.AddGeneratedStructType(layoutName)
        }
        return result
    }

    public static func GenerateArrayLayoutType(cgMod: CGModule, rawArrayTy: RawArrayType): LLVMTypeRef {
        let elementCGType = CGType.GetOrCreate(cgMod, rawArrayTy.GetElementType())
        let layoutName = ARRAY_LAYOUT_PREFIX + rawArrayTy.ToString()
        return GenerateArrayLayoutTypeInfo(cgMod.GetCGContext(), layoutName, elementCGType.GetLLVMType())
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let elementTy = if (let Some(rawArrayTy) <- (chirType as RawArrayType)) {
            CGType.GetOrCreate(cgMod, rawArrayTy.GetElementType()).GetLLVMType()
        } else {
            unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        }
        let layoutName = ARRAY_LAYOUT_PREFIX + chirType.ToString()
        layoutType = CGArrayType.GenerateArrayLayoutTypeInfo(cgCtx, layoutName, elementTy)
        return unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
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
