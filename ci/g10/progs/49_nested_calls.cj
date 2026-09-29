// G10 valid-program negative control: nested_calls.
func twice(x: Int64): Int64 { x * 2 }
main(): Int64 {
    if (twice(twice(10)) + 2 != 42) { return 1 }
    return 0
}
