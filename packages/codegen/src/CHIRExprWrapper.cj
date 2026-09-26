package cjcj::codegen

import std.collection.*
import cjcj::chir.BinaryExpression
import cjcj::chir.CHIRBuilder
import cjcj::chir.Constant
import cjcj::chir.Expression
import cjcj::chir.ExprKind
import cjcj::chir.BinaryExpressionBase
import cjcj::chir.TryBinaryExpression
import cjcj::chir.Apply
import cjcj::chir.TryApply
import cjcj::chir.Attribute
import cjcj::chir.FuncType
import cjcj::chir.Function
import cjcj::chir.Invoke
import cjcj::chir.InvokeStatic
import cjcj::chir.TryInvokeStatic
import cjcj::chir.TryInvoke
import cjcj::chir.Type
import cjcj::chir.TypeCast
import cjcj::chir.TryNumericCast
import cjcj::chir.UnaryExpression
import cjcj::chir.Value
import cjcj::utils.{CJC_ASSERT, CJC_ASSERT_WITH_MSG, OverflowStrategy}

public open class CHIRExprWrapper {
    public let expr: Expression

    public init(expr: Expression) {
        this.expr = expr
    }

    public func GetTopLevelFunc(): Option<Function> {
        return expr.GetTopLevelFunc()
    }

    public func GetExpression(): Expression {
        return expr
    }
}

public class CHIRUnaryExprWrapper <: CHIRExprWrapper {
    public let unaryExpr: UnaryExpression
    public init(expr: UnaryExpression) {
        super(expr)
        unaryExpr = expr
    }
}

public class CHIRBinaryExprWrapper <: CHIRExprWrapper {
    public init(binaryExpr: BinaryExpression) {
        super(binaryExpr)
    }

    public init(tryBinaryExpr: TryBinaryExpression) {
        super(tryBinaryExpr)
    }

    public func GetLHSOperand(): Value {
        return (expr as BinaryExpressionBase).getOrThrow().GetLHSOperand()
    }

    public func GetRHSOperand(): Value {
        return (expr as BinaryExpressionBase).getOrThrow().GetRHSOperand()
    }

    public func GetOverflowStrategy(): OverflowStrategy {
        return (expr as BinaryExpressionBase).getOrThrow().GetOverflowStrategy()
    }

    public func GetBinaryExprKind(): ExprKind {
        return (expr as BinaryExpressionBase).getOrThrow().GetOpKind()
    }
}

public class CHIRConstantExprWrapper <: CHIRExprWrapper {
    public let constant: Constant
    public init(expr: Constant) {
        super(expr)
        constant = expr
    }
}

public abstract class CHIRCallExpr <: CHIRExprWrapper {
    public init(expr: Expression) {
        super(expr)
    }

    public func GetThisType(fromObj: Bool): Option<Type>
    public func GetThisType(): Option<Type> {
        return GetThisType(true)
    }
    public func GetInstantiatedTypeArgs(): ArrayList<Type>
    public func IsCalleeMethod(): Bool
    public func IsCalleeStructInstanceMethod(): Bool
    public func IsCalleeStatic(): Bool
    public func GetOuterType(builder: CHIRBuilder): Type
    public func GetThisParam(): Option<Value>
    public func GetArgs(): ArrayList<Value>
}

public class CHIRApplyWrapper <: CHIRCallExpr {
    public init(apply: Apply) {
        super(apply)
        CheckCalleeTypeArgsNum()
    }

    public init(tryApply: TryApply) {
        super(tryApply)
        CheckCalleeTypeArgsNum()
    }

    public func GetCallee(): Value {
        if (let Some(apply) <- (expr as Apply)) {
            return apply.GetCallee()
        }
        return (expr as TryApply).getOrThrow().GetCallee()
    }

    public override func GetArgs(): ArrayList<Value> {
        if (let Some(apply) <- (expr as Apply)) {
            return apply.GetArgs()
        }
        return (expr as TryApply).getOrThrow().GetArgs()
    }

