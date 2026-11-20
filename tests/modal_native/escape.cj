package rejected_consumer

class Cell {
    public exclave init(this @local!) {}
}

func escape(): Cell {
    let c = Cell() @local!
    return c
}

main(): Int64 { return 0 }
