package cjcj::chir

import std.collection.*
import cjcj::utils.{CJC_ASSERT, OverflowStrategy}

public open class Terminator <: Expression {
    public init(kind: ExprKind, operands: ArrayList<Value>, successors: ArrayList<Block>, parent: Option<Block>) {
        super(kind, operands, parent)
        for (successor in successors) { this.operands.add(successor) }
    }
}

public class GoTo <: Terminator {
    public init(target: Block, parent: Option<Block>) {
        super(ExprKind.GOTO, ArrayList<Value>(), MakeOneSuccessor(target), parent)
    }

    public func GetDestination(): Block {
        return GetSuccessor(0)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateGoTo(GetDestination(), parent)
        return cloned
    }
}

public class Branch <: Terminator {
    private var sourceExpr: SourceExpr = SourceExpr.OTHER

    public init(cond: Value, trueBlock: Block, falseBlock: Block, parent: Option<Block>) {
        super(ExprKind.BRANCH, MakeUnaryTermOperands(cond), MakeTwoSuccessors(trueBlock, falseBlock), parent)
    }

    public func GetCondition(): Value {
        return GetOperand(0)
    }

    public func GetTrueBlock(): Block {
        return GetSuccessor(0)
    }

    public func GetFalseBlock(): Block {
        return GetSuccessor(1)
    }

    public func SetSourceExpr(srcExpr: SourceExpr): Unit {
        sourceExpr = srcExpr
    }

    public func GetSourceExpr(): SourceExpr {
        return sourceExpr
    }

    public override func AddExtraComment(): String {
        let base = super.AddExtraComment()
        if (sourceExpr == SourceExpr.OTHER) {
            return base
        }
        if (base.isEmpty()) {
            return SourceExprName(sourceExpr)
        }
        return base + " " + SourceExprName(sourceExpr)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateBranch(GetCondition(), GetTrueBlock(), GetFalseBlock(), parent)
        cloned.SetSourceExpr(GetSourceExpr())
        return cloned
    }
}

public class MultiBranch <: Terminator {
    private var sourceExpr: SourceExpr = SourceExpr.OTHER
    public func SetSourceExpr(value: SourceExpr): Unit { sourceExpr = value }
    public func GetSourceExpr(): SourceExpr { return sourceExpr }
    private let caseVals: ArrayList<UInt64> = ArrayList<UInt64>()

    public init(cond: Value, defaultBlock: Block, vals: ArrayList<UInt64>, succs: ArrayList<Block>,
        parent: Option<Block>) {
        super(ExprKind.MULTIBRANCH, MakeUnaryTermOperands(cond), MakeMultiBranchSuccessors(defaultBlock, succs), parent)
        for (caseValue in vals) {
            caseVals.add(caseValue)
        }
    }

    public func GetCondition(): Value {
        return GetOperand(0)
    }

    public func GetCaseVals(): ArrayList<UInt64> {
        let out = ArrayList<UInt64>()
        for (caseValue in caseVals) {
            out.add(caseValue)
        }
        return out
    }

    public func GetCaseValByIndex(index: Int64): UInt64 {
        return caseVals[index]
    }

    public func GetCaseBlockByIndex(index: Int64): Block {
        return GetSuccessor(index + 1)
    }

    public func GetDefaultBlock(): Block {
        return GetSuccessor(0)
    }

    public func GetNormalBlocks(): ArrayList<Block> {
        let out = ArrayList<Block>()
        var idx: Int64 = 1
        while (idx < GetNumOfSuccessor()) {
            out.add(GetSuccessor(idx))
            idx++
        }
        return out
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(GetCondition().GetIdentifier())
        parts.add(GetDefaultBlock().GetIdentifier())
        var idx: Int64 = 0
        while (idx < caseVals.size) {
            parts.add("[${caseVals[idx]}, ${GetCaseBlockByIndex(idx).GetIdentifier()}]")
            idx++
        }
        return JoinStrings(parts, ", ")
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateMultiBranch(GetCondition(), GetDefaultBlock(), GetCaseVals(), GetNormalBlocks(),
            parent)
        cloned.SetSourceExpr(sourceExpr)
        return cloned
    }
}

public class Exit <: Terminator {
    public init(value: Option<Value>, parent: Option<Block>) {
        super(ExprKind.EXIT, MakeOptionalTermOperands(value), ArrayList<Block>(), parent)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        var exitValue: Option<Value> = None
        if (GetNumOfNonSuccessorOperands() > 0) {
            exitValue = GetOperand(0)
        }
        let cloned = builder.CreateExit(exitValue, parent)
        return cloned
    }
}

