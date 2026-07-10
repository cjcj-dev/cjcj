package cjcj::utils

public func Is<T>(value: Any): Bool {
    return value is T
}

public func As<T>(value: Any): Option<T> {
    if (value is T) {
        return value as T
    }
    return None
}

public func DynamicCast<T>(value: Any): Option<T> {
    return As<T>(value)
}

public func StaticCast<T>(value: Any): T {
    return (value as T).getOrThrow()
}

public func RawStaticCast<T>(value: Any): T {
    return (value as T).getOrThrow()
}
