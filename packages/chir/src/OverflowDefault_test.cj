package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::utils.{OverflowStrategy, OverflowStrategyIndex}
import cjcj::ast.Attribute as AstAttribute
import cjcj::ast.FuncDecl as AstFuncDecl
import cjcj::ast.FuncTy as AstFuncTy
import cjcj::ast.InterfaceDecl as AstInterfaceDecl
import cjcj::ast.PrimitiveTy as AstPrimitiveTy
import cjcj::ast.SrcIdentifier
import cjcj::ast.Ty as AstTy
import cjcj::ast.TypeKind as AstTypeKind

@Test
public class OverflowDefaultTest {
    private func Host(builder: CHIRBuilder): Block {
        let context = builder.context
        let host = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()),
            "_CNoverflow4hostHv", srcCodeIdentifier: "host", packageName: "overflow")
        let body = builder.CreateBlockGroup(host)
        host.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        return block
    }

    private func OverflowDecl(name: String, isStatic: Bool): AstFuncDecl {
        let iface = AstInterfaceDecl()
        iface.identifier = SrcIdentifier("Num")
        let decl = AstFuncDecl()
        decl.identifier = SrcIdentifier(name)
        decl.outerDecl = iface
        let int64 = AstPrimitiveTy(AstTypeKind.TYPE_INT64)
        decl.SetTy(AstFuncTy(Array<AstTy>(1, repeat: int64), int64))
        if (isStatic) {
            decl.EnableAttr(AstAttribute.STATIC)
        }
        return decl
    }

    private func TranslatorFor(builder: CHIRBuilder, table: FaithfulAST2CHIRNodeMap): Translator {
        return Translator(builder, CHIRType(builder, CHIRTypeCache()), table,
            deserializedVals: HashMap<String, Value>())
    }

    private func ClassWithMethod(builder: CHIRBuilder, name: String, isStatic: Bool): (ClassType, Function) {
        let context = builder.context
        let def = builder.CreateClassDef("overflow", "Num")
        let classTy = context.GetClassTy(def, ArrayList<Type>())
        def.SetType(classTy)
        let int64 = context.GetInt64Ty()
        let params = if (isStatic) {
            ArrayList<Type>([int64])
        } else {
            ArrayList<Type>([classTy, int64])
        }
        let method = builder.CreateFunction(context.GetFuncTy(params, int64), "_CN${name}",
            srcCodeIdentifier: name, packageName: "overflow")
        if (isStatic) {
            method.EnableAttr(Attribute.STATIC)
        }
        def.AddMethod(method)
        method.SetOuterDeclaredOrExtendedDef(def)
        return (classTy, method)
    }

    private func ObserveWrapper(isStatic: Bool, name: String): String {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let block = Host(builder)
        let (classTy, method) = ClassWithMethod(builder, name, isStatic)
        let int64 = context.GetInt64Ty()
        let decl = OverflowDecl(name, isStatic)
        let table = FaithfulAST2CHIRNodeMap()
        table.Set(decl, method)
        let translator = TranslatorFor(builder, table)
        translator.SetCurrentBlock(block)
        var thisObj: Option<Value> = None<Value>
        if (!isStatic) {
            let caller = builder.CreateConstant(int64, IntLiteral(1), block)
            block.AppendExpression(caller)
            thisObj = Some(caller.GetResult().getOrThrow())
        }
        let before = block.GetExpressionsNum()
        let params = if (isStatic) {
            ArrayList<Type>([int64])
        } else {
            ArrayList<Type>([classTy, int64])
        }
        let info = FaithfulInstCalleeInfo(classTy, classTy, params, int64, ArrayList<Type>(), true, decl)
        let _ = translator.WrapMemberMethodByLambda(decl, info, thisObj)
        let lambda = (block.GetExpressions()[before] as Lambda).getOrThrow()
        let entry = lambda.GetBody().getOrThrow().GetEntryBlock().getOrThrow()
        var observed = ""
        var found = false
        for (expr in entry.GetExpressions()) {
            if (let Some(dispatch) <- (expr as DynamicDispatch)) {
                found = true
                observed = dispatch.GetMethodName()
                println("OVERFLOW_DEFAULT path=wrapper static=${isStatic} op=${name} name=${observed}")
            }
        }
        @Expect(found, true)
        return observed
    }

    private func ObserveExplicit(isStatic: Bool, strategy: OverflowStrategy): String {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let block = Host(builder)
        let (classTy, method) = ClassWithMethod(builder, "+", isStatic)
        let int64 = context.GetInt64Ty()
        let decl = OverflowDecl("+", isStatic)
        let table = FaithfulAST2CHIRNodeMap()
        table.Set(decl, method)
        let translator = TranslatorFor(builder, table)
        let callerExpr = builder.CreateConstant(int64, IntLiteral(1), block)
        block.AppendExpression(callerExpr)
        let params = if (isStatic) {
            ArrayList<Type>([int64])
        } else {
            ArrayList<Type>([classTy, int64])
        }
        let info = FaithfulInstCalleeInfo(classTy, classTy, params, int64, ArrayList<Type>(), true, decl)
        let call = translator.GenerateInvokeCallContext(info, callerExpr.GetResult().getOrThrow(),
            ArrayList<Value>(), strategy: strategy)
        let invoke = if (isStatic) {
            builder.CreateInvokeStatic(int64, call, block)
        } else {
            builder.CreateInvoke(int64, call, block)
        }
        block.AppendExpression(invoke)
        let observed = invoke.GetMethodName()
        println("OVERFLOW_DEFAULT path=explicit static=${isStatic} strategy=${OverflowStrategyIndex(strategy)} name=${observed}")
        return observed
    }

    @TestCase
    public func StaticOmitted(): Unit {
        @Expect(ObserveWrapper(true, "+"), "~+")
    }

    @TestCase
    public func InstanceOmitted(): Unit {
        @Expect(ObserveWrapper(false, "+"), "~+")
    }

    @TestCase
    public func NonOverflowOmitted(): Unit {
        @Expect(ObserveWrapper(false, "read"), "read")
    }

    @TestCase
    public func StaticExplicitNA(): Unit {
        @Expect(ObserveExplicit(true, OverflowStrategy.NA), "+")
    }

    @TestCase
    public func InstanceExplicitNA(): Unit {
        @Expect(ObserveExplicit(false, OverflowStrategy.NA), "+")
    }

    @TestCase
    public func StaticExplicitWrapping(): Unit {
        @Expect(ObserveExplicit(true, OverflowStrategy.WRAPPING), "&+")
    }
}
