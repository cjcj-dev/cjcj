package cjcj::chir

import std.collection.*
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, OverflowStrategy, StaticCast}
import std.sync.AtomicInt64

private let gLambdaClonedIdx = AtomicInt64(0)

private func GetAllSuperClassDefs(def: ClassDef, allSuperDefs: HashSet<CustomTypeDef>): Unit {
    for (parent in def.GetImplementedInterfaceDefs()) {
        allSuperDefs.add(parent)
        GetAllSuperClassDefs(parent, allSuperDefs)
    }
    if (let Some(superClass) <- def.GetSuperClassDef()) {
        allSuperDefs.add(superClass)
        GetAllSuperClassDefs(superClass, allSuperDefs)
    }
    for (extendDef in def.GetExtends()) {
        for (parent in extendDef.GetImplementedInterfaceDefs()) {
            allSuperDefs.add(parent)
            GetAllSuperClassDefs(parent, allSuperDefs)
        }
    }
}

public open class Expression <: Base & Hashable & Equatable<Expression> {
    private let kind: ExprKind
    protected let operands: ArrayList<Value> = ArrayList<Value>()
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
    public func IsTryApply(): Bool { return kind == ExprKind.TRY_APPLY }
    public func IsBinaryExpr(): Bool { return GetExprMajorKind() == ExprMajorKind.BINARY_EXPR }
    public func IsConstant(): Bool { return kind == ExprKind.CONSTANT }
    public func IsDebug(): Bool { return kind == ExprKind.DEBUGEXPR }
    public func IsDynamicDispatch(): Bool { return kind == ExprKind.INVOKE || kind == ExprKind.INVOKESTATIC }
    public func IsField(): Bool { return kind == ExprKind.FIELD }
    public func IsFuncCall(): Bool { return kind == ExprKind.APPLY || kind == ExprKind.INVOKE || kind == ExprKind.INVOKESTATIC }
    public func IsTryUnaryExpression(): Bool { return kind == ExprKind.TRY_NEG }
    public func IsTryBinaryExpression(): Bool {
        let index = ExprKindIndex(kind)
        return index >= ExprKindIndex(ExprKind.TRY_ADD) &&
            index <= ExprKindIndex(ExprKind.TRY_RSHIFT)
    }
    public func IsInvoke(): Bool { return kind == ExprKind.INVOKE }
    public func IsInvokeStaticBase(): Bool {
        return kind == ExprKind.INVOKESTATIC || kind == ExprKind.TRY_INVOKESTATIC
    }
    public func IsLambda(): Bool { return kind == ExprKind.LAMBDA }
    public func IsLoad(): Bool { return kind == ExprKind.LOAD }
    public func IsTerminator(): Bool { return GetExprMajorKind() == ExprMajorKind.TERMINATOR }
    public func IsNumericCast(): Bool { return kind == ExprKind.NUMERIC_CAST }
    public func IsTypeCast(): Bool { return (this as TypeCast).isSome() }
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
        return kind == ExprKind.TRY_APPLY || kind == ExprKind.TRY_INVOKE ||
            kind == ExprKind.TRY_INVOKESTATIC ||
            IsTryUnaryExpression() || IsTryBinaryExpression() ||
            kind == ExprKind.TRY_SPAWN ||
            kind == ExprKind.TRY_NUMERIC_CAST || kind == ExprKind.TRY_INTRINSIC ||
            kind == ExprKind.TRY_ALLOCATE || kind == ExprKind.TRY_RAW_ARRAY_ALLOCATE
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

    public func GetSuccessorIndex(index: Int64): Int64 {
        var first: Int64 = 0
        while (first < operands.size && !(operands[first] as Block).isSome()) { first++ }
        return first + index
    }

    public func GetNumOfNonSuccessorOperands(): Int64 { return GetSuccessorIndex(0) }

    public func GetNonSuccessorOperands(): ArrayList<Value> {
        let out = ArrayList<Value>()
        for (i in 0..GetNumOfNonSuccessorOperands()) { out.add(operands[i]) }
        return out
    }

    public func GetSuccessors(): ArrayList<Block> {
        let out = ArrayList<Block>()
        for (operand in operands) {
            if (let Some(block) <- (operand as Block)) { out.add(block) }
        }
        return out
    }

