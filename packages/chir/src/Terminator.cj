package cjcj::chir

import std.collection.*
import cjcj::utils.{CJC_ASSERT, OverflowStrategy, OverflowStrategyName}

public open class Terminator <: Expression {
    private let successors: ArrayList<Block> = ArrayList<Block>()

    public init(kind: ExprKind, operands: ArrayList<Value>, successors: ArrayList<Block>, parent: Option<Block>) {
        super(kind, operands, parent)
        for (successor in successors) {
            this.successors.add(successor)
        }
    }

    public override func AsTerminator(): Option<Terminator> { return this }

    public func GetSuccessors(): ArrayList<Block> {
        return successors.clone()
    }

    public func GetSuccessorsRef(): ArrayList<Block> {
        return successors
    }

    public func GetNumOfSuccessor(): Int64 {
        return successors.size
    }

    public func GetSuccessor(index: Int64): Block {
        return successors[index]
    }

    public func AddSuccessor(block: Block): Unit {
        successors.add(block)
        if (let Some(parentBlock) <- GetParentBlock()) {
            block.AddPredecessor(parentBlock)
        }
    }

    public func ReplaceSuccessor(oldBlock: Block, newBlock: Block): Unit {
        var idx: Int64 = 0
        while (idx < successors.size) {
            if (successors[idx].nodeId == oldBlock.nodeId) {
                successors[idx] = newBlock
            }
            idx++
        }
        if (let Some(parentBlock) <- GetParentBlock()) {
            oldBlock.RemovePredecessor(parentBlock)
            newBlock.AddPredecessor(parentBlock)
        }
    }

    public func ReplaceSuccessor(index: Int64, newBlock: Block): Unit {
        let oldBlock = successors[index]
        successors[index] = newBlock
        if (let Some(parentBlock) <- GetParentBlock()) {
            oldBlock.RemovePredecessor(parentBlock)
            newBlock.AddPredecessor(parentBlock)
        }
    }

    public func SyncSuccessorPredecessors(): Unit {
        if (let Some(parentBlock) <- GetParentBlock()) {
            for (successor in successors) {
                successor.AddPredecessor(parentBlock)
            }
        }
    }

    private func LetSuccessorsRemoveCurBlock(): Unit {
        if (let Some(parentBlock) <- GetParentBlock()) {
            for (successor in successors) {
                successor.RemovePredecessor(parentBlock)
            }
        }
    }

    public override func DetachFromBlockOnly(): Unit {
        if (let Some(parentBlock) <- GetParentBlock()) {
            for (successor in successors) {
                successor.RemovePredecessor(parentBlock)
            }
        }
        super.DetachFromBlockOnly()
    }

    public override func RemoveSelfFromBlock(): Unit {
        LetSuccessorsRemoveCurBlock()
        if (let Some(parentBlock) <- GetParentBlock()) {
            parentBlock.RemoveExprOnly(this)
            ClearParent()
        }
        EraseOperands()
    }

    public override func ReplaceWith(newExpr: Expression): Unit {
        let newTerminator = newExpr as Terminator ??
            throw IllegalArgumentException("new expression is not a terminator")
        let newTerminatorHadParent = newTerminator.GetParentBlock().isSome()
        if (let Some(newParent) <- newTerminator.GetParentBlock()) {
            newParent.RemoveExprOnly(newTerminator)
            newTerminator.ClearParent()
        }
        if (let Some(oldResult) <- GetResult()) {
            let newResult = newTerminator.GetResult() ??
                throw IllegalStateException("new terminator has no result")
            for (user in oldResult.GetUsers()) {
                user.ReplaceOperand(oldResult, newResult)
            }
        }
        let oldParent = GetParentBlock() ??
            throw IllegalStateException("terminator has no parent block")
        RemoveSelfFromBlock()
        if (newTerminatorHadParent) {
            oldParent.GetExpressionsRef().add(newTerminator)
            newTerminator.SetParent(oldParent)
            newTerminator.SyncSuccessorPredecessors()
        } else {
            oldParent.AppendExpression(newTerminator)
        }
    }

