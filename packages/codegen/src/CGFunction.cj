package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Value

public class CGFunction <: CGValue {
    private let cgMod: CGModule
    private let chirFunc: Value
    private let cgFunctionType: Option<CGFunctionType>
    private var wrapperF: LLVMValueRef = LLVMNullValue()
    public let genericParamsMap: HashMap<String, (IRBuilder2) -> LLVMValueRef> = HashMap<String, (IRBuilder2) -> LLVMValueRef>()

    public init(function: LLVMValueRef, cgType: CGType, chirFunc: Value, cgMod: CGModule) {
        super(function, cgType)
        this.cgMod = cgMod
        this.chirFunc = chirFunc
        cgFunctionType = cgType as CGFunctionType
    }

    public func GetOriginal(): Value { return chirFunc }
    public func GetRawFunction(): LLVMValueRef { return GetRawValue() }
    public func GetCGFunctionType(): Option<CGFunctionType> { return cgFunctionType }
    public func IsSRet(): Bool {
        if (let Some(functionType) <- cgFunctionType) {
            return functionType.HasSRet()
        }
        return false
    }

    public func GetWrapperFunction(): LLVMValueRef { return wrapperF }
    public func SetWrapperFunction(wrapper: LLVMValueRef): Unit { wrapperF = wrapper }

    public func GetArgByIndexFromCHIR(index: Int64): LLVMValueRef {
        let offset = if (IsSRet()) { 1 } else { 0 }
        return unsafe { LLVMGetParam(GetRawFunction(), UInt32(index + offset)) }
    }

    public func Opt(): Unit {
        CGFunction.RemoveUnreachableBlocks(GetRawFunction())
    }

    public func DumpIR(): Unit {
        println("CGFunction " + chirFunc.GetIdentifierWithoutPrefix())
    }

    public static func RemoveUnreachableBlocks(function: LLVMValueRef): Unit {
        if (function.isNull() || unsafe { LLVMIsDeclaration(function) } != 0) {
            return
        }
        let blocks = ArrayList<LLVMBasicBlockRef>()
        var block = unsafe { LLVMGetFirstBasicBlock(function) }
        while (!block.isNull()) {
            blocks.add(block)
            block = unsafe { LLVMGetNextBasicBlock(block) }
        }
        if (blocks.isEmpty()) {
            return
        }

        let reachable = ArrayList<Bool>()
        var initIdx: Int64 = 0
        while (initIdx < blocks.size) {
            reachable.add(false)
            initIdx++
        }

        let worklist = ArrayList<Int64>()
        reachable[0] = true
        worklist.add(0)
        var worklistIdx: Int64 = 0
        while (worklistIdx < worklist.size) {
            let currentIdx = worklist[worklistIdx]
            worklistIdx++
            let terminator = unsafe { LLVMGetBasicBlockTerminator(blocks[currentIdx]) }
            if (terminator.isNull()) {
                continue
            }
            let successorCount = unsafe { LLVMGetNumSuccessors(terminator) }
            var successorIdx: UInt32 = 0u32
            while (successorIdx < successorCount) {
                let successor = unsafe { LLVMGetSuccessor(terminator, successorIdx) }
                let blockIdx = CGFunction.FindBlockIndex(blocks, successor)
                if (blockIdx >= 0 && !reachable[blockIdx]) {
                    reachable[blockIdx] = true
                    worklist.add(blockIdx)
                }
                successorIdx++
            }
        }

        var eraseIdx = blocks.size - 1
        while (eraseIdx >= 0) {
            if (!reachable[eraseIdx]) {
                unsafe { LLVMDeleteBasicBlock(blocks[eraseIdx]) }
            }
            eraseIdx--
        }
    }

    private static func FindBlockIndex(blocks: ArrayList<LLVMBasicBlockRef>, target: LLVMBasicBlockRef): Int64 {
        if (target.isNull()) {
            return -1
        }
        let targetName = unsafe { LLVMGetBasicBlockName(target) }
        if (targetName.isNull()) {
            return -1
        }
        var idx: Int64 = 0
        while (idx < blocks.size) {
            let blockName = unsafe { LLVMGetBasicBlockName(blocks[idx]) }
            if (!blockName.isNull() && unsafe { strcmp(blockName, targetName) } == 0) {
                return idx
            }
            idx++
        }
        return -1
    }

    public static func EraseUselessLoadAndAlloca(function: LLVMValueRef): Unit {
        if (function.isNull() || unsafe { LLVMIsDeclaration(function) } != 0) {
            return
        }
        let unusedLoads = ArrayList<LLVMValueRef>()
        var block = unsafe { LLVMGetFirstBasicBlock(function) }
        while (!block.isNull()) {
            CGFunction.CollectUnusedInstructions(block, 27, unusedLoads)
            block = unsafe { LLVMGetNextBasicBlock(block) }
        }
        CGFunction.EraseInstructions(unusedLoads)

        let unusedAllocas = ArrayList<LLVMValueRef>()
        let entryBlock = unsafe { LLVMGetEntryBasicBlock(function) }
        if (!entryBlock.isNull()) {
            CGFunction.CollectUnusedInstructions(entryBlock, 26, unusedAllocas)
        }
        CGFunction.EraseInstructions(unusedAllocas)
    }

    private static func CollectUnusedInstructions(block: LLVMBasicBlockRef, opcode: Int32,
        output: ArrayList<LLVMValueRef>): Unit {
        var inst = unsafe { LLVMGetFirstInstruction(block) }
        while (!inst.isNull()) {
            if (unsafe { LLVMGetInstructionOpcode(inst) } == opcode && CGFunction.HasNoUse(inst)) {
                output.add(inst)
            }
            inst = unsafe { LLVMGetNextInstruction(inst) }
        }
    }

    private static func EraseInstructions(instructions: ArrayList<LLVMValueRef>): Unit {
        var idx: Int64 = 0
        while (idx < instructions.size) {
            unsafe { LLVMInstructionEraseFromParent(instructions[idx]) }
            idx++
        }
    }

    public static func HasNoUse(value: LLVMValueRef): Bool {
        return unsafe { LLVMGetFirstUse(value) }.isNull()
    }
}
