package cangjie_compiler::option

import std.collection.*

public class OptionValue {
    public let value: String
    public let help: String
    public let backends: Array<Backend>
    public let groups: Array<Group>

    public init(value: String, help: String, backends: Array<Backend>, groups: Array<Group>) {
        this.value = value
        this.help = help
        this.backends = backends
        this.groups = groups
    }
}

public class OptionInfo {
    public let name: String
    public let id: ID
    public let kind: Kind
    public let backends: Array<Backend>
    public let groups: Array<Group>
    public let alias: String
    public let values: Array<OptionValue>
    public let occurrence: Occurrence
    public let help: String

    public init(
        name: String,
        id: ID,
        kind: Kind,
        backends: Array<Backend>,
        groups: Array<Group>,
        alias: String,
        values: Array<OptionValue>,
        occurrence: Occurrence,
        help: String
    ) {
        this.name = name
        this.id = id
        this.kind = kind
        this.backends = backends
        this.groups = groups
        this.alias = alias
        this.values = values
        this.occurrence = occurrence
        this.help = help
    }

    public func GetID(): ID { return id }
    public func GetAlias(): String { return alias }
    public func GetKind(): Kind { return kind }
    public func GetGroups(): Array<Group> { return groups }
    public func GetName(): String { return name }
    public func GetOptionValues(): Array<OptionValue> { return values }
    public func GetOccurrenceType(): Occurrence { return occurrence }

    public func BelongsGroup(group: Group): Bool {
        for (item in groups) { if (item == group) { return true } }
        return false
    }

    public func BelongsToAnyOfGroup(targets: Array<Group>): Bool {
        for (target in targets) {
            if (BelongsGroup(target)) { return true }
        }
        return false
    }

    public func BelongsToBackend(target: Backend): Bool {
        for (backend in backends) {
            if (backend == Backend.ALL || backend == target) { return true }
        }
        return false
    }
}

private let EMPTY_VALUES: Array<OptionValue> = Array<OptionValue>()
private let STABLE_GLOBAL: Array<Group> = [Group.GLOBAL, Group.STABLE, Group.VISIBLE]
private let STABLE_DRIVER: Array<Group> = [Group.DRIVER, Group.STABLE, Group.VISIBLE]
private let ALL_BACKENDS: Array<Backend> = [Backend.ALL]
private let CJNATIVE_BACKEND: Array<Backend> = [Backend.CJNATIVE]

private func oneOf(values: Array<String>): Array<OptionValue> {
    let ret = ArrayList<OptionValue>()
    for (value in values) {
        ret.add(OptionValue(value, "", ALL_BACKENDS, [Group.STABLE, Group.VISIBLE]))
    }
    return ret.toArray()
}

