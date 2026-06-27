package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.IntType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind

public class CGCStringType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let int8Ty = unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        let llvmType = unsafe { LLVMPointerType(int8Ty, 0u32) }
        // Mirror C++ CGCStringType::GenLLVMType (CGCStringType.cpp:21-23): wrap the pointer in a
        // "CString.Type" layout struct and record it as the layout type, so the generated TypeInfo
        // carries a GC layout. Without it, passing a CString through a generic type parameter emits an
        // llvm.cj.alloca.generic whose TypeInfo has a null layout type (rejected by the cangjie pass).
        let layoutName = "CString.Type"
        let layout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            let body = ArrayList<LLVMTypeRef>()
            body.add(llvmType)
            SetStructTypeBody(layout, body)
            cgCtx.AddGeneratedStructType(layoutName)
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
