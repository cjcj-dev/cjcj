package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.RefType
import cangjie_compiler::chir.RawArrayType
import cangjie_compiler::chir.Type
import cangjie_compiler::mangle.{DecimalToManglingNumber, GetTypeQualifiedName}

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

    public static func IsRefArray(elemType: CGType): Bool {
        let original = elemType.GetOriginal()
        if (elemType.GetSize().isNone() || original.IsCPointer() || original.IsCString() || original.IsCFunc()) {
            return false
        }
        return elemType.IsRefType()
    }

    public static func GenerateRefArrayLayoutType(cgCtx: CGContext): LLVMTypeRef {
        let i8Type = unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        let i8RefType = unsafe { LLVMPointerType(i8Type, 1u32) }
        return GenerateArrayLayoutTypeInfo(cgCtx, ARRAY_LAYOUT_PREFIX + "refArray", i8RefType)
    }

    public static func GenerateArrayLayoutType(cgMod: CGModule, rawArrayTy: RawArrayType): LLVMTypeRef {
        let elementCGType = CGType.GetOrCreate(cgMod, rawArrayTy.GetElementType())
        if (IsRefArray(elementCGType)) {
            return CGArrayType.GenerateRefArrayLayoutType(cgMod.GetCGContext())
        }
        let layoutName = ARRAY_LAYOUT_PREFIX + GetTypeNameByArrayType(cgMod, rawArrayTy)
        return GenerateArrayLayoutTypeInfo(cgMod.GetCGContext(), layoutName, elementCGType.GetLLVMType())
    }

    public static func GetTypeNameByArrayType(cgMod: CGModule, rawArrayTy: RawArrayType): String {
        let prefix = if (rawArrayTy.GetDims() > 1u64) {
            "A" + DecimalToManglingNumber(rawArrayTy.GetDims().toString())
        } else {
            ""
        }
        return prefix + GetTypeNameByArrayElementType(cgMod, rawArrayTy.GetElementType())
    }

    public static func GetTypeNameByArrayElementType(cgMod: CGModule, elemType: Type): String {
        let elementTy = if (let Some(refTy) <- (elemType as RefType)) {
            refTy.GetBaseType()
        } else {
            elemType
        }
        if (elementTy.IsEnum()) {
            if (let Some(enumCGType) <- (CGType.GetOrCreate(cgMod, elementTy) as CGEnumType)) {
                if (enumCGType.IsTrivial()) {
                    return "UInt32"
                }
            }
        }
        if (elemType.IsNominal()) {
            let customTy = (elemType as CustomType).getOrThrow()
            if (let Some(defTy) <- customTy.GetCustomTypeDef().GetType()) {
                if (CGType.GetOrCreate(cgMod, defTy).GetSize().isSome()) {
                    return GetTypeQualifiedName(defTy)
                }
            }
        }
        return GetTypeQualifiedName(elementTy)
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        let llvmType = unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
        let rawArrayTy = (chirType as RawArrayType).getOrThrow()
        let elemType = CGType.GetOrCreate(cgMod, rawArrayTy.GetElementType())
        if (elemType.GetSize().isNone()) {
            return llvmType
        }
        if (IsRefArray(elemType)) {
            layoutType = CGArrayType.GenerateRefArrayLayoutType(cgCtx)
            return llvmType
        }
        let layoutName = ARRAY_LAYOUT_PREFIX + GetTypeNameByArrayType(cgMod, rawArrayTy)
        layoutType = CGArrayType.GenerateArrayLayoutTypeInfo(cgCtx, layoutName, elemType.GetLLVMType())
        return llvmType
    }

    protected override func GenContainedCGTypes(): Unit {
        if (let Some(rawArrayTy) <- (chirType as RawArrayType)) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, rawArrayTy.GetElementType()))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        if (layoutType.isSome()) {
            let rawArrayTy = (chirType as RawArrayType) ?? throw IllegalArgumentException("expected raw array type")
            size = CGType.GetOrCreate(cgMod, rawArrayTy.GetElementType()).GetSize()
            align = 1
        }
    }
}
