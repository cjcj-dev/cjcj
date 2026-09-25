package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.FuncDecl as AstFuncDecl
import cjcj::ast.FuncTy as AstFuncTy
import cjcj::ast.InterfaceDecl as AstInterfaceDecl
import cjcj::ast.PrimitiveTy as AstPrimitiveTy
import cjcj::ast.SrcIdentifier
import cjcj::ast.Ty as AstTy
import cjcj::ast.TypeKind as AstTypeKind

@Test
public class InvokeOriginalCalleeTest {
    @TestCase
    public func VirtualCalleeIsOriginalDecl(): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let int64 = context.GetInt64Ty()
        let parentDef = builder.CreateClassDef("dispatch", "ParentReader")
        let parentTy = context.GetClassTy(parentDef, ArrayList<Type>())
        parentDef.SetType(parentTy)
        let childDef = builder.CreateClassDef("dispatch", "DefaultReader")
        let childTy = context.GetClassTy(childDef, ArrayList<Type>())
        childDef.SetType(childTy)
        let parent = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>([parentTy, int64]), int64),
            "_CNparentRead", srcCodeIdentifier: "read", packageName: "dispatch")
        parent.SetOuterDeclaredOrExtendedDef(parentDef)
        parentDef.AddMethod(parent)
        let child = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>([childTy, int64]), int64),
            "_CNchildRead", srcCodeIdentifier: "read", packageName: "dispatch")
        child.SetOuterDeclaredOrExtendedDef(childDef)
        childDef.AddMethod(child)
        let iface = AstInterfaceDecl()
        iface.identifier = SrcIdentifier("ParentReader")
        let decl = AstFuncDecl()
        decl.identifier = SrcIdentifier("read")
        decl.outerDecl = iface
        let astInt = AstPrimitiveTy(AstTypeKind.TYPE_INT64)
        decl.SetTy(AstFuncTy(Array<AstTy>(1, repeat: astInt), astInt))
        let table = FaithfulAST2CHIRNodeMap()
        table.Set(decl, parent)
        let translator = Translator(builder, CHIRType(builder, CHIRTypeCache()), table,
            deserializedVals: HashMap<String, Value>())
        let host = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()),
            "_CNhost", srcCodeIdentifier: "host", packageName: "dispatch")
        let body = builder.CreateBlockGroup(host)
        host.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        translator.SetCurrentBlock(block)
        let callerExpr = builder.CreateConstant(int64, IntLiteral(1), block)
        block.AppendExpression(callerExpr)
        let info = FaithfulInstCalleeInfo(parentTy, childTy, ArrayList<Type>([childTy, int64]), int64,
            ArrayList<Type>(), true, decl)
        let call = translator.GenerateInvokeCallContext(info, callerExpr.GetResult().getOrThrow(),
            ArrayList<Value>())
        let invoke = builder.CreateInvoke(int64, call, block)
        block.AppendExpression(invoke)
        let observed = invoke.GetCallee().GetIdentifier()
        println("INVOKE_ORIGINAL_CALLEE expected=@_CNparentRead observed=${observed} child=@_CNchildRead")
        @Expect(observed, "@_CNparentRead")
    }
}
