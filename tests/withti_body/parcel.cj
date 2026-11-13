package withti_body

import std.runtime.*

public class Cell {
    public var value: Int64
    public init(value: Int64) { this.value = value }
}

public class Holder<T> {
    public var value: T
    public init(value: T) { this.value = value }
}

public struct Parcel<T> {
    public var tag: Int64
    public var value: T
    public var tail: Cell
    public init(value: T, tail: Cell) {
        tag = 17
        this.value = value
        this.tail = tail
    }
    public mut func replace(value: T, tail: Cell): Unit {
        tag = 71
        this.value = value
        this.tail = tail
    }
    public func boxed(hook: () -> Unit): Any {
        hook()
        gc(heavy: true)
        return this
    }
    public func save(holder: Holder<Parcel<T>>, hook: () -> Unit): Unit {
        hook()
        gc(heavy: true)
        holder.value = this
    }
}
