package cangjie_compiler::utils

public func Is<T>(value: Any): Bool {
    return value is T
}

public func As<T>(value: Any): Option<T> {
    if (value is T) {
        return value as T
    }
    return None
}

