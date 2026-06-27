package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.IntType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind

public class CGCPointerType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        // C++ CGCPointerType::GenLLVMType (CGCPointerType.cpp:13-26): CPointer<T> lowers to a UNIFORM
        // i8* regardless of the element type, wrapped in a "CPointer.Type" layout struct. Lowering it to
        // a pointer to the element's LLVM type instead made CPointer<T> vary by T (i8** for CString,
        // i32* for Int32, ...), which broke the shared (def-keyed) struct layout of generic containers
        // such as CPointerResource<T>: the layout's GEP slot and a field load computed from a different
        // instantiation's element type disagreed (load <T>, i8*** %gep).
        let int8Ty = unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        let llvmType = unsafe { LLVMPointerType(int8Ty, 0u32) }
        let layoutName = "CPointer.Type"
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
        // C++ CGCPointerType::GenContainedCGTypes (CGCPointerType.cpp:28-31): the single contained type
        // is always Int8, never the element type.
        containedCGTypes.add(CGType.GetOrCreate(cgMod, IntType(TypeKind.TYPE_INT8)))
    }

    protected override func CalculateSizeAndAlign(): Unit {
        size = 8
        align = 8
    }
}
