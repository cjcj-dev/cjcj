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
        DetachFromBlockOnly()
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

public class Allocate <: Expression {
    private let allocatedType: Type

    public init(ty: Type, parent: Option<Block>) {
        super(ExprKind.ALLOCATE, ArrayList<Value>(), parent)
        allocatedType = ty
    }

    public func GetType(): Type {
        return allocatedType
    }

    public override func OperandsToString(): String {
        return allocatedType.ToString()
    }
}

public class Load <: Expression {
    public init(location: Value, parent: Option<Block>) {
        super(ExprKind.LOAD, MakeUnaryOperands(location), parent)
    }

    public func GetLocation(): Value {
        return GetOperand(0)
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
        return CopyTypeList(instantiatedTypeArgs)
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
