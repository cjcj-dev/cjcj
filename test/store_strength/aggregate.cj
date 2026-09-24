// A value record embedded in a heap object has no object header of its own.
// Its String/reference slots have compile-time strong access semantics.
public class AggregateValue {}

public struct AggregateToken {
    public var kind: UInt32 = 144
    public var delimiterNum: UInt32 = 1
    public var padding: UInt64 = 0
    public var text: String = ""
    public var reference = AggregateValue()

    public mut func aggregateStringStore(value: String): Unit { text = value }
    public mut func aggregateReferenceStore(value: AggregateValue): Unit { reference = value }
}

public class AggregateHolder {
    public var token = AggregateToken()
    public var reference = AggregateValue()

    public func ordinaryReferenceStore(value: AggregateValue): Unit { reference = value }
    public func update(value: String): Unit { token.aggregateStringStore(value) }
}

let aggregateHolder = AggregateHolder()

main() {
    let value = AggregateValue()
    aggregateHolder.update("updated")
    aggregateHolder.token.aggregateReferenceStore(value)
    aggregateHolder.ordinaryReferenceStore(value)
    if (aggregateHolder.token.text != "updated") { return 17 }
    println("AGGREGATE_STRING_STORE_OK")
    return 0
}
