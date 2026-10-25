package constructor_receiver

open class Base {
    public var value: Int64 = 0
    public init(value: Int64) { this.value = value }
    public func read(): Int64 { value }
}
class Finalized <: Base {
    public init(value: Int64) { super(value); this.value = this.value + 1 }
    public init() { this(40) }
    ~init() {}
}
class Ordinary <: Base {
    public init(value: Int64) { super(value); this.value = this.value + 2 }
}
class Throwing <: Base {
    public init() { super(0); throw Exception("constructor-abort") }
    ~init() {}
}
struct Control {
    public let value: Int64
    public init(value: Int64) { this.value = value }
}
main(): Int64 {
    let root = Object()
    let finalizable = Finalized()
    let ordinary = Ordinary(40)
    if (finalizable.read() != 41 || ordinary.read() != 42 || Control(43).value != 43) { return 1 }
    var caught = false
    try {
        let _ = Throwing()
    } catch (e: Exception) {
        caught = e.message == "constructor-abort"
    }
    if (!caught) { return 2 }
    var boundsCaught = false
    try {
        let data = [1, 2]
        let _ = data[ordinary.read()]
    } catch (_: IndexOutOfBoundsException) {
        boundsCaught = true
    }
    if (!boundsCaught) { return 4 }
    if (!refEq(root, root) || !refEq(finalizable, finalizable)) { return 3 }
    println("CONSTRUCTOR_RECEIVER normal=41 ordinary=42 struct=43 exception=caught root=valid")
    return 0
}
