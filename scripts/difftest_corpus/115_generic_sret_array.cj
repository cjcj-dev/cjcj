struct Cell {
    let value: Int64
    init(v: Int64) {
        value = v
    }
}

func wrap<T>(_: T): Cell {
    return Cell(7)
}

main() {
    let strings = Array<String>(2, repeat: "x")
    println(strings[0])
    let ints = Array<Int64>(3, repeat: 0)
    println(ints[2])
    let cell = wrap<String>("ok")
    println(cell.value)
}
