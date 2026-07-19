package cjcj::chir

import cjcj::utils.CJC_ASSERT
import std.collection.*

// C++ TypeAnalysis.h:14-61 and TypeAnalysis.cpp:14-75.
public class TypeValue <: HasEqual<TypeValue> {
    protected let kind: DevirtualTyKind
    protected let baseLineType: Type

    private static var builder: Option<CHIRBuilder> = None

    public init(kind: DevirtualTyKind, baseLineType: Type) {
        this.kind = kind
        this.baseLineType = baseLineType
    }

    public func Join(rhs: TypeValue): Option<Option<TypeValue>> {
        let rhsClassTy = rhs.GetSpecificType()
        if (baseLineType != rhsClassTy) {
            if (!baseLineType.IsClass() || !rhsClassTy.IsClass()) {
                return Some(None)
            }
            let fatherTy = LeastCommonSuperClass(
                (baseLineType as ClassType).getOrThrow(),
                (rhsClassTy as ClassType).getOrThrow(),
                TypeValue.builder.getOrThrow())
            if (let Some(value) <- fatherTy) {
                return Some(Some(TypeValue(DevirtualTyKind.SUBTYPE_OF, value)))
            } else {
                return Some(None)
            }
        } else {
            if (kind == DevirtualTyKind.EXACTLY && rhs.kind == DevirtualTyKind.SUBTYPE_OF) {
                return Some(Some(TypeValue(DevirtualTyKind.SUBTYPE_OF, baseLineType)))
            } else {
                return None
            }
        }
    }

    public func ToString(): String {
        return "{ " + GetKindString(kind) + ", " + baseLineType.ToString() + " }"
    }

    public func Clone(): TypeValue {
        // TypeValue is immutable; Join constructs a replacement on change.
        return this
    }

    public func GetTypeKind(): DevirtualTyKind {
        return kind
    }

    public func GetSpecificType(): Type {
        return baseLineType
    }

    public static func SetCHIRBuilder(chirBuilder: CHIRBuilder): Unit {
        builder = Some(chirBuilder)
    }

    private func GetKindString(clsTyKind: DevirtualTyKind): String {
        return match (clsTyKind) {
            case DevirtualTyKind.SUBTYPE_OF => "SUBTYPE_OF"
            case DevirtualTyKind.EXACTLY => "EXACTLY"
            case _ => "Unknown"
        }
    }
}

public type TypeValueDomain = ValueDomain<TypeValue>
public type TypeDomain = State<TypeValueDomain, FullStatePool<TypeValueDomain>>

// C++ TypeAnalysis.cpp:108-115 explicit TypeValueDomain instantiation.
public let globalState = ValueAnalysisGlobals<TypeValueDomain, FullStatePool<TypeValueDomain>>()

// C++ TypeAnalysis.cpp:79-103.
private func GetRealGenericRetType(apply: Apply, genericType: Type,
    calleeFunc: Function, builder: CHIRBuilder): Option<Type> {
    let instTypes = apply.GetInstantiatedTypeArgs()
    let genericTypes = calleeFunc.GetGenericTypeParams()
    CJC_ASSERT(instTypes.size == genericTypes.size)
    let genericMap = HashMap<GenericType, Type>()
    var index: Int64 = 0
    while (index < instTypes.size) {
        genericMap[genericTypes[index]] = instTypes[index]
        index++
    }
    if (let Some(def) <- calleeFunc.GetParentCustomTypeDef()) {
        let thisType = apply.GetThisType().getOrThrow().StripAllRefs()
        if (thisType.IsClassOrStruct()) {
            let customType = (thisType as CustomType).getOrThrow()
            let defGenericParams = def.GetGenericTypeParams()
            let genericArgs = customType.GetGenericArgs()
            CJC_ASSERT(defGenericParams.size == genericArgs.size)
            var genericIndex: Int64 = 0
            while (genericIndex < customType.GetGenericArgs().size) {
                genericMap[defGenericParams[genericIndex]] = genericArgs[genericIndex]
                genericIndex++
            }
        }
    }
    return Some(ReplaceRawGenericArgType(genericType, genericMap, builder))
}