    public override func GetInstantiatedTypeArgs(): ArrayList<Type> {
        if (let Some(apply) <- (expr as Apply)) {
            return apply.GetInstantiatedTypeArgs()
        }
        return (expr as TryApply).getOrThrow().GetInstantiatedTypeArgs()
    }

    public override func GetThisType(fromObj: Bool): Option<Type> {
        let _ = fromObj
        if (let Some(apply) <- (expr as Apply)) {
            return apply.GetThisType()
        }
        return (expr as TryApply).getOrThrow().GetThisType()
    }

    public override func IsCalleeMethod(): Bool {
        if (let Some(calleeFunc) <- GetCallee().AsFunction()) {
            return calleeFunc.IsMemberFunc()
        }
        return false
    }

    public override func IsCalleeStatic(): Bool {
        return GetCallee().TestAttr(Attribute.STATIC)
    }

    public override func IsCalleeStructInstanceMethod(): Bool {
        if (!IsCalleeMethod() || IsCalleeStatic()) {
            return false
        }
        let calleeFunc = GetCallee().AsFunction().getOrThrow()
        let outer = calleeFunc.GetOuterDeclaredOrExtendedDef() ?? return false
        return outer.IsStruct()
    }

    public func IsCalleeStructMutOrCtorMethod(): Bool {
        let calleeFunc = GetCallee().AsFunction().getOrThrow()
        return IsCalleeStructInstanceMethod() &&
            (GetCallee().TestAttr(Attribute.MUT) || calleeFunc.IsConstructor())
    }

    public override func GetOuterType(builder: CHIRBuilder): Type {
        let res = if (expr.GetExprKind() == ExprKind.APPLY) {
            (expr as Apply).getOrThrow().GetInstParentCustomTyOfCallee(builder)
        } else {
            (expr as TryApply).getOrThrow().GetInstParentCustomTyOfCallee(builder)
        }
        CJC_ASSERT(res.isSome())
        return res.getOrThrow()
    }

    public override func GetThisParam(): Option<Value> {
        if (IsCalleeMethod() && !IsCalleeStatic()) {
            return GetArgs()[0]
        }
        return None
    }

    private func CheckCalleeTypeArgsNum(): Unit {
        CJC_ASSERT_WITH_MSG(GetInstantiatedTypeArgs().size == GetCalleeTypeArgsNum(),
            "Incorrect ApplyExpr from CHIR, type arguments are missing.")
    }

    private func GetCalleeTypeArgsNum(): Int64 {
        if (let Some(calleeFunc) <- GetCallee().AsFunction()) {
            return calleeFunc.GetGenericTypeParams().size
        }
        return 0
    }
}

public abstract class CHIRInvokeExpr <: CHIRCallExpr {
    private var prepForVirtualCallBB: LLVMBasicBlockRef = LLVMNullBasicBlock()

    public init(expr: Expression) {
        super(expr)
    }

    public func GetVirtualMethodOffset(): UInt64

    public func SetPrepForVirtualCallBB(prepForVirtualCallBB: LLVMBasicBlockRef): Unit {
        this.prepForVirtualCallBB = prepForVirtualCallBB
    }

    public func GetPrepForVirtualCallBB(): LLVMBasicBlockRef {
        return prepForVirtualCallBB
    }
}

public class CHIRInvokeWrapper <: CHIRInvokeExpr {
    public init(invoke: Invoke) {
        super(invoke)
    }

    public init(tryInvoke: TryInvoke) {
        super(tryInvoke)
    }

