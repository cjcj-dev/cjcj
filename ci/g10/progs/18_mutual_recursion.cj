// G10 valid-program negative control: mutual_recursion.
func even(x: Int64): Bool { if (x == 0) { return true }; odd(x - 1) }
func odd(x: Int64): Bool { if (x == 0) { return false }; even(x - 1) }
main(): Int64 {
    if (!even(8)) { return 1 }
    return 0
}
