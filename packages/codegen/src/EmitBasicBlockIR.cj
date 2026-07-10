package cjcj::codegen

import std.collection.*
import cjcj::chir.Block

private class BasicBlockGeneratorImpl <: IRGeneratorImpl {
    private let cgMod: CGModule
    private let entryBlock: Block
    private let functionToEmitIR: LLVMValueRef

    public init(cgMod: CGModule, entryBlock: Block) {
        this.cgMod = cgMod
        this.entryBlock = entryBlock
        let topLevelFunc = if (let Some(functionValue) <- entryBlock.GetTopLevelFunc()) {
            functionValue
        } else {
            throw IllegalStateException("entry CHIR block has no top-level function: " +
                entryBlock.GetIdentifierWithoutPrefix())
        }
        functionToEmitIR = cgMod.GetOrInsertCGFunction(topLevelFunc).GetRawFunction()
    }

    public func EmitIR(): Unit {
        let builder = IRBuilder2(cgMod)
        CreateBasicBlocks(builder)
        CreateBasicBlocksIRs(builder)
    }

    private func CreateBasicBlocks(builder: IRBuilder2): Unit {
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
            cgMod.CreateOrGetMappedBB(builder, functionToEmitIR, currentBlock)
            CreateLandingPad(currentBlock)
            PushUnvisitedSuccessors(blockStack, visited, currentBlock)
        }
    }

    private func CreateBasicBlocksIRs(builder: IRBuilder2): Unit {
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

    private func PushUnvisitedSuccessors(blockStack: ArrayList<Block>, visited: HashSet<Int64>,
        currentBlock: Block): Unit {
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

    private func CreateLandingPad(block: Block): Unit {
        if (!block.IsLandingPadBlock()) {
            return
        }
        let irBuilder = IRBuilder2(cgMod)
        try (scope = CodeGenBlockScope(irBuilder, block)) {
            let landingPad = irBuilder.CreateLandingPad(irBuilder.GetLandingPadType(), 0u32)
            let exceptions = block.GetExceptions()
            if (exceptions.isEmpty()) {
                irBuilder.AddLandingPadCatchAllClause(landingPad)
                return
            }
            let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
            for (exceptClass in exceptions) {
                let typeInfo = irBuilder.CreateTypeInfo(exceptClass)
                irBuilder.AddLandingPadClause(landingPad, unsafe { LLVMConstBitCast(typeInfo, i8PtrType) })
            }
        }
    }
}

public func EmitBasicBlockIR(cgMod: CGModule, entryBlock: Block): Unit {
    IRGenerator(BasicBlockGeneratorImpl(cgMod, entryBlock)).EmitIR()
}

public func EmitBasicBlockIR(cgMod: CGModule, builder: IRBuilder2, block: Block): Unit {
    try (scope = CodeGenBlockScope(builder, block)) {
        EmitExpressionIR(cgMod, builder, block.GetExpressions())
    }
}
