package cjcj::sema.NativeFFI.ObjC

import std.collection.*

// C++ src/Sema/NativeFFI/ObjC/ObjCCodeTranspiler/Utils.h:14-17.
public enum ObjCFunctionType {
    | STATIC
    | INSTANCE
}

public enum GenerationTarget {
    | HEADER
    | SOURCE
    | BOTH
}

public enum FunctionListFormat {
    | DECLARATION
    | STATIC_REF
    | CANGJIE_DECL
}

public enum OptionalBlockOp {
    | OPEN
    | CLOSE
    | NONE
}

// C++ src/Sema/NativeFFI/ObjC/ObjCCodeTranspiler/Utils.h:19-42.
public func JoinVec<T>(vec: ArrayList<T>, trans: (T) -> String, sep!: String = ", ",
    pre!: String = "", suf!: String = "", force!: Bool = true): String {
    let result = StringBuilder()
    if (vec.isEmpty()) {
        if (!force) {
            return ""
        }
        result.append(pre)
        result.append(suf)
        return result.toString()
    }
    result.append(pre)
    for (idx in 0..vec.size) {
        result.append(trans(vec[idx]))
        if (idx + 1 < vec.size) {
            result.append(sep)
        }
    }
    result.append(suf)
    return result.toString()
}
