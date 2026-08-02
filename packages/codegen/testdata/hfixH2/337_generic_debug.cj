package hfixh2_337

public func identity<T>(value: T): T {
    return value
}

public func useIdentity(): Int64 {
    return identity<Int64>(37)
}
