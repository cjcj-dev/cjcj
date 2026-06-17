package cangjie_compiler::modules

import std.collection.*

public class SerializedExpr {
    public var kind: String = ""
    public var value: String = ""
    public var begin: Position = INVALID_POSITION
    public var end: Position = INVALID_POSITION
    public let operands: ArrayList<SerializedExpr> = ArrayList<SerializedExpr>()
    public let attributes: HashMap<String, String> = HashMap<String, String>()

    public init() {}

    public init(kind: String) {
        this.kind = kind
    }

    public init(kind: String, value: String) {
        this.kind = kind
        this.value = value
    }
}

public class ExprWriter {
    public init() {}

    public func WriteExprTag(tag: String): String {
        return WriteExpr(SerializedExpr(tag))
    }

    public func WriteExpr(expr: SerializedExpr): String {
        let lines = ArrayList<String>()
        let rootIndex = AppendExpr(expr, lines)
        let header = ArrayList<String>()
        header.add("expr-root")
        header.add(rootIndex.toString())
        lines.add(JoinFields(header))
        return JoinStrings(lines, "\n")
    }

    private func AppendExpr(expr: SerializedExpr, lines: ArrayList<String>): Int64 {
        let childIndexes = ArrayList<String>()
        for (operand in expr.operands) {
            childIndexes.add(AppendExpr(operand, lines).toString())
        }
        let attrPairs = ArrayList<String>()
        for (key in expr.attributes.keys()) {
            if (let Some(value) <- expr.attributes.get(key)) {
                attrPairs.add(EncodeField(key) + "=" + EncodeField(value))
            }
        }
        sortExprWriterStringsInPlace(attrPairs)
        let index = lines.size + 1
        let fields = ArrayList<String>()
        fields.add("expr")
        fields.add(index.toString())
        fields.add(expr.kind)
        fields.add(expr.value)
        fields.add(expr.begin.fileID.toString())
        fields.add(expr.begin.line.toString())
        fields.add(expr.begin.column.toString())
        fields.add(expr.end.fileID.toString())
        fields.add(expr.end.line.toString())
        fields.add(expr.end.column.toString())
        fields.add(JoinStringList(childIndexes))
        fields.add(JoinStringList(attrPairs))
        lines.add(JoinFields(fields))
        return index
    }
}

private func sortExprWriterStringsInPlace(values: ArrayList<String>): Unit {
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
