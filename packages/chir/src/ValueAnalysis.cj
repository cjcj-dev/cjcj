package cangjie_compiler::chir

import cangjie_compiler::utils.{BOX_DECL_PREFIX, CJC_ASSERT, CORE_PACKAGE_NAME, InternalError}
import std.collection.*

private var valueAnalysisGlobalChildrenMap: ChildrenMap = ChildrenMap()
private var valueAnalysisGlobalAllocatedRefMap: AllocatedRefMap = AllocatedRefMap()
private var valueAnalysisGlobalAllocatedTwoLevelRefMap: AllocatedRefMap = AllocatedRefMap()
private var valueAnalysisGlobalAllocatedObjMap: AllocatedObjMap = AllocatedObjMap()
private var valueAnalysisGlobalRefPool: ArrayList<Ref> = ArrayList<Ref>()
private var valueAnalysisGlobalAbsObjPool: ArrayList<AbstractObject> = ArrayList<AbstractObject>()
private var valueAnalysisGlobalState: State<ConstValue, FullStatePool<ConstValue>> =
    State<ConstValue, FullStatePool<ConstValue>>(valueAnalysisGlobalChildrenMap,
        valueAnalysisGlobalAllocatedRefMap, valueAnalysisGlobalAllocatedTwoLevelRefMap,
        valueAnalysisGlobalAllocatedObjMap, valueAnalysisGlobalRefPool, valueAnalysisGlobalAbsObjPool,
        isGlobalState: true)

private func GetValueAnalysisGlobalState<AV, Pool>(): State<AV, Pool> where AV <: ConstValue {
    return (valueAnalysisGlobalState as State<AV, Pool>).getOrThrow()
}

private func ResetValueAnalysisGlobalState(): Unit {
    valueAnalysisGlobalChildrenMap.Clear()
    valueAnalysisGlobalAllocatedRefMap.Clear()
    valueAnalysisGlobalAllocatedTwoLevelRefMap.Clear()
    valueAnalysisGlobalAllocatedObjMap.Clear()
    valueAnalysisGlobalRefPool.clear()
    valueAnalysisGlobalAbsObjPool.clear()
    valueAnalysisGlobalState = State<ConstValue, FullStatePool<ConstValue>>(valueAnalysisGlobalChildrenMap,
        valueAnalysisGlobalAllocatedRefMap, valueAnalysisGlobalAllocatedTwoLevelRefMap,
        valueAnalysisGlobalAllocatedObjMap, valueAnalysisGlobalRefPool, valueAnalysisGlobalAbsObjPool,
        isGlobalState: true)
}

public open class ValueAnalysis<AV, Pool> <: Analysis<State<AV, Pool>> where AV <: ConstValue {
    private let childrenMap: ChildrenMap = ChildrenMap()
    private let allocatedRefMap: AllocatedRefMap = AllocatedRefMap()
    private let allocatedTwoLevelRefMap: AllocatedRefMap = AllocatedRefMap()
    private let allocatedObjMap: AllocatedObjMap = AllocatedObjMap()
    private let refPool: ArrayList<Ref> = ArrayList<Ref>()
    private let absObjPool: ArrayList<AbstractObject> = ArrayList<AbstractObject>()
    protected let builder: CHIRBuilder

    public init(functionValue: Function, builder: CHIRBuilder, isDebug!: Bool = false) {
        super(functionValue, isDebug: isDebug)
        this.builder = builder
    }

    public static func ResetGlobalState(): Unit {
        ResetValueAnalysisGlobalState()
    }

    public static func InitialiseLetGVState(pkg: Package, builder: CHIRBuilder): Unit {
        ResetGlobalState()
        let globalState = GetValueAnalysisGlobalState<AV, Pool>()
        globalState.SetReachable(true)
        for (gv in pkg.GetGlobalVarsWithInit()) {
            if (!gv.TestAttr(Attribute.READONLY) || gv.GetInitFunc().isNone() || !IsTrackedGV(gv)) {
                continue
            }
            let realTy = (gv.GetType().getOrThrow() as RefType).getOrThrow().GetBaseType()
            if (realTy.IsRef()) {
                let refValue = globalState.CreateNewRef()
                globalState.programState.SetRef(gv, refValue)
                let oRef = globalState.CreateNewRef()
                globalState.refMap.Set(refValue, RefMapValue.RefTarget(oRef))
                let obj = globalState.CreateNewObject(GetObjName(valueAnalysisGlobalAllocatedObjMap.Size()))
                globalState.refMap.Set(oRef, RefMapValue.ObjectTarget(obj))
                globalState.programState.SetBound(obj, true)
            } else {
                let obj = globalState.GetReferencedObjAndSetToTop(gv)
                SetObjChildrenStateToTop(globalState, obj, realTy, builder)
            }
        }
    }

