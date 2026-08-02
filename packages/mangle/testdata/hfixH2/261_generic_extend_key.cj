package hfixh2_261

public struct Box<T> {
    public init() {}
}

extend Box<Int64> {
    public func numberTag(): Int64 {
        return 64
    }
}

extend Box<String> {
    public func stringTag(): Int64 {
        return 8
    }
}
