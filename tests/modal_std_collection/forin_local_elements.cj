package modalcollforin

public class Item {
    public init() {}
    public exclave init(this @local!) {}
}

public class Bag<K> {
    public demode var hits: Int64 = 0
    public init() {}
    public exclave init(this @local!) {}
    public func add(key: K): Int64 {
        hits += 1
        hits
    }
    public exclave func add(this @local!, key: K @local!): Int64 {
        hits += 10
        hits
    }
    // Same shape as HashMap.add(all!:) and HashSet.add(all!:): an element of a @local! collection
    // selects the @local! overload inside the loop body.
    public exclave func addAll(this @local!, all: Array<K> @local!): Unit {
        for (k in all) {
            add(k)
        }
    }
}

main(): Int64 {
    let bag = Bag<Item>() @local!
    let items: Array<Item> @local! = [Item() @local!, Item() @local!]
    bag.addAll(items)
    if (bag.hits == 20) { 0 } else { 1 }
}