    public override func Bottom(): State<AV, Pool> {
        return State<AV, Pool>(childrenMap, allocatedTwoLevelRefMap, allocatedRefMap, allocatedObjMap,
            refPool, absObjPool)
    }

    public override func InitializeFuncEntryState(state: State<AV, Pool>): Unit {
        state.SetReachable(true)
        for (param in this.`func`.GetParams()) {
            let paramTy = param.GetType().getOrThrow()
            if (paramTy.IsRef() || paramTy.IsGeneric()) {
                let refObj = state.GetReferencedObjAndSetToTop(param)
                HandleFuncParam(state, param, refObj)
            } else {
                state.programState.SetBound(param, true)
            }
        }
    }

    public override func InitializeLambdaEntryState(state: State<AV, Pool>): Unit {
        let lambda = currentLambda.getOrThrow()
        for (param in lambda.GetParams()) {
            let paramTy = param.GetType().getOrThrow()
            if (paramTy.IsRef() || paramTy.IsGeneric()) {
                let refObj = state.GetReferencedObjAndSetToTop(param)
                HandleFuncParam(state, param, refObj)
            } else {
                state.programState.SetBound(param, true)
            }
        }
    }

    public override func HandleVarStateCapturedByLambda(state: State<AV, Pool>, lambda: Lambda): Unit {
        for (value in GetLambdaCapturedVarsRecursively(lambda)) {
            state.SetSelfAndChildrenStateToTop(value)
        }
    }

    public override func PreHandleLambdaExpression(state: State<AV, Pool>, lambda: Lambda): Unit {
        state.SetToBound(lambda.GetResult().getOrThrow(), true)
    }

    public override func PropagateExpressionEffect(state: State<AV, Pool>, expression: Expression): Unit {
        match (expression.GetExprMajorKind()) {
            case ExprMajorKind.MEMORY_EXPR => PreHandleMemoryExpr(state, expression)
            case ExprMajorKind.UNARY_EXPR => ()
            case ExprMajorKind.BINARY_EXPR => ()
            case ExprMajorKind.OTHERS => PreHandleOthersExpr(state, expression)
            case ExprMajorKind.STRUCTURED_CTRL_FLOW_EXPR => InternalError("Unsupported major expr kind")
            case _ => InternalError("Unsupported major expr kind")
        }
        HandleNormalExpressionEffect(state, expression)
    }

    public override func PropagateTerminatorEffect(state: State<AV, Pool>, terminator: Terminator): Option<Block> {
        match (terminator.GetExprKind()) {
            case ExprKind.APPLY_WITH_EXCEPTION =>
                return PreHandleApplyWithExceptionExpr(state, (terminator as ApplyWithException).getOrThrow())
            case ExprKind.INVOKE_WITH_EXCEPTION =>
                return PreHandleInvokeWithExceptionExpr(state, (terminator as InvokeWithException).getOrThrow())
            case ExprKind.ALLOCATE_WITH_EXCEPTION =>
                let allocate = (terminator as AllocateWithException).getOrThrow()
                let refObj = PreHandleAllocateExpr(state, allocate)
                return HandleAllocateWithExceptionTerminator(state, allocate, refObj)
            case ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION =>
                return PreHandleRawArrayAllocateWithException(state,
                    (terminator as RawArrayAllocateWithException).getOrThrow())
            case ExprKind.INTRINSIC_WITH_EXCEPTION =>
                let intrinsic = (terminator as IntrinsicWithException).getOrThrow()
                if (intrinsic.GetIntrinsicKind() == IntrinsicKind.INOUT_PARAM) {
                    return PreHandleInoutIntrinsicWithException(state, intrinsic)
                }
            case _ => ()
        }
        return HandleTerminatorEffect(state, terminator)
    }