public func CreateOptionInfos(): Array<OptionInfo> {
    return [
        OptionInfo("--output", ID.OUTPUT_FILE, Kind.SEPARATED, ALL_BACKENDS, STABLE_GLOBAL, "-o", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Specify product name or output directory when compiling a package"),
        OptionInfo("--output-dir", ID.OUTPUT_DIR, Kind.SEPARATED, ALL_BACKENDS, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Specify output directory"),
        OptionInfo("--module-name", ID.MODULE_NAME, Kind.SEPARATED, ALL_BACKENDS, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Tell compiler name of the module"),
        OptionInfo("--package", ID.PACKAGE_COMPILE, Kind.FLAG, ALL_BACKENDS, STABLE_GLOBAL, "-p", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Specify package directory to be compiled"),
        OptionInfo("--import-path", ID.IMPORT_PATH, Kind.SEPARATED, ALL_BACKENDS, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Add .cjo search path"),
        OptionInfo("--target", ID.TARGET, Kind.SEPARATED, CJNATIVE_BACKEND, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Generate code for the given target platform"),
        OptionInfo("--backend", ID.BACKEND_MODE, Kind.SEPARATED, ALL_BACKENDS, [Group.GLOBAL, Group.STABLE], "", oneOf(["llvm"]), Occurrence.SINGLE_OCCURRENCE, "Specify backend toolchain"),
        OptionInfo("--output-type", ID.OUTPUT_TYPE, Kind.SEPARATED, ALL_BACKENDS, STABLE_GLOBAL, "", oneOf(["exe", "staticlib", "dylib", "chir", "obj", "hotreload"]), Occurrence.SINGLE_OCCURRENCE, "Specify output file type"),
        OptionInfo("--compile-target", ID.COMPILE_TARGET, Kind.SEPARATED, ALL_BACKENDS, [Group.DRIVER, Group.VISIBLE], "", oneOf(["exe", "staticlib", "dylib"]), Occurrence.SINGLE_OCCURRENCE, "Specify compile target for obj"),
        OptionInfo("-O0", ID.OPTIMIZATION_0, Kind.FLAG, CJNATIVE_BACKEND, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Optimization level 0"),
        OptionInfo("-O1", ID.OPTIMIZATION_1, Kind.FLAG, CJNATIVE_BACKEND, STABLE_GLOBAL, "-O", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Optimization level 1"),
        OptionInfo("-O2", ID.OPTIMIZATION_2, Kind.FLAG, CJNATIVE_BACKEND, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Optimization level 2"),
        OptionInfo("-O3", ID.OPTIMIZATION_3, Kind.FLAG, CJNATIVE_BACKEND, [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Optimization level 3"),
        OptionInfo("-Os", ID.OPTIMIZATION_S, Kind.FLAG, CJNATIVE_BACKEND, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Optimization level s"),
        OptionInfo("-Oz", ID.OPTIMIZATION_Z, Kind.FLAG, CJNATIVE_BACKEND, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Optimization level z"),
        OptionInfo("-O", ID.OPTIMIZATION_CUSTOM, Kind.CONTINOUS, CJNATIVE_BACKEND, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Set optimization level"),
        OptionInfo("--warn-off", ID.WARN_OFF, Kind.SEPARATED, ALL_BACKENDS, STABLE_GLOBAL, "-Woff", oneOf(["all", "unused", "driver-arg", "deprecated", "parser", "semantics"]), Occurrence.MULTIPLE_OCCURRENCE, "Suppress a warning group"),
        OptionInfo("--warn-on", ID.WARN_ON, Kind.SEPARATED, ALL_BACKENDS, STABLE_GLOBAL, "-Won", oneOf(["all", "unused", "driver-arg", "deprecated", "parser", "semantics"]), Occurrence.MULTIPLE_OCCURRENCE, "Enable a warning group"),
        OptionInfo("--error-count-limit", ID.ERROR_COUNT_LIMIT, Kind.SEPARATED, ALL_BACKENDS, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Emit specified number of errors only"),
        OptionInfo("--verbose", ID.VERBOSE, Kind.FLAG, ALL_BACKENDS, STABLE_GLOBAL, "-V", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable verbose"),
        OptionInfo("--version", ID.VERSION, Kind.FLAG, ALL_BACKENDS, STABLE_GLOBAL, "-v", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Print compiler version information"),
        OptionInfo("--help", ID.HELP, Kind.FLAG, ALL_BACKENDS, STABLE_GLOBAL, "-h", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Show usage"),
        OptionInfo("--experimental", ID.EXPERIMENTAL, Kind.FLAG, CJNATIVE_BACKEND, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable experimental options"),
        OptionInfo("--cfg", ID.CONDITIONAL_COMPILATION_CONFIG, Kind.SEPARATED, ALL_BACKENDS, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "User defined condition to compile"),
        OptionInfo("-g", ID.COMPILE_DEBUG, Kind.FLAG, ALL_BACKENDS, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Enable compile debug version target"),
        OptionInfo("--no-prelude", ID.NO_PRELUDE, Kind.FLAG, ALL_BACKENDS, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Do not import prelude by default"),
        OptionInfo("--static-std", ID.STATIC_STD, Kind.FLAG, CJNATIVE_BACKEND, STABLE_DRIVER, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Statically link std"),
        OptionInfo("--dy-std", ID.DY_STD, Kind.FLAG, CJNATIVE_BACKEND, STABLE_DRIVER, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Dynamically link std"),
        OptionInfo("--lto", ID.LTO, Kind.SEPARATED, CJNATIVE_BACKEND, STABLE_DRIVER, "", oneOf(["full", "thin"]), Occurrence.SINGLE_OCCURRENCE, "Enable LTO"),
        OptionInfo("--compile-as-exe", ID.COMPILE_AS_EXE, Kind.FLAG, CJNATIVE_BACKEND, STABLE_DRIVER, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Hide symbols from bitcode files in LTO mode"),
        OptionInfo("--lto-keep-pkg-visibility", ID.LTO_KEEP_PKG_VISIBILITY, Kind.SEPARATED, CJNATIVE_BACKEND, STABLE_DRIVER, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Keep packages visible in LTO mode"),
        OptionInfo("--dump-ast", ID.DUMP_AST, Kind.FLAG, ALL_BACKENDS, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Dump AST"),
        OptionInfo("--dump-chir", ID.DUMP_CHIR, Kind.FLAG, ALL_BACKENDS, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Dump CHIR"),
        OptionInfo("--dump-ir", ID.DUMP_IR, Kind.FLAG, ALL_BACKENDS, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Dump IR"),
        OptionInfo("--dump-all", ID.DUMP_ALL, Kind.FLAG, ALL_BACKENDS, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Dump AST, CHIR, and IR"),
        OptionInfo("--dump-to-screen", ID.DUMP_TO_SCREEN, Kind.FLAG, ALL_BACKENDS, STABLE_GLOBAL, "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Dump to screen"),
        OptionInfo("--chir-ea", ID.CHIR_EA, Kind.SEPARATED, ALL_BACKENDS, [Group.GLOBAL, Group.STABLE], "", oneOf(["on", "off"]), Occurrence.SINGLE_OCCURRENCE, "Escape analysis for CHIR"),
        OptionInfo("--chir-wfc", ID.CHIR_WFC, Kind.SEPARATED, ALL_BACKENDS, [Group.GLOBAL, Group.STABLE], "", oneOf(["on", "off"]), Occurrence.SINGLE_OCCURRENCE, "Well-formedness check for CHIR"),
        OptionInfo("--disable-chir-opt", ID.DISABLE_CHIR_OPT, Kind.FLAG, ALL_BACKENDS, [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable CHIR optimization"),
        OptionInfo("--disable-backend-opt", ID.DISABLE_BACKEND_OPT, Kind.FLAG, ALL_BACKENDS, [Group.GLOBAL, Group.STABLE], "", EMPTY_VALUES, Occurrence.MULTIPLE_OCCURRENCE, "Disable backend optimization"),
        OptionInfo("--sanitize", ID.SANITIZE, Kind.SEPARATED, CJNATIVE_BACKEND, [Group.GLOBAL, Group.STABLE], "", oneOf(["address", "thread", "hwaddress"]), Occurrence.SINGLE_OCCURRENCE, "Enable sanitizer"),
        OptionInfo("--jobs", ID.JOBS, Kind.SEPARATED, CJNATIVE_BACKEND, STABLE_GLOBAL, "-j", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Number of tasks to run at once"),
        OptionInfo("--aggressive-parallel-compile", ID.AGGRESSIVE_PARALLEL_COMPILE, Kind.FLAG_WITH_ARG, CJNATIVE_BACKEND, STABLE_GLOBAL, "--apc", EMPTY_VALUES, Occurrence.SINGLE_OCCURRENCE, "Enable aggressive parallel compile"),
    ]
}

public open class ArgInstance {
    public let argInstanceType: ArgInstanceType
    public var str: String = ""
    protected init(argInstanceType: ArgInstanceType) {
        this.argInstanceType = argInstanceType
    }
}

public class InputArgInstance <: ArgInstance {
    public let value: String
    public init(value: String) {
        super(ArgInstanceType.Input)
        this.value = value
        str = value
    }
}

public class OptionArgInstance <: ArgInstance {
    public let info: OptionInfo
    public var name: String
    public var argType: ArgType = ArgType.PartiallyParsed
    public var hasJoinedValue: Bool = false
    public var value: String

    public init(info: OptionInfo, name: String, value!: String = "") {
        super(ArgInstanceType.Option)
        this.info = info
        this.name = name
        this.value = value
    }
}

public class ArgListEntry {
    public let argInstanceType: ArgInstanceType
    public let index: Int64
    public init(argInstanceType: ArgInstanceType, index: Int64) {
        this.argInstanceType = argInstanceType
        this.index = index
    }
}

public class ArgList {
    public let args: ArrayList<ArgInstance> = ArrayList<ArgInstance>()
    public let inputArgs: ArrayList<InputArgInstance> = ArrayList<InputArgInstance>()
    public let optionArgs: ArrayList<OptionArgInstance> = ArrayList<OptionArgInstance>()
    public let entries: ArrayList<ArgListEntry> = ArrayList<ArgListEntry>()
    private let specified: ArrayList<ID> = ArrayList<ID>()
    private let warned: ArrayList<ID> = ArrayList<ID>()
    private let inputs: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func AddParsedInput(input: String): Unit {
        let arg = InputArgInstance(input)
        inputArgs.add(arg)
        args.add(arg)
        entries.add(ArgListEntry(ArgInstanceType.Input, inputArgs.size - 1))
    }

    public func AddParsedOption(arg: OptionArgInstance): Unit {
        optionArgs.add(arg)
        args.add(arg)
        entries.add(ArgListEntry(ArgInstanceType.Option, optionArgs.size - 1))
    }

    public func MarkSpecified(arg: OptionArgInstance): Unit {
        if (!containsID(specified, arg.info.GetID())) { specified.add(arg.info.GetID()) }
    }

    public func IsSpecified(id: ID): Bool { return containsID(specified, id) }
    public func AddInput(input: String): Unit { inputs.add(input) }
    public func GetInputs(): Array<String> { return inputs.toArray() }
    public func MarkWarned(id: ID): Unit { if (!containsID(warned, id)) { warned.add(id) } }
    public func IsWarned(id: ID): Bool { return containsID(warned, id) }
}

private func containsID(values: ArrayList<ID>, target: ID): Bool {
    for (value in values) { if (value == target) { return true } }
    return false
}

public class OptionArgParseResult {
    public let ok: Bool
    public let arg: OptionArgInstance
    public init(ok: Bool, arg: OptionArgInstance) {
        this.ok = ok
        this.arg = arg
    }
}

private class ParsedArgumentName {
    let name: String
    let hasValue: Bool
    let value: String
    init(name: String, hasValue: Bool, value: String) {
        this.name = name
        this.hasValue = hasValue
        this.value = value
    }
}

public class OptionTable {
    public let optionInfos: Array<OptionInfo>
    private let frontendMode: Bool
    private let enabledBackends: Array<Backend>
    private let enabledGroups: Array<Group>

    public init(infos: Array<OptionInfo>, frontendMode: Bool) {
        optionInfos = infos
        this.frontendMode = frontendMode
        enabledBackends = [Backend.CJNATIVE]
        enabledGroups = if (frontendMode) { [Group.GLOBAL, Group.FRONTEND] } else { [Group.GLOBAL, Group.DRIVER] }
    }

    private func parseArgumentName(argStr: String): ParsedArgumentName {
        if (let Some(pos) <- argStr.indexOf("=")) {
            return ParsedArgumentName(argStr[0..pos], true, argStr[pos + 1..])
        }
        return ParsedArgumentName(argStr, false, "")
    }

    private func belongsToBackend(objects: Array<Backend>): Bool {
        for (object in objects) {
            if (object == Backend.ALL) { return true }
            for (target in enabledBackends) { if (object == target) { return true } }
        }
        return false
    }

    private func belongsToGroup(objects: Array<Group>): Bool {
        for (object in objects) {
            if (object == Group.GLOBAL) { return true }
            for (target in enabledGroups) { if (object == target) { return true } }
        }
        return false
    }

    private func shouldRecognize(argName: String, hasValue: Bool, info: OptionInfo): Bool {
        if (argName != info.name && argName != info.alias) { return false }
        if (!belongsToBackend(info.backends) || !belongsToGroup(info.groups)) { return false }
        if (info.kind == Kind.FLAG_WITH_ARG && hasValue) { return true }
        if (info.kind != Kind.SEPARATED && hasValue) { return false }
        return true
    }

    private func checkValue(value: String, info: OptionInfo): Bool {
        if (info.values.isEmpty()) { return true }
        for (item in info.values) { if (item.value == value) { return true } }
        return false
    }

    private func parseOptionArg(argStr: String): OptionArgParseResult {
        let parsed = parseArgumentName(argStr)
        var argName = parsed.name
        var value = parsed.value
        var foundIndex: Int64 = -1
        var idx: Int64 = 0
        while (idx < optionInfos.size) {
            if (shouldRecognize(argName, parsed.hasValue, optionInfos[idx])) {
                foundIndex = idx
                break
            }
            idx++
        }
        var joinedWithoutSpace = false
        if (foundIndex < 0) {
            idx = 0
            while (idx < optionInfos.size) {
                let info = optionInfos[idx]
                let aliasMatch = info.kind == Kind.SEPARATED && !info.alias.isEmpty() && StartsWith(argStr, info.alias)
                let continuousMatch = info.kind == Kind.CONTINOUS && StartsWith(argStr, info.name)
                if (belongsToBackend(info.backends) && belongsToGroup(info.groups) && (aliasMatch || continuousMatch)) {
                    foundIndex = idx
                    joinedWithoutSpace = true
                    argName = if (info.kind == Kind.SEPARATED) { info.alias } else { info.name }
                    value = argStr[argName.size..]
                    break
                }
                idx++
            }
        }
        if (foundIndex < 0) {
            Errorln("invalid option: '" + argName + "'.")
            return OptionArgParseResult(false, OptionArgInstance(optionInfos[0], argName))
        }
        let arg = OptionArgInstance(optionInfos[foundIndex], argName)
        arg.str = argStr
        arg.value = value
        arg.hasJoinedValue = parsed.hasValue
        if (arg.hasJoinedValue || arg.info.GetKind() == Kind.CONTINOUS || joinedWithoutSpace) {
            if (!checkValue(value, arg.info)) {
                Errorln("invalid value: '" + value + "'")
                return OptionArgParseResult(false, arg)
            }
            arg.value = value
        }
        let partial = !arg.hasJoinedValue && arg.info.GetKind() == Kind.SEPARATED && !joinedWithoutSpace
        arg.argType = if (partial) { ArgType.PartiallyParsed } else { ArgType.FullyParsed }
        return OptionArgParseResult(true, arg)
    }

    public func ParseArgs(argsStrs: Array<String>, argList: ArgList): Bool {
        if (argsStrs.size <= 1) { return true }
        var idx: Int64 = 1
        while (idx < argsStrs.size) {
            let argStr = argsStrs[idx]
            if (argStr.trimAscii().isEmpty()) {
                idx++
                continue
            }
            if (argStr[0] != b'-') {
                argList.AddParsedInput(argStr)
                idx++
                continue
            }
            if (argStr.size <= 1) {
                Errorln("invalid option: '-'.")
                return false
            }
            let parsed = parseOptionArg(argStr)
            if (!parsed.ok) { return false }
            let arg = parsed.arg
            if (arg.argType == ArgType.PartiallyParsed) {
                idx++
                if (idx >= argsStrs.size) {
                    Errorln("this Option needs a value: '" + arg.name + "'")
                    return false
                }
                if (!checkValue(argsStrs[idx], arg.info)) {
                    Errorln("invalid value: '" + argsStrs[idx] + "'")
                    return false
                }
                arg.value = argsStrs[idx]
                arg.str = arg.name + " " + arg.value
            }
            argList.AddParsedOption(arg)
            idx++
        }
        return true
    }

    public func Usage(backend: Backend, groups: Array<Group>, showExperimental!: Bool = false): Unit {
        Println("Usage:")
        if (containsGroup(groups, Group.FRONTEND)) { Println("  cjc-frontend [option] file...") }
        else { Println("  cjc [option] file...") }
        Println()
        Println("Options:")
        for (info in optionInfos) {
            if (info.BelongsToAnyOfGroup(groups) && info.BelongsToBackend(backend)) {
                if (!showExperimental && !info.BelongsGroup(Group.STABLE)) { continue }
                var name = info.name
                if (!info.alias.isEmpty()) { name = info.alias + ", " + name }
                if (info.kind == Kind.SEPARATED) { name += " <value>" }
                Println(name + "    " + info.help)
            }
        }
    }
}

private func containsGroup(values: Array<Group>, target: Group): Bool {
    for (value in values) { if (value == target) { return true } }
    return false
}

public func CreateOptionTable(frontendMode!: Bool = false): OptionTable {
    return OptionTable(CreateOptionInfos(), frontendMode)
}
