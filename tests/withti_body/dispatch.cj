package withti_dispatch

import std.runtime.*

public class Cell {
    public var value: Int64
    public init(value: Int64) { this.value = value }
}
public class Holder<T> {
    public var value: T
    public init(value: T) { this.value = value }
}
public interface Dispatch<T> {
    func boxed(hook: () -> Unit): Any
    func save(holder: Holder<DynamicParcel<T>>, hook: () -> Unit): Unit
}
public struct DynamicParcel<T> <: Dispatch<T> {
    public let tag: Int64 = 17
    public let value: T
    public let tail: Cell
    public init(value: T, tail: Cell) { this.value = value; this.tail = tail }
    public func boxed(hook: () -> Unit): Any {
        hook()
        gc(heavy: true)
        return this
    }
    public func save(holder: Holder<DynamicParcel<T>>, hook: () -> Unit): Unit {
        hook()
        gc(heavy: true)
        holder.value = this
    }
}

// The separately compiled generic callers retain interface dispatch. Concrete
// main calls alone can select the payload entry and miss the with-TI body.
public func invokeBox<T>(value: Dispatch<T>, hook: () -> Unit): Any {
    return value.boxed(hook)
}
public func invokeSave<T>(value: Dispatch<T>, holder: Holder<DynamicParcel<T>>, hook: () -> Unit): Unit {
    value.save(holder, hook)
}
