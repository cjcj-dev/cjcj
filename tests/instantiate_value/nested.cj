package instantiate_nested
func capture<T>(value: T): () -> T {
    func inner<U>(other: U): T { return value }
    let f = inner<Int64>
    return { => f(3) }
}
main(): Int64 { return capture<Int64>(29)() }
