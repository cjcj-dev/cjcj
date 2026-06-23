class Point {
    let x: Int64
    let y: Int64

    public init(x: Int64, y: Int64) {
        this.x = x
        this.y = y
    }

    public func label(): String {
        return "P"
    }

    public func toString(): String {
        return "(${x},${y})"
    }
}

main() {
    let a = 3
    let b = 4
    let p = Point(1, 2)
    println("${a} + ${b} = ${a + b}, name=${p.toString()}, lbl=${p.label()}")
}