    protected open func PreHandleGetElementRefExpr(state: State<AV, Pool>, getElemRef: GetElementRef): Unit {
        let dest = getElemRef.GetResult().getOrThrow()
        if (!state.programState.Contains(dest)) {
            let destRef = state.CreateNewRef(expr: Some(getElemRef))
            state.programState.SetRef(dest, destRef)
            state.refMap.Set(destRef, RefMapValue.ObjectTarget(FindTargetElement(state, getElemRef)))
        } else {
            let domain = state.programState.At(dest)
            CJC_ASSERT(domain.GetKind() == ValueDomainKind.REF)
            let destRef = domain.GetRef().getOrThrow()
            CJC_ASSERT(state.refMap.Get(destRef).isSome())
            state.refMap.Set(destRef, RefMapValue.ObjectTarget(FindTargetElement(state, getElemRef)))
        }
    }

    protected open func PreHandleFieldExpr(state: State<AV, Pool>, field: Field): Unit {
        let dest = field.GetResult().getOrThrow()
        let indexes = field.GetPath()
        if (indexes.size > 1) {
            if (!state.programState.Contains(dest)) {
                state.InitToTopOrTopRef(dest, dest.GetType().getOrThrow().IsRef())
            }
            return
        }
        if (let Some(children) <- childrenMap.Get(field.GetBase())) {
            let idx = Int64(indexes[0])
            if (idx < children.size) {
                state.PropagateWithoutChildren(children[idx], dest)
                return
            }
        }
        state.SetToTopOrTopRef(dest, dest.GetType().getOrThrow().IsRef())
    }

    private func PreHandleMemoryExpr(state: State<AV, Pool>, expression: Expression): Unit {
        match (expression.GetExprKind()) {
            case ExprKind.ALLOCATE =>
                let allocate = (expression as Allocate).getOrThrow()
                let refObj = PreHandleAllocateExpr(state, allocate)
                HandleAllocateExpr(state, allocate, refObj)
            case ExprKind.LOAD => PreHandleLoadExpr(state, (expression as Load).getOrThrow())
            case ExprKind.STORE => PreHandleStoreExpr(state, (expression as Store).getOrThrow())
            case ExprKind.GET_ELEMENT_REF =>
                PreHandleGetElementRefExpr(state, (expression as GetElementRef).getOrThrow())
            case ExprKind.STORE_ELEMENT_REF =>
                PreHandleStoreElementRefExpr(state, (expression as StoreElementRef).getOrThrow())
            case _ => InternalError("Unexpected memory expr")
        }
    }

    private func PreHandleOthersExpr(state: State<AV, Pool>, expression: Expression): Bool {
        match (expression.GetExprKind()) {
            case ExprKind.CONSTANT =>
                PreHandleConstantExpr(state, (expression as Constant).getOrThrow())
                return true
            case ExprKind.DEBUGEXPR => return true
            case ExprKind.TUPLE =>
                PreHandleTupleExpr(state, (expression as Tuple).getOrThrow())
                return true
            case ExprKind.FIELD =>
                PreHandleFieldExpr(state, (expression as Field).getOrThrow())
                return true
            case ExprKind.APPLY =>
                PreHandleApplyExpr(state, (expression as Apply).getOrThrow())
                return true
            case ExprKind.INVOKE =>
                PreHandleInvokeExpr(state, (expression as Invoke).getOrThrow())
                return true
            case ExprKind.TYPECAST =>
                let cast = (expression as TypeCast).getOrThrow()
                if (!cast.GetNeedCheckCast()) {
                    return PreHandleNonCheckedTypeCast(state, cast)
                }
                return false
            case ExprKind.RAW_ARRAY_ALLOCATE =>
                PreHandleRawArrayAllocate(state, (expression as RawArrayAllocate).getOrThrow())
                return true
            case ExprKind.INTRINSIC =>
                let intrinsic = (expression as Intrinsic).getOrThrow()
                if (intrinsic.GetIntrinsicKind() == IntrinsicKind.INOUT_PARAM) {
                    PreHandleInoutIntrinsic(state, intrinsic)
                    return true
                }
                return false
            case _ => return false
        }
    }

