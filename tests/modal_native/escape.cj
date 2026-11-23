package rejected_consumer

class Cell {
    public exclave init(this @local!) {}
}

func escape(): Cell {
    let c = Cell() @local!
    return c
}

class Link {
    public let value: Cell
    public exclave init(this @local!, value: Cell @local!) { this.value = value }
}

func projected(flag: Bool, outer: Link @local!): Cell @local! {
    let item = Cell() @local!
    let inner = Link(item) @local!
    return (if (flag) { outer } else { inner }).value
}

main(): Int64 { return 0 }
