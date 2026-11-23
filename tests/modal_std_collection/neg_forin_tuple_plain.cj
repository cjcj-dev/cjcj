package modalcollnegtuple

public class Item {
    public init() {}
    public exclave init(this @local!) {}
}

public class Sink<K, V> {
    public init() {}
    public func add(key: K, value: V): Int64 {
        1
    }
}

// Negative control: tuple elements of a @local! collection must not reach non-local parameters.
exclave func feed(sink: Sink<Item, Item>, all: Array<(Item, Item)> @local!): Int64 {
    var n = 0
    for ((k, v) in all) {
        n += sink.add(k, v)
    }
    n
}

main(): Int64 {
    let items: Array<(Item, Item)> @local! = [(Item() @local!, Item() @local!)]
    feed(Sink<Item, Item>(), items)
}