    private func PreHandleConstantExpr(state: State<AV, Pool>, constant: Constant): Unit {
        let dest = constant.GetResult().getOrThrow()
        if (state.programState.Contains(dest)) {
            return
        }
        if (constant.IsConstantNull()) {
            if (dest.GetType().getOrThrow().IsRef()) {
                state.programState.SetRef(dest, Ref.GetTopRefInstance())
            } else {
                state.programState.SetBound(dest, true)
            }
        } else {
            state.programState.Insert(dest, HandleNonNullLiteralValue<AV>(constant.GetValue(), typed: true))
        }
    }

    private func FindTargetElement(state: State<AV, Pool>, elemRef: GetElementRef): AbstractObject {
        return FindTargetElementImpl(state, elemRef.GetLocation(), elemRef.GetPath())
    }

    private func FindTargetElement(state: State<AV, Pool>, elemRef: StoreElementRef): AbstractObject {
        return FindTargetElementImpl(state, elemRef.GetLocation(), elemRef.GetPath())
    }

    private func FindTargetElementImpl(state: State<AV, Pool>, loc: Value,
        paths: ArrayList<UInt64>): AbstractObject {
        if (loc.IsGlobal() || loc.TestAttr(Attribute.STATIC)) {
            return AbstractObject.GetTopObjInstance()
        }
        if (paths.size > 1) {
            return AbstractObject.GetTopObjInstance()
        }
        let locVal = state.CheckAbstractValueWithTopBottom(loc)
        if (locVal.isNone()) {
            if (isDebug) {
                println("Value Analysis: use-before-initialization detected")
            }
            return AbstractObject.GetTopObjInstance()
        }
        let domain = locVal.getOrThrow()
        CJC_ASSERT(domain.GetKind() == ValueDomainKind.REF)
        let locRef = domain.GetRef().getOrThrow()
        if (locRef.IsTopRefInstance()) {
            return AbstractObject.GetTopObjInstance()
        }
        let refValue = state.refMap.Get(locRef).getOrThrow()
        let rootObj = match (refValue) {
            case RefMapValue.ObjectTarget(obj) => obj
            case RefMapValue.RefTarget(_) => throw IllegalStateException("ValueAnalysis expected object ref target")
        }
        let children = state.childrenMap.Get(rootObj) ?? return AbstractObject.GetTopObjInstance()
        let idx = Int64(paths[0])
        if (idx >= children.size) {
            return AbstractObject.GetTopObjInstance()
        }
        return children[idx]
    }

    private func PreHandleStoreExpr(state: State<AV, Pool>, store: Store): Unit {
        let value = store.GetValue()
        if (value.IsGlobal() || value.TestAttr(Attribute.STATIC)) {
            return
        }
        let location = store.GetLocation()
        if (location.IsGlobal() || location.TestAttr(Attribute.STATIC)) {
            HandleStoreToGlobal(state, location, value)
            return
        }
        let valDomain = state.CheckAbstractValueWithTopBottom(value).getOrThrow()
        let locDomain = state.CheckAbstractValueWithTopBottom(location).getOrThrow()
        CJC_ASSERT(locDomain.GetKind() == ValueDomainKind.REF)
        let locRef = locDomain.GetRef().getOrThrow()
        if (locRef.IsTopRefInstance()) {
            return
        }
        if (let Some(locRefVal) <- state.refMap.Get(locRef)) {
            match (locRefVal) {
                case RefMapValue.ObjectTarget(dest) =>
                    if (!dest.IsTopObjInstance()) {
                        let local = (location as LocalVar).getOrThrow()
                        if (local.GetExpr().getOrThrow().GetExprKind() == ExprKind.GET_ELEMENT_REF) {
                            state.PropagateWithoutChildren(value, dest)
                        } else {
                            state.Propagate(value, dest)
                        }
                    }
                case RefMapValue.RefTarget(_) =>
                    CJC_ASSERT(valDomain.GetKind() == ValueDomainKind.REF)
                    state.refMap.Set(locRef, RefMapValue.RefTarget(valDomain.GetRef().getOrThrow()))
            }
        } else {
            CJC_ASSERT(valDomain.GetKind() == ValueDomainKind.REF)
            state.refMap.Set(locRef, RefMapValue.RefTarget(valDomain.GetRef().getOrThrow()))
        }
    }

