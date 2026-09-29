package cjcj::chir.devirtualization_tests

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::chir.*
import cjcj::option.GlobalOptions

@Test
public class StaticDispatchTest {
    private func Observe(isTry: Bool, dynamicRTTI: Bool): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pkg = builder.CreatePackage("static_dispatch")
        let def = builder.CreateClassDef("static_dispatch", "Receiver")
        let ty = context.GetClassTy(def, ArrayList<Type>())
        def.SetType(ty)
        let signature = context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy())
        let method = builder.CreateFunction(signature, "method", srcCodeIdentifier: "method",
            packageName: "static_dispatch")
        method.EnableAttr(Attribute.STATIC)
        method.SetOuterDeclaredOrExtendedDef(def)
        def.AddMethod(method)
        def.GetDefVTable().AddNewItemToTypeVTable(ty,
            VirtualMethodInfo(FuncSigInfo(signature, funcName: "method"), method,
                method.GetAttributeInfo(), signature, ty, context.GetUnitTy()))
        let host = builder.CreateFunction(signature, "host", srcCodeIdentifier: "host",
            packageName: "static_dispatch")
        let body = builder.CreateBlockGroup(host)
        host.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let success = builder.CreateBlock(body)
        let error = builder.CreateBlock(body)
        body.AddBlock(success)
        body.AddBlock(error)
        success.AppendExpression(builder.CreateExit(None, success))
        error.AppendExpression(builder.CreateExit(None, error))
        let object = builder.CreateParameter(ty, host.GetDebugLocation(), host)
        let rtti: Expression = if (dynamicRTTI) {
            builder.CreateGetRTTI(context.GetUnitTy(), object, block)
        } else {
            builder.CreateGetRTTIStatic(context.GetUnitTy(), ty, block)
        }
        block.AppendExpression(rtti)
        let call = InvokeCallContext(method, rtti.GetResult().getOrThrow(),
            FuncCallContext(thisType: Some(ty)))
        let invoke: Expression = if (isTry) {
            builder.CreateTryInvokeStatic(context.GetUnitTy(), call, success, error, block)
        } else {
            builder.CreateInvokeStatic(context.GetUnitTy(), call, block)
        }
        block.AppendExpression(invoke)
        if (!isTry) { block.AppendExpression(builder.CreateExit(None, block)) }
        let funcs = Devirtualization.CollectContainInvokeExprFuncs(pkg)
        println("STATIC_FILTER selected=${funcs.contains(host)}")
        @Expect(funcs.contains(host), true)
        let pass = Devirtualization(AnalysisWrapper<TypeAnalysis, TypeDomain>(builder),
            DevirtualizationInfo(pkg), builder, pkg, GlobalOptions())
        pass.RunOnFuncs(funcs)
        var observed = ExprKind.INVALID
        var calleeCorrect = false
        var successorsCorrect = false
        for (expr in block.GetExpressions()) {
            if (expr is Apply || expr is TryApply || expr.IsInvokeStaticBase()) {
                observed = expr.GetExprKind()
                if (let Some(apply) <- (expr as Apply)) {
                    calleeCorrect = apply.GetCallee() == method
                } else if (let Some(apply) <- (expr as TryApply)) {
                    calleeCorrect = apply.GetCallee() == method
                }
                let (next, failure) = expr.GetSuccessAndErrorBlocks()
                successorsCorrect = next == Some(success) && failure == Some(error)
            }
        }
        let expected = if (dynamicRTTI) {
            if (isTry) { ExprKind.TRY_INVOKESTATIC } else { ExprKind.INVOKESTATIC }
        } else {
            if (isTry) { ExprKind.TRY_APPLY } else { ExprKind.APPLY }
        }
        println("STATIC_RESULT try=${isTry} dynamic=${dynamicRTTI} expected=${ExprKindName(expected)} observed=${ExprKindName(observed)} callee=${calleeCorrect} successors=${successorsCorrect}")
        @Expect(observed, expected)
        if (!dynamicRTTI) { @Expect(calleeCorrect, true) }
        if (isTry) { @Expect(successorsCorrect, true) }
    }

    @TestCase public func StaticRTTIRewrites(): Unit { Observe(false, false) }
    @TestCase public func ValueRTTIRetainsDispatch(): Unit { Observe(false, true) }
    @TestCase public func TryStaticPreservesSuccessors(): Unit { Observe(true, false) }
    @TestCase public func TryValueRTTIRetainsDispatch(): Unit { Observe(true, true) }
}
