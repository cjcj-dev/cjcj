package cangjie_compiler::chir

import std.collection.*

public func GetGenericTypeConstaintsStr(genericTypeParams: ArrayList<GenericType>): String {
    if (genericTypeParams.isEmpty()) {
        return ""
    }
    let genericTypeStr = ArrayList<String>()
    for (genericTypeParam in genericTypeParams) {
        let upperBounds = genericTypeParam.GetUpperBounds()
        if (upperBounds.isEmpty()) {
            continue
        }
        let constaintStr = TypeVecToString("", upperBounds, "", delimiter: " & ")
        genericTypeStr.add(genericTypeParam.ToString() + " <: " + constaintStr)
    }
    if (genericTypeStr.isEmpty()) {
        return ""
    }
    return "genericConstraints: [" + StringJoin(genericTypeStr, ", ") + "]"
}

public func GetGenericTypeConstraintsStr(genericTypeParams: ArrayList<GenericType>): String {
    return GetGenericTypeConstaintsStr(genericTypeParams)
}

public func PackageAccessLevelToString(level: AccessLevel): String {
    return match (level) {
        case AccessLevel.INTERNAL => "internal"
        case AccessLevel.PROTECTED => "protected"
        case AccessLevel.PUBLIC => "public"
        case AccessLevel.INVALID => throw IllegalArgumentException("invalid package access level")
    }
}

public func StringJoin(candidates: ArrayList<String>, delimiter: String): String {
    var result = ""
    for (candidate in candidates) {
        if (candidate.isEmpty()) {
            continue
        }
        if (!result.isEmpty()) {
            result += delimiter
        }
        result += candidate
    }
    return result
}

public func ValueIdVecToString(prefix: String, values: ArrayList<Value>, suffix: String,
    hasExceptionBranch!: Bool = false): String {
    if (values.isEmpty()) {
        return ""
    }
    let ids = ArrayList<String>()
    for (value in values) {
        ids.add(ValueIdToString(value))
    }
    if (hasExceptionBranch) {
        if (ids.size < 2) {
            throw IllegalArgumentException("exception branch value list must contain normal and exception successors")
        }
        ids[ids.size - 2] = "normal: " + ids[ids.size - 2]
        ids[ids.size - 1] = "exception: " + ids[ids.size - 1]
    }
    return prefix + StringJoin(ids, ", ") + suffix
}

public func TypeVecToString(prefix: String, types: ArrayList<Type>, suffix: String,
    delimiter!: String = ", "): String {
    if (types.isEmpty()) {
        return ""
    }
    let ids = ArrayList<String>()
    for (ty in types) {
        ids.add(ty.ToString())
    }
    return prefix + StringJoin(ids, delimiter) + suffix
}

public func GenericTypeVecToString(prefix: String, types: ArrayList<GenericType>, suffix: String,
    delimiter!: String = ", "): String {
    if (types.isEmpty()) {
        return ""
    }
    let ids = ArrayList<String>()
    for (ty in types) {
        ids.add(ty.ToString())
    }
    return prefix + StringJoin(ids, delimiter) + suffix
}

public func AddNewLineOrNot(message: String): String {
    if (message.isEmpty()) {
        return ""
    }
    return message + "\n"
}

public func CommentToString(message: ArrayList<String>): String {
    return CommentToString(StringJoin(message, ", "))
}

public func CommentToString(message: String): String {
    if (message.isEmpty()) {
        return ""
    }
    return " // " + message
}

private func ValueIdToString(value: Value): String {
    if (value.IsLiteral()) {
        return value.ToString(0)
    }
    if (let Some(local) <- value.AsLocalVar()) {
        if (let Some(expr) <- local.GetExpr()) {
            if (let Some(constant) <- (expr as Constant)) {
                return constant.literal.ToString()
            }
        }
    }
    return value.GetIdentifier()
}