    private func HandleStoreToGlobal(state: State<AV, Pool>, location: Value, value: Value): Unit {
        if (isStable || !location.IsGlobalVarWithInitializer()) {
            return
        }
        let globalState = GetValueAnalysisGlobalState<AV, Pool>()
        let gv = (location as GlobalVar).getOrThrow()
        if (!gv.TestAttr(Attribute.READONLY) || !globalState.programState.Contains(gv)) {
            return
        }
        let targetObj = globalState.CheckAbstractObjectRefBy(gv).getOrThrow()
        if (gv.GetType().getOrThrow().GetRefDims() == 1) {
            state.PropagateWithoutChildren(value, targetObj, targetProgramState: Some(globalState.programState))
            state.StoreGVChildrenState(value, targetObj, globalState)
        } else {
            CJC_ASSERT(globalState.GetChildren(targetObj).isEmpty())
            if (let Some(srcObj) <- state.CheckAbstractObjectRefBy(value)) {
                state.PropagateWithoutChildren(srcObj, targetObj, targetProgramState: Some(globalState.programState))
            } else {
                globalState.Update(targetObj, ValueDomain<AV>(true))
            }
        }
    }

    private func PreHandleLoadExpr(state: State<AV, Pool>, load: Load): Unit {
        let loc = load.GetLocation()
        if (loc.IsGlobal() || loc.TestAttr(Attribute.STATIC)) {
            HandleLoadFromGlobal(state, load)
            return
        }
        let dest = load.GetResult().getOrThrow()
        let locVal = state.CheckAbstractValueWithTopBottom(loc).getOrThrow()
        CJC_ASSERT(locVal.GetKind() == ValueDomainKind.REF)
        let locRef = locVal.GetRef().getOrThrow()
        if (locRef.IsTopRefInstance()) {
            state.SetToTopOrTopRef(dest, dest.GetType().getOrThrow().IsRef())
            return
        }
        let refValOpt = state.refMap.Get(locRef)
        if (refValOpt.isNone()) {
            if (isDebug) {
                println("Value Analysis: use-before-initialization detected")
            }
            return
        }
        match (refValOpt.getOrThrow()) {
            case RefMapValue.RefTarget(refValue) =>
                CJC_ASSERT(dest.GetType().getOrThrow().IsRef())
                state.Update(dest, refValue)
            case RefMapValue.ObjectTarget(obj) =>
                if (obj.IsTopObjInstance()) {
                    state.SetToTopOrTopRef(dest, dest.GetType().getOrThrow().IsRef())
                } else {
                    state.Propagate(obj, dest)
                }
        }
    }

    private func HandleLoadFromGlobal(state: State<AV, Pool>, load: Load): Unit {
        let dest = load.GetResult().getOrThrow()
        if (state.programState.Contains(dest)) {
            return
        }
        let globalState = GetValueAnalysisGlobalState<AV, Pool>()
        let loc = load.GetLocation()
        if (!loc.IsGlobalVarWithInitializer()) {
            state.InitToTopOrTopRef(dest, dest.GetType().getOrThrow().IsRef())
            return
        }
        let globalVar = (loc as GlobalVar).getOrThrow()
        if (!globalVar.TestAttr(Attribute.READONLY)) {
            state.InitToTopOrTopRef(dest, dest.GetType().getOrThrow().IsRef())
            return
        }
        if (let Some(initializer) <- globalVar.GetInitializer()) {
            CJC_ASSERT(!initializer.IsNullLit())
            state.programState.Insert(dest, HandleNonNullLiteralValue<AV>(initializer, typed: true))
        } else {
            let gvDomain = globalState.CheckAbstractValueWithTopBottom(globalVar)
            if (gvDomain.isNone()) {
                state.InitToTopOrTopRef(dest, dest.GetType().getOrThrow().IsRef())
                return
            }
            let gRef = gvDomain.getOrThrow().GetRef().getOrThrow()
            let gRefVal = globalState.refMap.Get(gRef).getOrThrow()
            match (gRefVal) {
                case RefMapValue.RefTarget(oRef) =>
                    state.programState.SetRef(dest, oRef)
                    let obj = match (globalState.refMap.Get(oRef).getOrThrow()) {
                        case RefMapValue.ObjectTarget(value) => value
                        case RefMapValue.RefTarget(_) =>
                            throw IllegalStateException("ValueAnalysis global ref expected object")
                    }
                    state.refMap.Set(oRef, RefMapValue.ObjectTarget(obj))
                    state.programState.Insert(obj, globalState.programState.At(obj))
                case RefMapValue.ObjectTarget(obj) =>
                    globalState.PropagateWithoutChildren(obj, dest, targetProgramState: Some(state.programState))
                    state.LoadGVChildrenState(obj, dest, globalState)
            }
        }
    }

