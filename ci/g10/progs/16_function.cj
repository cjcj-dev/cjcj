// G10 valid-program negative control: function.
func twice(x: Int64): Int64 { x * 2 }
main(): Int64 {
    if (twice(21) != 42) { return 1 }
    return 0
}
