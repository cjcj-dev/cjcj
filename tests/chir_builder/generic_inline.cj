package builder_generic_inline
class Impl {
    public let value: Int64 = 29
}
func identity<T>(value: T): T {
    var local = value
    return local
}
main(): Int64 {
    let result: Impl = identity<Impl>(Impl())
    return result.value
}
