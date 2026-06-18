package cangjie_compiler::codegen

foreign {
    func LLVMCreateMemoryBufferWithContentsOfFile(path: CString, outMemBuf: CPointer<LLVMMemoryBufferRef>,
        outMessage: CPointer<CString>): Int32
    func LLVMCreateMemoryBufferWithMemoryRange(inputData: CString, inputDataLength: UIntNative, bufferName: CString,
        requiresNullTerminator: Int32): LLVMMemoryBufferRef
    func LLVMCreateMemoryBufferWithMemoryRangeCopy(inputData: CString, inputDataLength: UIntNative,
        bufferName: CString): LLVMMemoryBufferRef
    func LLVMGetBufferStart(memBuf: LLVMMemoryBufferRef): CString
    func LLVMGetBufferSize(memBuf: LLVMMemoryBufferRef): UIntNative
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
    private var owned: Bool = true
    private var closed: Bool = false

    public init(raw: LLVMMemoryBufferRef, owned!: Bool = true) {
        this.raw = raw
        this.owned = owned
    }

    public static func CreateFromStringCopy(contents: String, name!: String = ""): Option<LLVMMemoryBufferHandle> {
        var result: Option<LLVMMemoryBufferHandle> = None
        try (contentsCString = unsafe { LibC.mallocCString(contents) }.asResource(),
            nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            let rawBuffer = unsafe {
                LLVMCreateMemoryBufferWithMemoryRangeCopy(contentsCString.value, UIntNative(contents.size),
                    nameCString.value)
            }
            if (!rawBuffer.isNull()) {
                result = LLVMMemoryBufferHandle(rawBuffer)
            }
        }
        return result
    }

    public static func CreateFromCStringRange(data: CString, length: UIntNative, name!: String = "",
        requiresNullTerminator!: Bool = false): Option<LLVMMemoryBufferHandle> {
        if (data.isNull()) {
            return None
        }
        var result: Option<LLVMMemoryBufferHandle> = None
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            let rawBuffer = unsafe {
                LLVMCreateMemoryBufferWithMemoryRange(data, length, nameCString.value,
                    if (requiresNullTerminator) { 1 } else { 0 })
            }
            if (!rawBuffer.isNull()) {
                result = LLVMMemoryBufferHandle(rawBuffer)
            }
        }
        return result
    }

    public func ReleaseOwnership(): Unit {
        owned = false
        closed = true
    }

    public func GetSize(): UIntNative {
        if (raw.isNull()) {
            return 0
        }
        return unsafe { LLVMGetBufferSize(raw) }
    }

    public func ToString(): String {
        if (raw.isNull()) {
            return ""
        }
        let bufferStart = unsafe { LLVMGetBufferStart(raw) }
        if (bufferStart.isNull()) {
            return ""
        }
        return LLVMCStringToString(bufferStart, unsafe { LLVMGetBufferSize(raw) }) ?? ""
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        if (owned && !raw.isNull()) {
            unsafe { LLVMDisposeMemoryBuffer(raw) }
        }
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}

public class LLVMMemoryBufferResult {
    public let ok: Bool
    public let buffer: Option<LLVMMemoryBufferHandle>
    public let message: String

    public init(buffer: LLVMMemoryBufferHandle) {
        ok = true
        this.buffer = Some(buffer)
        message = ""
    }

