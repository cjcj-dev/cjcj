package cjcj::chir

import std.collection.*
import cjcj::utils.{CJC_ABORT, StaticCast}

public type ConvertTypeFunc = (Type) -> Type

private let GENERIC_VIRTUAL_FUNC: String = "$GenericVirtualFunc"

public interface ExprTypeFunctor {
    func VisitExpr(o: Expression): Unit {
        match (o.GetExprKind()) {
            case ExprKind.ALLOCATE => VisitSubExpression(StaticCast<Allocate>(o))
            case ExprKind.ALLOCATE_WITH_EXCEPTION => VisitSubExpression(StaticCast<AllocateWithException>(o))
            case ExprKind.INSTANCEOF => VisitSubExpression(StaticCast<InstanceOf>(o))
            case ExprKind.RAW_ARRAY_ALLOCATE => VisitSubExpression(StaticCast<RawArrayAllocate>(o))
            case ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION =>
                VisitSubExpression(StaticCast<RawArrayAllocateWithException>(o))
            case ExprKind.APPLY => VisitSubExpression(StaticCast<Apply>(o))
            case ExprKind.APPLY_WITH_EXCEPTION => VisitSubExpression(StaticCast<ApplyWithException>(o))
            case ExprKind.INVOKE => VisitSubExpression(StaticCast<Invoke>(o))
            case ExprKind.INVOKE_WITH_EXCEPTION => VisitSubExpression(StaticCast<InvokeWithException>(o))
            case ExprKind.INVOKESTATIC => VisitSubExpression(StaticCast<InvokeStatic>(o))
            case ExprKind.INVOKESTATIC_WITH_EXCEPTION =>
                VisitSubExpression(StaticCast<InvokeStaticWithException>(o))
            case ExprKind.CONSTANT => VisitSubExpression(StaticCast<Constant>(o))
            case ExprKind.INTRINSIC => VisitSubExpression(StaticCast<Intrinsic>(o))
            case ExprKind.INTRINSIC_WITH_EXCEPTION => VisitSubExpression(StaticCast<IntrinsicWithException>(o))
            case ExprKind.GET_INSTANTIATE_VALUE => VisitSubExpression(StaticCast<GetInstantiateValue>(o))
            case ExprKind.LAMBDA => VisitSubExpression(StaticCast<Lambda>(o))
            case ExprKind.GET_RTTI_STATIC => VisitSubExpression(StaticCast<GetRTTIStatic>(o))
            case _ => VisitExprDefaultImpl(o)
        }
    }

    func VisitExprDefaultImpl(o: Expression): Unit
    func VisitSubExpression(o: Allocate): Unit
    func VisitSubExpression(o: AllocateWithException): Unit
    func VisitSubExpression(o: InstanceOf): Unit
    func VisitSubExpression(o: RawArrayAllocate): Unit
    func VisitSubExpression(o: RawArrayAllocateWithException): Unit
    func VisitSubExpression(o: Apply): Unit
    func VisitSubExpression(o: ApplyWithException): Unit
    func VisitSubExpression(o: Invoke): Unit
    func VisitSubExpression(o: InvokeWithException): Unit
    func VisitSubExpression(o: InvokeStatic): Unit
    func VisitSubExpression(o: InvokeStaticWithException): Unit
    func VisitSubExpression(o: Constant): Unit
    func VisitSubExpression(o: Intrinsic): Unit
    func VisitSubExpression(o: IntrinsicWithException): Unit
    func VisitSubExpression(o: GetInstantiateValue): Unit
    func VisitSubExpression(o: Lambda): Unit
    func VisitSubExpression(o: GetRTTIStatic): Unit
}

public interface ValueTypeFunctor {
    func VisitValue(o: Value): Unit {
        match (o.GetValueKind()) {
            case ValueKind.KIND_FUNC => VisitSubValue(StaticCast<Function>(o))
            case _ => VisitValueDefaultImpl(o)
        }
    }

    func VisitValueDefaultImpl(_: Value): Unit {
        CJC_ABORT()
    }
    func VisitSubValue(o: Function): Unit {
        VisitValueDefaultImpl(o)
    }
}