// C++ TypeAnalysis.h:93-155 and TypeAnalysis.cpp:117-477.
public class TypeAnalysis <: ValueAnalysis<TypeValueDomain, FullStatePool<TypeValueDomain>> {
    private let realRetTyMap: HashMap<Int64, Type>
    private let constMemberTypeMap: HashMap<Int64, HashMap<Int64, Type>>

    public init(functionValue: Function, builder: CHIRBuilder, isDebug: Bool,
        devirtInfo: DevirtualizationInfo) {
        super(functionValue, builder, globalState,
            { literal: LiteralValue => TypeAnalysis.HandleNonNullLiteralValue(literal) }, isDebug: isDebug)
        realRetTyMap = devirtInfo.GetReturnTypeMap()
        constMemberTypeMap = devirtInfo.GetConstMemberMap()
    }

    public override func GetAnalysisName(): String {
        return "type-analysis"
    }

    public override func GetBlockLimit(): Option<UInt32> {
        return None
    }

    // C++ TypeAnalysis.cpp:117-125 specialization of IsTrackedGV.
    public static func IsTrackedGV(gv: GlobalVar): Bool {
        var baseTy = gv.GetType().getOrThrow()
        while (baseTy.IsRef()) {
            baseTy = (baseTy as RefType).getOrThrow().GetBaseType()
        }
        return baseTy.IsClass()
    }

    // C++ ValueAnalysis.h:711-714 primary HandleNonNullLiteralValue template.
    public static func HandleNonNullLiteralValue(literal: LiteralValue): TypeValueDomain {
        let _ = literal
        return TypeValueDomain(true)
    }

    public static func CheckFuncHasInvoke(body: BlockGroup): Bool {
        let blocks = body.GetBlocks()
        for (block in blocks) {
            let expressions = block.GetNonTerminatorExpressions()
            var index: Int64 = 0
            while (index < expressions.size) {
                if (expressions[index].GetExprKind() == ExprKind.LAMBDA) {
                    if (CheckFuncHasInvoke((expressions[index] as Lambda).getOrThrow().GetBody().getOrThrow())) {
                        return true
                    }
                }
                if (expressions[index].GetExprKind() == ExprKind.INVOKE) {
                    return true
                }
                index++
            }
        }
        return false
    }

    public static func Filter(method: Function): Bool {
        if (!CheckFuncHasInvoke(method.GetBody().getOrThrow())) {
            return false
        }
        if (IsSTDFunction(method)) {
            return true
        }
        let OVERHEAD_BLOCK_SIZE: Int64 = 300
        return method.GetBody().getOrThrow().GetBlocks().size <= OVERHEAD_BLOCK_SIZE
    }

    public func PrintDebugMessage(expr: Expression, absVal: TypeValue): Unit {
        let message = "The value of " + expr.GetResult().getOrThrow().GetIdentifier() + " = " +
            expr.ToString(0) + " has been set to " + absVal.ToString()
        println(message)
    }

    public override func HandleNormalExpressionEffect(state: TypeDomain, expression: Expression): Unit {
        match (expression.GetExprKind()) {
            case ExprKind.TYPECAST =>
                HandleTypeCastExpr(state, (expression as TypeCast).getOrThrow())
                return
            case ExprKind.BOX =>
                HandleBoxExpr(state, (expression as Box).getOrThrow())
                return
            case _ =>
                let result = expression.GetResult().getOrThrow()
                let domain = state.GetAbstractDomain(result)
                if ((domain.isNone() || domain.getOrThrow().IsTop()) &&
                    result.GetType().getOrThrow().IsPrimitive()) {
                    state.Update(result, TypeValue(DevirtualTyKind.EXACTLY, result.GetType().getOrThrow()))
                } else {
                    state.TrySetToTopOrTopRef(result, result.GetType().getOrThrow().IsRef())
                }
        }
        let resultType = expression.GetResult().getOrThrow().GetType().getOrThrow()
        if (isDebug && !resultType.IsRef() && !resultType.IsGeneric()) {
            if (let Some(absVal) <- state.CheckAbstractValue(expression.GetResult().getOrThrow())) {
                PrintDebugMessage(expression, absVal)
            }
        }
    }

    public override func HandleAllocateExpr(state: TypeDomain, expression: Allocate,
        newObj: Option<Value>): Unit {
        let obj = newObj ?? return
        let baseTy = expression.GetType()
        if (baseTy.IsClass()) {
            state.Update(obj, TypeValue(DevirtualTyKind.EXACTLY, (baseTy as ClassType).getOrThrow()))
        }
    }

