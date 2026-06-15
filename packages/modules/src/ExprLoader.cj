package cangjie_compiler::modules

import std.collection.*

public class ExprLoader {
    public init() {}

    public func LoadExprTag(tag: String): String {
        if (tag.contains("expr-root") || tag.contains("expr|")) {
            if (let Some(expr) <- LoadExpr(tag)) {
                return expr.kind
            }
        }
        return tag
    }

    public func LoadExpr(serialized: String): Option<SerializedExpr> {
        let nodes = HashMap<Int64, SerializedExpr>()
        let childMap = HashMap<Int64, ArrayList<Int64>>()
        var rootIndex: Int64 = 0
        for (line in SplitRawLines(serialized)) {
            if (line.isEmpty()) {
                continue
            }
            let fields = SplitFields(line)
            if (fields.isEmpty()) {
                continue
            }
            if (fields[0] == "expr" && fields.size >= 12) {
                let index = ParseInt64Field(fields[1])
                let expr = SerializedExpr(fields[2], fields[3])
                expr.begin = Position(ParseUInt64Field(fields[4]), ParseInt64Field(fields[5]), ParseInt64Field(fields[6]))
                expr.end = Position(ParseUInt64Field(fields[7]), ParseInt64Field(fields[8]), ParseInt64Field(fields[9]))
                childMap[index] = parseIndexList(fields[10])
                parseAttrs(fields[11], expr.attributes)
                nodes[index] = expr
            } else if (fields[0] == "expr-root" && fields.size > 1) {
                rootIndex = ParseInt64Field(fields[1])
            }
        }
        for (index in childMap.keys()) {
            if (let Some(exprNode) <- nodes.get(index)) {
                if (let Some(children) <- childMap.get(index)) {
                    for (childIndex in children) {
                        if (let Some(child) <- nodes.get(childIndex)) {
                            exprNode.operands.add(child)
                        }
                    }
                }
            }
        }
        if (rootIndex == 0) {
            rootIndex = nodes.size
        }
        return nodes.get(rootIndex)
    }

    private func parseIndexList(value: String): ArrayList<Int64> {
        let out = ArrayList<Int64>()
        for (part in SplitStringList(value)) {
            if (!part.isEmpty()) {
                out.add(ParseInt64Field(part))
            }
        }
        return out
    }

    private func parseAttrs(value: String, attrs: HashMap<String, String>): Unit {
        for (part in SplitStringList(value)) {
            if (let Some(pos) <- part.indexOf("=")) {
                attrs[DecodeField(part[0..pos])] = DecodeField(part[pos + 1..])
            }
        }
    }
}
