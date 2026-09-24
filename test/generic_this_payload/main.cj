class PayloadNode {
    public let id: Int64
    public init(id: Int64) { this.id = id }
}

struct GenericReceiver<T> {
    let payload: T
    var node: PayloadNode

    public init(payload: T, node: PayloadNode) {
        this.payload = payload
        this.node = node
    }

    public func readNode(): PayloadNode { node }
    public func readPayload(): T { payload }
    public mut func replaceNode(node: PayloadNode): Unit { this.node = node }
}

class ReceiverHolder<T> {
    var receiver: GenericReceiver<T>
    public init(payload: T, node: PayloadNode) {
        receiver = GenericReceiver<T>(payload, node)
    }
    public func replace(node: PayloadNode): Unit { receiver.replaceNode(node) }
    public func read(): PayloadNode { receiver.readNode() }
}

struct ConcreteReceiver {
    let node: PayloadNode
    public init(node: PayloadNode) { this.node = node }
    public func concreteRead(): PayloadNode { node }
}

main() {
    let first = PayloadNode(17)
    let second = PayloadNode(29)
    let receiver = GenericReceiver<String>("payload", first)
    if (receiver.readNode().id != 17 || receiver.readPayload() != "payload") {
        throw Exception("generic receiver copy result mismatch")
    }
    let holder = ReceiverHolder<String>("other", first)
    holder.replace(second)
    if (holder.read().id != 29 || ConcreteReceiver(first).concreteRead().id != 17) {
        throw Exception("receiver control result mismatch")
    }
    println("GENERIC_THIS_PAYLOAD_OK")
    0
}
