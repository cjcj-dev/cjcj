package cangjie_compiler::chir

import std.collection.*

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
            parts.add("${IndentToString(indent)}@${key}(${value})")
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