    public init(message: String) {
        ok = false
        buffer = None
        this.message = message
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

public class LLVMBitcodeWriteResult {
    public let ok: Bool
    public let message: String
    public let buffer: Option<LLVMMemoryBufferHandle>

    public init(ok: Bool, message: String, buffer: Option<LLVMMemoryBufferHandle>) {
        this.ok = ok
        this.message = message
        this.buffer = buffer
    }

    public static func Success(): LLVMBitcodeWriteResult {
        return LLVMBitcodeWriteResult(true, "", None)
    }

    public static func Success(buffer: LLVMMemoryBufferHandle): LLVMBitcodeWriteResult {
        return LLVMBitcodeWriteResult(true, "", Some(buffer))
    }

    public static func Failure(message: String): LLVMBitcodeWriteResult {
        return LLVMBitcodeWriteResult(false, message, None)
    }
}

private func LLVMModuleParseSuccess(rawModule: LLVMModuleRef, context: LLVMContextHandle,
    name: String): LLVMModuleParseResult {
    if (rawModule.isNull()) {
        return LLVMModuleParseResult("LLVM parser returned a null module")
    }
    return LLVMModuleParseResult(LLVMModuleHandle(rawModule, name, context: Some(context)))
}

private func LLVMConsumeOutMessage(messagePtr: CPointer<CString>): String {
    if (messagePtr.isNull()) {
        return ""
    }
    let rawMessage = unsafe { messagePtr.read() }
    if (rawMessage.isNull()) {
        return ""
    }
    return LLVMConsumeMessage(rawMessage)
}

public func LLVMCreateMemoryBufferFromFileChecked(path: String): LLVMMemoryBufferResult {
    var result = LLVMMemoryBufferResult("failed to open LLVM memory buffer: " + path)
    try (pathCString = unsafe { LibC.mallocCString(path) }.asResource(),
        outMemBuf = LibC.malloc<LLVMMemoryBufferRef>().asResource(),
        outMessage = LibC.malloc<CString>().asResource()) {
        unsafe { outMemBuf.value.write(CPointer<Unit>()) }
        unsafe { outMessage.value.write(CString(CPointer<UInt8>())) }
        let status = unsafe {
            LLVMCreateMemoryBufferWithContentsOfFile(pathCString.value, outMemBuf.value, outMessage.value)
        }
        if (status == 0) {
            let rawBuffer = unsafe { outMemBuf.value.read() }
            if (rawBuffer.isNull()) {
                result = LLVMMemoryBufferResult("LLVM returned a null memory buffer: " + path)
            } else {
                result = LLVMMemoryBufferResult(LLVMMemoryBufferHandle(rawBuffer))
            }
            let successMessage = unsafe { outMessage.value.read() }
            if (!successMessage.isNull()) {
                let _ = LLVMConsumeMessage(successMessage)
            }
        } else {
            let failureMessage = LLVMConsumeOutMessage(outMessage.value)
            if (!failureMessage.isEmpty()) {
                result = LLVMMemoryBufferResult(failureMessage)
            }
        }
    }
    return result
}

public func LLVMCreateMemoryBufferFromFile(path: String): Option<LLVMMemoryBufferHandle> {
    return LLVMCreateMemoryBufferFromFileChecked(path).buffer
}

public func LLVMParseBitcodeModule(context: LLVMContextHandle, buffer: LLVMMemoryBufferHandle,
    name!: String = ""): LLVMModuleParseResult {
    var result = LLVMModuleParseResult("failed to parse LLVM bitcode")
    try (outModule = LibC.malloc<LLVMModuleRef>().asResource()) {
        unsafe { outModule.value.write(LLVMNullModule()) }
        let status = unsafe { LLVMParseBitcodeInContext2(context.raw, buffer.raw, outModule.value) }
        if (status == 0) {
            result = LLVMModuleParseSuccess(unsafe { outModule.value.read() }, context, name)
        }
    }
    return result
}

public func LLVMParseBitcodeModule(buffer: LLVMMemoryBufferHandle, name!: String = ""): LLVMModuleParseResult {
    var result = LLVMModuleParseResult("failed to parse LLVM bitcode")
    try (outModule = LibC.malloc<LLVMModuleRef>().asResource()) {
        unsafe { outModule.value.write(LLVMNullModule()) }
        let status = unsafe { LLVMParseBitcode2(buffer.raw, outModule.value) }
        if (status == 0) {
            let rawModule = unsafe { outModule.value.read() }
            if (rawModule.isNull()) {
                result = LLVMModuleParseResult("LLVM bitcode parser returned a null module")
            } else {
                result = LLVMModuleParseResult(LLVMModuleHandle(rawModule, name))
            }
        }
    }
    return result
}

public func LLVMGetBitcodeModule(context: LLVMContextHandle, buffer: LLVMMemoryBufferHandle,
    name!: String = ""): LLVMModuleParseResult {
    var result = LLVMModuleParseResult("failed to read LLVM bitcode module")
    try (outModule = LibC.malloc<LLVMModuleRef>().asResource()) {
        unsafe { outModule.value.write(LLVMNullModule()) }
        let status = unsafe { LLVMGetBitcodeModuleInContext2(context.raw, buffer.raw, outModule.value) }
        if (status == 0) {
            let rawModule = unsafe { outModule.value.read() }
            result = LLVMModuleParseSuccess(rawModule, context, name)
            if (!rawModule.isNull()) {
                buffer.ReleaseOwnership()
            }
        }
    }
    return result
}

public func LLVMGetBitcodeModule(buffer: LLVMMemoryBufferHandle, name!: String = ""): LLVMModuleParseResult {
    var result = LLVMModuleParseResult("failed to read LLVM bitcode module")
    try (outModule = LibC.malloc<LLVMModuleRef>().asResource()) {
        unsafe { outModule.value.write(LLVMNullModule()) }
        let status = unsafe { LLVMGetBitcodeModule2(buffer.raw, outModule.value) }
        if (status == 0) {
            let rawModule = unsafe { outModule.value.read() }
            if (rawModule.isNull()) {
                result = LLVMModuleParseResult("LLVM bitcode reader returned a null module")
            } else {
                result = LLVMModuleParseResult(LLVMModuleHandle(rawModule, name))
                buffer.ReleaseOwnership()
            }
        }
    }
    return result
}

public func LLVMParseIRModule(context: LLVMContextHandle, buffer: LLVMMemoryBufferHandle,
    name!: String = ""): LLVMModuleParseResult {
    var result = LLVMModuleParseResult("failed to parse LLVM IR")
    try (outModule = LibC.malloc<LLVMModuleRef>().asResource(),
        outMessage = LibC.malloc<CString>().asResource()) {
        unsafe { outModule.value.write(LLVMNullModule()) }
        unsafe { outMessage.value.write(CString(CPointer<UInt8>())) }
        let status = unsafe { LLVMParseIRInContext(context.raw, buffer.raw, outModule.value, outMessage.value) }
        buffer.ReleaseOwnership()
        if (status == 0) {
            result = LLVMModuleParseSuccess(unsafe { outModule.value.read() }, context, name)
            let successMessage = unsafe { outMessage.value.read() }
            if (!successMessage.isNull()) {
                let _ = LLVMConsumeMessage(successMessage)
            }
        } else {
            let failureMessage = LLVMConsumeOutMessage(outMessage.value)
            if (!failureMessage.isEmpty()) {
                result = LLVMModuleParseResult(failureMessage)
            }
        }
    }
    return result
}

public func LLVMParseIRFile(context: LLVMContextHandle, path: String, name!: String = ""): LLVMModuleParseResult {
    let bufferResult = LLVMCreateMemoryBufferFromFileChecked(path)
    if (!bufferResult.ok) {
        return LLVMModuleParseResult(bufferResult.message)
    }
    if (let Some(bufferHandle) <- bufferResult.buffer) {
        let moduleName = if (name.isEmpty()) { path } else { name }
        let parseResult = LLVMParseIRModule(context, bufferHandle, name: moduleName)
        bufferHandle.close()
        return parseResult
    }
    return LLVMModuleParseResult("failed to open LLVM memory buffer: " + path)
}

public func LLVMParseBitcodeFile(context: LLVMContextHandle, path: String,
    name!: String = ""): LLVMModuleParseResult {
    let bufferResult = LLVMCreateMemoryBufferFromFileChecked(path)
    if (!bufferResult.ok) {
        return LLVMModuleParseResult(bufferResult.message)
    }
    if (let Some(bufferHandle) <- bufferResult.buffer) {
        let moduleName = if (name.isEmpty()) { path } else { name }
        let parseResult = LLVMParseBitcodeModule(context, bufferHandle, name: moduleName)
        bufferHandle.close()
        return parseResult
    }
    return LLVMModuleParseResult("failed to open LLVM memory buffer: " + path)
}

public func LLVMGetBitcodeFile(context: LLVMContextHandle, path: String, name!: String = ""): LLVMModuleParseResult {
    let bufferResult = LLVMCreateMemoryBufferFromFileChecked(path)
    if (!bufferResult.ok) {
        return LLVMModuleParseResult(bufferResult.message)
    }
    if (let Some(bufferHandle) <- bufferResult.buffer) {
        let moduleName = if (name.isEmpty()) { path } else { name }
        let parseResult = LLVMGetBitcodeModule(context, bufferHandle, name: moduleName)
        bufferHandle.close()
        return parseResult
    }
    return LLVMModuleParseResult("failed to open LLVM memory buffer: " + path)
}

public func LLVMWriteBitcodeToFileChecked(module: LLVMModuleHandle, path: String): LLVMBitcodeWriteResult {
    if (module.raw.isNull()) {
        return LLVMBitcodeWriteResult.Failure("cannot write null LLVM module to bitcode file")
    }
    var result = LLVMBitcodeWriteResult.Failure("failed to write LLVM bitcode to file: " + path)
    try (pathCString = unsafe { LibC.mallocCString(path) }.asResource()) {
        let status = unsafe { LLVMWriteBitcodeToFile(module.raw, pathCString.value) }
        if (status == 0) {
            result = LLVMBitcodeWriteResult.Success()
        }
    }
    return result
}

public func LLVMWriteBitcodeToFDChecked(module: LLVMModuleHandle, fd: Int32, shouldClose!: Bool = false,
    unbuffered!: Bool = false): LLVMBitcodeWriteResult {
    if (module.raw.isNull()) {
        return LLVMBitcodeWriteResult.Failure("cannot write null LLVM module to file descriptor")
    }
    let status = unsafe {
        LLVMWriteBitcodeToFD(module.raw, fd, if (shouldClose) { 1 } else { 0 }, if (unbuffered) { 1 } else { 0 })
    }
    if (status == 0) {
        return LLVMBitcodeWriteResult.Success()
    }
    return LLVMBitcodeWriteResult.Failure("failed to write LLVM bitcode to file descriptor")
}

public func LLVMWriteBitcodeToMemoryBufferChecked(module: LLVMModuleHandle): LLVMBitcodeWriteResult {
    if (module.raw.isNull()) {
        return LLVMBitcodeWriteResult.Failure("cannot write null LLVM module to memory buffer")
    }
    let rawBuffer = unsafe { LLVMWriteBitcodeToMemoryBuffer(module.raw) }
    if (rawBuffer.isNull()) {
        return LLVMBitcodeWriteResult.Failure("LLVM returned a null bitcode memory buffer")
    }
    return LLVMBitcodeWriteResult.Success(LLVMMemoryBufferHandle(rawBuffer))
}