    public func GetNumOfSuccessor(): Int64 { return operands.size - GetSuccessorIndex(0) }
    public func GetSuccessor(index: Int64): Block { return (operands[GetSuccessorIndex(index)] as Block).getOrThrow() }

    public func ReplaceSuccessor(oldBlock: Block, newBlock: Block): Unit {
        for (index in 0..GetNumOfSuccessor()) {
            if (GetSuccessor(index).nodeId == oldBlock.nodeId) { ReplaceSuccessor(index, newBlock) }
        }
    }

    public func ReplaceSuccessor(index: Int64, newBlock: Block): Unit {
        ReplaceOperand(GetSuccessorIndex(index), newBlock)
    }

    public func SyncSuccessorPredecessors(): Unit {
        if (let Some(parentBlock) <- parent) {
            for (successor in GetSuccessors()) { successor.AddPredecessor(parentBlock) }
        }
    }

    public open func GetNumOfOperands(): Int64 {
        return operands.size
    }

    public open func GetOperand(idx: Int64): Value {
        CJC_ASSERT(idx < GetNumOfNonSuccessorOperands())
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
        if (let Some(newBlock) <- (newOperand as Block)) {
            newBlock.AddPredecessor(parent.getOrThrow())
        } else {
            newOperand.AddUserOnly(this)
        }
        var stillUsed = false
        for (operand in operands) {
            if (operand.nodeId == oldOperand.nodeId) {
                stillUsed = true
            }
        }
        if (stillUsed) {
            return
        }
        if (let Some(oldBlock) <- (oldOperand as Block)) {
            oldBlock.RemovePredecessor(parent.getOrThrow())
        } else {
            oldOperand.RemoveUserOnly(this)
        }
    }

    public open func ReplaceOperand(oldOperand: Value, newOperand: Value): Unit {
        if (oldOperand.nodeId == newOperand.nodeId) {
            return
        }
        var found = false
        var idx: Int64 = 0
        while (idx < operands.size) {
            if (operands[idx].nodeId == oldOperand.nodeId) {
                operands[idx] = newOperand
                found = true
            }
            idx++
        }
        if (!found) {
            return
        }
        if (let Some(oldBlock) <- (oldOperand as Block)) {
            oldBlock.RemovePredecessor(parent.getOrThrow())
        } else {
            oldOperand.RemoveUserOnly(this)
        }
        if (let Some(newBlock) <- (newOperand as Block)) {
            newBlock.AddPredecessor(parent.getOrThrow())
        } else {
            newOperand.AddUserOnly(this)
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
                    if (let Some(terminator) <- (this as Terminator)) {
                        for (successor in terminator.GetSuccessors()) { successor.AddPredecessor(targetBlock) }
                    }
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
            for (successor in GetSuccessors()) { successor.RemovePredecessor(parentBlock) }
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
            for (successor in GetSuccessors()) { successor.RemovePredecessor(parentBlock) }
            for (successor in newExpr.GetSuccessors()) { successor.AddPredecessor(parentBlock) }
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

    public open func AddExtraComment(): String { return "" }

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

    public func AsTerminator(): Option<Expression> { return if (IsTerminator()) { Some(this) } else { None } }

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
        out += GetExprKindName()
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
        let value = constant.GetValue()
        var already = false
        for (operand in operands) {
            if (refEq(operand, value)) {
                already = true
                break
            }
        }
        if (!already) {
            operands.add(value)
        }
    }
    if (let Some(terminator) <- expression.AsTerminator()) {
        for (successor in terminator.GetSuccessors()) {
            var already = false
            for (operand in operands) {
                if (refEq(operand, successor)) {
                    already = true
                    break
                }
            }
            if (!already) {
                operands.add(successor)
            }
        }
    }
    return operands
}

public open class UnaryExpressionBase <: Expression {
    protected var overflowStrategy: OverflowStrategy

    public init(opKind: UnaryExprKind, operand: Value, successors: ArrayList<Block>, parent: Option<Block>,
        overflowStrategy!: OverflowStrategy = OverflowStrategy.NA, isTry!: Bool = false) {
        super(ToExprKind(opKind, isTry), MakeUnaryWithSuccessors(operand, successors), parent)
        this.overflowStrategy = overflowStrategy
    }

