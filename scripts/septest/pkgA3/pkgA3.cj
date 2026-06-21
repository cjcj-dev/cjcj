package pkgA3

public struct Step {
    public let value: Int64

    public init(v: Int64) {
        value = v
    }

    public func next(): Int64 {
        return value + 1
    }
}

public type Count = Int64

extend Step {
    public func scaled(factor: Count): Count {
        return value * factor
    }
}
