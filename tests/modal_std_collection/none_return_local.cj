package modalcollnone

public class Item {
    public init() {}
    public exclave init(this @local!) {}
}

// Same shape as ArrayList.get / iterator next (array_list.cj:176/494): a nullary enum value is
// returned from an exclave function whose result slot is `?T @local!`.
exclave func pick<T>(all: Array<T> @local!, want: Bool): ?T @local! {
    if (!want) {
        return Option<T>.None
    }
    let v: Option<T> @local! = Option<T>.Some(all[0])
    return v
}

main(): Int64 {
    let items: Array<Item> @local! = [Item() @local!]
    let b = pick<Item>(items, false)
    match (b) {
        case None => 0
        case Some(_) => 1
    }
}
