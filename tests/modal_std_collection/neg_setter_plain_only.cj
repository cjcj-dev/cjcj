package modalcollnegsetter

public class Item {
    public init() {}
    public exclave init(this @local!) {}
}

func keepPlain(x: Item): Unit {}

public class Cell {
    public init() {}
    public exclave init(this @local!) {}
    // Negative control: a @local! setter value must not reach a non-local parameter.
    public mut prop value: ?Item @local! {
        get() {
            None
        }
        set(v) {
            exclave {
                match (v) {
                    case Some(x) => keepPlain(x)
                    case None => ()
                }
            }
        }
    }
}

main(): Int64 {
    let cell = Cell() @local!
    cell.value = Some(Item() @local!)
    0
}