    public func GetObject(): Value {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetObject()
        }
        return (expr as TryInvoke).getOrThrow().GetObject()
    }

    public func GetMethodName(): String {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetMethodName()
        }
        return (expr as TryInvoke).getOrThrow().GetMethodName()
    }

    public func GetMethodType(): FuncType {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetMethodType()
        }
        return (expr as TryInvoke).getOrThrow().GetMethodType()
    }

    public override func GetArgs(): ArrayList<Value> {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetArgs()
        }
        return (expr as TryInvoke).getOrThrow().GetArgs()
    }

    public override func GetInstantiatedTypeArgs(): ArrayList<Type> {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetInstantiatedTypeArgs()
        }
        return (expr as TryInvoke).getOrThrow().GetInstantiatedTypeArgs()
    }

    public override func GetThisType(fromObj: Bool): Option<Type> {
        if (let Some(invoke) <- (expr as Invoke)) {
            return if (fromObj) { invoke.GetObject().GetType() } else { invoke.GetThisType() }
        }
        let tryInvoke = (expr as TryInvoke).getOrThrow()
        return if (fromObj) { tryInvoke.GetObject().GetType() } else { tryInvoke.GetThisType() }
    }

    public override func IsCalleeMethod(): Bool {
        return true
    }

    public override func IsCalleeStatic(): Bool {
        return false
    }

    public override func IsCalleeStructInstanceMethod(): Bool {
        return false
    }

    public override func GetOuterType(builder: CHIRBuilder): Type {
        CJC_ASSERT(!IsCalleeStatic())
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetInstSrcParentCustomTypeOfMethod(builder)
        }
        return (expr as TryInvoke).getOrThrow().GetInstSrcParentCustomTypeOfMethod(builder)
    }

    public override func GetThisParam(): Option<Value> {
        CJC_ASSERT(!IsCalleeStatic())
        return Some(GetObject())
    }

    public override func GetVirtualMethodOffset(): UInt64 {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetVirtualMethodOffset()
        }
        return (expr as TryInvoke).getOrThrow().GetVirtualMethodOffset()
    }

    public func TestVritualMethodAttr(attr: Attribute): Bool {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetVirtualMethodAttr().Test(attr)
        }
        return (expr as TryInvoke).getOrThrow().GetVirtualMethodAttr().Test(attr)
    }
}

public class CHIRInvokeStaticWrapper <: CHIRInvokeExpr {
    public init(invokeStatic: InvokeStatic) {
        super(invokeStatic)
    }

    public init(tryInvokeStatic: TryInvokeStatic) {
        super(tryInvokeStatic)
    }

    public func GetMethodName(): String {
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetMethodName()
        }
        return (expr as TryInvokeStatic).getOrThrow().GetMethodName()
    }

    public func GetMethodType(): FuncType {
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetMethodType()
        }
        return (expr as TryInvokeStatic).getOrThrow().GetMethodType()
    }

    public func GetRTTIValue(): Value {
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetRTTIValue()
        }
        return (expr as TryInvokeStatic).getOrThrow().GetRTTIValue()
    }

    public override func GetArgs(): ArrayList<Value> {
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetArgs()
        }
        return (expr as TryInvokeStatic).getOrThrow().GetArgs()
    }

    public override func GetThisType(fromObj: Bool): Option<Type> {
        let _ = fromObj
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetThisType()
        }
        return (expr as TryInvokeStatic).getOrThrow().GetThisType()
    }

    public override func GetInstantiatedTypeArgs(): ArrayList<Type> {
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetInstantiatedTypeArgs()
        }
        return (expr as TryInvokeStatic).getOrThrow().GetInstantiatedTypeArgs()
    }

    public override func IsCalleeMethod(): Bool {
        return true
    }

    public override func IsCalleeStatic(): Bool {
        return true
    }

    public override func IsCalleeStructInstanceMethod(): Bool {
        return false
    }

    public override func GetOuterType(builder: CHIRBuilder): Type {
        CJC_ASSERT(IsCalleeStatic())
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetInstSrcParentCustomTypeOfMethod(builder)
        }
        return (expr as TryInvokeStatic).getOrThrow().GetInstSrcParentCustomTypeOfMethod(builder)
    }

    public override func GetThisParam(): Option<Value> {
        CJC_ASSERT(false)
        return None
    }

    public override func GetVirtualMethodOffset(): UInt64 {
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetVirtualMethodOffset()
        }
        return (expr as TryInvokeStatic).getOrThrow().GetVirtualMethodOffset()
    }
}
