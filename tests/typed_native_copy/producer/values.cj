package typed_copy_values

public struct NativePair {
    public let first: UInt64
    public let second: UInt64
    public init(first: UInt64, second: UInt64) {
        this.first = first
        this.second = second
    }
}

public func choosePair(flag: Bool, value: UInt64): NativePair {
    if (flag) {
        return NativePair(value, 29u64)
    }
    return NativePair(17u64, value)
}

public func chooseByte(flag: Bool, value: UInt8): Option<UInt8> {
    if (flag) {
        return Some(value)
    }
    return None
}

public struct ReferencePair {
    public let text: String
    public let value: UInt64
    public init(text: String, value: UInt64) {
        this.text = text
        this.value = value
    }
}

public func referenceControl(text: String): ReferencePair {
    return ReferencePair(text, 31u64)
}