    private func PreHandleStoreElementRefExpr(state: State<AV, Pool>, storeElemRef: StoreElementRef): Unit {
        let value = storeElemRef.GetValue()
        if (value.IsGlobal() || value.TestAttr(Attribute.STATIC)) {
            return
        }
        let targetObj = FindTargetElement(state, storeElemRef)
        if (targetObj.IsTopObjInstance()) {
            return
        }
        state.PropagateWithoutChildren(value, targetObj)
    }

    private func PreHandleAllocateExpr(state: State<AV, Pool>, allocate: Allocate): Option<Value> {
        return PreHandleAllocateExprImpl(state, allocate.GetResult().getOrThrow(), allocate.GetType(), allocate)
    }

    private func PreHandleAllocateExpr(state: State<AV, Pool>, allocate: AllocateWithException): Option<Value> {
        return PreHandleAllocateExprImpl(state, allocate.GetResult().getOrThrow(), allocate.GetType(), allocate)
    }

    private func PreHandleAllocateExprImpl(state: State<AV, Pool>, dest: LocalVar, allocatedTy: Type,
        allocate: Expression): Option<Value> {
        if (allocatedTy.IsRef()) {
            state.programState.SetRef(dest, state.CreateNewRef(expr: Some(allocate)))
            return None
        }
        let obj = state.GetReferencedObjAndSetToTop(dest, expr: Some(allocate))
        SetObjChildrenStateToTop(state, obj, allocatedTy, builder)
        return obj
    }

    private func PreHandleApplyExpr(state: State<AV, Pool>, apply: Apply): Unit {
        if (apply.GetCallee().TestAttr(Attribute.MUT)) {
            let structArg = apply.GetArgs()[0]
            let structTy = (structArg.GetType().getOrThrow() as RefType).getOrThrow().GetBaseType()
            if (structTy.IsStruct()) {
                if (let Some(obj) <- state.CheckAbstractObjectRefBy(structArg)) {
                    if (childrenMap.Get(obj).isSome()) {
                        SetObjChildrenStateToTop(state, obj, structTy, builder)
                    }
                }
            } else {
                CJC_ASSERT(structTy.IsClass())
            }
        }
        let refObj = PreHandleFuncCall(state, apply.GetResult().getOrThrow(), apply)
        HandleApplyExpr(state, apply, refObj)
    }

    private func PreHandleApplyWithExceptionExpr(state: State<AV, Pool>,
        apply: ApplyWithException): Option<Block> {
        let refObj = PreHandleFuncCall(state, apply.GetResult().getOrThrow(), apply)
        return HandleApplyWithExceptionTerminator(state, apply, refObj)
    }

    private func PreHandleInvokeExpr(state: State<AV, Pool>, invoke: Invoke): Unit {
        let refObj = PreHandleFuncCall(state, invoke.GetResult().getOrThrow(), invoke)
        HandleInvokeExpr(state, invoke, refObj)
    }

    private func PreHandleInvokeWithExceptionExpr(state: State<AV, Pool>,
        invoke: InvokeWithException): Option<Block> {
        let refObj = PreHandleFuncCall(state, invoke.GetResult().getOrThrow(), invoke)
        return HandleInvokeWithExceptionTerminator(state, invoke, refObj)
    }

