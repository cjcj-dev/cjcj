package cangjie_compiler::codegen

foreign {
    func LLVMCreateMemoryBufferWithContentsOfFile(path: CString, outMemBuf: CPointer<LLVMMemoryBufferRef>,
        outMessage: CPointer<CString>): Int32
    func LLVMDisposeMemoryBuffer(memBuf: LLVMMemoryBufferRef): Unit
    func LLVMParseBitcode2(memBuf: LLVMMemoryBufferRef, outModule: CPointer<LLVMModuleRef>): Int32
    func LLVMParseBitcodeInContext2(context: LLVMContextRef, memBuf: LLVMMemoryBufferRef,
        outModule: CPointer<LLVMModuleRef>): Int32
    func LLVMGetBitcodeModule2(memBuf: LLVMMemoryBufferRef, outModule: CPointer<LLVMModuleRef>): Int32
    func LLVMGetBitcodeModuleInContext2(context: LLVMContextRef, memBuf: LLVMMemoryBufferRef,
        outModule: CPointer<LLVMModuleRef>): Int32
    func LLVMParseIRInContext(context: LLVMContextRef, memBuf: LLVMMemoryBufferRef,
        outModule: CPointer<LLVMModuleRef>, outMessage: CPointer<CString>): Int32
    func LLVMWriteBitcodeToFD(module: LLVMModuleRef, fd: Int32, shouldClose: Int32, unbuffered: Int32): Int32
    func LLVMWriteBitcodeToFileHandle(module: LLVMModuleRef, handle: Int32): Int32
    func LLVMWriteBitcodeToMemoryBuffer(module: LLVMModuleRef): LLVMMemoryBufferRef
}

public class LLVMMemoryBufferHandle <: Resource {
    public let raw: LLVMMemoryBufferRef
    private var closed: Bool = false

    public init(raw: LLVMMemoryBufferRef) {
        this.raw = raw
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        if (!raw.isNull()) {
            unsafe { LLVMDisposeMemoryBuffer(raw) }
        }
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}

public class LLVMModuleParseResult {
    public let ok: Bool
    public let module: LLVMModuleHandle
    public let message: String

    public init(module: LLVMModuleHandle) {
        ok = true
        this.module = module
        message = ""
    }

    public init(message: String) {
        ok = false
        module = LLVMModuleHandle(LLVMNullModule(), "")
        this.message = message
    }
}

public func LLVMCreateMemoryBufferFromFile(path: String): Option<LLVMMemoryBufferHandle> {
    var result: Option<LLVMMemoryBufferHandle> = None
    try (pathCString = unsafe { LibC.mallocCString(path) }.asResource(),
        outMemBuf = LibC.malloc<LLVMMemoryBufferRef>().asResource(),
        outMessage = LibC.malloc<CString>().asResource()) {
        unsafe { outMessage.value.write(CString(CPointer<UInt8>())) }
        let status = unsafe {
            LLVMCreateMemoryBufferWithContentsOfFile(pathCString.value, outMemBuf.value, outMessage.value)
        }
        if (status == 0) {
            result = LLVMMemoryBufferHandle(unsafe { outMemBuf.value.read() })
        } else {
            let rawMessage = unsafe { outMessage.value.read() }
            if (!rawMessage.isNull()) {
                let _ = LLVMConsumeMessage(rawMessage)
            }
        }
    }
    return result
}

public func LLVMParseBitcodeModule(context: LLVMContextHandle, buffer: LLVMMemoryBufferHandle,
    name!: String = ""): LLVMModuleParseResult {
    var result = LLVMModuleParseResult("failed to parse LLVM bitcode")
    try (outModule = LibC.malloc<LLVMModuleRef>().asResource()) {
        let status = unsafe { LLVMParseBitcodeInContext2(context.raw, buffer.raw, outModule.value) }
        if (status == 0) {
            result = LLVMModuleParseResult(LLVMModuleHandle(unsafe { outModule.value.read() }, name))
        }
    }
    return result
}
