package cangjie_compiler::codegen

import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.Type
import cangjie_compiler::utils.StaticCast

public open class CGCustomType <: CGType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type, cgTypeKind!: CGTypeKind = CGTypeKind.OTHERS) {
        super(cgMod, cgCtx, chirType, cgTypeKind: cgTypeKind)
    }

    protected open override func GenLLVMType(): LLVMTypeRef {
        let layoutName = STRUCT_TYPE_PREFIX + chirType.ToString()
        let customLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        layoutType = customLayout
        return customLayout
    }

    protected open override func GenContainedCGTypes(): Unit {
        for (argTy in chirType.GetTypeArgs()) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, argTy))
        }
    }

    protected open override func CalculateSizeAndAlign(): Unit {
        if (!IsSized()) {
            size = None
            align = None
            return
        }
        if (let Some(rawLayout) <- layoutType) {
            if (!rawLayout.isNull() && unsafe { LLVMGetTypeKind(rawLayout) } == 10) {
                size = Int64(cgMod.GetTypeSize(rawLayout))
                align = Int64(cgMod.GetABITypeAlignment(rawLayout))
                return
            }
        }
        size = None
        align = None
    }

    protected func IsSized(): Bool {
        let customType = StaticCast<CustomType>(chirType)
        let memberVars = customType.GetInstantiatedMemberTys()
        for (memberVar in memberVars) {
            if (memberVar.IsRef() || memberVar.IsCPointer() || memberVar.IsCFunc()) {
                continue
            }
            if (CGType.GetOrCreate(cgMod, memberVar).GetSize().isNone()) {
                return false
            }
        }
        return true
    }
}
