package cangjie_compiler::chir

import std.collection.*

public func IndentToString(indent: Int64): String {
    var out = ""
    var idx: Int64 = 0
    while (idx < indent) {
        out += " "
        idx++
    }
    return out
}

public func JoinStrings(values: ArrayList<String>, delimiter: String): String {
    var out = ""
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            out += delimiter
        }
        out += values[idx]
        idx++
    }
    return out
}

public func CopyTypeList(values: ArrayList<Type>): ArrayList<Type> {
    let out = ArrayList<Type>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func CopyValueList(values: ArrayList<Value>): ArrayList<Value> {
    let out = ArrayList<Value>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func CopyExpressionList(values: ArrayList<Expression>): ArrayList<Expression> {
    let out = ArrayList<Expression>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func CopyBlockList(values: ArrayList<Block>): ArrayList<Block> {
    let out = ArrayList<Block>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func CopyFunctionList(values: ArrayList<Function>): ArrayList<Function> {
    let out = ArrayList<Function>()
    for (value in values) {
        out.add(value)
    }
    return out
}

public func TypeListKey(values: ArrayList<Type>): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.ToString())
    }
    return JoinStrings(parts, ",")
}

public func RemoveExpressionById(values: ArrayList<Expression>, nodeId: Int64): Bool {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (values[idx].nodeId == nodeId) {
            values.remove(at: idx)
            return true
        }
        idx++
    }
    return false
}

public func RemoveValueById(values: ArrayList<Value>, nodeId: Int64): Bool {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (values[idx].nodeId == nodeId) {
            values.remove(at: idx)
            return true
        }
        idx++
    }
    return false
}

public func RemoveBlockById(values: ArrayList<Block>, nodeId: Int64): Bool {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (values[idx].nodeId == nodeId) {
            values.remove(at: idx)
            return true
        }
        idx++
    }
    return false
}

public func ContainsBlock(values: ArrayList<Block>, block: Block): Bool {
    for (value in values) {
        if (value.nodeId == block.nodeId) {
            return true
        }
    }
    return false
}

public func ContainsExpression(values: ArrayList<Expression>, expr: Expression): Bool {
    for (value in values) {
        if (value.nodeId == expr.nodeId) {
            return true
        }
    }
    return false
}

public func ContainsValue(values: ArrayList<Value>, value: Value): Bool {
    for (item in values) {
        if (item.nodeId == value.nodeId) {
            return true
        }
    }
    return false
}
