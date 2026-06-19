package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.BoxType
import cangjie_compiler::chir.CPointerType
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.EnumType
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.GenericType
import cangjie_compiler::chir.RawArrayType
import cangjie_compiler::chir.RefType
import cangjie_compiler::chir.StructType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TupleType
import cangjie_compiler::chir.VArrayType

public enum CGEnumTypeKind {
    | UNKNOWN
    | NON_EXHAUSTIVE_UNASSOCIATED
    | NON_EXHAUSTIVE_ASSOCIATED
    | EXHAUSTIVE_ZERO_SIZE
    | EXHAUSTIVE_UNASSOCIATED
    | EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF
    | EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF
    | EXHAUSTIVE_ASSOCIATED_NONREF
    | EXHAUSTIVE_OTHER
    | EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T
}

private func CGEnumTypeKindIndex(kind: CGEnumTypeKind): Int64 {
    return match (kind) {
        case CGEnumTypeKind.UNKNOWN => 0
        case CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED => 1
        case CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED => 2
        case CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE => 3
        case CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED => 4
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF => 5
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF => 6
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF => 7
        case CGEnumTypeKind.EXHAUSTIVE_OTHER => 8
        case CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T => 9
    }
}

extend CGEnumTypeKind <: Equatable<CGEnumTypeKind> {
    public operator func ==(right: CGEnumTypeKind): Bool {
        return CGEnumTypeKindIndex(this) == CGEnumTypeKindIndex(right)
    }

    public operator func !=(right: CGEnumTypeKind): Bool {
        return !(this == right)
    }
}

