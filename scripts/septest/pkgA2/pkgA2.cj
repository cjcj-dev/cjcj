package pkgA2

public class Meter <: Describer {
    public let value: Int64

    public init(x: Int64) {
        value = x
    }

    public func doubled(): Int64 {
        return value * 2
    }

    public func describe(): String {
        return "meter"
    }
}

public interface Describer {
    func describe(): String
}

public class IntStore {
    let stored: Int64

    public init(x: Int64) {
        stored = x
    }

    public func get(): Int64 {
        return stored
    }
}

public enum Choice {
    Empty | Num(Int64) | Pair(Int64, Int64)
}

public class Cargo<T> {
    public let item: T

    public init(x: T) {
        item = x
    }

    public func get(): T {
        return item
    }
}
