package cangjie_compiler::utils

foreign {
    func abort(): Unit
}

private func AbortProcess(): Unit {
    unsafe {
        abort()
    }
}

public func CJC_ASSERT(condition: Bool): Unit {
    if (!condition) {
        AbortProcess()
    }
}

public func CJC_ASSERT_WITH_MSG(condition: Bool, message: String): Unit {
    if (!condition) {
        eprintln("CJC_ASSERT failed: ${message}")
        AbortProcess()
    }
}

public func CJC_ABORT(): Unit {
    AbortProcess()
}

public func CJC_ABORT_WITH_MSG(message: String): Unit {
    eprintln("CJC_ABORT: ${message}")
    AbortProcess()
}

public func CJC_NULLPTR_CHECK<T>(value: Option<T>): Unit {
    if (let None <- value) {
        CJC_ASSERT(false)
    }
}
