// G10 valid-program negative control: recursion.
func fact(x: Int64): Int64 { if (x < 2) { return 1 }; x * fact(x - 1) }
main(): Int64 {
    if (fact(5) != 120) { return 1 }
    return 0
}