public interface CustomDefTypeFunctor {
    func VisitDef(o: CustomTypeDef): Unit {
        match (o.GetCustomKind()) {
            case CustomDefKind.TYPE_STRUCT => VisitSubDef(StaticCast<StructDef>(o))
            case CustomDefKind.TYPE_ENUM => VisitSubDef(StaticCast<EnumDef>(o))
            case CustomDefKind.TYPE_CLASS => VisitSubDef(StaticCast<ClassDef>(o))
            case CustomDefKind.TYPE_EXTEND => VisitSubDef(StaticCast<ExtendDef>(o))
        }
    }

    func VisitDefDefaultImpl(o: CustomTypeDef): Unit
    func VisitSubDef(o: StructDef): Unit
    func VisitSubDef(o: EnumDef): Unit
    func VisitSubDef(o: ClassDef): Unit
    func VisitSubDef(o: ExtendDef): Unit
}

public open class TypeConverter {
    protected let converter: ConvertTypeFunc
    protected let builder: CHIRBuilder

    public init(converter: ConvertTypeFunc, builder: CHIRBuilder) {
        this.converter = converter
        this.builder = builder
    }

    public open func ConvertType(ty: Type): Type {
        return converter(ty)
    }

    public func ConvertFuncParamsAndRetType(input: FuncType): FuncType {
        let newParamTys = ArrayList<Type>()
        for (oldParamTy in input.GetParamTypes()) {
            newParamTys.add(ConvertType(oldParamTy))
        }
        let newRetTy = ConvertType(input.GetReturnType())
        return builder.context.GetFuncTy(newParamTys, newRetTy,
            hasVarLenParam: input.HasVarArg(), isCFunc: input.IsCFunc())
    }
}

public open class ExprTypeConverter <: TypeConverter & ExprTypeFunctor {
    public init(converter: ConvertTypeFunc, builder: CHIRBuilder) {
        super(converter, builder)
    }

    public open func VisitValue(_: Value): Unit {}

    public open func VisitExprDefaultImpl(o: Expression): Unit {
        if (let Some(result) <- o.GetResult()) {
            VisitValue(result)
        }
    }

    public open func VisitSubExpression(o: Allocate): Unit {
        VisitExprDefaultImpl(o)
        o.SetType(ConvertType(o.GetType()))
    }

    public open func VisitSubExpression(o: AllocateWithException): Unit {
        VisitExprDefaultImpl(o)
        o.SetType(ConvertType(o.GetType()))
    }

    public open func VisitSubExpression(o: InstanceOf): Unit {
        VisitExprDefaultImpl(o)
        o.SetTestedType(ConvertType(o.GetType()))
    }

    public open func VisitSubExpression(o: RawArrayAllocate): Unit {
        VisitExprDefaultImpl(o)
        o.SetElementType(ConvertType(o.GetElementType()))
    }

    public open func VisitSubExpression(o: RawArrayAllocateWithException): Unit {
        VisitExprDefaultImpl(o)
        o.SetElementType(ConvertType(o.GetElementType()))
    }

    public open func VisitSubExpression(o: Apply): Unit {
        VisitExprDefaultImpl(o)
        let instantiatedTypeArgs = o.GetInstantiatedTypeArgs()
        for (idx in 0..instantiatedTypeArgs.size) {
            instantiatedTypeArgs[idx] = converter(instantiatedTypeArgs[idx])
        }
        o.SetInstantiatedTypeArgs(instantiatedTypeArgs)
        if (let Some(thisType) <- o.GetThisType()) {
            o.SetThisType(ConvertType(thisType))
        }
    }

    public open func VisitSubExpression(o: ApplyWithException): Unit {
        VisitExprDefaultImpl(o)
        let instantiatedTypeArgs = o.GetInstantiatedTypeArgs()
        for (idx in 0..instantiatedTypeArgs.size) {
            instantiatedTypeArgs[idx] = converter(instantiatedTypeArgs[idx])
        }
        o.SetInstantiatedTypeArgs(instantiatedTypeArgs)
        if (let Some(thisType) <- o.GetThisType()) {
            o.SetThisType(ConvertType(thisType))
        }
    }

    public open func VisitSubExpression(o: Invoke): Unit {
        VisitExprDefaultImpl(o)
        o.SetMethodType(ConvertFuncParamsAndRetType(o.GetMethodType()))
        o.SetThisType(ConvertType(o.GetThisType().getOrThrow()))
        let instantiatedTypeArgs = o.GetInstantiatedTypeArgs()
        for (idx in 0..instantiatedTypeArgs.size) {
            instantiatedTypeArgs[idx] = converter(instantiatedTypeArgs[idx])
        }
        o.SetInstantiatedTypeArgs(instantiatedTypeArgs)
    }

