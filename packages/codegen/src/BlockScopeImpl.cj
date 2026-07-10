package cjcj::codegen

import cjcj::chir.Block

public class CodeGenBlockScope <: Resource {
    private let irBuilder: IRBuilder2
    private let oldBlock: LLVMBasicBlockRef
    private var closed: Bool = false

    public init(irBuilder: IRBuilder2, llvmBlock: LLVMBasicBlockRef) {
        this.irBuilder = irBuilder
        oldBlock = irBuilder.GetInsertBlock()
        irBuilder.SetInsertPoint(llvmBlock)
    }

    public init(irBuilder: IRBuilder2, chirBlock: Block) {
        this.irBuilder = irBuilder
        oldBlock = irBuilder.GetInsertBlock()
        if (let Some(mappedBlock) <- irBuilder.GetCGModule().GetMappedBB(chirBlock)) {
            irBuilder.SetInsertPoint(mappedBlock)
        } else {
            throw IllegalStateException("CHIR basic block is not mapped: " + chirBlock.GetIdentifierWithoutPrefix())
        }
        if (let Some(topLevelFunc) <- chirBlock.GetTopLevelFunc()) {
            irBuilder.SetInsertCGFunction(irBuilder.GetCGModule().GetOrInsertCGFunction(topLevelFunc))
        } else {
            throw IllegalStateException("CHIR basic block has no top-level function: " +
                chirBlock.GetIdentifierWithoutPrefix())
        }
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        irBuilder.SetInsertPoint(oldBlock)
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}

public class CodeGenFunctionScope <: Resource {
    private let blockScope: CodeGenBlockScope
    private var closed: Bool = false

    public init(irBuilder: IRBuilder2, function: LLVMValueRef) {
        let entryBlock = unsafe { LLVMGetEntryBasicBlock(function) }
        if (entryBlock.isNull()) {
            throw IllegalStateException("LLVM function has no entry block for CodeGenFunctionScope")
        }
        blockScope = CodeGenBlockScope(irBuilder, entryBlock)
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        blockScope.close()
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}

public class CodeGenUnwindBlockScope <: Resource {
    private let cgMod: CGModule
    private var closed: Bool = false

    public init(cgMod: CGModule, unwindBlock: LLVMBasicBlockRef) {
        this.cgMod = cgMod
        cgMod.GetCGContext().PushUnwindBlockStack(unwindBlock)
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        cgMod.GetCGContext().PopUnwindBlockStack()
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}
