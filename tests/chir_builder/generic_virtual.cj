package builder_generic_virtual
open class Base<U> {
    let value: U
    public init(value: U) { this.value = value }
    public open func get(): U { return value }
}
class Impl <: Base<Int64> {
    public init() { super(23) }
    public override func get(): Int64 { return value }
}
func run<T, U>(value: T): U where T <: Base<U> {
    var receiver = value
    return receiver.get()
}
main(): Int64 { return run<Impl, Int64>(Impl()) }