    public open func VisitSubExpression(o: InvokeWithException): Unit {
        VisitExprDefaultImpl(o)
        o.SetMethodType(ConvertFuncParamsAndRetType(o.GetMethodType()))
        o.SetThisType(ConvertType(o.GetThisType().getOrThrow()))
        let instantiatedTypeArgs = o.GetInstantiatedTypeArgs()
        for (idx in 0..instantiatedTypeArgs.size) {
            instantiatedTypeArgs[idx] = converter(instantiatedTypeArgs[idx])
        }
        o.SetInstantiatedTypeArgs(instantiatedTypeArgs)
    }

    public open func VisitSubExpression(o: InvokeStatic): Unit {
        VisitExprDefaultImpl(o)
        o.SetMethodType(ConvertFuncParamsAndRetType(o.GetMethodType()))
        o.SetThisType(ConvertType(o.GetThisType().getOrThrow()))
        let instantiatedTypeArgs = o.GetInstantiatedTypeArgs()
        for (idx in 0..instantiatedTypeArgs.size) {
            instantiatedTypeArgs[idx] = converter(instantiatedTypeArgs[idx])
        }
        o.SetInstantiatedTypeArgs(instantiatedTypeArgs)
    }

    public open func VisitSubExpression(o: InvokeStaticWithException): Unit {
        VisitExprDefaultImpl(o)
        o.SetMethodType(ConvertFuncParamsAndRetType(o.GetMethodType()))
        o.SetThisType(ConvertType(o.GetThisType().getOrThrow()))
        let instantiatedTypeArgs = o.GetInstantiatedTypeArgs()
        for (idx in 0..instantiatedTypeArgs.size) {
            instantiatedTypeArgs[idx] = converter(instantiatedTypeArgs[idx])
        }
        o.SetInstantiatedTypeArgs(instantiatedTypeArgs)
    }

    public open func VisitSubExpression(o: Constant): Unit {
        VisitExprDefaultImpl(o)
        VisitValue(o.GetValue())
    }

    public open func VisitSubExpression(o: Intrinsic): Unit {
        VisitExprDefaultImpl(o)
        let instantiatedTypeArgs = o.GetInstantiatedTypeArgs()
        for (idx in 0..instantiatedTypeArgs.size) {
            instantiatedTypeArgs[idx] = converter(instantiatedTypeArgs[idx])
        }
        o.SetInstantiatedTypeArgs(instantiatedTypeArgs)
    }

    public open func VisitSubExpression(o: IntrinsicWithException): Unit {
        VisitExprDefaultImpl(o)
        let instantiatedTypeArgs = o.GetInstantiatedTypeArgs()
        for (idx in 0..instantiatedTypeArgs.size) {
            instantiatedTypeArgs[idx] = converter(instantiatedTypeArgs[idx])
        }
        o.SetInstantiatedTypeArgs(instantiatedTypeArgs)
    }

    public open func VisitSubExpression(o: GetInstantiateValue): Unit {
        VisitExprDefaultImpl(o)
        let instantiateTys = o.GetInstantiateTypesRef()
        for (idx in 0..instantiateTys.size) {
            instantiateTys[idx] = ConvertType(instantiateTys[idx])
        }
    }

    public open func VisitSubExpression(o: Lambda): Unit {
        VisitExprDefaultImpl(o)
        o.SetFuncType(ConvertFuncParamsAndRetType(o.GetFuncType().getOrThrow()))
        for (param in o.GetParams()) {
            VisitValue(param)
        }
    }

    public open func VisitSubExpression(o: GetRTTIStatic): Unit {
        VisitExprDefaultImpl(o)
        o.SetRTTIType(ConvertType(o.GetRTTIType()))
    }
}

public interface ValueTypeConverter <: ValueTypeFunctor {
    func ConvertType(ty: Type): Type
    func ConvertFuncParamsAndRetType(input: FuncType): FuncType

    func VisitValueDefaultImpl(o: Value): Unit {
        o.SetType(ConvertType(o.GetType().getOrThrow()))
    }