    private func PreHandleFuncCall(state: State<AV, Pool>, dest: LocalVar, callExpr: Expression): Option<Value> {
        let ty = dest.GetType().getOrThrow()
        if (ty.IsRef() || ty.IsGeneric()) {
            return state.GetReferencedObjAndSetToTop(dest, expr: Some(callExpr))
        }
        state.SetToBound(dest, true)
        SetObjChildrenStateToTop(state, dest, ty, builder)
        return None
    }

    public static func SetObjChildrenStateToTop(state: State<AV, Pool>, root: Value, rootTy: Type,
        builder: CHIRBuilder): Unit {
        let childrenTypes = ArrayList<Bool>()
        if (rootTy.GetTypeKind() == TypeKind.TYPE_STRUCT) {
            let structTy = (rootTy as StructType).getOrThrow()
            let structDef = structTy.GetStructDef()
            if (structTy.IsStructArray()) {
                childrenTypes.add(true)
                childrenTypes.add(false)
                childrenTypes.add(false)
            } else if (!structDef.IsCStruct()) {
                for (ty in structTy.GetInstantiatedMemberTys()) {
                    childrenTypes.add(ty.IsRef())
                }
            }
        } else if (rootTy.GetTypeKind() == TypeKind.TYPE_TUPLE) {
            let tupleTy = (rootTy as TupleType).getOrThrow()
            for (ty in tupleTy.GetElementTypes()) {
                childrenTypes.add(ty.IsRef())
            }
        } else if (rootTy.GetTypeKind() == TypeKind.TYPE_ENUM) {
            childrenTypes.add(false)
        } else if (rootTy.GetTypeKind() == TypeKind.TYPE_CLASS) {
            let classTy = (rootTy as ClassType).getOrThrow()
            let classDef = classTy.GetClassDef()
            if (StartsWith(classDef.GetSrcCodeIdentifier(), "$BOX_RNat5Array")) {
                childrenTypes.add(classDef.GetInstanceVar(0).ty.IsRef())
            }
        }

        if (let Some(children) <- state.childrenMap.Get(root)) {
            CJC_ASSERT(children.size == childrenTypes.size)
            var idx: Int64 = 0
            while (idx < children.size) {
                state.SetToTopOrTopRef(children[idx], childrenTypes[idx])
                idx++
            }
        } else {
            let setChildState = { child: AbstractObject, index: Int64 =>
                state.SetToTopOrTopRef(child, childrenTypes[index])
            }
            state.CreateChildren(root, childrenTypes.size, setChildState)
        }
        let _ = builder
    }

    private func PreHandleTupleExpr(state: State<AV, Pool>, tuple: Tuple): Unit {
        let result = tuple.GetResult().getOrThrow()
        state.SetToBound(result, true)
        let operands = tuple.GetOperands()
        let operandNum = if (result.GetType().getOrThrow().IsEnum()) { 1 } else { operands.size }
        if (let Some(children) <- childrenMap.Get(result)) {
            CJC_ASSERT(children.size == operandNum)
            var idx: Int64 = 0
            while (idx < operandNum) {
                state.PropagateWithoutChildren(operands[idx], children[idx])
                idx++
            }
        } else {
            let setChildState = { child: AbstractObject, index: Int64 =>
                state.PropagateWithoutChildren(operands[index], child)
            }
            state.CreateChildren(result, operandNum, setChildState)
        }
    }

    private func PreHandleNonCheckedTypeCast(state: State<AV, Pool>, cast: TypeCast): Bool {
        let dest = cast.GetResult().getOrThrow()
        let users = dest.GetUsers()
        if (users.size == 1 && users[0].GetExprKind() == ExprKind.MULTIBRANCH) {
            return false
        }
        let ty = dest.GetType().getOrThrow()
        if (ty.IsRef()) {
            let targetClassDef = GetClassDefFromRefType(ty)
            let isCollection = if (let Some(classDef) <- targetClassDef) {
                classDef.GetSrcCodeIdentifier() == "Collection" && classDef.GetPackageName() == CORE_PACKAGE_NAME
            } else {
                false
            }
            let sourceClassDef = GetClassDefFromRefType(cast.GetSourceTy().getOrThrow())
            let isBoxArray = if (let Some(classDef) <- sourceClassDef) {
                StartsWith(classDef.GetSrcCodeIdentifier(), BOX_DECL_PREFIX) &&
                    classDef.GetAllInstanceVarNum() == 1 && classDef.GetInstanceVar(0).ty.IsStructArray()
            } else {
                false
            }
            if (isBoxArray && isCollection) {
                return false
            }
            state.GetReferencedObjAndSetToTop(dest, expr: Some(cast))
        } else {
            state.SetToBound(dest, true)
            SetObjChildrenStateToTop(state, dest, ty, builder)
        }
        return true
    }

