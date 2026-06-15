package cangjie_compiler::utils

public func CJC_ASSERT(condition: Bool): Unit {
    if (!condition) {
        throw IllegalStateException("CJC_ASSERT failed")
    }
}

public func CJC_ASSERT_WITH_MSG(condition: Bool, message: String): Unit {
    if (!condition) {
        throw IllegalStateException("CJC_ASSERT failed: ${message}")
    }
}

public func CJC_ABORT(): Unit {
    throw IllegalStateException("CJC_ABORT")
}

public func CJC_ABORT_WITH_MSG(message: String): Unit {
    throw IllegalStateException("CJC_ABORT: ${message}")
}

public func CJC_NULLPTR_CHECK<T>(value: Option<T>): Unit {
    if (let None <- value) {
        throw IllegalArgumentException("null pointer")
    }
}

