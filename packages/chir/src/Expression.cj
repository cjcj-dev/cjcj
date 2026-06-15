package cangjie_compiler::chir

import std.collection.*

public open class Expression <: Base {
    private let kind: ExprKind
    private let operands: ArrayList<Value> = ArrayList<Value>()
    private let blockGroups: ArrayList<BlockGroup> = ArrayList<BlockGroup>()
    private var parent: Option<Block> = None
    private var result: Option<LocalVar> = None

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

    public func GetExprKind(): ExprKind { return kind }
    public func GetExprKindName(): String { return ExprKindName(kind) }
    public func GetExprMajorKind(): ExprMajorKind { return ExprKindMajor(kind) }

    public func IsApply(): Bool { return kind == ExprKind.APPLY }
    public func IsApplyWithException(): Bool { return kind == ExprKind.APPLY_WITH_EXCEPTION }
    public func IsBinaryExpr(): Bool { return GetExprMajorKind() == ExprMajorKind.BINARY_EXPR }
    public func IsConstant(): Bool { return kind == ExprKind.CONSTANT }
    public func IsDebug(): Bool { return kind == ExprKind.DEBUGEXPR }
    public func IsDynamicDispatch(): Bool { return kind == ExprKind.INVOKE || kind == ExprKind.INVOKESTATIC }
    public func IsField(): Bool { return kind == ExprKind.FIELD || kind == ExprKind.FIELD_BY_NAME }
    public func IsFuncCall(): Bool { return kind == ExprKind.APPLY || kind == ExprKind.INVOKE || kind == ExprKind.INVOKESTATIC }
    public func IsIntOpWithException(): Bool { return kind == ExprKind.INT_OP_WITH_EXCEPTION }
    public func IsInvoke(): Bool { return kind == ExprKind.INVOKE }
    public func IsInvokeStaticBase(): Bool {
        return kind == ExprKind.INVOKESTATIC || kind == ExprKind.INVOKESTATIC_WITH_EXCEPTION
    }
    public func IsLambda(): Bool { return kind == ExprKind.LAMBDA }
    public func IsLoad(): Bool { return kind == ExprKind.LOAD }
    public func IsTerminator(): Bool { return GetExprMajorKind() == ExprMajorKind.TERMINATOR }
    public func IsTypeCast(): Bool { return kind == ExprKind.TYPECAST || kind == ExprKind.TYPECAST_WITH_EXCEPTION }
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
            kind == ExprKind.INVOKESTATIC_WITH_EXCEPTION || kind == ExprKind.RAISE_EXCEPTION ||
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

    public func GetResult(): Option<LocalVar> {
        return result
    }

    public func SetResult(value: LocalVar): Unit {
        result = value
    }

    public func ConnectOperandsAndGroups(): Unit {
        for (operand in operands) {
            operand.AddUserOnly(this)
        }
        for (group in blockGroups) {
            group.AddUserOnly(this)
            group.SetOwnerExpression(this)
        }
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
        return CopyValueList(operands)
    }

    public open func ReplaceOperand(idx: Int64, newOperand: Value): Unit {
        let old = operands[idx]
        old.RemoveUserOnly(this)
        operands[idx] = newOperand
        newOperand.AddUserOnly(this)
    }

    public open func ReplaceOperand(oldOperand: Value, newOperand: Value): Unit {
        var idx: Int64 = 0
        while (idx < operands.size) {
            if (operands[idx].nodeId == oldOperand.nodeId) {
                ReplaceOperand(idx, newOperand)
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
            RemoveSelfFromBlock()
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
            RemoveSelfFromBlock()
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
        RemoveSelfFromBlock()
        block.AppendExpression(this)
    }

    public open func RemoveSelfFromBlock(): Unit {
        if (let Some(parentBlock) <- parent) {
            parentBlock.RemoveExprOnly(this)
        }
        parent = None
        EraseOperands()
    }

    public open func ReplaceWith(newExpr: Expression): Unit {
        if (let Some(parentBlock) <- parent) {
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
        RemoveSelfFromBlock()
    }

    public open func OperandsToString(): String {
        let parts = ArrayList<String>()
        for (operand in operands) {
            parts.add(operand.GetIdentifier())
        }
        return JoinStrings(parts, ", ")
    }

    public open func AddExtraComment(): String {
        return ""
    }

    public open func Clone(builder: CHIRBuilder, parent: Block): Expression {
        let clonedOperands = GetOperands()
        return builder.CreateExpression(kind, None, clonedOperands, parent)
    }

    public open func AsTerminator(): Option<Terminator> { return None }

    public func ToString(indent: Int64): String {
        var prefix = IndentToString(indent)
        if (let Some(res) <- result) {
            prefix += res.GetIdentifier() + " = "
        }
        var out = prefix + GetExprKindName()
        let operandsText = OperandsToString()
        if (!operandsText.isEmpty()) {
            out += "(" + operandsText + ")"
        }
        if (!blockGroups.isEmpty()) {
            let groupNames = ArrayList<String>()
            for (group in blockGroups) {
                groupNames.add(group.GetIdentifier())
            }
            out += " {" + JoinStrings(groupNames, ", ") + "}"
        }
        let extra = AddExtraComment()
        if (!extra.isEmpty()) {
            out += " // " + extra
        }
        return out
    }

    public func Dump(): Unit {
        println(ToString(0))
    }
}

public class UnaryExpression <: Expression {
    public init(kind: ExprKind, operand: Value, parent: Option<Block>) {
        super(kind, MakeUnaryOperands(operand), parent)
    }
}

public class BinaryExpression <: Expression {
    public init(kind: ExprKind, left: Value, right: Value, parent: Option<Block>) {
        super(kind, MakeBinaryOperands(left, right), parent)
    }
}

public class Constant <: Expression {
    public let literal: LiteralValue

    public init(literal: LiteralValue, parent: Option<Block>) {
        super(ExprKind.CONSTANT, ArrayList<Value>(), parent)
        this.literal = literal
    }

    public func IsNullLit(): Bool { return literal.IsNullLit() }
    public func IsBoolLit(): Bool { return literal.IsBoolLit() }
    public func IsIntLit(): Bool { return literal.IsIntLit() }
    public func IsFloatLit(): Bool { return literal.IsFloatLit() }
    public func IsStringLit(): Bool { return literal.IsStringLit() }

    public override func AddExtraComment(): String {
        return literal.ToString()
    }
}

public class Lambda <: Expression {
    private var body: Option<BlockGroup> = None
    private let params: ArrayList<Parameter> = ArrayList<Parameter>()

    public init(operands: ArrayList<Value>, body: BlockGroup, parent: Option<Block>) {
        super(ExprKind.LAMBDA, operands, MakeLambdaGroups(body), parent)
        this.body = body
    }

    public func GetBody(): Option<BlockGroup> { return body }

    public func AddParam(param: Parameter): Unit {
        params.add(param)
    }

    public func GetParams(): ArrayList<Parameter> {
        let out = ArrayList<Parameter>()
        for (param in params) {
            out.add(param)
        }
        return out
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

private func MakeLambdaGroups(body: BlockGroup): ArrayList<BlockGroup> {
    let groups = ArrayList<BlockGroup>()
    groups.add(body)
    return groups
}