    public override func HandleTerminatorEffect(state: TypeDomain, terminator: Terminator): Option<Block> {
        match (terminator.GetExprKind()) {
            case ExprKind.TYPECAST_WITH_EXCEPTION =>
                HandleTypeCastExpr(state, (terminator as TypeCastWithException).getOrThrow())
            case ExprKind.GOTO => HandleTerminatorEffectImpl(state, terminator)
            case ExprKind.EXIT => HandleTerminatorEffectImpl(state, terminator)
            case ExprKind.BRANCH => HandleTerminatorEffectImpl(state, terminator)
            case ExprKind.MULTIBRANCH => HandleTerminatorEffectImpl(state, terminator)
            case ExprKind.INT_OP_WITH_EXCEPTION => HandleTerminatorEffectImpl(state, terminator)
            case ExprKind.INTRINSIC_WITH_EXCEPTION => HandleTerminatorEffectImpl(state, terminator)
            case _ => HandleTerminatorEffectImpl(state, terminator)
        }
        return None
    }

    // C++ TypeAnalysis.cpp:227-232 default arm, split only to avoid repeating it.
    private func HandleTerminatorEffectImpl(state: TypeDomain, terminator: Terminator): Unit {
        if (let Some(dest) <- terminator.GetResult()) {
            state.SetToTopOrTopRef(dest, dest.GetType().getOrThrow().IsRef())
        }
    }

    public override func HandleInvokeExpr(state: TypeDomain, invoke: Invoke,
        refObj: Option<Value>): Unit {
        var resultType = invoke.GetResult().getOrThrow().GetType().getOrThrow()
        while (resultType.IsRef()) {
            resultType = (resultType as RefType).getOrThrow().GetBaseType()
        }
        if (!resultType.IsClass()) {
            return
        }
        state.Update(refObj.getOrThrow(),
            TypeValue(DevirtualTyKind.SUBTYPE_OF, (resultType as ClassType).getOrThrow()))
    }

    public override func HandleApplyExpr(state: TypeDomain, apply: Apply,
        refObj: Option<Value>): Unit {
        let callee = apply.GetCallee()
        if (!callee.IsFuncWithBody()) {
            HandleDefaultExpr(state, apply)
            return
        }

        let calleeFunc = (callee as Function).getOrThrow()
        let realRetTyOption = realRetTyMap.get(calleeFunc.nodeId)
        if (realRetTyOption.isNone()) {
            HandleDefaultExpr(state, apply)
            return
        }
        var realRetTy = realRetTyOption.getOrThrow()
        if (realRetTy.IsGenericRelated()) {
            let genericRetTy = GetRealGenericRetType(apply, realRetTy, calleeFunc, builder)
            if (genericRetTy.isNone()) {
                return
            }
            realRetTy = genericRetTy.getOrThrow()
        }
        let result: Option<Value> = match (apply.GetResult()) {
            case Some(value) => Some(value)
            case None => None
        }
        UpdateDefaultValue(state, result, refObj, Some(realRetTy))
    }

    private func HandleBoxExpr(state: TypeDomain, boxExpr: Box): Unit {
        let result = boxExpr.GetResult().getOrThrow()
        let obj = state.GetReferencedObjAndSetToTop(result, expr: Some(boxExpr))
        state.Propagate(boxExpr.GetSourceValue(), obj)
    }

    private func HandleTypeCastExpr(state: TypeDomain, typecast: TypeCast): Unit {
        HandleTypeCastExprImpl(state, typecast, typecast.GetSourceValue(),
            typecast.GetSourceTy().getOrThrow(), typecast.GetTargetTy().getOrThrow())
    }

    private func HandleTypeCastExpr(state: TypeDomain, typecast: TypeCastWithException): Unit {
        HandleTypeCastExprImpl(state, typecast, typecast.GetSourceValue(),
            typecast.GetSourceTy().getOrThrow(), typecast.GetTargetTy().getOrThrow())
    }

