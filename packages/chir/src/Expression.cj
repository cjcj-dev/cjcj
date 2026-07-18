package cjcj::chir

import std.collection.*
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, OverflowStrategy, StaticCast}
import std.sync.AtomicInt64

private let gLambdaClonedIdx = AtomicInt64(0)

public open class Expression <: Base & Hashable & Equatable<Expression> {
    private let kind: ExprKind
    private let operands: ArrayList<Value> = ArrayList<Value>()
    private let blockGroups: ArrayList<BlockGroup> = ArrayList<BlockGroup>()
    private var parent: Option<Block> = None
    private var result: Option<LocalVar> = None
    private var operandsAndGroupsConnected: Bool = false

    public init(kind: ExprKind, operands: ArrayList<Value>, blockGroups: ArrayList<BlockGroup>,
        parent: Option<Block>) {
        super()
        this.kind = kind
        for (operand in operands) {
            this.operands.add(operand)
        }
        for (group in blockGroups) {
            this.blockGroups.add(group)
        }
        this.parent = parent
    }

    public init(kind: ExprKind, operands: ArrayList<Value>, parent: Option<Block>) {
        super()
        this.kind = kind
        for (operand in operands) {
            this.operands.add(operand)
        }
        this.parent = parent
    }

    public operator func ==(right: Expression): Bool {
        return nodeId == right.nodeId
    }

    public operator func !=(right: Expression): Bool {
        return nodeId != right.nodeId
    }

    public func GetExprKind(): ExprKind { return kind }
    public func GetExprKindName(): String { return ExprKindName(kind) }
    public func GetExprMajorKind(): ExprMajorKind { return ExprKindMajor(kind) }

    public func IsApply(): Bool { return kind == ExprKind.APPLY }
    public func IsApplyWithException(): Bool { return kind == ExprKind.APPLY_WITH_EXCEPTION }
    public func IsBinaryExpr(): Bool { return GetExprMajorKind() == ExprMajorKind.BINARY_EXPR }
    public func IsConstant(): Bool { return kind == ExprKind.CONSTANT }
    public func IsDebug(): Bool { return kind == ExprKind.DEBUGEXPR }
    public func IsDynamicDispatch(): Bool { return kind == ExprKind.INVOKE || kind == ExprKind.INVOKESTATIC }
    public func IsField(): Bool { return kind == ExprKind.FIELD }
    public func IsFuncCall(): Bool { return kind == ExprKind.APPLY || kind == ExprKind.INVOKE || kind == ExprKind.INVOKESTATIC }
    public func IsIntOpWithException(): Bool { return kind == ExprKind.INT_OP_WITH_EXCEPTION }
    public func IsInvoke(): Bool { return kind == ExprKind.INVOKE }
    public func IsInvokeStaticBase(): Bool {
        return kind == ExprKind.INVOKESTATIC || kind == ExprKind.INVOKESTATIC_WITH_EXCEPTION
    }
    public func IsLambda(): Bool { return kind == ExprKind.LAMBDA }
    public func IsLoad(): Bool { return kind == ExprKind.LOAD }
    public func IsTerminator(): Bool { return GetExprMajorKind() == ExprMajorKind.TERMINATOR }
    public func IsTypeCast(): Bool { return kind == ExprKind.TYPECAST }
    public func IsUnaryExpr(): Bool { return GetExprMajorKind() == ExprMajorKind.UNARY_EXPR }

    public func IsConstantNull(): Bool {
        if (let Some(constant) <- (this as Constant)) {
            return constant.IsNullLit()
        }
        return false
    }

    public func IsConstantBool(): Bool {
        if (let Some(constant) <- (this as Constant)) {
            return constant.IsBoolLit()
        }
        return false
    }

    public func IsConstantInt(): Bool {
        if (let Some(constant) <- (this as Constant)) {
            return constant.IsIntLit()
        }
        return false
    }

    public func IsConstantFloat(): Bool {
        if (let Some(constant) <- (this as Constant)) {
            return constant.IsFloatLit()
        }
        return false
    }

    public func IsConstantString(): Bool {
        if (let Some(constant) <- (this as Constant)) {
            return constant.IsStringLit()
        }
        return false
    }

    public func HasExceptionBranch(): Bool {
        return kind == ExprKind.APPLY_WITH_EXCEPTION || kind == ExprKind.INVOKE_WITH_EXCEPTION ||
            kind == ExprKind.INVOKESTATIC_WITH_EXCEPTION ||
            kind == ExprKind.INT_OP_WITH_EXCEPTION || kind == ExprKind.SPAWN_WITH_EXCEPTION ||
            kind == ExprKind.TYPECAST_WITH_EXCEPTION || kind == ExprKind.INTRINSIC_WITH_EXCEPTION ||
            kind == ExprKind.ALLOCATE_WITH_EXCEPTION || kind == ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION
    }

    public func GetBlockGroups(): ArrayList<BlockGroup> {
        let out = ArrayList<BlockGroup>()
        for (group in blockGroups) {
            out.add(group)
        }
        return out
    }

    public func GetBlockGroup(idx: Int64): BlockGroup {
        return blockGroups[idx]
    }

    public func GetNumOfBlockGroups(): Int64 {
        return blockGroups.size
    }

    public func AppendBlockGroup(group: BlockGroup): Unit {
        blockGroups.add(group)
        group.SetOwnerExpression(this)
    }

    public func ClearBlockGroups(): Unit {
        blockGroups.clear()
    }

    public func GetResult(): Option<LocalVar> {
        return result
    }

    public func SetResult(value: LocalVar): Unit {
        result = value
    }

    public func ConnectOperandsAndGroups(): Unit {
        if (operandsAndGroupsConnected) {
            return
        }
        operandsAndGroupsConnected = true
        for (operand in operands) {
            operand.AddUserOnly(this)
        }
        for (group in blockGroups) {
            group.SetOwnerExpression(this)
        }
    }

    protected func MarkOperandsAndGroupsConnected(): Unit {
        operandsAndGroupsConnected = true
    }

    public func GetResultType(): Option<Type> {
        if (let Some(value) <- result) {
            return value.GetType()
        }
        return None
    }

    public func GetParentBlock(): Option<Block> {
        return parent
    }

    public func SetParent(newParent: Block): Unit {
        parent = newParent
    }

    public func ClearParent(): Unit {
        parent = None
    }

    public func GetParentBlockGroup(): Option<BlockGroup> {
        if (let Some(parentBlock) <- parent) {
            return parentBlock.GetParentBlockGroup()
        }
        return None
    }

    public func GetFuncOrLambdaBody(): Option<BlockGroup> {
        if (let Some(lambdaExpr) <- (this as Lambda)) {
            return lambdaExpr.GetBody()
        }
        if (let Some(group) <- GetParentBlockGroup()) {
            return group.GetFuncOrLambdaBody()
        }
        return None
    }

    public func GetTopLevelFunc(): Option<Function> {
        if (let Some(group) <- GetParentBlockGroup()) {
            return group.GetTopLevelFunc()
        }
        return None
    }

    public open func GetNumOfOperands(): Int64 {
        return operands.size
    }

    public open func GetOperand(idx: Int64): Value {
        return operands[idx]
    }

    public open func GetOperands(): ArrayList<Value> {
        return operands.clone()
    }

    public open func ReplaceOperand(idx: Int64, newOperand: Value): Unit {
        let oldOperand = operands[idx]
        if (oldOperand.nodeId == newOperand.nodeId) {
            return
        }
        operands[idx] = newOperand
        newOperand.AddUserOnly(this)
        var needRemoveOldOpUser = true
        for (operand in operands) {
            if (operand.nodeId == oldOperand.nodeId) {
                needRemoveOldOpUser = false
            }
        }
        if (needRemoveOldOpUser) {
            oldOperand.RemoveUserOnly(this)
        }
    }

