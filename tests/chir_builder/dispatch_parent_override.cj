package dispatch_parent_override
open class Parent {
    public open func read(): Int64 { return 11 }
}
open class Override <: Parent {
    public open override func read(): Int64 { return 23 }
}
class Leaf <: Override {
    public override func read(): Int64 { return 47 }
}
func call(value: Override): Int64 { return value.read() }
main(): Int64 {
    println(call(Leaf()))
    return 0
}