    func VisitFuncBase(o: Function): Unit {
        o.SetType(ConvertFuncParamsAndRetType(o.GetFuncType().getOrThrow()))
        if (let Some(srcFuncType) <- o.GetOverrideSrcFuncType()) {
            o.SetOverrideSrcFuncType(ConvertFuncParamsAndRetType(srcFuncType))
        }
        let genericTypeParams = o.GetGenericTypeParamsRef()
        for (idx in 0..genericTypeParams.size) {
            genericTypeParams[idx] = StaticCast<GenericType>(ConvertType(genericTypeParams[idx]))
        }
    }

    func VisitSubValue(o: Function): Unit {
        VisitFuncBase(o)
        for (param in o.GetParams()) {
            VisitValue(param)
        }
    }
}

public interface CustomDefTypeConverter <: CustomDefTypeFunctor {
    func ConvertType(ty: Type): Type
    func ConvertFuncParamsAndRetType(input: FuncType): FuncType

    func VisitDefDefaultImpl(o: CustomTypeDef): Unit {
        if (let Some(ty) <- o.GetType()) {
            o.SetType(StaticCast<CustomType>(ConvertType(ty)))
        }

        for (idx in 0..o.implementedInterfaceTys.size) {
            o.implementedInterfaceTys[idx] =
                StaticCast<ClassType>(ConvertType(o.implementedInterfaceTys[idx]))
        }
        for (member in o.GetDirectInstanceVars()) {
            member.ty = ConvertType(member.ty)
        }
        o.GetModifiableDefVTable().ConvertPrivateType(
            { ty: FuncType => ConvertFuncParamsAndRetType(ty) },
            { ty: Type => ConvertType(ty) })
    }

    func VisitSubDef(o: StructDef): Unit {
        VisitDefDefaultImpl(o)
    }

    func VisitSubDef(o: EnumDef): Unit {
        VisitDefDefaultImpl(o)
        for (ctor in o.GetCtors()) {
            ctor.funcType = Some(ConvertFuncParamsAndRetType(ctor.funcType.getOrThrow()))
        }
    }

    func VisitSubDef(o: ClassDef): Unit {
        VisitDefDefaultImpl(o)
        if (let Some(superClassTy) <- o.GetSuperClassTy()) {
            o.SetSuperClassTy(StaticCast<ClassType>(ConvertType(superClassTy)))
        }
    }

    func VisitSubDef(o: ExtendDef): Unit {
        VisitDefDefaultImpl(o)
        o.SetExtendedType(ConvertType(o.GetExtendedType().getOrThrow()))
        let genericParams = o.GetGenericTypeParamsRef()
        for (idx in 0..genericParams.size) {
            genericParams[idx] = StaticCast<GenericType>(ConvertType(genericParams[idx]))
        }
    }
}

public open class PrivateTypeConverter <: ExprTypeConverter & ValueTypeConverter {
    public init(converter: ConvertTypeFunc, builder: CHIRBuilder) {
        super(converter, builder)
    }

    public override func VisitValue(o: Value): Unit {
        match (o.GetValueKind()) {
            case ValueKind.KIND_FUNC => VisitSubValue(StaticCast<Function>(o))
            case _ => VisitValueDefaultImpl(o)
        }
    }
}

public class TypeConverterForCC <: ExprTypeConverter & ValueTypeConverter & CustomDefTypeConverter {
    private let funcConverter: ConvertTypeFunc

    public init(normalConverter: ConvertTypeFunc, funcConverter: ConvertTypeFunc, builder: CHIRBuilder) {
        super(normalConverter, builder)
        this.funcConverter = funcConverter
    }

    public override func VisitValue(o: Value): Unit {
        match (o.GetValueKind()) {
            case ValueKind.KIND_FUNC => VisitSubValue(StaticCast<Function>(o))
            case _ => VisitValueDefaultImpl(o)
        }
    }

    public override func ConvertType(ty: Type): Type {
        if (let Some(refTy) <- (ty as RefType)) {
            return builder.context.GetRefTy(ConvertType(refTy.GetBaseType()))
        } else if (ty.IsCJFunc()) {
            return funcConverter(ty)
        } else {
            return converter(ty)
        }
    }

    public override func VisitSubExpression(o: RawArrayAllocate): Unit {
        VisitExprDefaultImpl(o)
        o.SetElementType(converter(o.GetElementType()))
    }

