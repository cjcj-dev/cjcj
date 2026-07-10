package cjcj::driver

import std.collection.*
import std.process.*

public type ToolBatch = ArrayList<Tool>

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
    func waitpid(pid: Int32, status: CPointer<Int32>, options: Int32): Int32
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
private func DecodeWaitStatus(status: Int32): Int64 {
    let signalBits = status & 0x7f
    if (signalBits == 0) {
        return Int64((status >> 8) & 0xff)
    }
    if (signalBits == 0x7f) {
        return 1
    }
    return Int64(128 + signalBits)
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

    public func Run(): ToolFuture {
        if (toolType == ToolType.INTERNAL_IMPLEMENTED) {
            return ThreadFuture(InternalImplementedCommandExec())
        }
        try {
            let code = if (HostOS() == OSType.WINDOWS) {
                execute(name, args.toArray())
            } else {
                RunPOSIX()
            }
            return ProcessFuture(code)
        } catch (e: Exception) {
            return ErrorFuture(e.message)
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

    @When[os != "Windows"]
    private func RunPOSIX(): Int64 {
        let argvValues = GetFullArgs()
        let environmentValues = BuildEnvironmentVector()
        let allocatedStrings = ArrayList<CString>()
        var exitCode: Int64 = 1
        try (pidPtr = LibC.malloc<Int32>().asResource(),
            statusPtr = LibC.malloc<Int32>().asResource(),
            argvPtr = LibC.malloc<CString>(count: argvValues.size + 1).asResource(),
            envpPtr = LibC.malloc<CString>(count: environmentValues.size + 1).asResource(),
            nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            if (pidPtr.value.isNull() || statusPtr.value.isNull() || argvPtr.value.isNull() ||
                envpPtr.value.isNull() || nameCString.value.isNull()) {
                FreeCStringList(allocatedStrings)
                throw Exception("failed to allocate process launch buffers")
            }
            if (!WriteNativeStringArray(argvValues, argvPtr.value, allocatedStrings)) {
                FreeCStringList(allocatedStrings)
                throw Exception("failed to allocate process arguments")
            }
            if (!WriteNativeStringArray(environmentValues, envpPtr.value, allocatedStrings)) {
                FreeCStringList(allocatedStrings)
                throw Exception("failed to allocate process environment")
            }
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
                throw Exception(GetSystemErrorMessage(spawnStatus))
            }
            let pid = unsafe { pidPtr.value.read() }
            let waited = unsafe { waitpid(pid, statusPtr.value, 0) }
            if (waited < 0) {
                throw Exception("waitpid failed")
            }
            exitCode = DecodeWaitStatus(unsafe { statusPtr.value.read() })
        }
        return exitCode
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