    public func GetOpKind(): ExprKind { return PlainExprKind(GetExprKind()) }

    public func GetOverflowStrategy(): OverflowStrategy { return overflowStrategy }

    public func SetOverflowStrategy(strategy: OverflowStrategy): Unit { overflowStrategy = strategy }

    public override func AddExtraComment(): String {
        if (overflowStrategy != OverflowStrategy.NA) {
            return OverflowToString(overflowStrategy)
        }
        return ""
    }
}

public class UnaryExpression <: UnaryExpressionBase {
    public init(kind: ExprKind, operand: Value, parent: Option<Block>,
        overflowStrategy!: OverflowStrategy = OverflowStrategy.NA) {
        super(ToUnaryExprKind(kind), operand, ArrayList<Block>(), parent, overflowStrategy: overflowStrategy, isTry: false)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateUnaryExpression(GetExprKind(), GetResult().getOrThrow().GetType().getOrThrow(), GetOperand(0), parent,
            overflowStrategy: GetOverflowStrategy())
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public open class BinaryExpressionBase <: Expression {
    protected var overflowStrategy: OverflowStrategy

    public init(opKind: BinaryExprKind, left: Value, right: Value, successors: ArrayList<Block>, parent: Option<Block>,
        overflowStrategy!: OverflowStrategy = OverflowStrategy.NA, isTry!: Bool = false) {
        super(ToExprKind(opKind, isTry), MakeBinaryWithSuccessors(left, right, successors), parent)
        this.overflowStrategy = overflowStrategy
    }

    public func GetLHSOperand(): Value { return GetOperand(0) }

    public func GetRHSOperand(): Value { return GetOperand(1) }

    public func GetOpKind(): ExprKind { return PlainExprKind(GetExprKind()) }

    public func GetOverflowStrategy(): OverflowStrategy { return overflowStrategy }

    public func SetOverflowStrategy(strategy: OverflowStrategy): Unit { overflowStrategy = strategy }

    public override func AddExtraComment(): String {
        if (overflowStrategy != OverflowStrategy.NA) {
            return OverflowToString(overflowStrategy)
        }
        return ""
    }
}

public class BinaryExpression <: BinaryExpressionBase {
    public init(kind: ExprKind, left: Value, right: Value, parent: Option<Block>,
        overflowStrategy!: OverflowStrategy = OverflowStrategy.NA) {
        super(ToBinaryExprKind(kind), left, right, ArrayList<Block>(), parent, overflowStrategy: overflowStrategy, isTry: false)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateBinaryExpression(GetExprKind(), GetResult().getOrThrow().GetType().getOrThrow(), GetOperand(0), GetOperand(1),
            parent, overflowStrategy: GetOverflowStrategy())
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class Constant <: Expression {
    public init(literal: LiteralValue, parent: Option<Block>) {
        super(ExprKind.CONSTANT, ArrayList<Value>([literal]), parent)
    }

    public func GetValue(): LiteralValue {
        CJC_ASSERT(GetOperand(0).IsLiteral())
        return StaticCast<LiteralValue>(GetOperand(0))
    }
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
    public func IsNullLit(): Bool { return GetValue().IsNullLit() }
    public func IsBoolLit(): Bool { return GetValue().IsBoolLit() }
    public func IsIntLit(): Bool { return GetValue().IsIntLit() }
    public func IsFloatLit(): Bool { return GetValue().IsFloatLit() }
    public func IsRuneLit(): Bool { return GetValue().IsRuneLit() }
    public func IsSignedIntLit(): Bool {
        if (!IsIntLit()) {
            return false
        }
        return StaticCast<IntLiteral>(GetValue()).IsSigned()
    }
    public func IsUnSignedIntLit(): Bool {
        if (!IsIntLit()) {
            return false
        }
        return !IsSignedIntLit()
    }
    public func IsStringLit(): Bool { return GetValue().IsStringLit() }
    public func IsUnitLit(): Bool { return GetValue().IsUnitLit() }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let litVal: LiteralValue = if (GetValue().IsNullLit()) { NullLiteral() } else { GetValue() }
        let cloned = builder.CreateConstant(GetResult().getOrThrow().GetType().getOrThrow(), litVal, parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public open class AllocateBase <: Expression {
    private var allocatedType: Type

    protected init(kind: ExprKind, ty: Type, successors: ArrayList<Block>, parent: Option<Block>) {
        super(kind, ArrayList<Value>(), parent)
        allocatedType = ty
        for (successor in successors) { this.operands.add(successor) }
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

}

public class Allocate <: AllocateBase {
    public init(ty: Type, parent: Option<Block>) {
        super(ExprKind.ALLOCATE, ty, ArrayList<Block>(), parent)
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
    public let method: Function
    public let caller: Value
    public let funcCallCtx: FuncCallContext
    public let overflowStrategy: OverflowStrategy
    public init(method: Function, caller: Value, funcCallCtx: FuncCallContext,
        overflowStrategy!: OverflowStrategy = OverflowStrategy.NA) {
        this.method = method
        this.caller = caller
        this.funcCallCtx = funcCallCtx
        this.overflowStrategy = overflowStrategy
    }
}

public open class FuncCall <: Expression {
    private let instantiatedTypeArgs: ArrayList<Type> = ArrayList<Type>()
    private var thisType: Option<Type> = None

    public init(kind: ExprKind, funcCallCtx: FuncCallContext, parent: Option<Block>,
        operands!: ArrayList<Value> = ArrayList<Value>()) {
        super(kind, operands, parent)
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
        let operandsText = ArrayList<String>()
        operandsText.add(CallTargetPrefix() + GetCallee().GetIdentifier() + InstantiatedTypeArgsToString())
        operandsText.add(ValueIdVecToString("", GetArgs(), ""))
        return StringJoin(operandsText, ", ")
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
    let overflowStrategy: OverflowStrategy
    private var virtualMethodOffset: Option<UInt64> = None

    public init(kind: ExprKind, callContext: InvokeCallContext, parent: Option<Block>) {
        super(kind, callContext.funcCallCtx, parent, operands: ArrayList<Value>([callContext.method]))
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
        // #275 AutoEnv: codegen CreateOuterTypeInfo only needs a ClassType. Keep before the 09/04 lookup.
        if (let Some(thisTy) <- GetThisType()) {
            let stripped = thisTy.StripAllRefs()
            if (stripped.IsAutoEnv()) {
                if (let Some(ct) <- (stripped as ClassType)) {
                    return ct
                }
            }
        }
        var thisTypeDeref = (GetThisType() ??
            throw IllegalStateException("dynamic dispatch thisType is missing")).StripAllRefs()
        if (thisTypeDeref.IsThis()) {
            thisTypeDeref = GetTopLevelFunc().getOrThrow().GetParentCustomTypeDef().getOrThrow().GetType().getOrThrow()
        }
        if (let Some(parent) <- GetInstParentCustomTyOfCallee(GetCallee(), GetArgs(), Some(thisTypeDeref), builder)) {
            if (let Some(ct) <- (parent as ClassType)) {
                return ct
            }
        }
        if (let Some(ct) <- (thisTypeDeref as ClassType)) {
            return ct
        }
        throw IllegalStateException("instantiated source parent custom type of virtual method is not available name=${GetMethodName()}")
    }

    public func GetVirtualMethodAttr(): AttributeInfo {
        return GetCallee().GetAttributeInfo()
    }

    protected func DynamicDispatchPrefix(): String {
        if (let Some(ty) <- GetThisType()) {
            return ty.ToString() + "->"
        }
        return ""
    }

    public override func OperandsToString(): String {
        let parts = ArrayList<String>()
        parts.add(DynamicDispatchPrefix() + GetCallee().GetIdentifier() + InstantiatedTypeArgsToString())
        let operands = GetOperands()
        operands.remove(at: 0)
        parts.add(ValueIdsToString(operands))
        return JoinStrings(parts, ", ")
    }

    public override func AddExtraComment(): String {
        if (overflowStrategy != OverflowStrategy.NA) {
            return "methodName: " + GetMethodName()
        }
        return ""
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
        return GetOperand(1)
    }

    public override func GetArgs(): ArrayList<Value> {
        let operands = GetOperands()
        operands.remove(at: 0)
        return operands
    }

    public override func ReplaceOperand(idx: Int64, newOperand: Value): Unit {
        super.ReplaceOperand(idx, newOperand)
        if (idx == 1) {
            UpdateThisType()
        }
    }

    public override func ReplaceOperand(oldOperand: Value, newOperand: Value): Unit {
        let changedObject = GetObject() == oldOperand
        super.ReplaceOperand(oldOperand, newOperand)
        if (changedObject) {
            UpdateThisType()
        }
    }

    private func UpdateThisType(): Unit {
        let objType = GetObject().GetType().getOrThrow()
        let objDerefType = objType.StripAllRefs() as ClassType
        let thisDerefType = GetThisType().getOrThrow().StripAllRefs() as ClassType
        if (objDerefType.isNone() || thisDerefType.isNone()) {
            return
        }
        let actualObjDerefType = objDerefType.getOrThrow()
        let actualThisDerefType = thisDerefType.getOrThrow()
        if (actualObjDerefType == actualThisDerefType) {
            return
        }
        let parentDef = actualObjDerefType.GetClassDef()
        let allSuperDefs = HashSet<CustomTypeDef>()
        GetAllSuperClassDefs(actualThisDerefType.GetClassDef(), allSuperDefs)
        if (!allSuperDefs.contains(parentDef)) {
            SetThisType(objType)
        }
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let args = GetArgs()
        args.remove(at: 0)
        let funcContext = FuncCallContext(args: args, instTypeArgs: GetInstantiatedTypeArgs(), thisType: GetThisType())
        let invokeContext = InvokeCallContext(GetCallee(), GetObject(), funcContext,
            overflowStrategy: overflowStrategy)
        let cloned = builder.CreateInvoke(GetResult().getOrThrow().GetType().getOrThrow(), invokeContext, parent)
        if (let Some(offset) <- GetStoredVirMethodOffset()) {
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
        return GetOperand(1)
    }

    public override func GetArgs(): ArrayList<Value> {
        let out = ArrayList<Value>()
        var idx: Int64 = 2
        while (idx < GetNumOfOperands()) {
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
        let cloned = builder.CreateInvokeStatic(GetResult().getOrThrow().GetType().getOrThrow(), invokeContext, parent)
        if (let Some(offset) <- GetStoredVirMethodOffset()) {
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

public open class TypeCast <: Expression {
    protected init(kind: ExprKind, source: Value, successors: ArrayList<Block>, parent: Option<Block>) {
        super(kind, MakeUnaryOperands(source), parent)
        for (successor in successors) { this.operands.add(successor) }
    }

    public func GetSourceValue(): Value { return GetOperand(0) }
    public func GetSourceType(): Option<Type> { return GetSourceValue().GetType() }
    public func GetTargetType(): Option<Type> { return GetResultType() }
}

public open class NumericCastBase <: TypeCast {
    private let overflowStrategy: OverflowStrategy

    protected init(kind: ExprKind, source: Value, successors: ArrayList<Block>, parent: Option<Block>, overflowStrategy: OverflowStrategy) {
        super(kind, source, successors, parent)
        this.overflowStrategy = overflowStrategy
    }

    public func GetOverflowStrategy(): OverflowStrategy { return overflowStrategy }

    public override func AddExtraComment(): String {
        return if (overflowStrategy != OverflowStrategy.NA) { OverflowToString(overflowStrategy) } else { "" }
    }
}

public class ClassStaticCast <: TypeCast {
    public init(source: Value, parent: Option<Block>) {
        super(ExprKind.CLASS_STATIC_CAST, source, ArrayList<Block>(), parent)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateClassStaticCast(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(), parent)
        let resultValue = GetResult().getOrThrow()
        let clonedResult = cloned.GetResult().getOrThrow()
        clonedResult.AppendAttributeInfo(resultValue.GetAttributeInfo())
        cloned.SetNeedCheckCast(GetNeedCheckCast())
        clonedResult.SetEnumCaseIndex(resultValue.GetEnumCaseIndex())
        return cloned
    }
}

public class NumericCast <: NumericCastBase {
    public init(source: Value, parent: Option<Block>, overflowStrategy!: OverflowStrategy) {
        super(ExprKind.NUMERIC_CAST, source, ArrayList<Block>(), parent, overflowStrategy)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateNumericCast(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(), parent,
            overflowStrategy: GetOverflowStrategy())
        let resultValue = GetResult().getOrThrow()
        let clonedResult = cloned.GetResult().getOrThrow()
        clonedResult.AppendAttributeInfo(resultValue.GetAttributeInfo())
        cloned.SetNeedCheckCast(GetNeedCheckCast())
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

public class Box <: TypeCast {
    public init(source: Value, parent: Option<Block>) {
        super(ExprKind.BOX, source, ArrayList<Block>(), parent)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateBox(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class UnBoxToValue <: TypeCast {
    public init(source: Value, parent: Option<Block>) {
        super(ExprKind.UNBOX_TO_VALUE, source, ArrayList<Block>(), parent)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateUnBoxToValue(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class CastToGeneric <: TypeCast {
    public init(source: Value, parent: Option<Block>) {
        super(ExprKind.CAST_TO_GENERIC, source, ArrayList<Block>(), parent)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateCastToGeneric(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class CastToConcrete <: TypeCast {
    public init(source: Value, parent: Option<Block>) {
        super(ExprKind.CAST_TO_CONCRETE, source, ArrayList<Block>(), parent)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = builder.CreateCastToConcrete(GetResult().getOrThrow().GetType().getOrThrow(), GetSourceValue(), parent)
        cloned.GetResult().getOrThrow().AppendAttributeInfo(GetResult().getOrThrow().GetAttributeInfo())
        return cloned
    }
}

public class UnBoxToRef <: TypeCast {
    public init(source: Value, parent: Option<Block>) {
        super(ExprKind.UNBOX_TO_REF, source, ArrayList<Block>(), parent)
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

public open class RawArrayAllocateBase <: Expression {
    private var elementType: Type

    protected init(kind: ExprKind, elementTy: Type, size: Value, successors: ArrayList<Block>, parent: Option<Block>) {
        super(kind, MakeUnaryOperands(size), parent)
        elementType = elementTy
        for (successor in successors) { this.operands.add(successor) }
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

}

public class RawArrayAllocate <: RawArrayAllocateBase {
    public init(elementTy: Type, size: Value, parent: Option<Block>) {
        super(ExprKind.RAW_ARRAY_ALLOCATE, elementTy, size, ArrayList<Block>(), parent)
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

public open class SpawnBase <: Expression {
    private var executeClosure: Option<Function> = None

    protected init(kind: ExprKind, operands: ArrayList<Value>, successors: ArrayList<Block>, parent: Option<Block>) {
        super(kind, operands, parent)
        for (successor in successors) { this.operands.add(successor) }
    }

    public func GetObject(): Value { return GetOperand(0) }

    public func GetSpawnArg(): Option<Value> {
        if (GetNumOfNonSuccessorOperands() > 1) {
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

}

public class Spawn <: SpawnBase {
    public init(value: Value, parent: Option<Block>) {
        super(ExprKind.SPAWN, MakeUnaryOperands(value), ArrayList<Block>(), parent)
    }
    public init(value: Value, arg: Value, parent: Option<Block>) {
        super(ExprKind.SPAWN, MakeBinaryOperands(value, arg), ArrayList<Block>(), parent)
    }

    public override func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let cloned = if (let Some(spawnArg) <- GetSpawnArg()) {
            builder.CreateSpawn(GetResult().getOrThrow().GetType().getOrThrow(), GetObject(), spawnArg, parent)
        } else {
            builder.CreateSpawn(GetResult().getOrThrow().GetType().getOrThrow(), GetObject(), parent)
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

private func MakeUnaryWithSuccessors(operand: Value, successors: ArrayList<Block>): ArrayList<Value> {
    let ops = ArrayList<Value>()
    ops.add(operand)
    for (succ in successors) {
        ops.add(succ)
    }
    return ops
}

private func MakeBinaryWithSuccessors(left: Value, right: Value, successors: ArrayList<Block>): ArrayList<Value> {
    let ops = ArrayList<Value>()
    ops.add(left)
    ops.add(right)
    for (succ in successors) {
        ops.add(succ)
    }
    return ops
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
