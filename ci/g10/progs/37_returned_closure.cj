// G10 valid-program negative control: returned_closure.
func adder(n: Int64): (Int64) -> Int64 { { x => x + n } }
main(): Int64 {
    let f = adder(20)
    if (f(22) != 42) { return 1 }
    return 0
}