    public override func VisitSubExpression(o: RawArrayAllocateWithException): Unit {
        VisitExprDefaultImpl(o)
        o.SetElementType(converter(o.GetElementType()))
    }

    public override func VisitSubValue(o: Function): Unit {
        if (o.GetSrcCodeIdentifier() == GENERIC_VIRTUAL_FUNC) {
            let funcType = o.GetFuncType().getOrThrow()
            let newParamTys = ArrayList<Type>()
            for (oldParamTy in funcType.GetParamTypes()) {
                if (oldParamTy.IsCJFunc()) {
                    newParamTys.add(converter(oldParamTy))
                } else {
                    newParamTys.add(ConvertType(oldParamTy))
                }
            }
            let newRetTy = ConvertType(funcType.GetReturnType())
            o.SetType(builder.context.GetFuncTy(newParamTys, newRetTy,
                hasVarLenParam: funcType.HasVarArg(), isCFunc: funcType.IsCFunc()))
            let genericTypeParams = o.GetGenericTypeParamsRef()
            for (idx in 0..genericTypeParams.size) {
                genericTypeParams[idx] = StaticCast<GenericType>(ConvertType(genericTypeParams[idx]))
            }
            for (param in o.GetParams()) {
                VisitValue(param)
            }
        } else {
            VisitFuncBase(o)
            for (param in o.GetParams()) {
                VisitValue(param)
            }
        }
    }

    public override func VisitValueDefaultImpl(o: Value): Unit {
        if (let Some(param) <- o.AsParameter()) {
            if (let Some(ownerFunc) <- param.GetOwnerFunc()) {
                if (ownerFunc.GetSrcCodeIdentifier() == GENERIC_VIRTUAL_FUNC &&
                    o.GetType().getOrThrow().IsCJFunc()) {
                    o.SetType(converter(o.GetType().getOrThrow()))
                    return
                }
            }
        }
        o.SetType(ConvertType(o.GetType().getOrThrow()))
    }
}

public class PrivateTypeConverterNoInvokeOriginal <: PrivateTypeConverter {
    public init(converter: ConvertTypeFunc, builder: CHIRBuilder) {
        super(converter, builder)
    }

    public override func VisitSubExpression(o: Invoke): Unit {
        VisitExprDefaultImpl(o)
        o.SetThisType(ConvertType(o.GetThisType().getOrThrow()))
        let instantiatedTypeArgs = o.GetInstantiatedTypeArgs()
        for (idx in 0..instantiatedTypeArgs.size) {
            instantiatedTypeArgs[idx] = ConvertType(instantiatedTypeArgs[idx])
        }
        o.SetInstantiatedTypeArgs(instantiatedTypeArgs)
    }

    public override func VisitSubExpression(o: InvokeWithException): Unit {
        VisitExprDefaultImpl(o)
        o.SetThisType(ConvertType(o.GetThisType().getOrThrow()))
        let instantiatedTypeArgs = o.GetInstantiatedTypeArgs()
        for (idx in 0..instantiatedTypeArgs.size) {
            instantiatedTypeArgs[idx] = ConvertType(instantiatedTypeArgs[idx])
        }
        o.SetInstantiatedTypeArgs(instantiatedTypeArgs)
    }

    public override func VisitSubExpression(o: InvokeStatic): Unit {
        VisitExprDefaultImpl(o)
        o.SetThisType(ConvertType(o.GetThisType().getOrThrow()))
        let instantiatedTypeArgs = o.GetInstantiatedTypeArgs()
        for (idx in 0..instantiatedTypeArgs.size) {
            instantiatedTypeArgs[idx] = ConvertType(instantiatedTypeArgs[idx])
        }
        o.SetInstantiatedTypeArgs(instantiatedTypeArgs)
    }

    public override func VisitSubExpression(o: InvokeStaticWithException): Unit {
        VisitExprDefaultImpl(o)
        o.SetThisType(ConvertType(o.GetThisType().getOrThrow()))
        let instantiatedTypeArgs = o.GetInstantiatedTypeArgs()
        for (idx in 0..instantiatedTypeArgs.size) {
            instantiatedTypeArgs[idx] = ConvertType(instantiatedTypeArgs[idx])
        }
        o.SetInstantiatedTypeArgs(instantiatedTypeArgs)
    }
}
