package modalcollnegforin

public class Item {
    public init() {}
    public exclave init(this @local!) {}
}

public class Sink<K> {
    public init() {}
    public func add(key: K): Int64 {
        1
    }
}

// Negative control: an element of a @local! collection must not reach a parameter that
// requires a non-local value.
exclave func feed(sink: Sink<Item>, all: Array<Item> @local!): Int64 {
    var n = 0
    for (k in all) {
        n += sink.add(k)
    }
    n
}

main(): Int64 {
    let items: Array<Item> @local! = [Item() @local!]
    feed(Sink<Item>(), items)
}