    // C++ TypeAnalysis.cpp:287-347 template body.
    private func HandleTypeCastExprImpl(state: TypeDomain, typecast: Expression,
        sourceValue: Value, sourceType: Type, targetType: Type): Unit {
        var srcTy = sourceType
        var tgtTy = targetType
        while (srcTy.IsRef()) {
            srcTy = (srcTy as RefType).getOrThrow().GetBaseType()
        }
        while (tgtTy.IsRef()) {
            tgtTy = (tgtTy as RefType).getOrThrow().GetBaseType()
        }
        let result = typecast.GetResult().getOrThrow()
        if (result.GetType().getOrThrow().IsRef()) {
            state.GetReferencedObjAndSetToTop(result, expr: Some(typecast))
        } else {
            state.SetToTopOrTopRef(result, false)
        }

        if (!srcTy.IsClass() || !tgtTy.IsClass()) {
            return
        }

        let checkSubClass = { sourceTy: ClassType, targetTy: ClassType =>
            let fatherTy = LeastCommonSuperClass(sourceTy, targetTy, builder)
            if (fatherTy.isSome() && fatherTy.getOrThrow() == targetTy) {
                sourceTy
            } else {
                targetTy
            }
        }

        let srcAbsVal = state.CheckAbstractObjectRefBy(sourceValue)
        if (srcAbsVal.isNone()) {
            return
        }
        let srcVal = state.CheckAbstractValue(srcAbsVal.getOrThrow())
        if (srcVal.isNone()) {
            return
        }

        if (srcVal.getOrThrow().GetTypeKind() == DevirtualTyKind.EXACTLY) {
            state.Propagate(sourceValue, result)
            return
        } else if (srcVal.getOrThrow().GetTypeKind() == DevirtualTyKind.SUBTYPE_OF) {
            let srcClsTy = (srcTy as ClassType).getOrThrow()
            let tgtClsTy = (tgtTy as ClassType).getOrThrow()
            let resTy = checkSubClass(srcClsTy, tgtClsTy)
            if (srcVal.getOrThrow().GetSpecificType() == resTy) {
                state.Propagate(sourceValue, result)
                return
            } else {
                var resVal: Value = result
                if (result.GetType().getOrThrow().IsRef()) {
                    resVal = state.CheckAbstractObjectRefBy(result).getOrThrow()
                }
                state.Update(resVal, TypeValue(DevirtualTyKind.SUBTYPE_OF, tgtClsTy))
                return
            }
        }
    }

    private func GetInnerTypeFromMemberAccess(ma: GetElementRef): Type {
        return GetInnerTypeFromMemberAccessImpl(ma, ma.GetPath())
    }

    private func GetInnerTypeFromMemberAccess(ma: Field): Type {
        return GetInnerTypeFromMemberAccessImpl(ma, ma.GetPath())
    }

    // C++ TypeAnalysis.cpp:349-360 template body.
    private func GetInnerTypeFromMemberAccessImpl(ma: Expression, path: ArrayList<UInt64>): Type {
        var locationType = ma.GetOperands()[0].GetType().getOrThrow()
        var index: Int64 = 0
        while (index < path.size - 1) {
            locationType = GetFieldOfType(locationType, path[index], builder).getOrThrow()
            index++
        }
        return locationType
    }

    private func CheckMemberDefineInWhichParent(typeValue: CustomType, index: Int64): CustomTypeDef {
        let def = typeValue.GetCustomTypeDef()
        let memberInfo = def.GetInstanceVar(index)
        return memberInfo.outerDef ?? def
    }

    private func HandleMemberAccess(state: TypeDomain, memberAccess: GetElementRef): Unit {
        HandleMemberAccessImpl(state, memberAccess, memberAccess.GetPath(),
            GetInnerTypeFromMemberAccess(memberAccess), true)
    }

    private func HandleMemberAccess(state: TypeDomain, memberAccess: Field): Unit {
        HandleMemberAccessImpl(state, memberAccess, memberAccess.GetPath(),
            GetInnerTypeFromMemberAccess(memberAccess), false)
    }

