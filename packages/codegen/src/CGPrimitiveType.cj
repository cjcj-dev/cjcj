package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.NumericType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind
import cangjie_compiler::option.ArchType

public class CGPrimitiveType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType, cgTypeKind: CGTypeKind.CG_PRIMITIVE)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let context = cgCtx.GetLLVMContext().raw
        let generated = match (chirType.GetTypeKind()) {
            case TypeKind.TYPE_INT8 | TypeKind.TYPE_UINT8 => unsafe { LLVMInt8TypeInContext(context) }
            case TypeKind.TYPE_INT16 | TypeKind.TYPE_UINT16 => unsafe { LLVMInt16TypeInContext(context) }
            case TypeKind.TYPE_INT32 | TypeKind.TYPE_UINT32 | TypeKind.TYPE_RUNE => unsafe { LLVMInt32TypeInContext(context) }
            case TypeKind.TYPE_INT64 | TypeKind.TYPE_UINT64 => unsafe { LLVMInt64TypeInContext(context) }
            case TypeKind.TYPE_INT_NATIVE | TypeKind.TYPE_UINT_NATIVE =>
                if (cgCtx.GetCompileOptions().target.GetArchType() == ArchType.ARM32) {
                    unsafe { LLVMInt32TypeInContext(context) }
                } else {
                    unsafe { LLVMInt64TypeInContext(context) }
                }
            case TypeKind.TYPE_FLOAT16 => unsafe { LLVMHalfTypeInContext(context) }
            case TypeKind.TYPE_FLOAT32 => unsafe { LLVMFloatTypeInContext(context) }
            case TypeKind.TYPE_FLOAT64 => unsafe { LLVMDoubleTypeInContext(context) }
            case TypeKind.TYPE_BOOLEAN => unsafe { LLVMInt1TypeInContext(context) }
            case TypeKind.TYPE_UNIT | TypeKind.TYPE_NOTHING => CGType.GetUnitType(cgCtx.GetLLVMContext())
            case TypeKind.TYPE_VOID => unsafe { LLVMVoidTypeInContext(context) }
            case _ => LLVMNullType()
        }
        let layoutName = if (chirType.IsVoid()) { UNIT_TYPE_STR } else { chirType.ToString() + ".Type" }
        let layout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            let body = ArrayList<LLVMTypeRef>()
            if (!chirType.IsVoid() && !chirType.IsUnit() && !chirType.IsNothing()) {
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
            size = None
        }
        if (let Some(sizeValue) <- size) {
            align = if (sizeValue == 0) { 1 } else { sizeValue }
        } else {
            align = None
        }
    }
}
