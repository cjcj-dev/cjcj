package sret_reuse

public struct Large {
    public let a: Int64
    public let b: Int64
    public let c: Int64
    public let d: Int64
    public init(x: Int64) { a = x; b = x + 1; c = x + 2; d = x + 3 }
}

public func makeLarge(x: Int64): Large { Large(x) }
public func tailLarge(x: Int64): Large { makeLarge(x) }
public func nonTailLarge(x: Int64): Large {
    let value = makeLarge(x)
    println(x)
    return value
}
public func identity<T>(value: T): T { value }
public func tailGeneric<T>(value: T): T { identity<T>(value) }
public func scalar(x: Int64): Int64 { x + 1 }
public func unitLeaf(): Unit { () }
public func tailUnit(): Unit { unitLeaf() }
