// Upstream 37f1ba18 CHIRSerialzierTest.cpp:179 and CHIRDeSerialzierTest.cpp:175.
// Exercise the linked product serializer/deserializer, including MATCH_CASE metadata.
package unreachable_serialization

import cjcj::chir.*
import std.collection.*
import std.core.Box as CoreBox

main(): Int64 {
    let context = CHIRContext()
    let builder = CHIRBuilder(context)
    let pkg = builder.CreatePackage("unreachable_serialization")
    let host = builder.CreateFunction(context.GetFuncTy(ArrayList<Type>(), context.GetUnitTy()),
        "host", srcCodeIdentifier: "host", packageName: "unreachable_serialization")
    let body = builder.CreateBlockGroup(host)
    host.InitBody(body)
    let entry = builder.CreateBlock(body)
    body.SetEntryBlock(entry)
    let tableBlock = builder.CreateBlock(body)
    let end = builder.CreateBlock(body)
    body.AddBlock(tableBlock)
    body.AddBlock(end)
    let condition = builder.CreateConstant(context.GetBoolTy(), BoolLiteral(true), entry)
    entry.AppendExpression(condition)
    let branch = builder.CreateBranch(condition.GetResult().getOrThrow(), tableBlock, end, entry)
    branch.SetSourceExpr(SourceExpr.MATCH_CASE)
    entry.AppendExpression(branch)
    let selector = builder.CreateConstant(context.GetUInt64Ty(), IntLiteral(1), tableBlock)
    tableBlock.AppendExpression(selector)
    let table = builder.CreateMultiBranch(selector.GetResult().getOrThrow(), end,
        ArrayList<UInt64>([1u64]), ArrayList<Block>([end]), tableBlock)
    table.SetSourceExpr(SourceExpr.MATCH_CASE)
    tableBlock.Set<MatchCaseId, Option<Int64>>(Some(7))
    tableBlock.AppendExpression(table)
    end.AppendExpression(builder.CreateExit(None, end))
    CHIRSerializer.Serialize(pkg, "unreachable-serialization.chir", ToCHIRPhase.RAW)

    let restoredContext = CHIRContext()
    let restoredBuilder = CHIRBuilder(restoredContext)
    let phase = CoreBox<ToCHIRPhase>(ToCHIRPhase.RAW)
    let loaded = CHIRDeserializer.Deserialize("unreachable-serialization.chir", restoredBuilder, phase)
    println("SERIALIZATION_LOADED=${loaded}")
    var branchOK = false
    var tableOK = false
    var caseOK = false
    if (let Some(restored) <- restoredContext.GetCurPackage()) {
        for (fn in restored.GetGlobalFuncsWithBody()) {
            for (block in fn.GetBody().getOrThrow().GetBlocks()) {
                if (block.Get<MatchCaseId, Option<Int64>>() == Some(7)) { caseOK = true }
                for (expr in block.GetExpressions()) {
                    if (let Some(value) <- (expr as Branch)) {
                        branchOK = value.GetSourceExpr() == SourceExpr.MATCH_CASE
                    }
                    if (let Some(value) <- (expr as MultiBranch)) {
                        tableOK = value.GetSourceExpr() == SourceExpr.MATCH_CASE
                    }
                }
            }
        }
    }
    println("SERIALIZATION_BRANCH=${branchOK}")
    println("SERIALIZATION_MULTIBRANCH=${tableOK}")
    println("SERIALIZATION_CASE_ID=${caseOK}")
    return if (loaded && branchOK && tableOK && caseOK) { 0 } else { 1 }
}
