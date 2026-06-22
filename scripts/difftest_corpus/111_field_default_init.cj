class C {
    public var x = 5
    public let y = 7
    public let s = "ok"
    public let b = true
    public func sum(): Int64 {
        if (b && s == "ok") {
            return x + y
        }
        return 0
    }
}

class Explicit {
    public var x = 9
    public var y: Int64
    public init(v: Int64) {
        y = v
    }
    public func sum(): Int64 {
        return x + y
    }
}

class Delegated {
    public var x = 3
    public init() {
        this(4)
    }
    public init(v: Int64) {
        x = v
    }
    public func get(): Int64 {
        return x
    }
}

struct S {
    public var a = 11
    public let b = true
    public func get(): Int64 {
        if (b) {
            return a
        }
        return 0
    }
}

main() {
    println(C().sum())
    println(Explicit(6).sum())
    println(Delegated().get())
    println(S().get())
}
