package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.NumericType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind
import cangjie_compiler::chir.TypeKindIndex
import cangjie_compiler::option.ArchType
import cangjie_compiler::utils.{CJC_ASSERT, CJC_ASSERT_WITH_MSG}

public class CGPrimitiveType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType, cgTypeKind: CGTypeKind.CG_PRIMITIVE)
        CJC_ASSERT(TypeKindIndex(chirType.GetTypeKind()) >= TypeKindIndex(TypeKind.TYPE_INT8) &&
            TypeKindIndex(chirType.GetTypeKind()) <= TypeKindIndex(TypeKind.TYPE_VOID))
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        if (let Some(existingType) <- llvmType) {
            return existingType
        }
        let context = cgCtx.GetLLVMContext().raw
        var generated = LLVMNullType()
        match (chirType.GetTypeKind()) {
            case TypeKind.TYPE_INT8 | TypeKind.TYPE_UINT8 =>
                generated = unsafe { LLVMInt8TypeInContext(context) }
            case TypeKind.TYPE_INT16 | TypeKind.TYPE_UINT16 =>
                generated = unsafe { LLVMInt16TypeInContext(context) }
            case TypeKind.TYPE_INT32 | TypeKind.TYPE_UINT32 | TypeKind.TYPE_RUNE =>
                generated = unsafe { LLVMInt32TypeInContext(context) }
            case TypeKind.TYPE_INT64 | TypeKind.TYPE_UINT64 =>
                generated = unsafe { LLVMInt64TypeInContext(context) }
            case TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_UINT_NATIVE =>
                let archType = cgCtx.GetCompileOptions().target.GetArchType()
                if (archType == ArchType.X86_64 || archType == ArchType.AARCH64) {
                    generated = unsafe { LLVMInt64TypeInContext(context) }
                } else if (archType == ArchType.ARM32) {
                    generated = unsafe { LLVMInt32TypeInContext(context) }
                } else {
                    CJC_ASSERT_WITH_MSG(false, "Unsupported ArchType.")
                    return LLVMNullType()
                }
            case TypeKind.TYPE_FLOAT16 =>
                generated = unsafe { LLVMHalfTypeInContext(context) }
            case TypeKind.TYPE_FLOAT32 =>
                generated = unsafe { LLVMFloatTypeInContext(context) }
            case TypeKind.TYPE_FLOAT64 =>
                generated = unsafe { LLVMDoubleTypeInContext(context) }
            case TypeKind.TYPE_BOOLEAN =>
                generated = unsafe { LLVMInt1TypeInContext(context) }
            case TypeKind.TYPE_UNIT | TypeKind.TYPE_NOTHING =>
                generated = CGType.GetUnitType(cgCtx.GetLLVMContext())
            case TypeKind.TYPE_VOID =>
                generated = unsafe { LLVMVoidTypeInContext(context) }
                let voidLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), UNIT_TYPE_STR)
                if (!cgCtx.IsGeneratedStructType(UNIT_TYPE_STR)) {
                    SetStructTypeBody(voidLayout, ArrayList<LLVMTypeRef>())
                    cgCtx.AddGeneratedStructType(UNIT_TYPE_STR)
                }
                layoutType = voidLayout
                return generated
            case _ =>
                CJC_ASSERT_WITH_MSG(false, "Should not reach here: unsupported chir type")
                return LLVMNullType()
        }
        let layoutName = chirType.ToString() + ".Type"
        let layout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            let body = ArrayList<LLVMTypeRef>()
            if (!chirType.IsUnit()) {
                body.add(generated)
            }
            SetStructTypeBody(layout, body)
            cgCtx.AddGeneratedStructType(layoutName)
        }
        layoutType = layout
        return generated
    }

    protected override func CalculateSizeAndAlign(): Unit {
        if (let Some(numTy) <- (chirType as NumericType)) {
            size = Int64(numTy.GetBitness() / 8u64)
        } else if (chirType.IsRune()) {
            size = 4
        } else if (chirType.IsBoolean()) {
            size = 1
        } else if (chirType.IsUnit() || chirType.IsNothing() || chirType.IsVoid()) {
            size = 0
        } else {
            CJC_ASSERT_WITH_MSG(false, "Unsupported type")
            size = None
        }
        if (let Some(sizeValue) <- size) {
            align = if (sizeValue == 0) { 1 } else { sizeValue }
        } else {
            align = None
        }
    }
}
