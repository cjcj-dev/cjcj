// G10 valid-program negative control: generic_function.
func identity<T>(x: T): T { x }
main(): Int64 {
    if (identity<Int64>(42) != 42) { return 1 }
    return 0
}
