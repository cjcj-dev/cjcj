package cangjie_compiler::modules

import std.collection.*

public class IncrementalLoader {
    private var serializedData: String = ""

    public init() {}

    public init(serializedData: String) {
        this.serializedData = serializedData
    }

    public func SetSerializedData(serializedData: String): Unit {
        this.serializedData = serializedData
    }

    public func LoadRemovedMangles(): HashSet<String> {
        let removed = HashSet<String>()
        for (line in SplitRawLines(serializedData)) {
            if (line.isEmpty()) {
                continue
            }
            let fields = SplitFields(line)
            if (fields.size >= 2 && (fields[0] == "removed-mangle" || fields[0] == "removed")) {
                removed.add(fields[1])
            }
        }
        return removed
    }

    public func SerializeRemovedMangles(values: HashSet<String>): String {
        let lines = ArrayList<String>()
        for (value in values) {
            let fields = ArrayList<String>()
            fields.add("removed-mangle")
            fields.add(value)
            lines.add(JoinFields(fields))
        }
        return JoinStrings(lines, "\n")
    }
}
