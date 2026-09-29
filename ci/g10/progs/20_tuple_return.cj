// G10 valid-program negative control: tuple_return.
func pair(): (Int64, Int64) { (42, 7) }
main(): Int64 {
    let x = pair()
    if (x[0] != 42 || x[1] != 7) { return 1 }
    return 0
}
