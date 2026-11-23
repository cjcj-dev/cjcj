package modalcolltuple

public class Item {
    public init() {}
    public exclave init(this @local!) {}
}

public class Store<K, V> {
    public demode var hits: Int64 = 0
    public init() {}
    public exclave init(this @local!) {}
    public func add(key: K, value: V): Option<V> {
        hits += 1
        None
    }
    public exclave func add(this @local!, key: K @local!, value: V @local!): Option<V> @local! {
        hits += 10
        return Option<V>.None
    }
    // Same shape as HashMap.init(elements) / add(all!:) (hash_map.cj:706/1154): tuple elements of a
    // @local! collection select the @local! overload, and the loop body ends in its @local! result.
    public exclave func addAll(this @local!, all: Array<(K, V)> @local!): Unit {
        for ((k, v) in all) {
            add(k, v)
        }
    }
}

main(): Int64 {
    let s = Store<Item, Item>() @local!
    let items: Array<(Item, Item)> @local! = [(Item() @local!, Item() @local!)]
    s.addAll(items)
    if (s.hits == 10) { 0 } else { 1 }
}
