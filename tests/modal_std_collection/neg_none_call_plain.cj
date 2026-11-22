package modalcollnegnone

public class Item {
    public init() {}
    public exclave init(this @local!) {}
}

// Negative control: only a nullary enum value fits every slot; a constructor call carrying a
// non-local payload must not fill a `?T @local!` result slot.
exclave func wrap<T>(x: T): ?T @local! {
    return Option<T>.Some(x)
}

main(): Int64 {
    let r = wrap<Item>(Item())
    0
}
