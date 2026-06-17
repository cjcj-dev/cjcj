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
        let orderedValues = ArrayList<String>()
        for (value in values) {
            orderedValues.add(value)
        }
        sortIncrementalStringsInPlace(orderedValues)
        for (value in orderedValues) {
            let fields = ArrayList<String>()
            fields.add("removed-mangle")
            fields.add(value)
            lines.add(JoinFields(fields))
        }
        return JoinStrings(lines, "\n")
    }
}

private func sortIncrementalStringsInPlace(values: ArrayList<String>): Unit {
    var i: Int64 = 1
    while (i < values.size) {
        let key = values[i]
        var j = i - 1
        while (j >= 0 && values[j] > key) {
            values[j + 1] = values[j]
            j--
        }
        values[j + 1] = key
        i++
    }
}
