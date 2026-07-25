package cjcj::driver

import std.collection.*
import std.process.*
import cjcj::utils.Semaphore

public type ToolBatch = ArrayList<Tool>

@When[os == "Windows"]
private let FORMAT_MESSAGE_ALLOCATE_BUFFER: UInt32 = 0x00000100u32
@When[os == "Windows"]
private let FORMAT_MESSAGE_IGNORE_INSERTS: UInt32 = 0x00000200u32
@When[os == "Windows"]
private let FORMAT_MESSAGE_FROM_SYSTEM: UInt32 = 0x00001000u32
@When[os == "Windows"]
private let LANG_ENGLISH_SUBLANG_DEFAULT: UInt32 = 0x00000409u32
@When[os == "Windows"]
private let CP_UTF8: UInt32 = 65001u32

@When[os == "Windows"]
@C
struct STARTUPINFOA {
    var cb: UInt32
    var lpReserved: CString
    var lpDesktop: CString
    var lpTitle: CString
    var dwX: UInt32
    var dwY: UInt32
    var dwXSize: UInt32
    var dwYSize: UInt32
    var dwXCountChars: UInt32
    var dwYCountChars: UInt32
    var dwFillAttribute: UInt32
    var dwFlags: UInt32
    var wShowWindow: UInt16
    var cbReserved2: UInt16
    var lpReserved2: CPointer<UInt8>
    var hStdInput: CPointer<Unit>
    var hStdOutput: CPointer<Unit>
    var hStdError: CPointer<Unit>

    init() {
        cb = UInt32(sizeOf<STARTUPINFOA>())
        lpReserved = CString(CPointer<UInt8>())
        lpDesktop = CString(CPointer<UInt8>())
        lpTitle = CString(CPointer<UInt8>())
        dwX = 0u32
        dwY = 0u32
        dwXSize = 0u32
        dwYSize = 0u32
        dwXCountChars = 0u32
        dwYCountChars = 0u32
        dwFillAttribute = 0u32
        dwFlags = 0u32
        wShowWindow = 0u16
        cbReserved2 = 0u16
        lpReserved2 = CPointer<UInt8>()
        hStdInput = CPointer<Unit>()
        hStdOutput = CPointer<Unit>()
        hStdError = CPointer<Unit>()
    }
}

@When[os == "Windows"]
@C
struct PROCESS_INFORMATION {
    var hProcess: CPointer<Unit>
    var hThread: CPointer<Unit>
    var dwProcessId: UInt32
    var dwThreadId: UInt32

    init() {
        hProcess = CPointer<Unit>()
        hThread = CPointer<Unit>()
        dwProcessId = 0u32
        dwThreadId = 0u32
    }
}

@When[os == "Windows"]
foreign {
    func CreateProcessA(applicationName: CString, commandLine: CString, processAttributes: CPointer<Unit>,
        threadAttributes: CPointer<Unit>, inheritHandles: Int32, creationFlags: UInt32, environment: CPointer<Unit>,
        currentDirectory: CString, startupInfo: CPointer<STARTUPINFOA>,
        processInformation: CPointer<PROCESS_INFORMATION>): Int32
    func GetLastError(): UInt32
    func FormatMessageW(flags: UInt32, source: CPointer<Unit>, messageId: UInt32, languageId: UInt32,
        buffer: CPointer<CPointer<UInt16>>, size: UInt32, arguments: CPointer<Unit>): UInt32
    func LocalFree(memory: CPointer<Unit>): CPointer<Unit>
    func WideCharToMultiByte(codePage: UInt32, flags: UInt32, wideChars: CPointer<UInt16>,
        wideCharCount: Int32, multiByteChars: CPointer<UInt8>, multiByteCount: Int32,
        defaultChar: CString, usedDefaultChar: CPointer<Int32>): Int32
}

public func MakeSingleToolBatch(tool: Tool): ToolBatch {
    let result = ArrayList<Tool>()
    result.add(tool)
    return result
}

@When[os == "macOS"]
private let DYNAMIC_LIBRARY_PATH_ENV: String = "DYLD_LIBRARY_PATH"

@When[os != "macOS" && os != "Windows"]
private let DYNAMIC_LIBRARY_PATH_ENV: String = "LD_LIBRARY_PATH"

