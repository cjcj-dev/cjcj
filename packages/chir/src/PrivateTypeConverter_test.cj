package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class PrivateTypeConverterTest {
    @TestCase
    public func VisitExpr(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let converter = PrivateTypeConverter({ ty: Type =>
            if (ty.GetTypeKind() == TypeKind.TYPE_INT64) {
                return context.GetBoolTy()
            }
            return ty
        }, builder)

        let allocate = Allocate(context.GetInt64Ty(), None)
        let allocateResult = LocalVar(context.GetInt64Ty(), "%allocate", Some(allocate))
        converter.VisitExpr(allocate)
        @Expect(allocate.GetType().IsBoolean(), true)
        @Expect(allocateResult.GetType().getOrThrow().IsBoolean(), true)

        let methodParamTys = ArrayList<Type>([context.GetInt64Ty()])
        let methodType = context.GetFuncTy(methodParamTys, context.GetInt64Ty())
        let instantiatedTypeArgs = ArrayList<Type>([context.GetInt64Ty()])
        let funcCallContext = FuncCallContext(instTypeArgs: instantiatedTypeArgs,
            thisType: Some(context.GetInt64Ty()))
        let object = LocalVar(context.GetInt64Ty(), "%object", None)
        let invokeContext = InvokeCallContext(object, funcCallContext, FuncSigInfo(methodType))
        let invoke = Invoke(invokeContext, None)
        let invokeResult = LocalVar(context.GetInt64Ty(), "%invoke", Some(invoke))
        converter.VisitExpr(invoke)
        @Expect(invoke.GetMethodType().GetParamType(0).IsBoolean(), true)
        @Expect(invoke.GetMethodType().GetReturnType().IsBoolean(), true)
        @Expect(invoke.GetThisType().getOrThrow().IsBoolean(), true)
        @Expect(invoke.GetInstantiatedTypeArgs()[0].IsBoolean(), true)
        @Expect(invokeResult.GetType().getOrThrow().IsBoolean(), true)
    }

    @TestCase
    public func VisitValue(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let convertedGenericType = context.GetGenericTy("U")
        let converter = PrivateTypeConverter({ ty: Type =>
            if (ty.GetTypeKind() == TypeKind.TYPE_INT64) {
                return context.GetBoolTy()
            }
            if (ty.IsGeneric()) {
                return convertedGenericType
            }
            return ty
        }, builder)

        let paramTys = ArrayList<Type>([context.GetInt64Ty()])
        let funcType = context.GetFuncTy(paramTys, context.GetInt64Ty())
        let genericTypeParams = ArrayList<GenericType>([context.GetGenericTy("T")])
        let function = Function(funcType, "$function", "function", "", "test",
            genericTypeParams: genericTypeParams)
        function.SetOverrideSrcFuncType(funcType)
        let param = Parameter(context.GetInt64Ty(), "%param", Some(function))

        converter.VisitValue(function)
        @Expect(function.GetFuncType().getOrThrow().GetParamType(0).IsBoolean(), true)
        @Expect(function.GetFuncType().getOrThrow().GetReturnType().IsBoolean(), true)
        @Expect(function.GetOverrideSrcFuncType().getOrThrow().GetParamType(0).IsBoolean(), true)
        @Expect(function.GetOverrideSrcFuncType().getOrThrow().GetReturnType().IsBoolean(), true)
        @Expect(function.GetGenericTypeParams()[0].GetIdentifier(), "U")
        @Expect(param.GetType().getOrThrow().IsBoolean(), true)
    }
}
