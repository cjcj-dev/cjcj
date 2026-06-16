package cangjie_compiler::driver

import std.collection.*
import std.convert.*

private type DriverLLVMContextRef = CPointer<Unit>
private type DriverLLVMModuleRef = CPointer<Unit>
private type DriverLLVMMemoryBufferRef = CPointer<Unit>

foreign {
    func LLVMContextCreate(): DriverLLVMContextRef
    func LLVMContextDispose(context: DriverLLVMContextRef): Unit
    func LLVMCreateMemoryBufferWithContentsOfFile(
        path: CString,
        outMemBuf: CPointer<DriverLLVMMemoryBufferRef>,
        outMessage: CPointer<CString>
    ): Int32
    func LLVMDisposeMemoryBuffer(memBuf: DriverLLVMMemoryBufferRef): Unit
    func LLVMParseBitcodeInContext2(
        context: DriverLLVMContextRef,
        memBuf: DriverLLVMMemoryBufferRef,
        outModule: CPointer<DriverLLVMModuleRef>
    ): Int32
    func LLVMDisposeModule(module: DriverLLVMModuleRef): Unit
    func LLVMGetSourceFileName(module: DriverLLVMModuleRef, len: CPointer<UIntNative>): CString
    func memcpy(dest: CPointer<UInt8>, src: CString, count: UIntNative): CPointer<UInt8>
}

public enum BitcodePackageNameError {
    | OPEN_FAILED
    | PARSE_FAILED
    | INVALID_PACKAGE_NAME
}

private func BitcodePackageNameErrorIndex(err: BitcodePackageNameError): Int64 {
    return match (err) {
        case BitcodePackageNameError.OPEN_FAILED => 0
        case BitcodePackageNameError.PARSE_FAILED => 1
        case BitcodePackageNameError.INVALID_PACKAGE_NAME => 2
    }
}

extend BitcodePackageNameError <: Equatable<BitcodePackageNameError> {
    public operator func ==(right: BitcodePackageNameError): Bool {
        return BitcodePackageNameErrorIndex(this) == BitcodePackageNameErrorIndex(right)
    }

    public operator func !=(right: BitcodePackageNameError): Bool {
        return !(this == right)
    }
}

public class BitcodePackageNameResult {
    public let ok: Bool
    public let packageName: String
    public let error: BitcodePackageNameError

    public init(packageName: String) {
        ok = true
        this.packageName = packageName
        error = BitcodePackageNameError.OPEN_FAILED
    }

    public init(error: BitcodePackageNameError) {
        ok = false
        packageName = ""
        this.error = error
    }
}

public func ExtractBitcodePackageNameFromLLVM(bcPath: String): BitcodePackageNameResult {
    if (!FileUtil.FileExist(bcPath) || FileUtil.IsDir(bcPath)) {
        return BitcodePackageNameResult(BitcodePackageNameError.OPEN_FAILED)
    }
    let sourceName = ReadBitcodeSourceFileName(bcPath)
    if (let None <- sourceName) {
        return BitcodePackageNameResult(BitcodePackageNameError.PARSE_FAILED)
    }
    if (let Some(name) <- ParseBitcodePackageName(sourceName.getOrThrow())) {
        return BitcodePackageNameResult(name)
    }
    return BitcodePackageNameResult(BitcodePackageNameError.INVALID_PACKAGE_NAME)
}

private func ReadBitcodeSourceFileName(bcPath: String): Option<String> {
    var sourceName: Option<String> = None
    try (pathCString = unsafe { LibC.mallocCString(bcPath) }.asResource()) {
        try (memBufPtr = LibC.malloc<DriverLLVMMemoryBufferRef>().asResource()) {
            let opened = unsafe {
                LLVMCreateMemoryBufferWithContentsOfFile(pathCString.value, memBufPtr.value, CPointer<CString>())
            }
            if (opened != 0) {
                return None
            }
            let memBuf = unsafe { memBufPtr.value.read() }
            let context = unsafe { LLVMContextCreate() }
            try (modulePtr = LibC.malloc<DriverLLVMModuleRef>().asResource()) {
                let parsed = unsafe { LLVMParseBitcodeInContext2(context, memBuf, modulePtr.value) }
                if (parsed == 0) {
                    let module = unsafe { modulePtr.value.read() }
                    try (lenPtr = LibC.malloc<UIntNative>().asResource()) {
                        let rawName = unsafe { LLVMGetSourceFileName(module, lenPtr.value) }
                        let nameLen = unsafe { lenPtr.value.read() }
                        sourceName = CStringToString(rawName, nameLen)
                    }
                    unsafe { LLVMDisposeModule(module) }
                }
            }
            unsafe {
                LLVMContextDispose(context)
                LLVMDisposeMemoryBuffer(memBuf)
            }
        }
    } catch (e: Exception) {
        return None
    }
    return sourceName
}

private func CStringToString(raw: CString, len: UIntNative): Option<String> {
    if (raw.isNull()) {
        return None
    }
    if (len == 0) {
        return Some("")
    }
    var converted: Option<String> = None
    try (buffer = LibC.malloc<UInt8>(count: Int64(len)).asResource()) {
        if (buffer.value.isNull()) {
            return None
        }
        unsafe { memcpy(buffer.value, raw, len) }
        let bytes = ArrayList<UInt8>()
        var idx: Int64 = 0
        while (idx < Int64(len)) {
            bytes.add(unsafe { (buffer.value + idx).read() })
            idx++
        }
        converted = String.fromUtf8(bytes.toArray())
    }
    return converted
}

private func ParseBitcodePackageName(sourceName: String): Option<String> {
    let bytes = sourceName.toArray()
    var idx: Int64 = 0
    while (idx < bytes.size && bytes[idx] >= b'0' && bytes[idx] <= b'9') {
        idx++
    }
    if (idx == 0 || idx >= bytes.size || bytes[idx] != b'-') {
        return None
    }
    let ordinal = sourceName[0..idx]
    try {
        let _ = UInt64.parse(ordinal)
    } catch (e: Exception) {
        return None
    }
    let packageName = sourceName[idx + 1..]
    if (packageName.isEmpty()) {
        return None
    }
    return Some(packageName)
}
