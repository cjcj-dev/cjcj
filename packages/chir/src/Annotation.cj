package cangjie_compiler::chir

import std.collection.*

// GAP_TODO: MarkExpressionAsMustNotOverflow ConstAnalysis.h:243 producer absent.

public class GeneratedFromForIn {
    private let value: Bool

    public init() {
        value = false
    }

    public init(input: Bool) {
        value = input || !input
    }

    public func Clone(): GeneratedFromForIn {
        return GeneratedFromForIn()
    }

    public func ToString(): String {
        return "// generated-from-forin "
    }

    public static func Extract(label: GeneratedFromForIn): Bool {
        return label.value
    }
}

public enum SkipKind {
    | NO_SKIP | SKIP_DCE_WARNING | SKIP_FORIN_EXIT | SKIP_VIC
}

public func SkipKindIndex(kind: SkipKind): Int64 {
    return match (kind) {
        case SkipKind.NO_SKIP => 0
        case SkipKind.SKIP_DCE_WARNING => 1
        case SkipKind.SKIP_FORIN_EXIT => 2
        case SkipKind.SKIP_VIC => 3
    }
}

extend SkipKind <: Equatable<SkipKind> {
    public operator func ==(right: SkipKind): Bool {
        return SkipKindIndex(this) == SkipKindIndex(right)
    }

    public operator func !=(right: SkipKind): Bool {
        return !(this == right)
    }
}

public class SkipCheck {
    private let kind: SkipKind

    public init() {
        kind = SkipKind.NO_SKIP
    }

    public init(kind: SkipKind) {
        this.kind = kind
    }

    public func Clone(): SkipCheck {
        return SkipCheck(kind)
    }

    public func ToString(): String {
        return match (kind) {
            case SkipKind.SKIP_DCE_WARNING => "skip: dce warning"
            case SkipKind.SKIP_FORIN_EXIT => "skip: for-in exit"
            case SkipKind.SKIP_VIC => "skip: vic"
            case SkipKind.NO_SKIP => ""
        }
    }

    public static func Extract(label: SkipCheck): SkipKind {
        return label.kind
    }
}

public class NeverOverflowInfo {
    private let neverOverflowInfo: Bool

    public init() {
        neverOverflowInfo = false
    }

    public init(value: Bool) {
        neverOverflowInfo = value
    }

    public func Clone(): NeverOverflowInfo {
        return NeverOverflowInfo(neverOverflowInfo)
    }

    public func ToString(): String {
        let str = if (neverOverflowInfo) { "true" } else { "false" }
        return "NeverOverflowInfo: " + str
    }

    public static func Extract(info: NeverOverflowInfo): Bool {
        return info.neverOverflowInfo
    }
}

private func SkipKindFromAnnotationValue(value: String): SkipKind {
    return match (value) {
        case "1" => SkipKind.SKIP_DCE_WARNING
        case "2" => SkipKind.SKIP_FORIN_EXIT
        case "3" => SkipKind.SKIP_VIC
        case _ => SkipKind.NO_SKIP
    }
}

public class EnumCaseIndex {
    private let index: Option<Int64>

    public init() {
        index = None
    }

    public init(input: Option<Int64>) {
        index = input
    }

    public func Clone(): EnumCaseIndex {
        return EnumCaseIndex(index)
    }

    public func ToString(): String {
        if (let Some(value) <- index) {
            return "EnumCaseIndex: " + value.toString()
        }
        return "EnumCaseIndex: "
    }

    public static func Extract(label: EnumCaseIndex): Option<Int64> {
        return label.index
    }
}

public class AnnotationMap {
    private let values: HashMap<String, String> = HashMap<String, String>()

    public init() {}

    public func Set(key: String, value: String): Unit {
        values[key] = value
    }

    public func Remove(key: String): Unit {
        values.remove(key)
    }

    public func Get(key: String): Option<String> {
        return values.get(key)
    }

    public func Contains(key: String): Bool {
        return values.contains(key)
    }

    public func Clear(): Unit {
        values.clear()
    }

    public func CopyFrom(other: AnnotationMap): Unit {
        values.clear()
        for ((key, value) in other.values) {
            values[key] = value
        }
    }

    public func ToString(indent!: Int64 = 0): String {
        if (values.isEmpty()) {
            return ""
        }
        let parts = ArrayList<String>()
        for ((key, value) in values) {
            if (key == "SkipCheck") {
                let text = SkipCheck(SkipKindFromAnnotationValue(value)).ToString()
                if (!text.isEmpty()) {
                    parts.add("${IndentToString(indent)}${text}")
                }
            } else if (key == "NeverOverflowInfo") {
                let neverOverflowText = NeverOverflowInfo(value == "true").ToString()
                parts.add("${IndentToString(indent)}${neverOverflowText}")
            } else {
                parts.add("${IndentToString(indent)}@${key}(${value})")
            }
        }
        return JoinStrings(parts, "\n")
    }
}

public class CustomAnnoInstance {
    private let annoClassName: String
    private let argValues: ArrayList<String> = ArrayList<String>()
    private let loc: DebugLocation

    public init(className: String, argValues: ArrayList<String>, loc: DebugLocation) {
        annoClassName = className
        for (argValue in argValues) {
            this.argValues.add(argValue)
        }
        this.loc = loc
    }

    public func ToString(indent: Int64): String {
        var out = IndentToString(indent) + "@" + annoClassName
        let argStr = JoinStrings(argValues, ", ")
        if (!argStr.isEmpty()) {
            out += "[" + argStr + "]"
        }
        out += CommentToString(loc.ToString())
        return out
    }

    public func Dump(): Unit {
        println(ToString(0))
    }

    public func GetAnnoClassName(): String {
        return annoClassName
    }

    public func GetArgValues(): ArrayList<String> {
        let out = ArrayList<String>()
        for (argValue in argValues) {
            out.add(argValue)
        }
        return out
    }

    public func GetDebugLocation(): DebugLocation {
        return loc
    }
}

public class AnnoInfo {
    var mangledName: String = "none"
    let annoInstances: ArrayList<CustomAnnoInstance> = ArrayList<CustomAnnoInstance>()

    public init() {}

    public init(funcName: String, instances: ArrayList<CustomAnnoInstance>) {
        mangledName = funcName
        for (instance in instances) {
            annoInstances.add(instance)
        }
    }

    public func Add(annotation: String): Unit {
        annoInstances.add(CustomAnnoInstance(annotation, ArrayList<String>(), DebugLocation()))
    }

    public func Clear(): Unit {
        mangledName = "none"
        annoInstances.clear()
    }

    public func IsAvailable(): Bool {
        return mangledName != "none"
    }

    public func GetAnnotations(): ArrayList<String> {
        let out = ArrayList<String>()
        for (instance in annoInstances) {
            out.add(instance.GetAnnoClassName())
        }
        return out
    }

    public func ToString(indent!: Int64 = 0): String {
        if (!IsAvailable()) {
            return ""
        }
        let lines = ArrayList<String>()
        lines.add("${IndentToString(indent)}@AnnoFactoryFunc: ${mangledName}")
        for (instance in annoInstances) {
            lines.add(instance.ToString(indent))
        }
        return JoinStrings(lines, "\n")
    }

    public func Dump(): Unit {
        println(ToString())
    }

    public func GetAnnoFactoryFuncMangledName(): String {
        return mangledName
    }

    public func GetCustomAnnoInstances(): ArrayList<CustomAnnoInstance> {
        let out = ArrayList<CustomAnnoInstance>()
        for (instance in annoInstances) {
            out.add(instance)
        }
        return out
    }
}
