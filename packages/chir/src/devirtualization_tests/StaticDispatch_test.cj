package cjcj::chir.devirtualization_tests

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::chir.*
import cjcj::option.GlobalOptions

@Test
public class StaticDispatchTest {
    private func Observe(isTry: Bool, dynamicRTTI: Bool, instantiate!: Bool = false, unknownThis!: Int64 = 0): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pkg = builder.CreatePackage("static_dispatch")
        let def = builder.CreateClassDef("static_dispatch", "Receiver")
        let ty = context.GetClassTy(def, ArrayList<Type>())
        def.SetType(ty)
        let signature = context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy())
        let generics = ArrayList<GenericType>()
        if (instantiate) { generics.add(context.GetGenericTy("T")) }
        let method = builder.CreateFunction(signature, "_CN15static_dispatch8Receiver6methodHv", srcCodeIdentifier: "method",
            packageName: "static_dispatch", genericTypeParams: generics)
        method.EnableAttr(Attribute.STATIC)
        method.SetOuterDeclaredOrExtendedDef(def)
        def.AddMethod(method)
        if (instantiate) {
            method.EnableAttr(Attribute.GENERIC)
            let methodBody = builder.CreateBlockGroup(method)
            method.InitBody(methodBody)
            let entry = builder.CreateBlock(methodBody)
            methodBody.SetEntryBlock(entry)
            let result = builder.CreateConstant(context.GetUnitTy(), UnitLiteral(), entry)
            entry.AppendExpression(result)
            method.SetReturnValue(result.GetResult().getOrThrow())
            entry.AppendExpression(builder.CreateExit(Some(result.GetResult().getOrThrow()), entry))
        }
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
        let instTypes = ArrayList<Type>()
        if (instantiate) { instTypes.add(context.GetInt64Ty()) }
        let thisTy: Type = if (unknownThis == 1) { context.GetGenericTy("ReceiverT") }
            else if (unknownThis == 2) { context.GetThisTy() } else { ty }
        let call = InvokeCallContext(method, rtti.GetResult().getOrThrow(),
            FuncCallContext(instTypeArgs: instTypes, thisType: Some(thisTy)))
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
        var frozenStatic = true
        for (expr in block.GetExpressions()) {
            if (expr is Apply || expr is TryApply || expr.IsInvokeStaticBase()) {
                observed = expr.GetExprKind()
                if (let Some(apply) <- (expr as Apply)) {
                    calleeCorrect = apply.GetCallee() == method
                    if (instantiate) {
                        if (let Some(fn) <- apply.GetCallee().AsFunction()) {
                            calleeCorrect = fn.GetGenericDecl() == Some(method)
                            frozenStatic = fn.TestAttr(Attribute.STATIC)
                        }
                    }
                } else if (let Some(apply) <- (expr as TryApply)) {
                    calleeCorrect = apply.GetCallee() == method
                    if (instantiate) {
                        if (let Some(fn) <- apply.GetCallee().AsFunction()) {
                            calleeCorrect = fn.GetGenericDecl() == Some(method)
                            frozenStatic = fn.TestAttr(Attribute.STATIC)
                        }
                    }
                }
                if (expr.IsTerminator()) {
                    let successors = expr.GetSuccessors()
                    successorsCorrect = successors.size == 2 && successors[0] == success && successors[1] == error
                }
            }
        }
        let expected = if (dynamicRTTI || unknownThis != 0) {
            if (isTry) { ExprKind.TRY_INVOKESTATIC } else { ExprKind.INVOKESTATIC }
        } else {
            if (isTry) { ExprKind.TRY_APPLY } else { ExprKind.APPLY }
        }
        println("STATIC_RESULT try=${isTry} dynamic=${dynamicRTTI} expected=${ExprKindName(expected)} observed=${ExprKindName(observed)} callee=${calleeCorrect} successors=${successorsCorrect}")
        @Expect(observed, expected)
        if (!dynamicRTTI && unknownThis == 0) { @Expect(calleeCorrect, true) }
        if (instantiate) {
            println("STATIC_FROZEN static=${frozenStatic}")
            @Expect(frozenStatic, false)
        }
        if (isTry) { @Expect(successorsCorrect, true) }
    }

    @TestCase public func InstantiatedFunctionDropsStatic(): Unit { Observe(false, false, instantiate: true) }
    @TestCase public func GenericThisRetainsDispatch(): Unit { Observe(false, false, unknownThis: 1) }
    @TestCase public func ThisTypeRetainsDispatch(): Unit { Observe(true, false, unknownThis: 2) }
    @TestCase public func StaticRTTIRewrites(): Unit { Observe(false, false) }
    @TestCase public func ValueRTTIRetainsDispatch(): Unit { Observe(false, true) }
    @TestCase public func TryStaticPreservesSuccessors(): Unit { Observe(true, false) }
    @TestCase public func TryValueRTTIRetainsDispatch(): Unit { Observe(true, true) }
}