public class RaiseException <: Terminator {
    public init(value: Value, parent: Option<Block>) {
        super(ExprKind.RAISE_EXCEPTION, MakeUnaryTermOperands(value), ArrayList<Block>(), parent)
    }

    public init(value: Value, exceptionBlock: Block, parent: Option<Block>) {
        super(ExprKind.RAISE_EXCEPTION, MakeUnaryTermOperands(value), MakeOneSuccessor(exceptionBlock), parent)
    }

    public func GetExceptionValue(): Value {
        return GetOperand(0)
    }

    public func GetExceptionBlock(): Option<Block> {
        if (GetNumOfSuccessor() == 0) {
            return None
        }
        return GetSuccessor(0)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = if (let Some(exceptionBlock) <- GetExceptionBlock()) {
            builder.CreateRaiseException(GetExceptionValue(), exceptionBlock, parent)
        } else {
            builder.CreateRaiseException(GetExceptionValue(), parent)
        }
        return cloned
    }
}

public open class ExpressionWithException <: Terminator {
    public init(kind: ExprKind, operands: ArrayList<Value>, successBlock: Block, errorBlock: Block,
        parent: Option<Block>) {
        super(kind, operands, MakeTwoSuccessors(successBlock, errorBlock), parent)
    }

    public func GetSuccessBlock(): Block {
        return GetSuccessor(0)
    }

    public func GetErrorBlock(): Block {
        return GetSuccessor(1)
    }
}

public open class FuncCallWithException <: ExpressionWithException {
    private let instantiatedTypeArgs: ArrayList<Type> = ArrayList<Type>()
    private var thisType: Option<Type> = None

    public init(kind: ExprKind, operands: ArrayList<Value>, callContext: FuncCallContext, successBlock: Block,
        errorBlock: Block, parent: Option<Block>) {
        super(kind, operands, successBlock, errorBlock, parent)
        for (ty in callContext.instTypeArgs) {
            instantiatedTypeArgs.add(ty)
        }
        thisType = callContext.thisType
    }

    public open func GetArgs(): ArrayList<Value> {
        return ArrayList<Value>()
    }

    public func GetThisType(): Option<Type> {
        return thisType
    }

    public func SetThisType(ty: Type): Unit {
        thisType = ty
    }

    public func GetInstantiatedTypeArgs(): ArrayList<Type> {
        return instantiatedTypeArgs.clone()
    }

    public func SetInstantiatedTypeArgs(args: ArrayList<Type>): Unit {
        instantiatedTypeArgs.clear()
        for (ty in args) {
            instantiatedTypeArgs.add(ty)
        }
    }

    protected func CallTargetPrefix(): String {
        if (let Some(ty) <- thisType) {
            return ty.ToString() + "->"
        }
        return ""
    }

    protected func InstantiatedTypeArgsToString(): String {
        if (instantiatedTypeArgs.isEmpty()) {
            return ""
        }
        let parts = ArrayList<String>()
        for (ty in instantiatedTypeArgs) {
            parts.add(ty.ToString())
        }
        return "<" + JoinStrings(parts, ",") + ">"
    }
}

public class TryApply <: FuncCallWithException {
    public init(callee: Value, callContext: FuncCallContext, successBlock: Block, errorBlock: Block,
        parent: Option<Block>) {
        super(ExprKind.TRY_APPLY, MakeTryApplyOperands(callee, callContext.args), callContext,
            successBlock, errorBlock, parent)
    }

    public func GetCallee(): Value {
        return GetOperand(0)
    }

    public func GetInstParentCustomTyOfCallee(builder: CHIRBuilder): Option<Type> {
        return GetInstParentCustomTypeForAweCallee(this, builder)
    }

