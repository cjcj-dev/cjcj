package serializer_queue

public class QueueItem {
    public let value: Int64
    public init(value: Int64) { this.value = value }
    public func next(): QueueItem { QueueItem(value + 1) }
}

public func first(value: Int64): Int64 {
    let item = QueueItem(value)
    return item.next().value
}

public func second(value: Int64): Int64 { first(value) + first(value + 2) }