    // C++ TypeAnalysis.cpp:370-413 template body.
    private func HandleMemberAccessImpl(state: TypeDomain, memberAccess: Expression,
        path: ArrayList<UInt64>, innerType: Type, isGetElementRef: Bool): Unit {
        let locationType = innerType.StripAllRefs()
        if (!locationType.IsClassOrStruct()) {
            HandleDefaultExpr(state, memberAccess)
            return
        }
        let index = Int64(path[path.size - 1])
        let customType = (locationType as CustomType).getOrThrow()
        let def = CheckMemberDefineInWhichParent(customType, index)
        let memberMapOption = constMemberTypeMap.get(def.nodeId)
        if (memberMapOption.isNone()) {
            HandleDefaultExpr(state, memberAccess)
            return
        }
        let resultTypeOption = memberMapOption.getOrThrow().get(index)
        if (resultTypeOption.isNone()) {
            HandleDefaultExpr(state, memberAccess)
            return
        }
        var resultType = resultTypeOption.getOrThrow().StripAllRefs()
        if (resultType.IsGenericRelated()) {
            let mapping = def.GetType().getOrThrow().CalculateGenericTyMapping(locationType)
            CJC_ASSERT(mapping[0])
            resultType = ReplaceRawGenericArgType(resultType, mapping[1], builder)
        }
        let result = memberAccess.GetResult().getOrThrow()
        let refObj: AbstractObject
        if (isGetElementRef) {
            refObj = state.GetTwoLevelRefAndSetToTop(result, memberAccess)
        } else {
            refObj = state.GetReferencedObjAndSetToTop(result, expr: Some(memberAccess))
        }
        UpdateDefaultValue(state, Some(result), Some(refObj), Some(resultType))
    }

    protected override func PreHandleGetElementRefExpr(state: TypeDomain,
        getElemRef: GetElementRef): Unit {
        HandleMemberAccess(state, getElemRef)
    }

    protected override func PreHandleFieldExpr(state: TypeDomain, field: Field): Unit {
        HandleMemberAccess(state, field)
    }

    private func HandleDefaultExpr(state: TypeDomain, expr: Expression): Unit {
        let refObj = PreHandleDefaultExpr(state, expr)
        let result: Option<Value> = match (expr.GetResult()) {
            case Some(value) => Some(value)
            case None => None
        }
        UpdateDefaultValue(state, result, refObj, None)
    }

    private func PreHandleDefaultExpr(state: TypeDomain, expr: Expression): Option<Value> {
        let result = expr.GetResult().getOrThrow()
        let resultType = result.GetType().getOrThrow()
        if (!resultType.IsRef()) {
            state.SetToTopOrTopRef(result, false)
            return None
        }
        let firstRefBaseType = (resultType as RefType).getOrThrow().GetBaseType()
        if (!firstRefBaseType.IsRef()) {
            return Some(state.GetReferencedObjAndSetToTop(result, expr: Some(expr)))
        }
        return Some(state.GetTwoLevelRefAndSetToTop(result, expr))
    }

    private func UpdateDefaultValue(state: TypeDomain, value: Option<Value>,
        refObj: Option<Value>, relType: Option<Type>): Unit {
        let concreteValue = value ?? return
        let dest = refObj ?? concreteValue
        var typeValue = relType ?? concreteValue.GetType().getOrThrow().StripAllRefs()
        if (typeValue.IsBox()) {
            typeValue = (typeValue as BoxType).getOrThrow().GetBaseType()
        }
        if (typeValue.IsPrimitive() || typeValue.IsStruct() || typeValue.IsEnum()) {
            state.Update(dest, TypeValue(DevirtualTyKind.EXACTLY, typeValue))
        }
        if (typeValue.IsClass()) {
            let classDef = (typeValue as ClassType).getOrThrow().GetClassDef()
            let typeKind = if (!classDef.IsInterface() && !classDef.TestAttr(Attribute.VIRTUAL) &&
                !classDef.IsAbstract()) {
                DevirtualTyKind.EXACTLY
            } else {
                DevirtualTyKind.SUBTYPE_OF
            }
            state.Update(dest, TypeValue(typeKind, typeValue))
        }
    }

    public override func HandleFuncParam(state: TypeDomain, param: Parameter, refObj: Value): Unit {
        HandleFuncParam(state, param, Some(refObj))
    }

    // C++ TypeAnalysis.cpp:472-477 pointer-null branch retained by an overload.
    private func HandleFuncParam(state: TypeDomain, param: Parameter, refObj: Option<Value>): Unit {
        if (refObj.isNone()) {
            return
        }
        UpdateDefaultValue(state, Some(param), refObj, None)
    }
}
