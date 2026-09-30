package mangle_shapes

public interface Value<T> {
    func getValue(): T
}
public class Box<T> <: Value<T> {
    private let stored: T
    public init(stored: T) { this.stored = stored }
    public func getValue(): T { stored }
    public prop value: T { get() { stored } }
}
public struct Pair<T> {
    public let left: T
    public let right: T
    public init(left: T, right: T) { this.left = left; this.right = right }
}
public enum Choice<T> { One(T) | Empty }
public func nested(value: Box<Pair<Int64>>): Int64 { value.getValue().left }
public func callback(f: (Int64) -> Int64, x: Int64): Int64 { f(x) }
public func locals(x: Int64): Int64 {
    let f = { y: Int64 =>
        func local(z: Int64): Int64 { z + y }
        local(x)
    }
    f(x)
}
public func tuple(value: (Int64, Bool)): Int64 { value[0] }
public func optional(value: Option<Int64>): Int64 { value ?? 0 }
public func variadicArray(value: VArray<Int64, $4>): Int64 { value[0] }
