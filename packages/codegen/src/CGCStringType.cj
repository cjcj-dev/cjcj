package cjcj::codegen

import std.collection.*
import cjcj::chir.IntType
import cjcj::chir.Type
import cjcj::chir.TypeKind

public class CGCStringType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let int8Ty = unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        let llvmType = unsafe { LLVMPointerType(int8Ty, 0u32) }
        let layoutName = "CString.Type"
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
        // A C pointer occupies one target pointer slot (4 bytes on wasm32/ARM32).
        let ptrSize: Int64 = if (cgMod.GetCGContext().GetCompileOptions().target.Is32BitPointer()) { 4 } else { 8 }
        size = ptrSize
        align = ptrSize
    }
}