@When[os == "macOS"]
private let DYNAMIC_PRELOAD_ENV: String = "DYLD_INSERT_LIBRARIES"

@When[os != "macOS" && os != "Windows"]
private let DYNAMIC_PRELOAD_ENV: String = "LD_PRELOAD"

@When[os != "Windows"]
foreign {
    func posix_spawn(
        pid: CPointer<Int32>,
        path: CString,
        fileActions: CPointer<Unit>,
        attrp: CPointer<Unit>,
        argv: CPointer<CString>,
        envp: CPointer<CString>
    ): Int32
    func posix_spawnp(
        pid: CPointer<Int32>,
        file: CString,
        fileActions: CPointer<Unit>,
        attrp: CPointer<Unit>,
        argv: CPointer<CString>,
        envp: CPointer<CString>
    ): Int32
    func strerror(errnum: Int32): CString
    func free(ptr: CString): Unit
}

@When[os != "Windows"]
private func FreeCStringList(values: ArrayList<CString>): Unit {
    for (value in values) {
        if (!value.isNull()) {
            unsafe { free(value) }
        }
    }
}

@When[os != "Windows"]
private func WriteNativeStringArray(
    values: Array<String>,
    target: CPointer<CString>,
    allocatedStrings: ArrayList<CString>
): Bool {
    var idx: Int64 = 0
    while (idx < values.size) {
        let nativeString = unsafe { LibC.mallocCString(values[idx]) }
        if (nativeString.isNull()) {
            return false
        }
        allocatedStrings.add(nativeString)
        unsafe { (target + idx).write(nativeString) }
        idx++
    }
    unsafe { (target + values.size).write(CString(CPointer<UInt8>())) }
    return true
}

@When[os != "Windows"]
private func GetSystemErrorMessage(error: Int32): String {
    let message = unsafe { strerror(error) }
    if (message.isNull()) {
        return "Unknown system error code: ${error}"
    }
    let text = message.toString()
    return if (text.isEmpty()) { "Unknown system error code: ${error}" } else { text }
}

// Mirrors Driver/Tool.cpp:39-70.
@When[os == "Windows"]
private func GetSystemErrorMessage(error: UInt32): String {
    if (error == 0u32) {
        return ""
    }
    try (messagePtr = LibC.malloc<CPointer<UInt16>>().asResource()) {
        if (messagePtr.value.isNull()) {
            return "Unknown system error code: " + error.toString()
        }
        unsafe { messagePtr.value.write(CPointer<UInt16>()) }
        let size = unsafe {
            FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                FORMAT_MESSAGE_IGNORE_INSERTS, CPointer<Unit>(), error, LANG_ENGLISH_SUBLANG_DEFAULT,
                messagePtr.value, 0u32, CPointer<Unit>())
        }
        let wideMessage = unsafe { messagePtr.value.read() }
        if (size == 0u32 || wideMessage.isNull()) {
            return "Unknown system error code: " + error.toString()
        }
        let utf8Size = unsafe {
            WideCharToMultiByte(CP_UTF8, 0u32, wideMessage, Int32(size), CPointer<UInt8>(), 0,
                CString(CPointer<UInt8>()), CPointer<Int32>())
        }
        if (utf8Size <= 0) {
            let _ = unsafe { LocalFree(CPointer<Unit>(wideMessage)) }
            return "Unknown system error code: " + error.toString()
        }
        var result = try (utf8Buffer = LibC.malloc<UInt8>(count: Int64(utf8Size) + 1).asResource()) {
            if (utf8Buffer.value.isNull()) {
                let _ = unsafe { LocalFree(CPointer<Unit>(wideMessage)) }
                return "Unknown system error code: " + error.toString()
            }
            let converted = unsafe {
                WideCharToMultiByte(CP_UTF8, 0u32, wideMessage, Int32(size), utf8Buffer.value, utf8Size,
                    CString(CPointer<UInt8>()), CPointer<Int32>())
            }
            let _ = unsafe { LocalFree(CPointer<Unit>(wideMessage)) }
            if (converted <= 0) {
                return "Unknown system error code: " + error.toString()
            }
            unsafe { (utf8Buffer.value + Int64(converted)).write(0u8) }
            CString(utf8Buffer.value).toString()
        }
        while (result.endsWith("\r") || result.endsWith("\n")) {
            result = result[0..result.size - 1]
        }
        return result
    }
}