    public open override func AddExtraComment(): String {
        if (successors.isEmpty()) {
            return ""
        }
        let names = ArrayList<String>()
        for (successor in successors) {
            names.add(successor.GetIdentifier())
        }
        return "successors: " + JoinStrings(names, ", ")
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
        return cloned
    }
}

public class Exit <: Terminator {
    public init(value: Option<Value>, parent: Option<Block>) {
        super(ExprKind.EXIT, MakeOptionalTermOperands(value), ArrayList<Block>(), parent)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        var exitValue: Option<Value> = None
        if (GetNumOfOperands() > 0) {
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

public class ApplyWithException <: FuncCallWithException {
    public init(callee: Value, callContext: FuncCallContext, successBlock: Block, errorBlock: Block,
        parent: Option<Block>) {
        super(ExprKind.APPLY_WITH_EXCEPTION, MakeApplyWithExceptionOperands(callee, callContext.args), callContext,
            successBlock, errorBlock, parent)
    }

    public func GetCallee(): Value {
        return GetOperand(0)
    }

    public override func GetArgs(): ArrayList<Value> {
        let out = ArrayList<Value>()
        var idx: Int64 = 1
        while (idx < GetNumOfOperands()) {
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
        let cloned = builder.CreateApplyWithException(GetResult().getOrThrow().GetType().getOrThrow(), GetCallee(), callContext,
            GetSuccessBlock(), GetErrorBlock(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public open class DynamicDispatchWithException <: FuncCallWithException {
    let virMethodCtx: FuncSigInfo
    private var virtualMethodOffset: Option<UInt64> = None

    public init(kind: ExprKind, callContext: InvokeCallContext, successBlock: Block, errorBlock: Block,
        parent: Option<Block>) {
        super(kind, MakeInvokeWithExceptionOperands(callContext.caller, callContext.funcCallCtx.args),
            callContext.funcCallCtx, successBlock, errorBlock, parent)
        virMethodCtx = callContext.virMethodCtx
    }

    public func GetMethodName(): String {
        return virMethodCtx.funcName
    }

    public func GetMethodType(): FuncType {
        return virMethodCtx.funcType
    }

    public func SetMethodType(ty: FuncType): Unit {
        virMethodCtx.funcType = ty
    }

    public func GetGenericTypeParams(): ArrayList<GenericType> {
        return virMethodCtx.GetGenericTypeParams()
    }

    public func SetVirtualMethodOffset(offset: UInt64): Unit {
        virtualMethodOffset = offset
    }

    public func GetVirtualMethodOffset(): Option<UInt64> {
        return virtualMethodOffset
    }

    public func GetVirtualMethodInfo(builder: CHIRBuilder): ArrayList<VTableSearchRes> {
        var thisTypeDeref = (GetThisType() ??
            throw IllegalStateException("dynamic dispatch with exception thisType is missing")).StripAllRefs()
        if (thisTypeDeref.IsThis()) {
            thisTypeDeref = GetTopLevelFunc().getOrThrow().GetParentCustomTypeDef().getOrThrow().GetType().getOrThrow()
        }
        let instParamTypes = ArrayList<Type>()
        for (arg in GetArgs()) {
            instParamTypes.add(arg.GetType().getOrThrow())
        }
        if (!IsInvokeStaticBase()) {
            instParamTypes.remove(at: 0)
        }
        let instFuncType = builder.context.GetFuncTy(instParamTypes, builder.context.GetUnitTy())
        let funcCallType = FuncCallType(instFuncType, funcName: virMethodCtx.funcName,
            genericTypeArgs: GetInstantiatedTypeArgs())
        let res = GetFuncIndexInVTable(thisTypeDeref, funcCallType, builder)
        CJC_ASSERT(!res.isEmpty())
        return res
    }

    public func GetVirtualMethodOffset(builder: CHIRBuilder): UInt64 {
        if (let Some(offset) <- virtualMethodOffset) {
            return offset
        }
        return GetVirtualMethodInfo(builder)[0].offset
    }

    public func GetInstSrcParentCustomTypeOfMethod(builder: CHIRBuilder): ClassType {
        let virtualOffset = GetVirtualMethodOffset().getOrThrow()
        for (res in GetVirtualMethodInfo(builder)) {
            if (res.offset == virtualOffset) {
                let instSrcParentType = res.instSrcParentType.getOrThrow()
                let def = instSrcParentType.GetClassDef()
                let defType = (def.GetType().getOrThrow() as ClassType).getOrThrow()
                let parentFuncInfo = def.GetDefVTable().GetExpectedTypeVTable(defType)
                let originalType = parentFuncInfo.GetVirtualMethods()[Int64(res.offset)].GetOriginalFuncType()
                if (VirMethodTypeIsMatched(originalType, GetMethodType())) {
                    return instSrcParentType
                }
            }
        }
        throw IllegalStateException("instantiated source parent custom type of virtual method is not available")
    }

    public func GetVirtualMethodAttr(builder: CHIRBuilder): AttributeInfo {
        let virtualOffset = GetVirtualMethodOffset().getOrThrow()
        for (res in GetVirtualMethodInfo(builder)) {
            if (res.offset == virtualOffset) {
                let _ = res.instSrcParentType.getOrThrow()
                return res.attr
            }
        }
        throw IllegalStateException("virtual method attribute is not available")
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(CallTargetPrefix() + GetMethodName() + InstantiatedTypeArgsToString())
        parts.add(GetMethodType().ToString())
        parts.add(TerminatorValueIdsToString(GetOperands()))
        return JoinStrings(parts, ", ")
    }
}

public class InvokeWithException <: DynamicDispatchWithException {
    public init(callContext: InvokeCallContext, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.INVOKE_WITH_EXCEPTION, callContext, successBlock, errorBlock, parent)
    }

    public func GetObject(): Value {
        return GetOperand(0)
    }

    public override func GetArgs(): ArrayList<Value> {
        return GetOperands()
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let args = GetArgs()
        args.remove(at: 0)
        let funcContext = FuncCallContext(args: args, instTypeArgs: GetInstantiatedTypeArgs(), thisType: GetThisType())
        let methodContext = FuncSigInfo(GetMethodType(), funcName: GetMethodName(),
            genericTypeParams: GetGenericTypeParams())
        let invokeContext = InvokeCallContext(GetObject(), funcContext, methodContext)
        let cloned = builder.CreateInvokeWithException(GetResult().getOrThrow().GetType().getOrThrow(), invokeContext, GetSuccessBlock(),
            GetErrorBlock(), parent)
        if (let Some(offset) <- GetVirtualMethodOffset()) {
            cloned.SetVirtualMethodOffset(offset)
        }
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class InvokeStaticWithException <: DynamicDispatchWithException {
    public init(callContext: InvokeCallContext, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.INVOKESTATIC_WITH_EXCEPTION, callContext, successBlock, errorBlock, parent)
    }

    public func GetRTTIValue(): Value {
        return GetOperand(0)
    }

    public override func GetArgs(): ArrayList<Value> {
        let out = ArrayList<Value>()
        var idx: Int64 = 1
        while (idx < GetNumOfOperands()) {
            out.add(GetOperand(idx))
            idx++
        }
        return out
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let funcContext = FuncCallContext(args: GetArgs(), instTypeArgs: GetInstantiatedTypeArgs(),
            thisType: GetThisType())
        let methodContext = FuncSigInfo(GetMethodType(), funcName: GetMethodName(),
            genericTypeParams: GetGenericTypeParams())
        let invokeContext = InvokeCallContext(GetRTTIValue(), funcContext, methodContext)
        let cloned = builder.CreateInvokeStaticWithException(GetResult().getOrThrow().GetType().getOrThrow(), invokeContext,
            GetSuccessBlock(), GetErrorBlock(), parent)
        if (let Some(offset) <- GetVirtualMethodOffset()) {
            cloned.SetVirtualMethodOffset(offset)
        }
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class IntOpWithException <: ExpressionWithException {
    private let opKind: ExprKind
    private var overflowStrategy: OverflowStrategy

    public init(opKind: ExprKind, operand: Value, successBlock: Block, errorBlock: Block, parent: Option<Block>,
        overflowStrategy!: OverflowStrategy = OverflowStrategy.NA) {
        super(ExprKind.INT_OP_WITH_EXCEPTION, MakeUnaryTermOperands(operand), successBlock, errorBlock, parent)
        this.opKind = opKind
        this.overflowStrategy = overflowStrategy
    }

    public init(opKind: ExprKind, left: Value, right: Value, successBlock: Block, errorBlock: Block,
        parent: Option<Block>, overflowStrategy!: OverflowStrategy = OverflowStrategy.NA) {
        super(ExprKind.INT_OP_WITH_EXCEPTION, MakeBinaryTermOperands(left, right), successBlock, errorBlock, parent)
        this.opKind = opKind
        this.overflowStrategy = overflowStrategy
    }

    public func GetOpKind(): ExprKind {
        return opKind
    }

    public func GetOpKindName(): String {
        return ExprKindName(opKind) + "WithException"
    }

    public func GetLHSOperand(): Value {
        return GetOperand(0)
    }

    public func GetRHSOperand(): Option<Value> {
        if (GetNumOfOperands() > 1) {
            return GetOperand(1)
        }
        return None
    }

    public func GetOverflowStrategy(): OverflowStrategy {
        if (opKind == ExprKind.DIV) {
            return overflowStrategy
        }
        return OverflowStrategy.THROWING
    }

    public func SetOverflowStrategy(strategy: OverflowStrategy): Unit {
        overflowStrategy = strategy
    }

    public override func AddExtraComment(): String {
        let base = super.AddExtraComment()
        let overflowText = if (overflowStrategy != OverflowStrategy.NA) {
            "Overflow: " + OverflowStrategyName(overflowStrategy)
        } else {
            ""
        }
        let opText = "op: " + GetOpKindName()
        if (base.isEmpty()) {
            if (overflowText.isEmpty()) {
                return opText
            }
            return overflowText + " " + opText
        }
        if (overflowText.isEmpty()) {
            return base + " " + opText
        }
        return base + " " + overflowText + " " + opText
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = if (let Some(rhs) <- GetRHSOperand()) {
            builder.CreateBinaryIntOpWithException(GetResult().getOrThrow().GetType().getOrThrow(), GetOpKind(), GetLHSOperand(), rhs,
                GetSuccessBlock(), GetErrorBlock(), parent)
        } else {
            builder.CreateUnaryIntOpWithException(GetResult().getOrThrow().GetType().getOrThrow(), GetOpKind(), GetLHSOperand(),
                GetSuccessBlock(), GetErrorBlock(), parent)
        }
        cloned.SetOverflowStrategy(overflowStrategy)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class TypeCastWithException <: ExpressionWithException {
    public init(source: Value, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.TYPECAST_WITH_EXCEPTION, MakeUnaryTermOperands(source), successBlock, errorBlock, parent)
    }

    public func GetSourceValue(): Value {
        return GetOperand(0)
    }

    public func GetSourceTy(): Option<Type> {
        return GetSourceValue().GetType()
    }

    public func GetTargetTy(): Option<Type> {
        if (let Some(res) <- GetResult()) {
            return res.GetType()
        }
        return None
    }

    public func GetOverflowStrategy(): OverflowStrategy {
        return OverflowStrategy.THROWING
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateTypeCastWithException(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(),
            GetSuccessBlock(), GetErrorBlock(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class IntrinsicWithException <: ExpressionWithException {
    private let intrinsicKind: IntrinsicKind
    private let instantiatedTypeArgs: ArrayList<Type> = ArrayList<Type>()

    public init(callContext: IntrisicCallContext, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.INTRINSIC_WITH_EXCEPTION, callContext.args, successBlock, errorBlock, parent)
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
        return GetOperands()
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
        let cloned = builder.CreateIntrinsicWithException(GetResult().getOrThrow().GetType().getOrThrow(), callContext, GetSuccessBlock(),
            GetErrorBlock(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class AllocateWithException <: ExpressionWithException {
    private var allocatedType: Type

    public init(ty: Type, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.ALLOCATE_WITH_EXCEPTION, ArrayList<Value>(), successBlock, errorBlock, parent)
        allocatedType = ty
    }

    public func GetType(): Type {
        return allocatedType
    }

    public func SetType(ty: Type): Unit {
        allocatedType = ty
    }

    public override func OperandsToString(): String {
        return allocatedType.ToString()
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateAllocateWithException(GetResult().getOrThrow().GetType().getOrThrow(), GetType(), GetSuccessBlock(),
            GetErrorBlock(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class RawArrayAllocateWithException <: ExpressionWithException {
    private var elementType: Type

    public init(elementTy: Type, size: Value, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION, MakeUnaryTermOperands(size), successBlock, errorBlock, parent)
        elementType = elementTy
    }

    public func GetSize(): Value {
        return GetOperand(0)
    }

    public func GetElementType(): Type {
        return elementType
    }

    public func SetElementType(ty: Type): Unit {
        elementType = ty
    }

    public override func OperandsToString(): String {
        return elementType.ToString() + ", " + GetSize().GetIdentifier()
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateRawArrayAllocateWithException(GetResult().getOrThrow().GetType().getOrThrow(), GetElementType(), GetSize(),
            GetSuccessBlock(), GetErrorBlock(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class SpawnWithException <: ExpressionWithException {
    private var executeClosure: Option<Function> = None

    public init(value: Value, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.SPAWN_WITH_EXCEPTION, MakeUnaryTermOperands(value), successBlock, errorBlock, parent)
    }

    public init(value: Value, arg: Value, successBlock: Block, errorBlock: Block, parent: Option<Block>) {
        super(ExprKind.SPAWN_WITH_EXCEPTION, MakeBinaryTermOperands(value, arg), successBlock, errorBlock, parent)
    }

    public func GetSpawnArg(): Option<Value> {
        if (GetNumOfOperands() > 1) {
            return GetOperand(1)
        }
        return None
    }

    public func IsExecuteClosure(): Bool {
        return executeClosure.isSome()
    }

    public func SetExecuteClosure(fn: Function): Unit {
        executeClosure = fn
    }

    public func GetFuture(): Value {
        return GetOperand(0)
    }

    public func GetClosure(): Value {
        return GetOperand(0)
    }

    public func GetExecuteClosure(): Option<Function> {
        return executeClosure
    }

    public override func AddExtraComment(): String {
        let base = super.AddExtraComment()
        if (let Some(fn) <- executeClosure) {
            let closureText = "executeClosure: " + fn.GetIdentifier()
            if (base.isEmpty()) {
                return closureText
            }
            return base + " " + closureText
        }
        return base
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = if (let Some(spawnArg) <- GetSpawnArg()) {
            builder.CreateSpawnWithException(GetResult().getOrThrow().GetType().getOrThrow(), GetFuture(), spawnArg, GetSuccessBlock(),
                GetErrorBlock(), parent)
        } else {
            builder.CreateSpawnWithException(GetResult().getOrThrow().GetType().getOrThrow(), GetFuture(), GetSuccessBlock(),
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

private func MakeApplyWithExceptionOperands(callee: Value, args: ArrayList<Value>): ArrayList<Value> {
    let operands = ArrayList<Value>()
    operands.add(callee)
    for (arg in args) {
        operands.add(arg)
    }
    return operands
}

private func MakeInvokeWithExceptionOperands(caller: Value, args: ArrayList<Value>): ArrayList<Value> {
    let operands = ArrayList<Value>()
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