    public override func GetArgs(): ArrayList<Value> {
        let out = ArrayList<Value>()
        var idx: Int64 = 1
        while (idx < GetNumOfNonSuccessorOperands()) {
            out.add(GetOperand(idx))
            idx++
        }
        return out
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(CallTargetPrefix() + GetCallee().GetIdentifier() + InstantiatedTypeArgsToString())
        parts.add(TerminatorValueIdsToString(GetArgs()))
        return JoinStrings(parts, ", ")
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let callContext = FuncCallContext(args: GetArgs(), instTypeArgs: GetInstantiatedTypeArgs(),
            thisType: GetThisType())
        let cloned = builder.CreateTryApply(GetResult().getOrThrow().GetType().getOrThrow(), GetCallee(), callContext,
            GetSuccessBlock(), GetErrorBlock(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public open class DynamicDispatchWithException <: FuncCallWithException {
    let overflowStrategy: OverflowStrategy
    private var virtualMethodOffset: Option<UInt64> = None

    public init(kind: ExprKind, callContext: InvokeCallContext, successBlock: Block, errorBlock: Block,
        parent: Option<Block>) {
        super(kind, MakeTryInvokeOperands(callContext.method, callContext.caller,
            callContext.funcCallCtx.args),
            callContext.funcCallCtx, successBlock, errorBlock, parent)
        overflowStrategy = callContext.overflowStrategy
        CJC_ASSERT(callContext.overflowStrategy != OverflowStrategy.CHECKED)
    }

    public func GetCallee(): Function {
        return (GetOperand(0) as Function).getOrThrow()
    }

    public func GetMethodName(): String {
        let name = GetCallee().GetSrcCodeIdentifier()
        if (overflowStrategy != OverflowStrategy.NA) {
            return OverflowStrategyPrefix(overflowStrategy) + name
        }
        return name
    }

    public func GetMethodType(): FuncType {
        return GetCallee().GetFuncType().getOrThrow()
    }

    public func GetGenericTypeParams(): ArrayList<GenericType> {
        return GetCallee().GetGenericTypeParams()
    }

    public func SetVirtualMethodOffset(offset: UInt64): Unit {
        virtualMethodOffset = offset
    }

    public func GetStoredVirMethodOffset(): Option<UInt64> {
        return virtualMethodOffset
    }

    public func GetVirtualMethodOffset(): UInt64 {
        if (let Some(offset) <- virtualMethodOffset) {
            return offset
        }
        return ComputeUnsetVirtualMethodOffset(GetCallee(), GetMethodName())
    }

    public func GetInstSrcParentCustomTypeOfMethod(builder: CHIRBuilder): ClassType {
        // #275 AutoEnv kept; the lookup itself matches 09/04 GetInstParentCustomTyOfCallee.
        if (let Some(thisTy) <- GetThisType()) {
            let stripped = thisTy.StripAllRefs()
            if (stripped.IsAutoEnv()) {
                if (let Some(ct) <- (stripped as ClassType)) {
                    return ct
                }
            }
        }
        var thisTypeDeref = (GetThisType() ??
            throw IllegalStateException("dynamic dispatch with exception thisType is missing")).StripAllRefs()
        if (thisTypeDeref.IsThis()) {
            thisTypeDeref = GetTopLevelFunc().getOrThrow().GetParentCustomTypeDef().getOrThrow().GetType().getOrThrow()
        }
        let parent = GetInstParentCustomTyOfCallee(GetCallee(), GetArgs(), Some(thisTypeDeref), builder).getOrThrow()
        return (parent as ClassType).getOrThrow()
    }

    public func GetVirtualMethodAttr(): AttributeInfo {
        return GetCallee().GetAttributeInfo()
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(CallTargetPrefix() + GetCallee().GetIdentifier() + InstantiatedTypeArgsToString())
        let operands = GetNonSuccessorOperands()
        operands.remove(at: 0)
        parts.add(TerminatorValueIdsToString(operands))
        return JoinStrings(parts, ", ")
    }

    public override func AddExtraComment(): String {
        if (overflowStrategy != OverflowStrategy.NA) {
            return "methodName: " + GetMethodName()
        }
        return ""
    }
}

public class TryInvoke <: DynamicDispatchWithException {
    public init(callContext: InvokeCallContext, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.TRY_INVOKE, callContext, successBlock, errorBlock, parent)
    }

    public func GetObject(): Value {
        return GetOperand(1)
    }

    public override func GetArgs(): ArrayList<Value> {
        let operands = GetNonSuccessorOperands()
        operands.remove(at: 0)
        return operands
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let args = GetArgs()
        args.remove(at: 0)
        let funcContext = FuncCallContext(args: args, instTypeArgs: GetInstantiatedTypeArgs(), thisType: GetThisType())
        let invokeContext = InvokeCallContext(GetCallee(), GetObject(), funcContext,
            overflowStrategy: overflowStrategy)
        let cloned = builder.CreateTryInvoke(GetResult().getOrThrow().GetType().getOrThrow(), invokeContext, GetSuccessBlock(),
            GetErrorBlock(), parent)
        if (let Some(offset) <- GetStoredVirMethodOffset()) {
            cloned.SetVirtualMethodOffset(offset)
        }
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class TryInvokeStatic <: DynamicDispatchWithException {
    public init(callContext: InvokeCallContext, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.TRY_INVOKESTATIC, callContext, successBlock, errorBlock, parent)
    }

    public func GetRTTIValue(): Value {
        return GetOperand(1)
    }

    public override func GetArgs(): ArrayList<Value> {
        let out = ArrayList<Value>()
        var idx: Int64 = 2
        while (idx < GetNumOfNonSuccessorOperands()) {
            out.add(GetOperand(idx))
            idx++
        }
        return out
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let funcContext = FuncCallContext(args: GetArgs(), instTypeArgs: GetInstantiatedTypeArgs(),
            thisType: GetThisType())
        let invokeContext = InvokeCallContext(GetCallee(), GetRTTIValue(), funcContext,
            overflowStrategy: overflowStrategy)
        let cloned = builder.CreateTryInvokeStatic(GetResult().getOrThrow().GetType().getOrThrow(), invokeContext,
            GetSuccessBlock(), GetErrorBlock(), parent)
        if (let Some(offset) <- GetStoredVirMethodOffset()) {
            cloned.SetVirtualMethodOffset(offset)
        }
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class TryUnaryExpression <: UnaryExpressionBase {
    public init(opKind: UnaryExprKind, operand: Value, successBlock: Block, errorBlock: Block, parent: Option<Block>,
        overflowStrategy!: OverflowStrategy = OverflowStrategy.NA) {
        super(opKind, operand, MakeTwoSuccessors(successBlock, errorBlock), parent, overflowStrategy: overflowStrategy,
            isTry: true)
    }

    public func GetSuccessBlock(): Block { return GetSuccessor(0) }
    public func GetErrorBlock(): Block { return GetSuccessor(1) }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateTryUnaryExpression(GetResult().getOrThrow().GetType().getOrThrow(),
            GetOpKind(), GetOperand(0), GetSuccessBlock(), GetErrorBlock(), parent)
        cloned.SetOverflowStrategy(GetOverflowStrategy())
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class TryBinaryExpression <: BinaryExpressionBase {
    public init(opKind: BinaryExprKind, left: Value, right: Value, successBlock: Block, errorBlock: Block,
        parent: Option<Block>, overflowStrategy!: OverflowStrategy = OverflowStrategy.NA) {
        super(opKind, left, right, MakeTwoSuccessors(successBlock, errorBlock), parent,
            overflowStrategy: overflowStrategy, isTry: true)
    }

    public func GetSuccessBlock(): Block { return GetSuccessor(0) }
    public func GetErrorBlock(): Block { return GetSuccessor(1) }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateTryBinaryExpression(GetResult().getOrThrow().GetType().getOrThrow(),
            GetOpKind(), GetLHSOperand(), GetRHSOperand(), GetSuccessBlock(), GetErrorBlock(), parent)
        cloned.SetOverflowStrategy(GetOverflowStrategy())
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class TryNumericCast <: NumericCastBase {
    public init(source: Value, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.TRY_NUMERIC_CAST, source, MakeTwoSuccessors(successBlock, errorBlock), parent, OverflowStrategy.THROWING)
    }
    public func GetSuccessBlock(): Block { return GetSuccessor(0) }
    public func GetErrorBlock(): Block { return GetSuccessor(1) }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateTryNumericCast(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(),
            GetSuccessBlock(), GetErrorBlock(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class TryIntrinsic <: ExpressionWithException {
    private let intrinsicKind: IntrinsicKind
    private let instantiatedTypeArgs: ArrayList<Type> = ArrayList<Type>()

    public init(callContext: IntrisicCallContext, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.TRY_INTRINSIC, callContext.args, successBlock, errorBlock, parent)
        intrinsicKind = callContext.kind
        for (ty in callContext.instTypeArgs) {
            instantiatedTypeArgs.add(ty)
        }
    }

    public func GetIntrinsicKind(): IntrinsicKind {
        return intrinsicKind
    }

    public func GetInstantiatedTypeArgs(): ArrayList<Type> {
        return instantiatedTypeArgs.clone()
    }

    public func SetInstantiatedTypeArgs(args: ArrayList<Type>): Unit {
        instantiatedTypeArgs.clear()
        for (ty in args) {
            instantiatedTypeArgs.add(ty)
        }
    }

    public func GetArgs(): ArrayList<Value> {
        return GetNonSuccessorOperands()
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(IntrinsicKindToString(intrinsicKind) + TypeVecToString("<", instantiatedTypeArgs, ">", delimiter: ","))
        parts.add(TerminatorValueIdsToString(GetArgs()))
        return JoinStrings(parts, ", ")
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let callContext = IntrisicCallContext(kind: GetIntrinsicKind(), args: GetArgs(),
            instTypeArgs: GetInstantiatedTypeArgs())
        let cloned = builder.CreateTryIntrinsic(GetResult().getOrThrow().GetType().getOrThrow(), callContext, GetSuccessBlock(),
            GetErrorBlock(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class TryAllocate <: AllocateBase {
    public init(ty: Type, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.TRY_ALLOCATE, ty, MakeTwoSuccessors(successBlock, errorBlock), parent)
    }
    public func GetSuccessBlock(): Block { return GetSuccessor(0) }
    public func GetErrorBlock(): Block { return GetSuccessor(1) }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateTryAllocate(GetResult().getOrThrow().GetType().getOrThrow(), GetType(), GetSuccessBlock(),
            GetErrorBlock(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class TryRawArrayAllocate <: RawArrayAllocateBase {
    public init(elementTy: Type, size: Value, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.TRY_RAW_ARRAY_ALLOCATE, elementTy, size, MakeTwoSuccessors(successBlock, errorBlock), parent)
    }
    public func GetSuccessBlock(): Block { return GetSuccessor(0) }
    public func GetErrorBlock(): Block { return GetSuccessor(1) }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateTryRawArrayAllocate(GetResult().getOrThrow().GetType().getOrThrow(), GetElementType(), GetSize(),
            GetSuccessBlock(), GetErrorBlock(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class TrySpawn <: SpawnBase {
    public init(value: Value, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.TRY_SPAWN, MakeUnaryTermOperands(value), MakeTwoSuccessors(successBlock, errorBlock), parent)
    }
    public init(value: Value, arg: Value, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.TRY_SPAWN, MakeBinaryTermOperands(value, arg), MakeTwoSuccessors(successBlock, errorBlock), parent)
    }
    public func GetSuccessBlock(): Block { return GetSuccessor(0) }
    public func GetErrorBlock(): Block { return GetSuccessor(1) }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = if (let Some(spawnArg) <- GetSpawnArg()) {
            builder.CreateTrySpawn(GetResult().getOrThrow().GetType().getOrThrow(), GetObject(), spawnArg, GetSuccessBlock(),
                GetErrorBlock(), parent)
        } else {
            builder.CreateTrySpawn(GetResult().getOrThrow().GetType().getOrThrow(), GetObject(), GetSuccessBlock(),
                GetErrorBlock(), parent)
        }
        if (let Some(fn) <- GetExecuteClosure()) {
            cloned.SetExecuteClosure(fn)
        }
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

private func MakeOneSuccessor(target: Block): ArrayList<Block> {
    let successors = ArrayList<Block>()
    successors.add(target)
    return successors
}

private func MakeTwoSuccessors(trueBlock: Block, falseBlock: Block): ArrayList<Block> {
    let successors = ArrayList<Block>()
    successors.add(trueBlock)
    successors.add(falseBlock)
    return successors
}

private func MakeMultiBranchSuccessors(defaultBlock: Block, succs: ArrayList<Block>): ArrayList<Block> {
    let successors = ArrayList<Block>()
    successors.add(defaultBlock)
    for (successor in succs) {
        successors.add(successor)
    }
    return successors
}

private func MakeUnaryTermOperands(value: Value): ArrayList<Value> {
    let operands = ArrayList<Value>()
    operands.add(value)
    return operands
}

private func MakeBinaryTermOperands(left: Value, right: Value): ArrayList<Value> {
    let operands = ArrayList<Value>()
    operands.add(left)
    operands.add(right)
    return operands
}

private func MakeOptionalTermOperands(value: Option<Value>): ArrayList<Value> {
    let operands = ArrayList<Value>()
    if (let Some(retValue) <- value) {
        operands.add(retValue)
    }
    return operands
}

private func MakeTryApplyOperands(callee: Value, args: ArrayList<Value>): ArrayList<Value> {
    let operands = ArrayList<Value>()
    operands.add(callee)
    for (arg in args) {
        operands.add(arg)
    }
    return operands
}

private func MakeTryInvokeOperands(method: Function, caller: Value,
    args: ArrayList<Value>): ArrayList<Value> {
    let operands = ArrayList<Value>()
    operands.add(method)
    operands.add(caller)
    for (arg in args) {
        operands.add(arg)
    }
    return operands
}

private func TerminatorValueIdsToString(values: ArrayList<Value>): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.GetIdentifier())
    }
    return JoinStrings(parts, ", ")
}
