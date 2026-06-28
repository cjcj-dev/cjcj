package cangjie_compiler::utils

foreign {
    func abort(): Unit
}

@When[debug]
public func CJC_ASSERT(condition: Bool): Unit {
    if (!condition) {
        unsafe { abort() }
    }
}

@When[!debug]
public func CJC_ASSERT(condition: Bool): Unit {
    let _ = condition
}

@When[debug]
public func CJC_ASSERT_WITH_MSG(condition: Bool, message: String): Unit {
    if (!condition) {
        eprintln("CJC_ASSERT failed: ${message}")
        unsafe { abort() }
    }
}

@When[!debug]
public func CJC_ASSERT_WITH_MSG(condition: Bool, message: String): Unit {
    let _ = condition
    let _ = message
}

@When[debug]
public func CJC_ABORT(): Unit {
    unsafe { abort() }
}

@When[!debug]
public func CJC_ABORT(): Unit {}

@When[debug]
public func CJC_ABORT_WITH_MSG(message: String): Unit {
    eprintln("CJC_ABORT: ${message}")
    unsafe { abort() }
}

@When[!debug]
public func CJC_ABORT_WITH_MSG(message: String): Unit {
    let _ = message
}

public func CJC_NULLPTR_CHECK<T>(value: Option<T>): Unit {
    if (let None <- value) {
        CJC_ASSERT(false)
    }
}