    private func PreHandleRawArrayAllocate(state: State<AV, Pool>, allocate: RawArrayAllocate): Option<Block> {
        state.GetReferencedObjAndSetToTop(allocate.GetResult().getOrThrow(), expr: Some(allocate))
        return None
    }

    private func PreHandleRawArrayAllocateWithException(state: State<AV, Pool>,
        allocate: RawArrayAllocateWithException): Option<Block> {
        state.GetReferencedObjAndSetToTop(allocate.GetResult().getOrThrow(), expr: Some(allocate))
        return None
    }

    private func PreHandleInoutIntrinsic(state: State<AV, Pool>, intrinsic: Intrinsic): Option<Block> {
        let param = intrinsic.GetOperand(0)
        if (!param.IsLocalVar()) {
            return None
        }
        state.SetSelfAndChildrenStateToTop(param)
        return None
    }

    private func PreHandleInoutIntrinsicWithException(state: State<AV, Pool>,
        intrinsic: IntrinsicWithException): Option<Block> {
        let param = intrinsic.GetOperand(0)
        if (!param.IsLocalVar()) {
            return None
        }
        state.SetSelfAndChildrenStateToTop(param)
        return None
    }

    public open func HandleFuncParam(state: State<AV, Pool>, param: Parameter, refObj: Value): Unit {
        let _ = state
        let _ = param
        let _ = refObj
    }

    public open func HandleAllocateExpr(state: State<AV, Pool>, expression: Allocate, refObj: Option<Value>): Unit {
        let _ = state
        let _ = expression
        let _ = refObj
    }

    public open func HandleAllocateWithExceptionTerminator(state: State<AV, Pool>,
        allocate: AllocateWithException, refObj: Option<Value>): Option<Block> {
        let _ = state
        let _ = allocate
        let _ = refObj
        return None
    }

    public open func HandleApplyExpr(state: State<AV, Pool>, apply: Apply, refObj: Option<Value>): Unit {
        let _ = state
        let _ = apply
        let _ = refObj
    }

    public open func HandleApplyWithExceptionTerminator(state: State<AV, Pool>,
        apply: ApplyWithException, refObj: Option<Value>): Option<Block> {
        let _ = state
        let _ = apply
        let _ = refObj
        return None
    }

    public open func HandleInvokeExpr(state: State<AV, Pool>, invoke: Invoke, refObj: Option<Value>): Unit {
        let _ = state
        let _ = invoke
        let _ = refObj
    }

    public open func HandleInvokeWithExceptionTerminator(state: State<AV, Pool>,
        invoke: InvokeWithException, refObj: Option<Value>): Option<Block> {
        let _ = state
        let _ = invoke
        let _ = refObj
        return None
    }

    public open func HandleNormalExpressionEffect(state: State<AV, Pool>, expression: Expression): Unit {
        let _ = state
        let _ = expression
    }

    public open func HandleTerminatorEffect(state: State<AV, Pool>, terminator: Terminator): Option<Block> {
        let _ = state
        let _ = terminator
        return None
    }

    private static func GetClassDefFromRefType(ty: Type): Option<ClassDef> {
        if (!ty.IsRef()) {
            return None
        }
        let baseTy = (ty as RefType).getOrThrow().GetBaseType()
        if (!baseTy.IsClass()) {
            return None
        }
        return (baseTy as ClassType).getOrThrow().GetClassDef()
    }

    private static func StartsWith(value: String, prefix: String): Bool {
        if (let Some(index) <- value.indexOf(prefix)) {
            return index == 0
        }
        return false
    }
}