public class CGEnumType <: CGCustomType {
    private var cgEnumTypeKind: CGEnumTypeKind = CGEnumTypeKind.UNKNOWN
    private var optionLikeAssociatedValueType: Option<Type> = None
    private var isAntiOptionLike: Bool = false

    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType, cgTypeKind: CGTypeKind.CG_ENUM)
    }

    public func IsTrivial(): Bool {
        return cgEnumTypeKind == CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED
    }

    public func IsOptionLike(): Bool {
        return cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF ||
            cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF
    }

    public func GetCGEnumTypeKind(): CGEnumTypeKind { return cgEnumTypeKind }

    public func IsOptionLikeNonRef(): Bool {
        return cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF
    }

    public func IsOptionLikeRef(): Bool {
        return cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF
    }

    public func IsOptionLikeT(): Bool {
        return cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T
    }

    public func IsAntiOptionLike(): Bool { return isAntiOptionLike }

    public func GetAssociatedValueTypeOfOptionLike(): Option<Type> {
        return optionLikeAssociatedValueType
    }

    protected override func GenLLVMType(): LLVMTypeRef {
        cgEnumTypeKind = ClassifyEnumType()
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T) {
            let i8Ty = unsafe { LLVMInt8TypeInContext(cgCtx.GetLLVMContext().raw) }
            llvmType = i8Ty
            return i8Ty
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            let refTy = CGType.GetRefType(cgCtx.GetLLVMContext())
            llvmType = refTy
            layoutType = refTy
            return refTy
        }
        let layoutName = STRUCT_TYPE_PREFIX + chirType.ToString()
        let enumLayout = GetOrCreateNamedStructType(cgCtx.GetLLVMContext(), layoutName)
        layoutType = enumLayout
        llvmType = enumLayout
        if (!cgCtx.IsGeneratedStructType(layoutName)) {
            cgCtx.AddGeneratedStructType(layoutName)
            SetStructTypeBody(enumLayout, BuildEnumFieldTypes())
        }
        return enumLayout
    }

    protected override func GenContainedCGTypes(): Unit {
        if (cgEnumTypeKind == CGEnumTypeKind.UNKNOWN) {
            cgEnumTypeKind = ClassifyEnumType()
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T) {
            return
        }
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            if (let Some(associatedTy) <- optionLikeAssociatedValueType) {
                containedCGTypes.add(CGType.GetOrCreate(cgMod, associatedTy))
            }
            return
        }
        let selectorTy = if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF) {
            cgCtx.GetCHIRBuilder().context.GetBoolTy()
        } else {
            cgCtx.GetCHIRBuilder().context.GetUInt32Ty()
        }
        containedCGTypes.add(CGType.GetOrCreate(cgMod, selectorTy))
        for (fieldTy in BuildEnumPayloadFieldTypes()) {
            containedCGTypes.add(CGType.GetOrCreate(cgMod, fieldTy))
        }
    }

    protected override func CalculateSizeAndAlign(): Unit {
        if (ContainsGenericType(chirType)) {
            size = None
            align = None
            return
        }
        var total: Int64 = 0
        var maxAlign: Int64 = 1
        for (fieldCGType in GetContainedTypes()) {
            let fieldAlign = if (let Some(value) <- fieldCGType.GetAlign()) { value } else { 1 }
            let fieldSize = if (let Some(value) <- fieldCGType.GetSize()) { value } else { 0 }
            if (total % fieldAlign != 0) {
                total += fieldAlign - (total % fieldAlign)
            }
            total += fieldSize
            if (fieldAlign > maxAlign) { maxAlign = fieldAlign }
        }
        if (total % maxAlign != 0) {
            total += maxAlign - (total % maxAlign)
        }
        size = total
        align = maxAlign
    }

    private func ClassifyEnumType(): CGEnumTypeKind {
        if (let Some(enumTy) <- (chirType as EnumType)) {
            if (enumTy.GetEnumDef().IsOptionLike()) {
                isAntiOptionLike = enumTy.GetEnumDef().IsAntiOptionLike()
                if (let Some(associatedTy) <- enumTy.GetEnumDef().GetOptionLikeAssociatedValueType()) {
                    let instantiatedAssociatedTy = InstantiateEnumPayloadType(enumTy, associatedTy)
                    optionLikeAssociatedValueType = Some(instantiatedAssociatedTy)
                    if (instantiatedAssociatedTy.IsGeneric()) {
                        return CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T
                    }
                    if (instantiatedAssociatedTy.StripAllRefs().IsReferenceType()) {
                        return CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF
                    }
                    return CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF
                }
            }
            for (ctor in enumTy.GetEnumDef().GetCtors()) {
                if (!ctor.payloadTypes.isEmpty()) {
                    return CGEnumTypeKind.EXHAUSTIVE_OTHER
                }
            }
        }
        return CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED
    }

    private func BuildEnumFieldTypes(): ArrayList<LLVMTypeRef> {
        let out = ArrayList<LLVMTypeRef>()
        let selectorTy = if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF) {
            cgCtx.GetCHIRBuilder().context.GetBoolTy()
        } else {
            cgCtx.GetCHIRBuilder().context.GetUInt32Ty()
        }
        out.add(CGType.GetOrCreate(cgMod, selectorTy).GetLLVMType())
        for (fieldTy in BuildEnumPayloadFieldTypes()) {
            out.add(CGType.GetOrCreate(cgMod, fieldTy).GetLLVMType())
        }
        return out
    }

    private func BuildEnumPayloadFieldTypes(): ArrayList<Type> {
        let out = ArrayList<Type>()
        if (cgEnumTypeKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF) {
            if (let Some(associatedTy) <- optionLikeAssociatedValueType) {
                out.add(associatedTy)
            }
            return out
        }
        if (let Some(enumTy) <- (chirType as EnumType)) {
            for (ctor in enumTy.GetEnumDef().GetCtors()) {
                var idx: Int64 = 0
                for (payloadTy in ctor.payloadTypes) {
                    let instantiatedPayloadTy = InstantiateEnumPayloadType(enumTy, payloadTy)
                    if (idx >= out.size) {
                        out.add(instantiatedPayloadTy)
                    } else if (!out[idx].IsEqual(instantiatedPayloadTy)) {
                        out[idx] = PickEnumPayloadStorageType(out[idx], instantiatedPayloadTy)
                    }
                    idx++
                }
            }
        }
        return out
    }

    private func InstantiateEnumPayloadType(enumTy: EnumType, payloadTy: Type): Type {
        return SubstituteGenericType(payloadTy, enumTy.GetEnumDef().GetGenericTypeParams(), enumTy.GetGenericArgs())
    }

    private func SubstituteGenericType(ty: Type, genericParams: ArrayList<GenericType>,
        replacements: ArrayList<Type>): Type {
        if (let Some(genericTy) <- (ty as GenericType)) {
            var idx: Int64 = 0
            while (idx < genericParams.size && idx < replacements.size) {
                if (genericTy.IsEqual(genericParams[idx])) {
                    return replacements[idx]
                }
                idx++
            }
            return ty
        }
        if (let Some(refTy) <- (ty as RefType)) {
            return RefType(SubstituteGenericType(refTy.GetBaseType(), genericParams, replacements))
        }
        if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
            return RawArrayType(SubstituteGenericType(rawArrayTy.GetElementType(), genericParams, replacements),
                dims: rawArrayTy.GetDims())
        }
        if (let Some(varrayTy) <- (ty as VArrayType)) {
            return VArrayType(SubstituteGenericType(varrayTy.GetElementType(), genericParams, replacements),
                varrayTy.size)
        }
        if (let Some(pointerTy) <- (ty as CPointerType)) {
            return CPointerType(SubstituteGenericType(pointerTy.GetElementType(), genericParams, replacements))
        }
        if (let Some(boxTy) <- (ty as BoxType)) {
            return BoxType(SubstituteGenericType(boxTy.GetBaseType(), genericParams, replacements))
        }
        if (let Some(tupleTy) <- (ty as TupleType)) {
            return TupleType(SubstituteGenericTypeArgs(tupleTy.GetTypeArgs(), genericParams, replacements))
        }
        if (let Some(funcTy) <- (ty as FuncType)) {
            let params = SubstituteGenericTypeArgs(funcTy.GetParamTypes(), genericParams, replacements)
            let retTy = SubstituteGenericType(funcTy.GetReturnType(), genericParams, replacements)
            return FuncType(params, retTy, hasVarLenParam: funcTy.HasVarArg(), isCFunc: funcTy.IsCFunc())
        }
        if (let Some(structTy) <- (ty as StructType)) {
            return StructType(structTy.GetStructDef(),
                SubstituteGenericTypeArgs(structTy.GetGenericArgs(), genericParams, replacements))
        }
        if (let Some(classTy) <- (ty as ClassType)) {
            return ClassType(classTy.GetClassDef(),
                SubstituteGenericTypeArgs(classTy.GetGenericArgs(), genericParams, replacements))
        }
        if (let Some(enumTy) <- (ty as EnumType)) {
            return EnumType(enumTy.GetEnumDef(),
                SubstituteGenericTypeArgs(enumTy.GetGenericArgs(), genericParams, replacements))
        }
        return ty
    }

    private func SubstituteGenericTypeArgs(args: ArrayList<Type>, genericParams: ArrayList<GenericType>,
        replacements: ArrayList<Type>): ArrayList<Type> {
        let out = ArrayList<Type>()
        for (arg in args) {
            out.add(SubstituteGenericType(arg, genericParams, replacements))
        }
        return out
    }

    private func PickEnumPayloadStorageType(left: Type, right: Type): Type {
        if (left.IsEqual(right)) {
            return left
        }
        if (left.IsRef() && right.IsRef()) {
            return left
        }
        if (left.IsRef() || right.IsRef()) {
            return cgCtx.GetCHIRBuilder().context.GetUInt64Ty()
        }
        let leftSize = CGType.GetOrCreate(cgMod, left).GetSize() ?? 0
        let rightSize = CGType.GetOrCreate(cgMod, right).GetSize() ?? 0
        return if (leftSize >= rightSize) { left } else { right }
    }
}