public class Tool {
    public let toolType: ToolType
    public let name: String
    public let environmentVars: HashMap<String, String>
    private let args: ArrayList<String> = ArrayList<String>()
    private var ldLibraryPath: String = ""

    public init(name: String, toolType: ToolType, environmentVars: HashMap<String, String>) {
        this.name = name
        this.toolType = toolType
        this.environmentVars = environmentVars
    }

    public func GetArgs(): Array<String> {
        return args.toArray()
    }

    public func GetFullArgs(): Array<String> {
        let full = ArrayList<String>()
        full.add(name)
        for (arg in args) {
            full.add(arg)
        }
        return full.toArray()
    }

    public func AppendArg(arg: String): Unit {
        args.add(arg)
    }

    public func AppendArg(first: String, second: String): Unit {
        AppendArg(first)
        AppendArg(second)
    }

    public func AppendArgs(values: Array<String>): Unit {
        for (value in values) {
            AppendArg(value)
        }
    }

    public func AppendArgIf(condition: Bool, arg: String): Unit {
        if (condition) {
            AppendArg(arg)
        }
    }

    public func AppendMultiArgs(argStr: String): Unit {
        for (item in SplitString(argStr, " ")) {
            if (!item.isEmpty()) {
                args.add(item)
            }
        }
    }

    public func AppendMultiArgs(values: Array<String>): Unit {
        for (value in values) {
            AppendMultiArgs(value)
        }
    }

    public func SetLdLibraryPath(newLdLibraryPath: String): Unit {
        ldLibraryPath = newLdLibraryPath
    }

    public func GetLdLibraryPath(): String {
        return ldLibraryPath
    }

    @When[os == "Windows"]
    public func Run(): ToolFuture {
        if (toolType == ToolType.INTERNAL_IMPLEMENTED) {
            Semaphore.Get().Acquire()
            return ThreadFuture(spawn { InternalImplementedCommandExec() })
        }
        try {
            let code = execute(name, args.toArray())
            return ProcessFuture(code)
        } catch (e: Exception) {
            return ErrorFuture(e.message)
        }
    }

    @When[os != "Windows"]
    public func Run(): ToolFuture {
        if (toolType == ToolType.INTERNAL_IMPLEMENTED) {
            Semaphore.Get().Acquire()
            return ThreadFuture(spawn { InternalImplementedCommandExec() })
        }
        let argvValues = GetFullArgs()
        let environmentValues = BuildEnvironmentVector()
        let allocatedStrings = ArrayList<CString>()
        try (pidPtr = LibC.malloc<Int32>().asResource(),
            argvPtr = LibC.malloc<CString>(count: argvValues.size + 1).asResource(),
            envpPtr = LibC.malloc<CString>(count: environmentValues.size + 1).asResource(),
            nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            if (pidPtr.value.isNull() || argvPtr.value.isNull() || envpPtr.value.isNull() || nameCString.value.isNull()) {
                FreeCStringList(allocatedStrings)
                return ErrorFuture("failed to allocate process launch buffers")
            }
            if (!WriteNativeStringArray(argvValues, argvPtr.value, allocatedStrings)) {
                FreeCStringList(allocatedStrings)
                return ErrorFuture("failed to allocate process arguments")
            }
            if (!WriteNativeStringArray(environmentValues, envpPtr.value, allocatedStrings)) {
                FreeCStringList(allocatedStrings)
                return ErrorFuture("failed to allocate process environment")
            }
            Semaphore.Get().Acquire()
            let spawnStatus = unsafe {
                if (name.contains("/")) {
                    posix_spawn(pidPtr.value, nameCString.value, CPointer<Unit>(), CPointer<Unit>(),
                        argvPtr.value, envpPtr.value)
                } else {
                    posix_spawnp(pidPtr.value, nameCString.value, CPointer<Unit>(), CPointer<Unit>(),
                        argvPtr.value, envpPtr.value)
                }
            }
            FreeCStringList(allocatedStrings)
            if (spawnStatus != 0) {
                Semaphore.Get().Release()
                return ErrorFuture(GetSystemErrorMessage(spawnStatus))
            }
            return LinuxProcessFuture(unsafe { pidPtr.value.read() })
        }
    }