    public open func ReplaceOperand(oldOperand: Value, newOperand: Value): Unit {
        if (oldOperand.nodeId == newOperand.nodeId) {
            return
        }
        var idx: Int64 = 0
        while (idx < operands.size) {
            if (operands[idx].nodeId == oldOperand.nodeId) {
                operands[idx] = newOperand
                newOperand.AddUserOnly(this)
                oldOperand.RemoveUserOnly(this)
            }
            idx++
        }
    }

    public func AppendOperand(op: Value): Unit {
        operands.add(op)
        op.AddUserOnly(this)
    }

    public func EraseOperands(): Unit {
        for (operand in operands) {
            operand.RemoveUserOnly(this)
        }
        operands.clear()
    }

    public func MoveAfter(expr: Expression): Unit {
        if (let Some(targetBlock) <- expr.GetParentBlock()) {
            DetachFromBlockOnly()
            let exprList = targetBlock.GetExpressionsRef()
            var idx: Int64 = 0
            while (idx < exprList.size) {
                if (exprList[idx].nodeId == expr.nodeId) {
                    exprList.add(this, at: idx + 1)
                    SetParent(targetBlock)
                    return
                }
                idx++
            }
            targetBlock.AppendExpression(this)
        }
    }

    public func MoveBefore(expr: Expression): Unit {
        if (let Some(targetBlock) <- expr.GetParentBlock()) {
            DetachFromBlockOnly()
            let exprList = targetBlock.GetExpressionsRef()
            var idx: Int64 = 0
            while (idx < exprList.size) {
                if (exprList[idx].nodeId == expr.nodeId) {
                    exprList.add(this, at: idx)
                    SetParent(targetBlock)
                    return
                }
                idx++
            }
            targetBlock.InsertExprIntoHead(this)
        }
    }

    public func MoveTo(block: Block): Unit {
        let parentBlock = parent ?? throw IllegalStateException("expression has no parent block")
        CJC_ASSERT(refEq(GetParentBlockGroup().getOrThrow(), block.GetParentBlockGroup().getOrThrow()))
        parentBlock.RemoveExprOnly(this)
        if (let Some(term) <- AsTerminator()) {
            for (successor in term.GetSuccessors()) {
                successor.RemovePredecessor(parentBlock)
            }
        }
        block.AppendExpression(this)
    }

    public open func DetachFromBlockOnly(): Unit {
        if (let Some(parentBlock) <- parent) {
            parentBlock.RemoveExprOnly(this)
        }
        parent = None
    }

    public open func RemoveSelfFromBlock(): Unit {
        DetachFromBlockOnly()
        EraseOperands()
    }

    public open func ReplaceWith(newExpr: Expression): Unit {
        if (let Some(newParent) <- newExpr.GetParentBlock()) {
            newParent.RemoveExprOnly(newExpr)
            newExpr.ClearParent()
        }
        let oldParent = parent
        if (let Some(parentBlock) <- oldParent) {
            let exprList = parentBlock.GetExpressionsRef()
            var idx: Int64 = 0
            while (idx < exprList.size) {
                if (exprList[idx].nodeId == nodeId) {
                    exprList[idx] = newExpr
                    newExpr.SetParent(parentBlock)
                    break
                }
                idx++
            }
        }
        if (let Some(oldResult) <- result) {
            if (let Some(newResult) <- newExpr.GetResult()) {
                oldResult.ReplaceWith(newResult)
            }
        }
        parent = None
        EraseOperands()
    }

    public open func OperandsToString(): String {
        return ValueIdVecToString("", operands, "", hasExceptionBranch: HasExceptionBranch())
    }

    public open func AddExtraComment(): String {
        return ""
    }

    protected func CommentToString(): String {
        let comments = ArrayList<String>()
        let baseComment = BaseCommentToString()
        if (!baseComment.isEmpty()) {
            comments.add(baseComment)
        }
        let extra = AddExtraComment()
        if (!extra.isEmpty()) {
            comments.add(extra)
        }
        return CommentToString(comments)
    }

    public open func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let clonedOperands = GetOperands()
        return builder.CreateExpression(kind, None, clonedOperands, parent)
    }

    public open func AsTerminator(): Option<Terminator> { return None }

    public func ToString(indent: Int64): String {
        var out = IndentToString(indent)
        if (let Some(res) <- result) {
            if (res.IsRetValue()) {
                out += "[ret] "
            }
            out += res.GetIdentifier()
            let srcName = res.GetSrcCodeIdentifier()
            if (!srcName.isEmpty()) {
                out += "[" + srcName + "]"
            }
            out += ": " + res.GetType().getOrThrow().ToString() + " = "
        }
        if (kind == ExprKind.INT_OP_WITH_EXCEPTION) {
            out += (this as IntOpWithException).getOrThrow().GetOpKindName()
        } else {
            out += GetExprKindName()
        }
        if (kind == ExprKind.LAMBDA) {
            out += (this as Lambda).getOrThrow().LambdaOperandsToString(indent)
        } else {
            out += "(" + OperandsToString() + ")"
        }
        out += CommentToString()
        for (group in blockGroups) {
            out += "\n" + group.ToString(indent)
        }
        return out
    }

    public func Dump(): Unit {
        println(ToString(0))
    }
}

func GetOperands(expression: Expression): ArrayList<Value> {
    let operands = expression.GetOperands()
    if (let Some(constant) <- (expression as Constant)) {
        operands.add(constant.GetValue())
    }
    if (let Some(terminator) <- expression.AsTerminator()) {
        for (successor in terminator.GetSuccessors()) {
            operands.add(successor)
        }
    }
    return operands
}

public class UnaryExpression <: Expression {
    private let overflowStrategy: OverflowStrategy

    public init(kind: ExprKind, operand: Value, parent: Option<Block>,
        overflowStrategy!: OverflowStrategy = OverflowStrategy.NA) {
        super(kind, MakeUnaryOperands(operand), parent)
        this.overflowStrategy = overflowStrategy
    }

    public func GetOverflowStrategy(): OverflowStrategy {
        return overflowStrategy
    }

