package dispatch_extend
interface Reader {
    func read(): Int64
}
struct Value {
    let number: Int64
    public init(number: Int64) { this.number = number }
}
extend Value <: Reader {
    public func read(): Int64 { return number }
}
func call<T>(value: T): Int64 where T <: Reader { return value.read() }
main(): Int64 {
    println(call(Value(37)))
    return 0
}
