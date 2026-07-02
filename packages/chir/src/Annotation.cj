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

public class AnnoInfo {
    private let customAnnotations: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func Add(annotation: String): Unit {
        customAnnotations.add(annotation)
    }

    public func Clear(): Unit {
        customAnnotations.clear()
    }

    public func GetAnnotations(): ArrayList<String> {
        let out = ArrayList<String>()
        for (annotation in customAnnotations) {
            out.add(annotation)
        }
        return out
    }

    public func ToString(indent!: Int64 = 0): String {
        if (customAnnotations.isEmpty()) {
            return ""
        }
        let lines = ArrayList<String>()
        for (annotation in customAnnotations) {
            lines.add("${IndentToString(indent)}@${annotation}")
        }
        return JoinStrings(lines, "\n")
    }
}
