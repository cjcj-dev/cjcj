package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::option.OptimizationLevel

@Test
public class ArrayListConstStartOptTest {
    private func AddPads(def: CustomTypeDef, count: UInt64, ty: Type): Unit {
        var idx: UInt64 = 0
        while (idx < count) {
            def.AddInstanceVar(MemberVarInfo("pad${idx}", ty))
            idx++
        }
    }

    private func RewrittenToZero(block: Block): Bool {
        var zeros: Int64 = 0
        var fields: Int64 = 0
        for (expr in block.GetExpressions()) {
            if (let Some(constant) <- (expr as Constant)) {
                if (constant.IsIntLit() && constant.GetSignedIntLitVal() == 0) {
                    zeros++
                }
            } else if (let Some(field) <- (expr as Field)) {
                if (field.GetExprKind() == ExprKind.FIELD) {
                    fields++
                }
            }
        }
        return zeros == 1 && fields == 0
    }

    private func RunNoApply(funcName: String, parentName: String, startName: String, startIdx: UInt64,
        myDataName: String, myDataIdx: UInt64): Bool {
        let context = CHIRContext()
        let pkg = Package("std.collection")
        context.SetCurPackage(pkg)
        let builder = CHIRBuilder(context)
        let int64 = context.GetInt64Ty()
        let arrayDef = builder.CreateClassDef("std.core", "Array", "Array")
        let arrayTy = context.GetClassTy(arrayDef, ArrayList<Type>())
        arrayDef.SetType(arrayTy)
        AddPads(arrayDef, startIdx, int64)
        arrayDef.AddInstanceVar(MemberVarInfo(startName, int64))
        let listDef = builder.CreateClassDef("std.collection", parentName, parentName)
        let listTy = context.GetClassTy(listDef, ArrayList<Type>())
        listDef.SetType(listTy)
        AddPads(listDef, myDataIdx, int64)
        listDef.AddInstanceVar(MemberVarInfo(myDataName, arrayTy))
        let fn = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>([listTy]), int64),
            "_CN${funcName}", srcCodeIdentifier: funcName, packageName: "std.collection")
        fn.SetOuterDeclaredOrExtendedDef(listDef)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let param = builder.CreateParameter(listTy, DebugLocation(), fn)
        let ger = builder.CreateGetElementRef(context.GetRefTy(arrayTy), param,
            ArrayList<UInt64>([myDataIdx]), block)
        block.AppendExpression(ger)
        let load = builder.CreateLoad(arrayTy, ger.GetResult().getOrThrow(), block)
        block.AppendExpression(load)
        let field = builder.CreateField(int64, load.GetResult().getOrThrow(),
            ArrayList<UInt64>([startIdx]), block)
        block.AppendExpression(field)
        let inlinePass = FunctionInline(builder, OptimizationLevel.O2, false)
        let pass = ArrayListConstStartOpt(builder, inlinePass)
        pass.RunOnPackage(pkg)
        return RewrittenToZero(block)
    }

    @TestCase
    public func MismatchedLayoutStillRewrites(): Unit {
        let rewritten = RunNoApply("[]", "ArrayList", "start", 2u64, "myData", 3u64)
        println("ARRAYLIST_CONST_START case=mismatch startIdx=2 myDataIdx=3 rewritten=${rewritten}")
        @Expect(rewritten, true)
    }

    @TestCase
    public func IndexOneStillRewrites(): Unit {
        let rewritten = RunNoApply("[]", "ArrayList", "start", 1u64, "myData", 1u64)
        println("ARRAYLIST_CONST_START case=index1 startIdx=1 myDataIdx=1 rewritten=${rewritten}")
        @Expect(rewritten, true)
    }

    @TestCase
    public func NonWhitelistUnchanged(): Unit {
        let rewritten = RunNoApply("size", "ArrayList", "start", 2u64, "myData", 3u64)
        println("ARRAYLIST_CONST_START case=nonwhitelist rewritten=${rewritten}")
        @Expect(rewritten, false)
    }

    @TestCase
    public func WrongNameUnchanged(): Unit {
        let rewritten = RunNoApply("[]", "ArrayList", "len", 2u64, "buf", 3u64)
        println("ARRAYLIST_CONST_START case=wrongname rewritten=${rewritten}")
        @Expect(rewritten, false)
    }
}
