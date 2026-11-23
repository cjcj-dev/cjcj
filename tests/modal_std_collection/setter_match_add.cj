package modalcollsettermatch

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
        None
    }
}

// Same shape as HashMapEntryView.value (hash_map.cj:529): the setter value of a @local! property is
// matched, and the bound payload is passed to the @local! overload of a member of a local field.
public class View<K, V> {
    let map: Store<K, V>
    let _key: K
    public init(map: Store<K, V>, key: K) {
        this.map = map
        this._key = key
    }
    public exclave init(this @local!, map: Store<K, V> @local!, key: K @local!) {
        this.map = map
        this._key = key
    }
    public mut prop value: ?V @local! {
        get() {
            None
        }
        set(v) {
            exclave {
                match (v) {
                    case Some(x) =>
                        let old: ?V @local? = map.add(_key, x)
                        let _ = old
                    case None => ()
                }
            }
        }
    }
}

main(): Int64 {
    let store = Store<Item, Item>() @local!
    let view = View<Item, Item>(store, Item() @local!) @local!
    view.value = Some(Item() @local!)
    if (store.hits == 10) { 0 } else { 1 }
}
