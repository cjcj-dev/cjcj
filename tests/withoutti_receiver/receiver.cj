package receiver_copy

public class Cell {
    public var value: Int64
    public init(value: Int64) { this.value = value }
}

// Two live references, with a non-reference first word and intervening data.
public struct Snapshot<T> {
    public var tag: Int64
    public var first: T
    public var gap: Int64
    public var last: Cell
    public init(first: T, last: Cell) {
        tag = 17
        this.first = first
        gap = 31
        this.last = last
    }
    public mut func replace(first: T, last: Cell): Unit {
        tag = 71
        this.first = first
        this.last = last
    }
    public func observe(hook: () -> Unit): (T, Cell, Int64) {
        hook()
        return (first, last, tag + gap)
    }
    public func fail(hook: () -> Unit): Unit {
        hook()
        throw IllegalStateException("receiver-copy-exception")
    }
}
