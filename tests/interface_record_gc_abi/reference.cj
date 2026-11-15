interface DefaultMut {
    mut func inspect(): Int64 { 7 }
}
class Cell {
    public var value: Int64
    public init(value: Int64) { this.value = value }
}
struct WithReference <: DefaultMut {
    public var cell: Cell = Cell(5)
}
main(): Int64 {
    var value = WithReference()
    if (value.inspect() != 7 || value.cell.value != 5) {
        throw Exception("interface adapter changed reference payload")
    }
    println("INTERFACE_REFERENCE_PAYLOAD_OK")
    return 0
}
