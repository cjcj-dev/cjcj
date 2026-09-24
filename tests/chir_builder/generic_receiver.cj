package builder_generic_receiver
interface Getter<U> {
    func get(): U
}
func capture<T, U>(value: T): () -> U where T <: Getter<U> {
    return value.get
}
class IntGetter <: Getter<Int64> {
    public func get(): Int64 { return 17 }
}
main(): Int64 {
    let getValue = capture<IntGetter, Int64>(IntGetter())
    return getValue()
}
