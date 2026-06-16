package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Block

public func EmitBasicBlockIR(cgMod: CGModule, entryBlock: Block): Unit {
    let topLevelFunc = if (let Some(functionValue) <- entryBlock.GetTopLevelFunc()) {
        functionValue
    } else {
        throw IllegalStateException("entry CHIR block has no top-level function: " +
            entryBlock.GetIdentifierWithoutPrefix())
    }
    let cgFunc = cgMod.GetOrInsertCGFunction(topLevelFunc)
    let builder = IRBuilder2(cgMod)
    builder.SetInsertCGFunction(cgFunc)
    CreateBasicBlocks(cgMod, builder, cgFunc.GetRawFunction(), entryBlock)
    CreateBasicBlocksIRs(cgMod, builder, entryBlock)
}

public func EmitBasicBlockIR(cgMod: CGModule, builder: IRBuilder2, block: Block): Unit {
    try (scope = CodeGenBlockScope(builder, block)) {
        EmitExpressionIR(cgMod, builder, block.GetExpressions())
    }
}

private func CreateBasicBlocks(cgMod: CGModule, builder: IRBuilder2, functionValue: LLVMValueRef,
    entryBlock: Block): Unit {
    let visited = HashSet<Int64>()
    let blockStack = ArrayList<Block>()
    blockStack.add(entryBlock)
    while (!blockStack.isEmpty()) {
        let currentBlock = blockStack[blockStack.size - 1]
        blockStack.remove(at: blockStack.size - 1)
        if (visited.contains(currentBlock.nodeId)) {
            continue
        }
        visited.add(currentBlock.nodeId)
        cgMod.CreateOrGetMappedBB(builder, functionValue, currentBlock)
        PushUnvisitedSuccessors(blockStack, visited, currentBlock)
    }
}

private func CreateBasicBlocksIRs(cgMod: CGModule, builder: IRBuilder2, entryBlock: Block): Unit {
    let visited = HashSet<Int64>()
    let blockStack = ArrayList<Block>()
    blockStack.add(entryBlock)
    while (!blockStack.isEmpty()) {
        let currentBlock = blockStack[blockStack.size - 1]
        blockStack.remove(at: blockStack.size - 1)
        if (visited.contains(currentBlock.nodeId)) {
            continue
        }
        visited.add(currentBlock.nodeId)
        EmitBasicBlockIR(cgMod, builder, currentBlock)
        PushUnvisitedSuccessors(blockStack, visited, currentBlock)
    }
}

private func PushUnvisitedSuccessors(blockStack: ArrayList<Block>, visited: HashSet<Int64>, currentBlock: Block): Unit {
    let successors = currentBlock.GetSuccessors()
    var idx = successors.size - 1
    while (idx >= 0) {
        let successorBlock = successors[idx]
        if (!visited.contains(successorBlock.nodeId)) {
            blockStack.add(successorBlock)
        }
        idx--
    }
}
