package cjcj::chir

import std.collection.*
import std.core.Box as CoreBox
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::utils.OverflowStrategy

@Test
public class DynamicDispatchTest {
    private func MakePackage(kind: ExprKind): (CHIRBuilder, Package, Expression, Function) {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pkg = builder.CreatePackage("dispatch")
        let method = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>([context.GetInt64Ty()]),
            context.GetInt64Ty()), "method", srcCodeIdentifier: "method", packageName: "dispatch")
        let host = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()),
            "host", srcCodeIdentifier: "host", packageName: "dispatch")
        let body = builder.CreateBlockGroup(host)
        host.InitBody(body)
        pkg.SetPackageLiteralInitFunc(host)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let normal = builder.CreateBlock(body)
        let error = builder.CreateBlock(body)
        body.AddBlock(normal)
        body.AddBlock(error)
        normal.AppendExpression(builder.CreateExit(None, normal))
        error.AppendExpression(builder.CreateExit(None, error))
        let object = builder.CreateConstant(context.GetInt64Ty(), IntLiteral(17), block)
        block.AppendExpression(object)
        let isStatic = kind == ExprKind.INVOKESTATIC || kind == ExprKind.INVOKESTATIC_WITH_EXCEPTION
        var caller = object.GetResult().getOrThrow()
        if (isStatic) {
            let rtti = builder.CreateGetRTTIStatic(context.GetUnitTy(), context.GetInt64Ty(), block)
            block.AppendExpression(rtti)
            caller = rtti.GetResult().getOrThrow()
        }
        let call = InvokeCallContext(method, caller,
            FuncCallContext(thisType: Some(context.GetInt64Ty())), overflowStrategy: OverflowStrategy.WRAPPING)
        let invoke: Expression = match (kind) {
            case ExprKind.INVOKE => builder.CreateInvoke(context.GetInt64Ty(), call, block)
            case ExprKind.INVOKESTATIC => builder.CreateInvokeStatic(context.GetInt64Ty(), call, block)
            case ExprKind.INVOKE_WITH_EXCEPTION =>
                builder.CreateInvokeWithException(context.GetInt64Ty(), call, normal, error, block)
            case _ => builder.CreateInvokeStaticWithException(context.GetInt64Ty(), call, normal, error, block)
        }
        block.AppendExpression(invoke)
        if (kind == ExprKind.INVOKE || kind == ExprKind.INVOKESTATIC) {
            block.AppendExpression(builder.CreateExit(None, block))
        }
        return (builder, pkg, invoke, method)
    }

    private func CheckSignature(expr: Expression, expected: Function): Unit {
        // Nonfatal assertions expose the actual product result even if an earlier check fails.
        if (let Some(dispatch) <- (expr as DynamicDispatch)) {
            @Expect(dispatch.GetCallee() == expected, true)
            @Expect(dispatch.GetMethodType() == expected.GetFuncType().getOrThrow(), true)
            @Expect(dispatch.GetMethodName(), "&" + expected.GetSrcCodeIdentifier())
            @Expect(dispatch.GetGenericTypeParams().size, expected.GetGenericTypeParams().size)
            println("DISPATCH_RESULT kind=${expr.GetExprKindName()} type=${dispatch.GetMethodType().ToString()} name=${dispatch.GetMethodName()}")
        } else {
            let dispatch = (expr as DynamicDispatchWithException).getOrThrow()
            @Expect(dispatch.GetCallee() == expected, true)
            @Expect(dispatch.GetMethodType() == expected.GetFuncType().getOrThrow(), true)
            @Expect(dispatch.GetMethodName(), "&" + expected.GetSrcCodeIdentifier())
            @Expect(dispatch.GetGenericTypeParams().size, expected.GetGenericTypeParams().size)
            println("DISPATCH_RESULT kind=${expr.GetExprKindName()} type=${dispatch.GetMethodType().ToString()} name=${dispatch.GetMethodName()}")
        }
    }

    private func CalleeReplacement(kind: ExprKind): Unit {
        let (builder, _, invoke, _) = MakePackage(kind)
        let context = builder.context
        let replacement = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>([context.GetBoolTy()]),
            context.GetBoolTy()), "replacement", srcCodeIdentifier: "replacement",
            genericTypeParams: ArrayList<GenericType>([context.GetGenericTy("T")]))
        invoke.ReplaceOperand(0, replacement)
        CheckSignature(invoke, replacement)
        let clone = invoke.Clone(builder, invoke.GetParentBlock().getOrThrow())
        CheckSignature(clone, replacement)
    }

    private func RoundTrip(kind: ExprKind, binary: Bool): Unit {
        let (_, pkg, invoke, method) = MakePackage(kind)
        CheckSignature(invoke, method)
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        if (binary) {
            let filename = "dispatch-${ExprKindName(kind)}.chir"
            CHIRSerializer.Serialize(pkg, filename, ToCHIRPhase.RAW)
            let phase = CoreBox<ToCHIRPhase>(ToCHIRPhase.RAW)
            @Expect(CHIRDeserializer.Deserialize(filename, builder, phase), true)
        } else {
            let text = CHIRSerializerImpl().SerializePackage(pkg)
            CHIRDeserializerImpl(builder).DeserializePackage(text)
        }
        let restored = context.GetCurPackage().getOrThrow()
        let host = restored.TryGetGlobalFunc(GLOBAL_VALUE_PREFIX + "host").getOrThrow()
        let restoredMethod = restored.TryGetGlobalFunc(GLOBAL_VALUE_PREFIX + "method").getOrThrow()
        var observed: Int64 = 0
        let entry = host.GetEntryBlock()
        @Expect(host.GetBody().isSome(), true)
        @Expect(entry.isSome(), true)
        println("DISPATCH_ENTRY kind=${ExprKindName(kind)} body=${host.GetBody().isSome()} entry=${entry.isSome()}")
        if (let Some(block) <- entry) {
            for (expr in block.GetExpressions()) {
                if (expr.GetExprKind() == kind) {
                    observed++
                    CheckSignature(expr, restoredMethod)
                }
            }
        }
        @Expect(observed, 1)
        println("DISPATCH_ROUNDTRIP kind=${ExprKindName(kind)} binary=${binary} observed=${observed}")
    }

    @TestCase public func InvokeCallee(): Unit { CalleeReplacement(ExprKind.INVOKE) }
    @TestCase public func InvokeStaticCallee(): Unit { CalleeReplacement(ExprKind.INVOKESTATIC) }
    @TestCase public func InvokeExceptionCallee(): Unit { CalleeReplacement(ExprKind.INVOKE_WITH_EXCEPTION) }
    @TestCase public func InvokeStaticExceptionCallee(): Unit { CalleeReplacement(ExprKind.INVOKESTATIC_WITH_EXCEPTION) }
    @TestCase public func InvokeBinary(): Unit { RoundTrip(ExprKind.INVOKE, true) }
    @TestCase public func InvokeStaticBinary(): Unit { RoundTrip(ExprKind.INVOKESTATIC, true) }
    @TestCase public func InvokeExceptionBinary(): Unit { RoundTrip(ExprKind.INVOKE_WITH_EXCEPTION, true) }
    @TestCase public func InvokeStaticExceptionBinary(): Unit { RoundTrip(ExprKind.INVOKESTATIC_WITH_EXCEPTION, true) }
    @TestCase public func InvokeText(): Unit { RoundTrip(ExprKind.INVOKE, false) }
    @TestCase public func InvokeStaticText(): Unit { RoundTrip(ExprKind.INVOKESTATIC, false) }
    @TestCase public func InvokeExceptionText(): Unit { RoundTrip(ExprKind.INVOKE_WITH_EXCEPTION, false) }
    @TestCase public func InvokeStaticExceptionText(): Unit { RoundTrip(ExprKind.INVOKESTATIC_WITH_EXCEPTION, false) }
}
