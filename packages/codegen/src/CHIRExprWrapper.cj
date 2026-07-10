package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.BinaryExpression
import cangjie_compiler::chir.CHIRBuilder
import cangjie_compiler::chir.Constant
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Apply
import cangjie_compiler::chir.ApplyWithException
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.GetInstParentCustomTyOfCallee
import cangjie_compiler::chir.Invoke
import cangjie_compiler::chir.InvokeStatic
import cangjie_compiler::chir.InvokeStaticWithException
import cangjie_compiler::chir.InvokeWithException
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.UnaryExpression
import cangjie_compiler::chir.Value
import cangjie_compiler::utils.{CJC_ASSERT, CJC_ASSERT_WITH_MSG}

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
    public let binaryExpr: BinaryExpression
    public init(expr: BinaryExpression) {
        super(expr)
        binaryExpr = expr
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

    public init(applyWithException: ApplyWithException) {
        super(applyWithException)
        CheckCalleeTypeArgsNum()
    }

    public func GetCallee(): Value {
        if (let Some(apply) <- (expr as Apply)) {
            return apply.GetCallee()
        }
        return (expr as ApplyWithException).getOrThrow().GetCallee()
    }

    public override func GetArgs(): ArrayList<Value> {
        if (let Some(apply) <- (expr as Apply)) {
            return apply.GetArgs()
        }
        return (expr as ApplyWithException).getOrThrow().GetArgs()
    }

    public override func GetInstantiatedTypeArgs(): ArrayList<Type> {
        if (let Some(apply) <- (expr as Apply)) {
            return apply.GetInstantiatedTypeArgs()
        }
        return (expr as ApplyWithException).getOrThrow().GetInstantiatedTypeArgs()
    }

    public override func GetThisType(fromObj: Bool): Option<Type> {
        let _ = fromObj
        if (let Some(apply) <- (expr as Apply)) {
            return apply.GetThisType()
        }
        return (expr as ApplyWithException).getOrThrow().GetThisType()
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
        let res = GetInstParentCustomTyOfCallee(GetCallee(), GetArgs(), GetThisType(), builder)
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

    public init(invokeWithException: InvokeWithException) {
        super(invokeWithException)
    }

    public func GetObject(): Value {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetObject()
        }
        return (expr as InvokeWithException).getOrThrow().GetObject()
    }

    public func GetMethodName(): String {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetMethodName()
        }
        return (expr as InvokeWithException).getOrThrow().GetMethodName()
    }

    public func GetMethodType(): FuncType {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetMethodType()
        }
        return (expr as InvokeWithException).getOrThrow().GetMethodType()
    }

    public override func GetArgs(): ArrayList<Value> {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetArgs()
        }
        return (expr as InvokeWithException).getOrThrow().GetArgs()
    }

    public override func GetInstantiatedTypeArgs(): ArrayList<Type> {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetInstantiatedTypeArgs()
        }
        return (expr as InvokeWithException).getOrThrow().GetInstantiatedTypeArgs()
    }

    public override func GetThisType(fromObj: Bool): Option<Type> {
        if (let Some(invoke) <- (expr as Invoke)) {
            return if (fromObj) { invoke.GetObject().GetType() } else { invoke.GetThisType() }
        }
        let invokeWithException = (expr as InvokeWithException).getOrThrow()
        return if (fromObj) { invokeWithException.GetObject().GetType() } else { invokeWithException.GetThisType() }
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
        return (expr as InvokeWithException).getOrThrow().GetInstSrcParentCustomTypeOfMethod(builder)
    }

    public override func GetThisParam(): Option<Value> {
        CJC_ASSERT(!IsCalleeStatic())
        return Some(GetObject())
    }

    public override func GetVirtualMethodOffset(): UInt64 {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetVirtualMethodOffset().getOrThrow()
        }
        return (expr as InvokeWithException).getOrThrow().GetVirtualMethodOffset().getOrThrow()
    }

    public func TestVritualMethodAttr(builder: CHIRBuilder, attr: Attribute): Bool {
        if (let Some(invoke) <- (expr as Invoke)) {
            return invoke.GetVirtualMethodAttr(builder).Test(attr)
        }
        return (expr as InvokeWithException).getOrThrow().GetVirtualMethodAttr(builder).Test(attr)
    }
}

public class CHIRInvokeStaticWrapper <: CHIRInvokeExpr {
    public init(invokeStatic: InvokeStatic) {
        super(invokeStatic)
    }

    public init(invokeStaticWithException: InvokeStaticWithException) {
        super(invokeStaticWithException)
    }

    public func GetMethodName(): String {
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetMethodName()
        }
        return (expr as InvokeStaticWithException).getOrThrow().GetMethodName()
    }

    public func GetMethodType(): FuncType {
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetMethodType()
        }
        return (expr as InvokeStaticWithException).getOrThrow().GetMethodType()
    }

    public func GetRTTIValue(): Value {
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetRTTIValue()
        }
        return (expr as InvokeStaticWithException).getOrThrow().GetRTTIValue()
    }

    public override func GetArgs(): ArrayList<Value> {
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetArgs()
        }
        return (expr as InvokeStaticWithException).getOrThrow().GetArgs()
    }

    public override func GetThisType(fromObj: Bool): Option<Type> {
        let _ = fromObj
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetThisType()
        }
        return (expr as InvokeStaticWithException).getOrThrow().GetThisType()
    }

    public override func GetInstantiatedTypeArgs(): ArrayList<Type> {
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetInstantiatedTypeArgs()
        }
        return (expr as InvokeStaticWithException).getOrThrow().GetInstantiatedTypeArgs()
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
        return (expr as InvokeStaticWithException).getOrThrow().GetInstSrcParentCustomTypeOfMethod(builder)
    }

    public override func GetThisParam(): Option<Value> {
        CJC_ASSERT(false)
        return None
    }

    public override func GetVirtualMethodOffset(): UInt64 {
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return invokeStatic.GetVirtualMethodOffset().getOrThrow()
        }
        return (expr as InvokeStaticWithException).getOrThrow().GetVirtualMethodOffset().getOrThrow()
    }
}
