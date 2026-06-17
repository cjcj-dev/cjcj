package cangjie_compiler::option

import cangjie_compiler::basic.PrintCommandDesc as BasicPrintCommandDesc
import cangjie_compiler::basic.PrintIndentOnly as BasicPrintIndentOnly
import std.collection.*

private let OPTION_WIDTH: Int64 = 28

private func printIndentOnly(indent: Int64, numSpaces!: Int64 = 2): Unit {
    BasicPrintIndentOnly(UInt64(indent), numSpaces: UInt64(numSpaces))
}

private func printCommandDesc(option: String, desc: String): Unit {
    BasicPrintCommandDesc(option, desc, OPTION_WIDTH)
}

private func containsBackendValue(values: Array<Backend>, target: Backend): Bool {
    for (value in values) {
        if (value == Backend.ALL || value == target) { return true }
    }
    return false
}

private func containsGroupValue(values: Array<Group>, target: Group): Bool {
    for (value in values) {
        if (value == target) { return true }
    }
    return false
}

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
        if (!frontendMode && arg.info.BelongsGroup(Group.FRONTEND)) {
            Errorln("invalid option: '" + argName + "'.")
            return OptionArgParseResult(false, arg)
        }
        if (arg.hasJoinedValue || arg.info.GetKind() == Kind.CONTINOUS || joinedWithoutSpace) {
            if ((arg.hasJoinedValue || arg.info.GetKind() == Kind.CONTINOUS) && value.isEmpty() &&
                arg.info.GetID() != ID.LTO_KEEP_PKG_VISIBILITY) {
                Warningln("option '" + arg.name + "' requires some values, format: option=value or option=\"v1, v2...\"")
            }
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
        if (optionInfos.isEmpty()) { return }
        Println("Usage:")
        printIndentOnly("Usage:".size, numSpaces: 1)
        if (containsGroup(groups, Group.FRONTEND)) { Println("cjc-frontend [option] file...") }
        else { Println("cjc [option] file...") }
        Println()
        Println("Options:")
        for (info in optionInfos) {
            if (info.BelongsToAnyOfGroup(groups) && info.BelongsToBackend(backend)) {
                var name = info.name
                if (!info.alias.isEmpty()) { name = info.alias + ", " + name }
                if (info.kind == Kind.SEPARATED) { name += " <value>" }
                else if (info.kind == Kind.CONTINOUS) { name += "<value>" }
                var desc = info.help
                if (!info.BelongsGroup(Group.STABLE)) { desc += " (Experimental)" }
                if (name.size < OPTION_WIDTH) {
                    printCommandDesc(name, desc)
                } else {
                    printCommandDesc(name, "")
                    printCommandDesc("", desc)
                }
                for (optionValue in info.values) {
                    if (!containsBackendValue(optionValue.backends, backend)) { continue }
                    if (!containsGroupValue(optionValue.groups, Group.STABLE) && !showExperimental) { continue }
                    let valueName = "  <value>=" + optionValue.value
                    var valueHelp = "  " + optionValue.help
                    if (!containsGroupValue(optionValue.groups, Group.STABLE)) { valueHelp += " (Experimental)" }
                    printCommandDesc(valueName, valueHelp)
                }
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
