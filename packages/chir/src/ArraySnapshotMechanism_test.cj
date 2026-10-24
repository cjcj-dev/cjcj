package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class ArraySnapshotMechanismTest {
    private func Check(nested: Bool, interfere: Bool): Unit {
        let c = CHIRContext()
        let b = CHIRBuilder(c)
        let inner = c.GetTupleTy(ArrayList<Type>([c.GetInt64Ty(), c.GetInt64Ty()]))
        let element = if (nested) { c.GetTupleTy(ArrayList<Type>([inner, c.GetInt64Ty()])) } else { inner }
        let arrayTy = c.GetRefTy(c.GetRawArrayTy(element))
        let fn = b.CreateFunction(c.GetFuncTy(ArrayList<Type>([arrayTy, c.GetBoolTy()]), c.GetInt64Ty()), "snapshotBranches", packageName: "fixture")
        let array = b.CreateParameter(arrayTy, DebugLocation(), fn)
        let cond = b.CreateParameter(c.GetBoolTy(), DebugLocation(), fn)
        let body = b.CreateBlockGroup(fn)
        fn.InitBody(body)
        let entry = b.CreateBlock(body)
        let left = b.CreateBlock(body)
        let right = b.CreateBlock(body)
        body.SetEntryBlock(entry)
        let ret = b.CreateAllocate(c.GetRefTy(c.GetInt64Ty()), c.GetInt64Ty(), entry)
        fn.SetReturnValue(ret.GetResult().getOrThrow())
        entry.AppendExpression(ret)
        let index = b.CreateConstant(c.GetInt64Ty(), IntLiteral(0), entry)
        let get = b.CreateIntrinsic(element, IntrisicCallContext(kind: IntrinsicKind.ARRAY_GET_UNCHECKED,
            args: ArrayList<Value>([array, index.GetResult().getOrThrow()])), entry)
        entry.AppendExpressions(ArrayList<Expression>([index, get]))
        let writer = b.CreateFunction(c.GetFuncTy(ArrayList<Type>([arrayTy]), c.GetUnitTy()), "overwrite")
        let call: Option<Apply> = if (interfere) {
            let expr = b.CreateApply(c.GetUnitTy(), writer, FuncCallContext(args: ArrayList<Value>([array])), entry)
            entry.AppendExpression(expr)
            Some(expr)
        } else { None }
        entry.AppendExpression(b.CreateBranch(cond, left, right, entry))
        let fields = ArrayList<Field>()
        let outputs = ArrayList<Store>()
        var idx: UInt64 = 0u64
        for (succ in ArrayList<Block>([left, right])) {
            let path = if (nested) { ArrayList<UInt64>([0u64, idx]) } else { ArrayList<UInt64>([idx]) }
            let field = b.CreateField(c.GetInt64Ty(), get.GetResult().getOrThrow(), path, succ)
            let output = b.CreateStore(field.GetResult().getOrThrow(), ret.GetResult().getOrThrow(), succ)
            succ.AppendExpressions(ArrayList<Expression>([field, output, b.CreateExit(None, succ)]))
            fields.add(field); outputs.add(output)
            idx++
        }
        CheckMechanismIR(fn, b)
        @Expect(GetRefToArrayElem.RunOnFunc(fn, b), 1)
        @Expect(get.GetParentBlock().isNone(), true)
        var observed: Int64 = 0
        for (i in 0..outputs.size) {
            let load = (outputs[i].GetOperand(0).AsLocalVar().getOrThrow().GetExpr().getOrThrow() as Load).getOrThrow()
            let ref = (load.GetLocation().AsLocalVar().getOrThrow().GetExpr().getOrThrow() as GetElementRef).getOrThrow()
            @Expect(ref.GetPath().size, fields[i].GetPath().size)
            for (j in 0..ref.GetPath().size) { @Expect(ref.GetPath()[j], fields[i].GetPath()[j]) }
            @Expect(fields[i].GetParentBlock().isNone(), true)
            if (interfere) {
                // Entry is the only predecessor of each user, so placing the
                // load here before the write proves both dominance and timing.
                @Expect(load.GetParentBlock().getOrThrow().nodeId, entry.nodeId)
                @Expect(ref.GetParentBlock().getOrThrow().nodeId, entry.nodeId)
                let userBlock = outputs[i].GetParentBlock().getOrThrow()
                @Expect(userBlock.GetPredecessors().size, 1)
                @Expect(userBlock.GetPredecessors()[0].nodeId, entry.nodeId)
                var loadAt: Int64 = -1
                var callAt: Int64 = -1
                for (k in 0..entry.GetExpressions().size) {
                    if (entry.GetExpressions()[k].nodeId == load.nodeId) { loadAt = k }
                    if (entry.GetExpressions()[k].nodeId == call.getOrThrow().nodeId) { callAt = k }
                }
                @Expect(loadAt >= 0 && loadAt < callAt, true)
            }
            observed++
        }
        @Expect(observed, 2)
        @Expect(outputs[0].GetOperand(0).nodeId != outputs[1].GetOperand(0).nodeId, true)
        println("MECHANISM Snapshot nested=${nested} interfere=${interfere} observed=${observed}")
    }

    @TestCase public func CrossBlockMultipleFields(): Unit { Check(false, true) }
    @TestCase public func CrossBlockNestedFields(): Unit { Check(true, true) }
    @TestCase public func MultipleFieldsNoWriteControl(): Unit { Check(false, false) }
    @TestCase public func NestedFieldsNoWriteControl(): Unit { Check(true, false) }
}
