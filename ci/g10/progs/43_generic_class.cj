// G10 valid-program negative control: generic_class.
class Box<T> { let value: T; init(v: T) { value = v }; func get(): T { value } }
main(): Int64 {
    let b = Box<Int64>(42)
    if (b.get() != 42) { return 1 }
    return 0
}
