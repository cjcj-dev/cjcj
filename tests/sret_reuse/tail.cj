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
// Generic callee sret uses a different LLVM pointer type from the concrete caller.
public func concreteGeneric(value: Large): Large { identity<Large>(value) }
// The callee is sret, but this caller returns a scalar in a register.
public func scalarGeneric(value: Int64): Int64 { identity<Int64>(value) }
// Unknown-size aggregate return exercises the non-generic load/copy branch.
public struct GenericBox<T> {
    public let value: T
    public init(value: T) { this.value = value }
}
public func makeBox<T>(value: T): GenericBox<T> { GenericBox<T>(value) }
public func tailBox<T>(value: T): GenericBox<T> { makeBox<T>(value) }
// Iterator-shaped generic Option return: only the complete Some is built in the
// function's own sret slot; the None arm keeps its box and whole-value copy.
public class SomeForward<T> {
    private var pos: Int64 = 0
    private let data: Array<T>
    public init(data: Array<T>) { this.data = data }
    @OverflowWrapping
    public func nextSome(): Option<T> {
        if (pos < data.size) {
            var v: Option<T> = Some(data[pos])
            this.pos++
            return v
        }
        return None
    }
}
