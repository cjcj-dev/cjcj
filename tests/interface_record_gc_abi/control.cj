class Cell {
    public var value: Int64
    public init(value: Int64) { this.value = value }
}
struct Plain {
    public var cell: Cell = Cell(5)
    public mut func replace(): Unit { cell = Cell(9) }
}
main(): Int64 {
    var p = Plain()
    p.replace()
    if (p.cell.value != 9) { throw Exception("plain mut reference receiver changed") }
    println("PLAIN_MUT_REFERENCE_OK")
    return 0
}