    public func Execute(verbose: Bool): ToolFuture {
        if (verbose) {
            println(FileUtil.Normalize(GetCommandString()))
        }
        if (TempFileManager.Instance().IsDeleted()) {
            return ErrorFuture("temporary files were deleted before command execution")
        }
        return Run()
    }

    public func GetName(): String {
        return name
    }

    public func GetCommandString(): String {
        return GenerateCommand()
    }

    @When[os == "Windows"]
    private func GenerateCommand(): String {
        let argBuilder = StringBuilder()
        for (arg in args) {
            argBuilder.append(FileUtil.GetQuoted(arg))
            argBuilder.append(" ")
        }
        let builder = StringBuilder()
        builder.append(FileUtil.GetQuoted(name))
        builder.append(" ")
        builder.append(argBuilder.toString())
        return "\"" + builder.toString() + "\""
    }

    @When[os != "Windows"]
    private func GenerateCommand(): String {
        let argBuilder = StringBuilder()
        for (arg in args) {
            argBuilder.append(GetSingleQuoted(arg))
            argBuilder.append(" ")
        }
        let builder = StringBuilder()
        if (!ldLibraryPath.isEmpty()) {
            builder.append(DYNAMIC_LIBRARY_PATH_ENV)
            builder.append("=")
            builder.append(GetSingleQuoted(ldLibraryPath))
            builder.append(":$")
            builder.append(DYNAMIC_LIBRARY_PATH_ENV)
            builder.append(" ")
        }
        builder.append(GetSingleQuoted(name))
        builder.append(" ")
        builder.append(argBuilder.toString())
        return builder.toString()
    }

    private func InternalImplementedCommandExec(): Bool {
        if (toolType == ToolType.INTERNAL_IMPLEMENTED && name == "CacheCopy") {
            let full = GetFullArgs()
            if (full.size < 3) {
                return false
            }
            return CopyFile(full[1], full[2])
        }
        return false
    }

    @When[os != "Windows"]
    public func BuildEnvironmentVector(): Array<String> {
        let environment = ArrayList<String>()
        if (!ldLibraryPath.isEmpty()) {
            let inherited = environmentVars.get(DYNAMIC_LIBRARY_PATH_ENV) ?? ""
            let value = if (inherited.isEmpty()) { ldLibraryPath } else { ldLibraryPath + ":" + inherited }
            environment.add(DYNAMIC_LIBRARY_PATH_ENV + "=" + value)
        } else if (let Some(value) <- environmentVars.get(DYNAMIC_LIBRARY_PATH_ENV)) {
            environment.add(DYNAMIC_LIBRARY_PATH_ENV + "=" + value)
        }
        for ((key, value) in environmentVars) {
            if (IsBlockedEnvironmentVariable(key)) {
                continue
            }
            if (key == DYNAMIC_LIBRARY_PATH_ENV) {
                continue
            }
            environment.add(key + "=" + value)
        }
        return environment.toArray()
    }

}

@When[os != "Windows"]
private func IsBlockedEnvironmentVariable(key: String): Bool {
    return key == DYNAMIC_LIBRARY_PATH_ENV || key == DYNAMIC_PRELOAD_ENV || key == "LD_AUDIT" ||
        key == "LD_DEBUG" || key == "LD_PROFILE" || key == "LD_TRACE_LOADED_OBJECTS" ||
        key == "DYLD_FRAMEWORK_PATH" || key == "DYLD_FALLBACK_FRAMEWORK_PATH" || key == "DYLD_FALLBACK_LIBRARY_PATH" ||
        key == "DYLD_VERSIONED_FRAMEWORK_PATH" || key == "DYLD_VERSIONED_LIBRARY_PATH" ||
        key == "DYLD_PRINT_LIBRARIES" || key == "DYLD_PRINT_TO_FILE" || key == "RUSTC_WRAPPER" ||
        key.startsWith("LLVM_SYS_") || key.startsWith("MLIR_SYS_") || key.startsWith("TABLEGEN_")
}
