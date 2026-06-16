package cangjie_compiler::driver

import std.collection.*
import std.process.*

public type ToolBatch = ArrayList<Tool>

public func MakeSingleToolBatch(tool: Tool): ToolBatch {
    let result = ArrayList<Tool>()
    result.add(tool)
    return result
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
            let code = execute(name, args.toArray())
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

    private func GenerateCommand(): String {
        let builder = StringBuilder()
        if (!ldLibraryPath.isEmpty()) {
            builder.append("LD_LIBRARY_PATH=")
            builder.append(GetSingleQuoted(ldLibraryPath))
            builder.append(":$LD_LIBRARY_PATH ")
        }
        builder.append(GetSingleQuoted(name))
        for (arg in args) {
            builder.append(" ")
            builder.append(GetSingleQuoted(arg))
        }
        return builder.toString()
    }

    private func InternalImplementedCommandExec(): Bool {
        if (toolType == ToolType.INTERNAL_IMPLEMENTED && name == "CacheCopy") {
            let full = GetFullArgs()
            if (full.size < 3) {
                return false
            }
            return FileUtil.CopyFile(full[1], full[2])
        }
        return false
    }

    public func BuildEnvironmentVector(): Array<String> {
        let environment = ArrayList<String>()
        if (!ldLibraryPath.isEmpty()) {
            let inherited = environmentVars.get("LD_LIBRARY_PATH") ?? ""
            let value = if (inherited.isEmpty()) { ldLibraryPath } else { ldLibraryPath + ":" + inherited }
            environment.add("LD_LIBRARY_PATH=" + value)
        } else if (let Some(value) <- environmentVars.get("LD_LIBRARY_PATH")) {
            environment.add("LD_LIBRARY_PATH=" + value)
        }
        for ((key, value) in environmentVars) {
            if (IsBlockedEnvironmentVariable(key)) {
                continue
            }
            if (key == "LD_LIBRARY_PATH") {
                continue
            }
            environment.add(key + "=" + value)
        }
        return environment.toArray()
    }
}

private func IsBlockedEnvironmentVariable(key: String): Bool {
    return key == "LD_PRELOAD" || key == "LD_AUDIT" || key == "LD_DEBUG" || key == "LD_PROFILE" ||
        key == "LD_TRACE_LOADED_OBJECTS" || key == "DYLD_INSERT_LIBRARIES" || key == "DYLD_FRAMEWORK_PATH" ||
        key == "DYLD_FALLBACK_FRAMEWORK_PATH" || key == "DYLD_FALLBACK_LIBRARY_PATH" ||
        key == "DYLD_VERSIONED_FRAMEWORK_PATH" || key == "DYLD_VERSIONED_LIBRARY_PATH" ||
        key == "DYLD_PRINT_LIBRARIES" || key == "DYLD_PRINT_TO_FILE" || key == "RUSTC_WRAPPER" ||
        key.startsWith("LLVM_SYS_") || key.startsWith("MLIR_SYS_") || key.startsWith("TABLEGEN_")
}
