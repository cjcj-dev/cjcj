package modalcollsetter

public class Item {
    public init() {}
    public exclave init(this @local!) {}
}

public class Cell<V> {
    public demode var hits: Int64 = 0
    public init() {}
    public exclave init(this @local!) {}
    public func put(v: V): Unit {
        hits += 1
    }
    public exclave func put(this @local!, v: V @local!): Unit {
        hits += 10
    }
    // Same shape as HashMapEntryView.value: the setter value has the property mode.
    public mut prop value: ?V @local! {
        get() {
            None
        }
        set(v) {
            exclave {
                match (v) {
                    case Some(x) => put(x)
                    case None => ()
                }
            }
        }
    }
}

main(): Int64 {
    let cell = Cell<Item>() @local!
    cell.value = Some(Item() @local!)
    if (cell.hits == 10) { 0 } else { 1 }
}