    public override func AddExtraComment(): String {
        if (overflowStrategy != OverflowStrategy.NA) {
            return OverflowToString(overflowStrategy)
        }
        return ""
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateUnaryExpression(GetExprKind(), GetResult().getOrThrow().GetType().getOrThrow(), GetOperand(0), parent,
            overflowStrategy: GetOverflowStrategy())
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class BinaryExpression <: Expression {
    private let overflowStrategy: OverflowStrategy

    public init(kind: ExprKind, left: Value, right: Value, parent: Option<Block>,
        overflowStrategy!: OverflowStrategy = OverflowStrategy.NA) {
        super(kind, MakeBinaryOperands(left, right), parent)
        this.overflowStrategy = overflowStrategy
    }

    public func GetLHSOperand(): Value {
        return GetOperand(0)
    }

    public func GetRHSOperand(): Value {
        return GetOperand(1)
    }

    public func GetOverflowStrategy(): OverflowStrategy {
        return overflowStrategy
    }

    public override func AddExtraComment(): String {
        if (overflowStrategy != OverflowStrategy.NA) {
            return OverflowToString(overflowStrategy)
        }
        return ""
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateBinaryExpression(GetExprKind(), GetResult().getOrThrow().GetType().getOrThrow(), GetOperand(0), GetOperand(1),
            parent, overflowStrategy: GetOverflowStrategy())
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class Constant <: Expression {
    public let literal: LiteralValue

    public init(literal: LiteralValue, parent: Option<Block>) {
        super(ExprKind.CONSTANT, ArrayList<Value>(), parent)
        this.literal = literal
    }

    public func GetValue(): LiteralValue { return literal }
    public func GetBoolLitVal(): Bool {
        let boolLiteral = (GetValue() as BoolLiteral) ?? throw IllegalStateException("constant is not a bool literal")
        return boolLiteral.GetVal()
    }
    public func GetFloatLitVal(): Float64 {
        let floatLiteral = (GetValue() as FloatLiteral) ?? throw IllegalStateException("constant is not a float literal")
        return floatLiteral.GetVal()
    }
    public func GetRuneLitVal(): Rune {
        let runeLiteral = (GetValue() as RuneLiteral) ?? throw IllegalStateException("constant is not a rune literal")
        return runeLiteral.GetVal()
    }
    public func GetSignedIntLitVal(): Int64 {
        let intLiteral = (GetValue() as IntLiteral) ?? throw IllegalStateException("constant is not an int literal")
        return intLiteral.GetSignedVal()
    }
    public func GetStringLitVal(): String {
        let stringLiteral = (GetValue() as StringLiteral) ?? throw IllegalStateException("constant is not a string literal")
        return stringLiteral.GetVal()
    }
    public func GetUnsignedIntLitVal(): UInt64 {
        let intLiteral = (GetValue() as IntLiteral) ?? throw IllegalStateException("constant is not an int literal")
        return intLiteral.GetUnsignedVal()
    }
    public func IsNullLit(): Bool { return literal.IsNullLit() }
    public func IsBoolLit(): Bool { return literal.IsBoolLit() }
    public func IsIntLit(): Bool { return literal.IsIntLit() }
    public func IsFloatLit(): Bool { return literal.IsFloatLit() }
    public func IsRuneLit(): Bool { return literal.IsRuneLit() }
    public func IsSignedIntLit(): Bool {
        if (!IsIntLit()) {
            return false
        }
        return StaticCast<IntLiteral>(literal).IsSigned()
    }
    public func IsUnSignedIntLit(): Bool {
        if (!IsIntLit()) {
            return false
        }
        return !IsSignedIntLit()
    }
    public func IsStringLit(): Bool { return literal.IsStringLit() }
    public func IsUnitLit(): Bool { return literal.IsUnitLit() }

    public override func AddExtraComment(): String {
        return literal.ToString(0)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let litVal: LiteralValue = if (literal.IsNullLit()) { NullLiteral() } else { literal }
        let cloned = builder.CreateConstant(GetResult().getOrThrow().GetType().getOrThrow(), litVal, parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class Allocate <: Expression {
    private var allocatedType: Type

    public init(ty: Type, parent: Option<Block>) {
        super(ExprKind.ALLOCATE, ArrayList<Value>(), parent)
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
        let cloned = builder.CreateAllocate(GetResult().getOrThrow().GetType().getOrThrow(), GetType(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class Load <: Expression {
    public init(location: Value, parent: Option<Block>) {
        super(ExprKind.LOAD, MakeUnaryOperands(location), parent)
    }

    public func GetLocation(): Value {
        return GetOperand(0)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateLoad(GetResult().getOrThrow().GetType().getOrThrow(), GetLocation(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class Store <: Expression {
    public init(value: Value, location: Value, parent: Option<Block>) {
        super(ExprKind.STORE, MakeBinaryOperands(value, location), parent)
    }

    public func GetValue(): Value {
        return GetOperand(0)
    }

    public func GetLocation(): Value {
        return GetOperand(1)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateStore(GetValue(), GetLocation(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class GetElementRef <: Expression {
    private let path: ArrayList<UInt64> = ArrayList<UInt64>()

    public init(location: Value, path: ArrayList<UInt64>, parent: Option<Block>) {
        super(ExprKind.GET_ELEMENT_REF, MakeUnaryOperands(location), parent)
        for (item in path) {
            this.path.add(item)
        }
    }

    public func GetLocation(): Value {
        return GetOperand(0)
    }

    public func GetPath(): ArrayList<UInt64> {
        let out = ArrayList<UInt64>()
        for (item in path) {
            out.add(item)
        }
        return out
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(GetLocation().GetIdentifier())
        for (item in path) {
            parts.add("${item}")
        }
        return JoinStrings(parts, ", ")
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateGetElementRef(GetResult().getOrThrow().GetType().getOrThrow(), GetLocation(), GetPath(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class GetElementByName <: Expression {
    private let names: ArrayList<String> = ArrayList<String>()

    public init(location: Value, names: ArrayList<String>, parent: Option<Block>) {
        super(ExprKind.GET_ELEMENT_BY_NAME, MakeUnaryOperands(location), parent)
        for (name in names) {
            this.names.add(name)
        }
    }

    public func GetLocation(): Value {
        return GetOperand(0)
    }

    public func GetNames(): ArrayList<String> {
        let out = ArrayList<String>()
        for (name in names) {
            out.add(name)
        }
        return out
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(GetLocation().GetIdentifier())
        for (name in names) {
            parts.add(name)
        }
        return JoinStrings(parts, ", ")
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateGetElementByName(GetResult().getOrThrow().GetType().getOrThrow(), GetLocation(), GetNames(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class StoreElementRef <: Expression {
    private let path: ArrayList<UInt64> = ArrayList<UInt64>()

    public init(value: Value, location: Value, path: ArrayList<UInt64>, parent: Option<Block>) {
        super(ExprKind.STORE_ELEMENT_REF, MakeBinaryOperands(value, location), parent)
        for (item in path) {
            this.path.add(item)
        }
    }

    public func GetValue(): Value {
        return GetOperand(0)
    }

    public func GetLocation(): Value {
        return GetOperand(1)
    }

    public func GetPath(): ArrayList<UInt64> {
        let out = ArrayList<UInt64>()
        for (item in path) {
            out.add(item)
        }
        return out
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(GetValue().GetIdentifier())
        parts.add(GetLocation().GetIdentifier())
        for (item in path) {
            parts.add("${item}")
        }
        return JoinStrings(parts, ", ")
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateStoreElementRef(GetValue(), GetLocation(), GetPath(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class StoreElementByName <: Expression {
    private let names: ArrayList<String> = ArrayList<String>()

    public init(value: Value, location: Value, names: ArrayList<String>, parent: Option<Block>) {
        super(ExprKind.STORE_ELEMENT_BY_NAME, MakeBinaryOperands(value, location), parent)
        for (name in names) {
            this.names.add(name)
        }
    }

    public func GetValue(): Value {
        return GetOperand(0)
    }

    public func GetLocation(): Value {
        return GetOperand(1)
    }

    public func GetNames(): ArrayList<String> {
        let out = ArrayList<String>()
        for (name in names) {
            out.add(name)
        }
        return out
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(GetValue().GetIdentifier())
        parts.add(GetLocation().GetIdentifier())
        for (name in names) {
            parts.add(name)
        }
        return JoinStrings(parts, ", ")
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateStoreElementByName(GetValue(), GetLocation(), GetNames(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class FuncCallContext {
    public let args: ArrayList<Value> = ArrayList<Value>()
    public let instTypeArgs: ArrayList<Type> = ArrayList<Type>()
    public var thisType: Option<Type> = None

    public init(args!: ArrayList<Value> = ArrayList<Value>(), instTypeArgs!: ArrayList<Type> = ArrayList<Type>(),
        thisType!: Option<Type> = None) {
        for (arg in args) {
            this.args.add(arg)
        }
        for (ty in instTypeArgs) {
            this.instTypeArgs.add(ty)
        }
        this.thisType = thisType
    }
}

public class InvokeCallContext {
    public let caller: Value
    public let funcCallCtx: FuncCallContext
    public let virMethodCtx: FuncSigInfo

    public init(caller: Value, funcCallCtx: FuncCallContext, virMethodCtx: FuncSigInfo) {
        this.caller = caller
        this.funcCallCtx = funcCallCtx
        this.virMethodCtx = virMethodCtx
    }
}

public open class FuncCall <: Expression {
    private let instantiatedTypeArgs: ArrayList<Type> = ArrayList<Type>()
    private var thisType: Option<Type> = None

    public init(kind: ExprKind, funcCallCtx: FuncCallContext, parent: Option<Block>) {
        super(kind, ArrayList<Value>(), parent)
        for (ty in funcCallCtx.instTypeArgs) {
            instantiatedTypeArgs.add(ty)
        }
        thisType = funcCallCtx.thisType
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

    public func ClearThisType(): Unit {
        thisType = None
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

public class Apply <: FuncCall {
    private var isSuperCall: Bool = false

    public init(callee: Value, callContext: FuncCallContext, parent: Option<Block>) {
        super(ExprKind.APPLY, callContext, parent)
        AppendOperand(callee)
        for (arg in callContext.args) {
            AppendOperand(arg)
        }
        MarkOperandsAndGroupsConnected()
    }

    public func GetCallee(): Value {
        return GetOperand(0)
    }

    public func GetInstParentCustomTyOfCallee(builder: CHIRBuilder): Option<Type> {
        return GetInstParentCustomTypeForApplyCallee(this, builder)
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

    public func IsSuperCall(): Bool {
        return isSuperCall
    }

    public func SetSuperCall(): Unit {
        isSuperCall = true
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(CallTargetPrefix() + GetCallee().GetIdentifier() + InstantiatedTypeArgsToString())
        let argNames = ArrayList<String>()
        for (arg in GetArgs()) {
            argNames.add(arg.GetIdentifier())
        }
        parts.add(JoinStrings(argNames, ", "))
        return JoinStrings(parts, ", ")
    }

    public override func AddExtraComment(): String {
        return if (isSuperCall) { "isSuperCall" } else { "" }
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let callContext = FuncCallContext(args: GetArgs(), instTypeArgs: GetInstantiatedTypeArgs(),
            thisType: GetThisType())
        let cloned = builder.CreateApply(GetResult().getOrThrow().GetType().getOrThrow(), GetCallee(), callContext, parent)
        if (IsSuperCall()) {
            cloned.SetSuperCall()
        }
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public open class DynamicDispatch <: FuncCall {
    let virMethodCtx: FuncSigInfo
    private var virtualMethodOffset: Option<UInt64> = None

    public init(kind: ExprKind, callContext: InvokeCallContext, parent: Option<Block>) {
        super(kind, callContext.funcCallCtx, parent)
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
            throw IllegalStateException("dynamic dispatch thisType is missing")).StripAllRefs()
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
        if (let Some(offset) <- GetVirtualMethodOffset()) {
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

    protected func DynamicDispatchPrefix(): String {
        if (let Some(ty) <- GetThisType()) {
            return ty.ToString() + "->"
        }
        return ""
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(DynamicDispatchPrefix() + GetMethodName() + InstantiatedTypeArgsToString())
        parts.add(GetMethodType().ToString())
        parts.add(ValueIdsToString(GetOperands()))
        return JoinStrings(parts, ", ")
    }
}

public class Invoke <: DynamicDispatch {
    public init(callContext: InvokeCallContext, parent: Option<Block>) {
        super(ExprKind.INVOKE, callContext, parent)
        AppendOperand(callContext.caller)
        for (arg in callContext.funcCallCtx.args) {
            AppendOperand(arg)
        }
        MarkOperandsAndGroupsConnected()
    }

    public func GetObject(): Value {
        return GetOperand(0)
    }

    public override func GetArgs(): ArrayList<Value> {
        return GetOperands()
    }

    public override func ReplaceOperand(idx: Int64, newOperand: Value): Unit {
        super.ReplaceOperand(idx, newOperand)
        if (idx == 0) {
            UpdateThisType()
        }
    }

    public override func ReplaceOperand(oldOperand: Value, newOperand: Value): Unit {
        let changedObject = GetObject().nodeId == oldOperand.nodeId
        super.ReplaceOperand(oldOperand, newOperand)
        if (changedObject) {
            UpdateThisType()
        }
    }

    private func UpdateThisType(): Unit {
        if (GetThisType().isNone()) {
            if (let Some(objectTy) <- GetObject().GetType()) {
                SetThisType(objectTy)
            }
        }
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let args = GetArgs()
        args.remove(at: 0)
        let funcContext = FuncCallContext(args: args, instTypeArgs: GetInstantiatedTypeArgs(), thisType: GetThisType())
        let methodContext = FuncSigInfo(GetMethodType(), funcName: GetMethodName(),
            genericTypeParams: GetGenericTypeParams())
        let invokeContext = InvokeCallContext(GetObject(), funcContext, methodContext)
        let cloned = builder.CreateInvoke(GetResult().getOrThrow().GetType().getOrThrow(), invokeContext, parent)
        if (let Some(offset) <- GetVirtualMethodOffset()) {
            cloned.SetVirtualMethodOffset(offset)
        }
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class InvokeStatic <: DynamicDispatch {
    public init(callContext: InvokeCallContext, parent: Option<Block>) {
        super(ExprKind.INVOKESTATIC, callContext, parent)
        AppendOperand(callContext.caller)
        for (arg in callContext.funcCallCtx.args) {
            AppendOperand(arg)
        }
        MarkOperandsAndGroupsConnected()
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
        let cloned = builder.CreateInvokeStatic(GetResult().getOrThrow().GetType().getOrThrow(), invokeContext, parent)
        if (let Some(offset) <- GetVirtualMethodOffset()) {
            cloned.SetVirtualMethodOffset(offset)
        }
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class GetRTTI <: Expression {
    public init(value: Value, parent: Option<Block>) {
        super(ExprKind.GET_RTTI, MakeUnaryOperands(value), parent)
    }

    public func GetOperand(): Value {
        return GetOperand(0)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateGetRTTI(GetResult().getOrThrow().GetType().getOrThrow(), GetOperand(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class GetRTTIStatic <: Expression {
    private var rttiType: Type

    public init(ty: Type, parent: Option<Block>) {
        super(ExprKind.GET_RTTI_STATIC, ArrayList<Value>(), parent)
        rttiType = ty
    }

    public func GetRTTIType(): Type {
        return rttiType
    }

    public func SetRTTIType(ty: Type): Unit {
        rttiType = ty
    }

    public override func OperandsToString(): String {
        return rttiType.ToString()
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateGetRTTIStatic(GetResult().getOrThrow().GetType().getOrThrow(), GetRTTIType(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class TypeCast <: Expression {
    private let overflowStrategy: OverflowStrategy

    public init(source: Value, parent: Option<Block>, overflowStrategy!: OverflowStrategy = OverflowStrategy.NA) {
        super(ExprKind.TYPECAST, MakeUnaryOperands(source), parent)
        this.overflowStrategy = overflowStrategy
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
        return overflowStrategy
    }

    public override func AddExtraComment(): String {
        if (overflowStrategy != OverflowStrategy.NA) {
            return OverflowToString(overflowStrategy)
        }
        return ""
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateTypeCast(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(), parent,
            overflowStrategy: GetOverflowStrategy())
        let resultValue = GetResult().getOrThrow()
        let clonedResult = cloned.GetResult().getOrThrow()
        clonedResult.AppendAttributeInfo(resultValue.GetAttributeInfo())
        clonedResult.SetEnumCaseIndex(resultValue.GetEnumCaseIndex())
        return cloned
    }
}

public class InstanceOf <: Expression {
    private var testedType: Type

    public init(value: Value, ty: Type, parent: Option<Block>) {
        super(ExprKind.INSTANCEOF, MakeUnaryOperands(value), parent)
        testedType = ty
    }

    public func GetObject(): Value {
        return GetOperand(0)
    }

    public func GetType(): Type {
        return testedType
    }

    public func SetTestedType(ty: Type): Unit {
        testedType = ty
    }

    public override func OperandsToString(): String {
        return GetObject().GetIdentifier() + ", " + testedType.ToString()
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateInstanceOf(GetResult().getOrThrow().GetType().getOrThrow(), GetObject(), GetType(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class Box <: Expression {
    public init(source: Value, parent: Option<Block>) {
        super(ExprKind.BOX, MakeUnaryOperands(source), parent)
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

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateBox(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class UnBox <: Expression {
    public init(source: Value, parent: Option<Block>) {
        super(ExprKind.UNBOX, MakeUnaryOperands(source), parent)
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

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateUnBox(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class TransformToGeneric <: Expression {
    public init(source: Value, parent: Option<Block>) {
        super(ExprKind.TRANSFORM_TO_GENERIC, MakeUnaryOperands(source), parent)
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

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateTransformToGeneric(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class TransformToConcrete <: Expression {
    public init(source: Value, parent: Option<Block>) {
        super(ExprKind.TRANSFORM_TO_CONCRETE, MakeUnaryOperands(source), parent)
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

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateTransformToConcrete(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class UnBoxToRef <: Expression {
    public init(source: Value, parent: Option<Block>) {
        super(ExprKind.UNBOX_TO_REF, MakeUnaryOperands(source), parent)
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

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateUnBoxToRef(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class Tuple <: Expression {
    public init(values: ArrayList<Value>, parent: Option<Block>) {
        super(ExprKind.TUPLE, values, parent)
    }

    public func GetElementValues(): ArrayList<Value> {
        return GetOperands()
    }

    public func GetElementTypes(): ArrayList<Type> {
        let out = ArrayList<Type>()
        for (value in GetElementValues()) {
            if (let Some(valueTy) <- value.GetType()) {
                out.add(valueTy)
            }
        }
        return out
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateTuple(GetResult().getOrThrow().GetType().getOrThrow(), GetElementValues(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class Field <: Expression {
    private let path: ArrayList<UInt64> = ArrayList<UInt64>()

    public init(value: Value, path: ArrayList<UInt64>, parent: Option<Block>) {
        super(ExprKind.FIELD, MakeUnaryOperands(value), parent)
        for (item in path) {
            this.path.add(item)
        }
    }

    public func GetBase(): Value {
        return GetOperand(0)
    }

    public func GetPath(): ArrayList<UInt64> {
        let out = ArrayList<UInt64>()
        for (item in path) {
            out.add(item)
        }
        return out
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(GetBase().GetIdentifier())
        for (item in path) {
            parts.add("${item}")
        }
        return JoinStrings(parts, ", ")
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateField(GetResult().getOrThrow().GetType().getOrThrow(), GetBase(), GetPath(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class FieldByName <: Expression {
    private let names: ArrayList<String> = ArrayList<String>()

    public init(value: Value, names: ArrayList<String>, parent: Option<Block>) {
        super(ExprKind.FIELD_BY_NAME, MakeUnaryOperands(value), parent)
        for (name in names) {
            this.names.add(name)
        }
    }

    public func GetBase(): Value {
        return GetOperand(0)
    }

    public func GetNames(): ArrayList<String> {
        let out = ArrayList<String>()
        for (name in names) {
            out.add(name)
        }
        return out
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(GetBase().GetIdentifier())
        for (name in names) {
            parts.add(name)
        }
        return JoinStrings(parts, ", ")
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateFieldByName(GetResult().getOrThrow().GetType().getOrThrow(), GetBase(), GetNames(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class RawArrayAllocate <: Expression {
    private var elementType: Type

    public init(elementTy: Type, size: Value, parent: Option<Block>) {
        super(ExprKind.RAW_ARRAY_ALLOCATE, MakeUnaryOperands(size), parent)
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
        let cloned = builder.CreateRawArrayAllocate(GetResult().getOrThrow().GetType().getOrThrow(), GetElementType(), GetSize(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class RawArrayLiteralInit <: Expression {
    public init(rawArray: Value, elements: ArrayList<Value>, parent: Option<Block>) {
        super(ExprKind.RAW_ARRAY_LITERAL_INIT, ArrayList<Value>(), parent)
        AppendOperand(rawArray)
        for (element in elements) {
            AppendOperand(element)
        }
        MarkOperandsAndGroupsConnected()
    }

    public func GetRawArray(): Value {
        return GetOperand(0)
    }

    public func GetSize(): Int64 {
        return GetNumOfOperands() - 1
    }

    public func GetElements(): ArrayList<Value> {
        let out = ArrayList<Value>()
        var idx: Int64 = 1
        while (idx < GetNumOfOperands()) {
            out.add(GetOperand(idx))
            idx++
        }
        return out
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateRawArrayLiteralInit(GetResult().getOrThrow().GetType().getOrThrow(), GetRawArray(), GetElements(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class RawArrayInitByValue <: Expression {
    public init(rawArray: Value, size: Value, initValue: Value, parent: Option<Block>) {
        super(ExprKind.RAW_ARRAY_INIT_BY_VALUE, MakeThreeOperands(rawArray, size, initValue), parent)
    }

    public func GetRawArray(): Value {
        return GetOperand(0)
    }

    public func GetSize(): Value {
        return GetOperand(1)
    }

    public func GetInitValue(): Value {
        return GetOperand(2)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateRawArrayInitByValue(GetResult().getOrThrow().GetType().getOrThrow(), GetRawArray(), GetSize(),
            GetInitValue(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class `VArray` <: Expression {
    public init(elements: ArrayList<Value>, parent: Option<Block>) {
        super(ExprKind.VARRAY, elements, parent)
    }

    public func GetSize(): Int64 {
        return GetNumOfOperands()
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateVArray(GetResult().getOrThrow().GetType().getOrThrow(), GetOperands(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class VArrayBuilder <: Expression {
    public init(size: Value, item: Value, initFunc: Value, parent: Option<Block>) {
        super(ExprKind.VARRAY_BUILDER, MakeVArrayBuilderOperands(size, item, initFunc), parent)
    }

    public func GetSize(): Value {
        return GetOperand(0)
    }

    public func GetItem(): Value {
        return GetOperand(1)
    }

    public func GetInitFunc(): Value {
        return GetOperand(2)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateVArrayBuilder(GetResult().getOrThrow().GetType().getOrThrow(), GetSize(), GetItem(), GetInitFunc(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class GetException <: Expression {
    public init(parent: Option<Block>) {
        super(ExprKind.GET_EXCEPTION, ArrayList<Value>(), parent)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateGetException(GetResult().getOrThrow().GetType().getOrThrow(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class IntrisicCallContext {
    public var kind: IntrinsicKind
    public let args: ArrayList<Value> = ArrayList<Value>()
    public let instTypeArgs: ArrayList<Type> = ArrayList<Type>()

    public init(kind!: IntrinsicKind = IntrinsicKind.NOT_INTRINSIC,
        args!: ArrayList<Value> = ArrayList<Value>(), instTypeArgs!: ArrayList<Type> = ArrayList<Type>()) {
        this.kind = kind
        for (arg in args) {
            this.args.add(arg)
        }
        for (ty in instTypeArgs) {
            this.instTypeArgs.add(ty)
        }
    }
}

public class Intrinsic <: Expression {
    private let intrinsicKind: IntrinsicKind
    private let instantiatedTypeArgs: ArrayList<Type> = ArrayList<Type>()

    public init(callContext: IntrisicCallContext, parent: Option<Block>) {
        super(ExprKind.INTRINSIC, callContext.args, parent)
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
        parts.add(ValueIdsToString(GetArgs()))
        return JoinStrings(parts, ", ")
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let callContext = IntrisicCallContext(kind: GetIntrinsicKind(), args: GetArgs(),
            instTypeArgs: GetInstantiatedTypeArgs())
        let cloned = builder.CreateIntrinsic(GetResult().getOrThrow().GetType().getOrThrow(), callContext, parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class Debug <: Expression {
    private let srcCodeIdentifier: String

    public init(value: Value, srcCodeIdentifier: String, parent: Option<Block>) {
        super(ExprKind.DEBUGEXPR, MakeUnaryOperands(value), parent)
        this.srcCodeIdentifier = srcCodeIdentifier
    }

    public func GetSrcCodeIdentifier(): String {
        return srcCodeIdentifier
    }

    public func GetValue(): Value {
        return GetOperand(0)
    }

    public override func OperandsToString(): String {
        return GetValue().GetIdentifier() + ", " + srcCodeIdentifier
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateDebug(GetResult().getOrThrow().GetType().getOrThrow(), GetValue(), GetSrcCodeIdentifier(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class Spawn <: Expression {
    private var executeClosure: Option<Function> = None

    public init(value: Value, parent: Option<Block>) {
        super(ExprKind.SPAWN, MakeUnaryOperands(value), parent)
    }

    public init(value: Value, arg: Value, parent: Option<Block>) {
        super(ExprKind.SPAWN, MakeBinaryOperands(value, arg), parent)
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
        if (IsExecuteClosure()) {
            throw IllegalStateException("spawn future is unavailable for execute closure")
        }
        return GetOperand(0)
    }

    public func GetClosure(): Value {
        if (!IsExecuteClosure()) {
            throw IllegalStateException("spawn closure is unavailable without execute closure")
        }
        return GetOperand(0)
    }

    public func GetExecuteClosure(): Option<Function> {
        return executeClosure
    }

    public override func AddExtraComment(): String {
        if (let Some(fn) <- executeClosure) {
            return "executeClosure: " + fn.GetIdentifier()
        }
        return ""
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = if (let Some(spawnArg) <- GetSpawnArg()) {
            builder.CreateSpawn(GetResult().getOrThrow().GetType().getOrThrow(), GetFuture(), spawnArg, parent)
        } else {
            builder.CreateSpawn(GetResult().getOrThrow().GetType().getOrThrow(), GetFuture(), parent)
        }
        if (let Some(fn) <- GetExecuteClosure()) {
            cloned.SetExecuteClosure(fn)
        }
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class GetInstantiateValue <: Expression {
    private let instantiateTys: ArrayList<Type> = ArrayList<Type>()

    public init(value: Value, instantiatedTypes: ArrayList<Type>, parent: Option<Block>) {
        super(ExprKind.GET_INSTANTIATE_VALUE, MakeUnaryOperands(value), parent)
        for (ty in instantiatedTypes) {
            instantiateTys.add(ty)
        }
    }

    public func GetInstantiateTypes(): ArrayList<Type> {
        return instantiateTys.clone()
    }

    public func GetInstantiateTypesRef(): ArrayList<Type> {
        return instantiateTys
    }

    public func GetGenericResult(): Value {
        return GetOperand(0)
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(GetGenericResult().GetIdentifier())
        for (ty in instantiateTys) {
            parts.add(ty.ToString())
        }
        return JoinStrings(parts, ", ")
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let clonedTypes = if (GetGenericResult().IsLocalVar()) {
            let sourceResult = GetResult() ?? throw IllegalArgumentException("GetInstantiateValue clone requires result")
            let oldOutDefTypes = GetOutDefDeclaredTypes(sourceResult)
            let oldAllTypes = GetInstantiateTypes()
            let newAllTypes = GetOutDefDeclaredTypes(parent)
            var idx = oldOutDefTypes.size
            while (idx < oldAllTypes.size) {
                newAllTypes.add(oldAllTypes[idx])
                idx++
            }
            newAllTypes
        } else {
            GetInstantiateTypes()
        }
        let cloned = builder.CreateGetInstantiateValue(GetResult().getOrThrow().GetType().getOrThrow(), GetGenericResult(), clonedTypes, parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public open class ForIn <: Expression {
    public init(kind: ExprKind, inductionVar: Value, loopCondVar: Value, parent: Option<Block>) {
        super(kind, MakeBinaryOperands(inductionVar, loopCondVar), parent)
    }

    public func GetInductionVar(): Value {
        return GetOperand(0)
    }

    public func GetLoopCondVar(): Value {
        return GetOperand(1)
    }

    public func GetBody(): BlockGroup {
        return GetBlockGroup(0)
    }

    public func GetLatch(): BlockGroup {
        return GetBlockGroup(1)
    }

    public func GetCond(): BlockGroup {
        return GetBlockGroup(2)
    }

    public func InitBlockGroups(body: BlockGroup, latch: BlockGroup, cond: BlockGroup): Unit {
        if (GetNumOfBlockGroups() != 0) {
            throw IllegalArgumentException("ForIn block groups already initialized")
        }
        AppendBlockGroup(body)
        AppendBlockGroup(latch)
        AppendBlockGroup(cond)
    }

    public open func GetExecutionOrder(): ArrayList<BlockGroup> {
        return ArrayList<BlockGroup>()
    }
}

public class ForInRange <: ForIn {
    public init(inductionVar: Value, loopCondVar: Value, parent: Option<Block>) {
        super(ExprKind.FORIN_RANGE, inductionVar, loopCondVar, parent)
    }

    public override func GetExecutionOrder(): ArrayList<BlockGroup> {
        return MakeForInExecutionOrder(GetCond(), GetBody(), GetLatch())
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let parentGroup = parent.GetParentBlockGroup() ??
            throw IllegalArgumentException("for-in clone requires parent block group")
        let newCond = if (let Some(ownerFunc) <- parentGroup.GetOwnerFunc()) {
            GetCond().Clone(builder, ownerFunc)
        } else {
            let ownerExpr = parentGroup.GetOwnerExpression() ??
                throw IllegalArgumentException("for-in clone requires an owner expression")
            let parentLambda = (ownerExpr as Lambda) ??
                throw IllegalArgumentException("for-in clone owner expression must be lambda")
            GetCond().Clone(builder, parentLambda)
        }
        let newBody = if (let Some(ownerFunc) <- parentGroup.GetOwnerFunc()) {
            GetBody().Clone(builder, ownerFunc)
        } else {
            let ownerExpr = parentGroup.GetOwnerExpression() ??
                throw IllegalArgumentException("for-in clone requires an owner expression")
            let parentLambda = (ownerExpr as Lambda) ??
                throw IllegalArgumentException("for-in clone owner expression must be lambda")
            GetBody().Clone(builder, parentLambda)
        }
        let newLatch = if (let Some(ownerFunc) <- parentGroup.GetOwnerFunc()) {
            GetLatch().Clone(builder, ownerFunc)
        } else {
            let ownerExpr = parentGroup.GetOwnerExpression() ??
                throw IllegalArgumentException("for-in clone requires an owner expression")
            let parentLambda = (ownerExpr as Lambda) ??
                throw IllegalArgumentException("for-in clone owner expression must be lambda")
            GetLatch().Clone(builder, parentLambda)
        }
        let cloned = builder.CreateForInRange(GetResult().getOrThrow().GetType().getOrThrow(), GetInductionVar(), GetLoopCondVar(), parent)
        cloned.InitBlockGroups(newBody, newLatch, newCond)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class ForInIter <: ForIn {
    public init(inductionVar: Value, loopCondVar: Value, parent: Option<Block>) {
        super(ExprKind.FORIN_ITER, inductionVar, loopCondVar, parent)
    }

    public override func GetExecutionOrder(): ArrayList<BlockGroup> {
        return MakeForInExecutionOrder(GetLatch(), GetCond(), GetBody())
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let parentGroup = parent.GetParentBlockGroup() ??
            throw IllegalArgumentException("for-in clone requires parent block group")
        let newCond = if (let Some(ownerFunc) <- parentGroup.GetOwnerFunc()) {
            GetCond().Clone(builder, ownerFunc)
        } else {
            let ownerExpr = parentGroup.GetOwnerExpression() ??
                throw IllegalArgumentException("for-in clone requires an owner expression")
            let parentLambda = (ownerExpr as Lambda) ??
                throw IllegalArgumentException("for-in clone owner expression must be lambda")
            GetCond().Clone(builder, parentLambda)
        }
        let newBody = if (let Some(ownerFunc) <- parentGroup.GetOwnerFunc()) {
            GetBody().Clone(builder, ownerFunc)
        } else {
            let ownerExpr = parentGroup.GetOwnerExpression() ??
                throw IllegalArgumentException("for-in clone requires an owner expression")
            let parentLambda = (ownerExpr as Lambda) ??
                throw IllegalArgumentException("for-in clone owner expression must be lambda")
            GetBody().Clone(builder, parentLambda)
        }
        let newLatch = if (let Some(ownerFunc) <- parentGroup.GetOwnerFunc()) {
            GetLatch().Clone(builder, ownerFunc)
        } else {
            let ownerExpr = parentGroup.GetOwnerExpression() ??
                throw IllegalArgumentException("for-in clone requires an owner expression")
            let parentLambda = (ownerExpr as Lambda) ??
                throw IllegalArgumentException("for-in clone owner expression must be lambda")
            GetLatch().Clone(builder, parentLambda)
        }
        let cloned = builder.CreateForInIter(GetResult().getOrThrow().GetType().getOrThrow(), GetInductionVar(), GetLoopCondVar(), parent)
        cloned.InitBlockGroups(newBody, newLatch, newCond)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class ForInClosedRange <: ForIn {
    public init(inductionVar: Value, loopCondVar: Value, parent: Option<Block>) {
        super(ExprKind.FORIN_CLOSED_RANGE, inductionVar, loopCondVar, parent)
    }

    public override func GetExecutionOrder(): ArrayList<BlockGroup> {
        return MakeForInExecutionOrder(GetBody(), GetCond(), GetLatch())
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let parentGroup = parent.GetParentBlockGroup() ??
            throw IllegalArgumentException("for-in clone requires parent block group")
        let newCond = if (let Some(ownerFunc) <- parentGroup.GetOwnerFunc()) {
            GetCond().Clone(builder, ownerFunc)
        } else {
            let ownerExpr = parentGroup.GetOwnerExpression() ??
                throw IllegalArgumentException("for-in clone requires an owner expression")
            let parentLambda = (ownerExpr as Lambda) ??
                throw IllegalArgumentException("for-in clone owner expression must be lambda")
            GetCond().Clone(builder, parentLambda)
        }
        let newBody = if (let Some(ownerFunc) <- parentGroup.GetOwnerFunc()) {
            GetBody().Clone(builder, ownerFunc)
        } else {
            let ownerExpr = parentGroup.GetOwnerExpression() ??
                throw IllegalArgumentException("for-in clone requires an owner expression")
            let parentLambda = (ownerExpr as Lambda) ??
                throw IllegalArgumentException("for-in clone owner expression must be lambda")
            GetBody().Clone(builder, parentLambda)
        }
        let newLatch = if (let Some(ownerFunc) <- parentGroup.GetOwnerFunc()) {
            GetLatch().Clone(builder, ownerFunc)
        } else {
            let ownerExpr = parentGroup.GetOwnerExpression() ??
                throw IllegalArgumentException("for-in clone requires an owner expression")
            let parentLambda = (ownerExpr as Lambda) ??
                throw IllegalArgumentException("for-in clone owner expression must be lambda")
            GetLatch().Clone(builder, parentLambda)
        }
        let cloned = builder.CreateForInClosedRange(GetResult().getOrThrow().GetType().getOrThrow(), GetInductionVar(), GetLoopCondVar(),
            parent)
        cloned.InitBlockGroups(newBody, newLatch, newCond)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class Lambda <: Expression {
    private var body: Option<BlockGroup> = None
    private let params: ArrayList<Parameter> = ArrayList<Parameter>()
    private let genericTypeParams: ArrayList<GenericType> = ArrayList<GenericType>()
    private var retValue: Option<LocalVar> = None
    private var funcTy: Option<FuncType> = None
    private var identifier: String = ""
    private var srcCodeIdentifier: String = ""
    private var isLocalFunc: Bool = false
    private var paramDftValHostFunc: Option<Lambda> = None
    private var isCompileTimeValue: Bool = false

    public init(operands: ArrayList<Value>, body: BlockGroup, parent: Option<Block>) {
        super(ExprKind.LAMBDA, operands, MakeLambdaGroups(body), parent)
        this.body = body
    }

    public init(funcTy: FuncType, parent: Option<Block>, isLocalFunc!: Bool = false, identifier!: String = "",
        srcCodeIdentifier!: String = "", genericTypeParams!: ArrayList<GenericType> = ArrayList<GenericType>()) {
        super(ExprKind.LAMBDA, ArrayList<Value>(), ArrayList<BlockGroup>(), parent)
        this.funcTy = funcTy
        this.isLocalFunc = isLocalFunc
        this.identifier = identifier
        this.srcCodeIdentifier = srcCodeIdentifier
        for (param in genericTypeParams) {
            this.genericTypeParams.add(param)
        }
    }

    public func IsCompileTimeValue(): Bool {
        return isCompileTimeValue
    }

    public func SetCompileTimeValue(): Unit {
        isCompileTimeValue = true
    }

    public func IsLocalFunc(): Bool {
        return isLocalFunc
    }

    public func GetFuncType(): Option<FuncType> {
        return funcTy
    }

    public func SetFuncType(ty: FuncType): Unit {
        funcTy = ty
    }

    public func GetIdentifier(): String {
        return identifier
    }

    public func GetIdentifierWithoutPrefix(): String {
        return identifier
    }

    public func GetSrcCodeIdentifier(): String {
        return srcCodeIdentifier
    }

    public func SetParamDftValHostFunc(hostFunc: Lambda): Unit {
        paramDftValHostFunc = hostFunc
    }

    public func GetParamDftValHostFunc(): Option<Lambda> {
        return paramDftValHostFunc
    }

    public func GetBody(): Option<BlockGroup> { return body }

    public func RemoveBody(): Unit {
        ClearBlockGroups()
        body = None
    }

    public func InitBody(newBody: BlockGroup): Unit {
        if (body.isSome() || GetNumOfBlockGroups() != 0) {
            throw IllegalArgumentException("Lambda body already initialized")
        }
        body = newBody
        AppendBlockGroup(newBody)
    }

    public func GetEntryBlock(): Option<Block> {
        if (let Some(lambdaBody) <- body) {
            return lambdaBody.GetEntryBlock()
        }
        return None
    }

    public func AddParam(param: Parameter): Unit {
        if (!ContainsParameter(params, param)) {
            params.add(param)
        }
        param.SetOwnerLambda(this)
    }

    public func GetNumOfParams(): Int64 {
        return params.size
    }

    public func GetParam(index: Int64): Parameter {
        return params[index]
    }

    public func GetParams(): ArrayList<Parameter> {
        let out = ArrayList<Parameter>()
        for (param in params) {
            out.add(param)
        }
        return out
    }

    public func GetGenericTypeParams(): ArrayList<GenericType> {
        let out = ArrayList<GenericType>()
        for (param in genericTypeParams) {
            out.add(param)
        }
        return out
    }

    public func SetReturnValue(ret: LocalVar): Unit {
        ret.SetRetValue(true)
        retValue = ret
    }

    public func GetReturnValue(): Option<LocalVar> {
        return retValue
    }

    public func GetReturnType(): Option<Type> {
        if (let Some(lambdaFuncTy) <- funcTy) {
            return lambdaFuncTy.GetReturnType()
        }
        return None
    }

    public override func RemoveSelfFromBlock(): Unit {
        if (let Some(lambdaBody) <- body) {
            lambdaBody.ClearBlockGroup()
        }
        body = None
        ClearBlockGroups()
        super.RemoveSelfFromBlock()
    }

    public func DetachLiftedBodyAndRemoveSelf(): Unit {
        body = None
        ClearBlockGroups()
        super.RemoveSelfFromBlock()
    }

    public func GetCapturedVariables(): ArrayList<Value> {
        let captured = ArrayList<Value>()
        if (let Some(lambdaBody) <- body) {
            CollectCapturedFromBlockGroup(lambdaBody, this, lambdaBody, captured)
        }
        return captured
    }

    public func LambdaOperandsToString(indent: Int64): String {
        let parts = ArrayList<String>()
        for (param in params) {
            parts.add("\n" + param.ToString(indent + 1))
        }
        let retText = if (let Some(retTy) <- GetReturnType()) { retTy.ToString() } else { "<none>" }
        return "[" + identifier + "]" + TypeVecToString("<", genericTypeParams, ">", delimiter: ",") + "(" +
            JoinStrings(parts, "") + "): " + retText
    }

    public override func AddExtraComment(): String {
        let parts = ArrayList<String>()
        if (isCompileTimeValue) {
            parts.add("compileTimeVal")
        }
        if (isLocalFunc) {
            parts.add("localFunc")
        }
        if (!srcCodeIdentifier.isEmpty()) {
            parts.add("srcCodeIdentifier: " + srcCodeIdentifier)
        }
        if (let Some(hostFunc) <- paramDftValHostFunc) {
            parts.add("paramDftValHostFunc: " + hostFunc.GetIdentifier())
        }
        return JoinStrings(parts, ", ")
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let lambdaFuncTy = funcTy ?? throw IllegalArgumentException("lambda clone requires a function type")
        let newIdentifier = identifier + "." + gLambdaClonedIdx.fetchAdd(1).toString()
        let cloned = builder.CreateLambda(GetResult().getOrThrow().GetType().getOrThrow(), lambdaFuncTy, parent, isLocalFunc: IsLocalFunc(),
            identifier: newIdentifier, srcCodeIdentifier: GetSrcCodeIdentifier(),
            genericTypeParams: GetGenericTypeParams())
        if (IsCompileTimeValue()) {
            cloned.SetCompileTimeValue()
        }
        if (let Some(hostFunc) <- GetParamDftValHostFunc()) {
            cloned.SetParamDftValHostFunc(hostFunc)
        }
        if (let Some(lambdaBody) <- body) {
            let clonedBody = lambdaBody.Clone(builder, cloned)
            for (param in GetParams()) {
                if (let Some(paramTy) <- param.GetType()) {
                    let clonedParam = builder.CreateParameter(paramTy, INVALID_LOCATION, cloned)
                    clonedParam.CopyBaseInfoFrom(param)
                    clonedParam.SetSrcCodeIdentifier(param.GetSrcCodeIdentifier())
                }
            }
            let (blockIdx, exprIdx) = GetAllocExprOfRetVal(GetBody().getOrThrow())
            let clonedRet = clonedBody.GetBlockByIdx(blockIdx).GetExpressionByIdx(exprIdx).GetResult().getOrThrow()
            cloned.SetReturnValue(clonedRet)
        }
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

private func MakeUnaryOperands(operand: Value): ArrayList<Value> {
    let ops = ArrayList<Value>()
    ops.add(operand)
    return ops
}

private func MakeBinaryOperands(left: Value, right: Value): ArrayList<Value> {
    let ops = ArrayList<Value>()
    ops.add(left)
    ops.add(right)
    return ops
}

private func MakeThreeOperands(first: Value, second: Value, third: Value): ArrayList<Value> {
    let ops = ArrayList<Value>()
    ops.add(first)
    ops.add(second)
    ops.add(third)
    return ops
}

private func MakeVArrayBuilderOperands(size: Value, item: Value, initFunc: Value): ArrayList<Value> {
    let ops = ArrayList<Value>()
    ops.add(size)
    ops.add(item)
    ops.add(initFunc)
    return ops
}

private func MakeLambdaGroups(body: BlockGroup): ArrayList<BlockGroup> {
    let groups = ArrayList<BlockGroup>()
    groups.add(body)
    return groups
}

private func MakeForInExecutionOrder(first: BlockGroup, second: BlockGroup, third: BlockGroup): ArrayList<BlockGroup> {
    let groups = ArrayList<BlockGroup>()
    groups.add(first)
    groups.add(second)
    groups.add(third)
    return groups
}

private func GetAllocExprOfRetVal(body: BlockGroup): (Int64, Int64) {
    let blocks = body.GetBlocks()
    var blockIdx: Int64 = 0
    while (blockIdx < blocks.size) {
        let exprs = blocks[blockIdx].GetExpressions()
        var exprIdx: Int64 = 0
        while (exprIdx < exprs.size) {
            if (let Some(result) <- exprs[exprIdx].GetResult()) {
                if (result.IsRetValue()) {
                    return (blockIdx, exprIdx)
                }
            }
            exprIdx++
        }
        blockIdx++
    }
    CJC_ABORT()
    return (0, 0)
}

private func ContainsParameter(values: ArrayList<Parameter>, param: Parameter): Bool {
    for (value in values) {
        if (value.nodeId == param.nodeId) {
            return true
        }
    }
    return false
}

private func CollectCapturedFromBlockGroup(group: BlockGroup, lambdaExpr: Lambda, rootBody: BlockGroup,
    captured: ArrayList<Value>): Unit {
    for (block in group.GetBlocks()) {
        for (expr in block.GetExpressions()) {
            CollectCapturedFromExpressionOperands(expr, lambdaExpr, rootBody, captured)
            if (!expr.IsLambda()) {
                for (subGroup in expr.GetBlockGroups()) {
                    CollectCapturedFromBlockGroup(subGroup, lambdaExpr, rootBody, captured)
                }
            }
        }
    }
}

private func CollectCapturedFromExpressionOperands(expr: Expression, lambdaExpr: Lambda, rootBody: BlockGroup,
    captured: ArrayList<Value>): Unit {
    for (operand in expr.GetOperands()) {
        var shouldCapture = false
        if (let Some(localVar) <- operand.AsLocalVar()) {
            var isLambdaResult = false
            if (let Some(lambdaResult) <- lambdaExpr.GetResult()) {
                isLambdaResult = lambdaResult.nodeId == localVar.nodeId
            }
            if (!isLambdaResult) {
                if (let Some(ownerGroup) <- localVar.GetOwnerBlockGroup()) {
                    shouldCapture = ownerGroup.nodeId != rootBody.nodeId
                } else {
                    shouldCapture = true
                }
            }
        } else if (let Some(param) <- operand.AsParameter()) {
            if (let Some(ownerLambda) <- param.GetOwnerLambda()) {
                shouldCapture = ownerLambda.nodeId != lambdaExpr.nodeId
            } else {
                shouldCapture = true
            }
        }
        var alreadyCaptured = false
        for (capturedValue in captured) {
            if (refEq(capturedValue, operand)) {
                alreadyCaptured = true
                break
            }
        }
        if (shouldCapture && !alreadyCaptured) {
            captured.add(operand)
        }
    }
}

private func ValueIdsToString(values: ArrayList<Value>): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.GetIdentifier())
    }
    return JoinStrings(parts, ", ")
}
