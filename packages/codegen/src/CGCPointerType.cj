package cjcj::codegen

import std.collection.*
import cjcj::chir.IntType
import cjcj::chir.Type
import cjcj::chir.TypeKind

public class CGCPointerType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let int8Ty = unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        let llvmType = unsafe { LLVMPointerType(int8Ty, 0u32) }
        let layoutName = "CPointer.Type"
        let layout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        if (unsafe { LLVMCountStructElementTypes(layout) } == 0u32) {
            let body = ArrayList<LLVMTypeRef>()
            body.add(llvmType)
            SetStructTypeBody(layout, body)
        }
        layoutType = layout
        return llvmType
    }

    protected override func GenContainedCGTypes(): Unit {
        containedCGTypes.add(CGType.GetOrCreate(cgMod, IntType(TypeKind.TYPE_INT8)))
    }

    protected override func CalculateSizeAndAlign(): Unit {
        size = 8
        align = 8
    }
}
