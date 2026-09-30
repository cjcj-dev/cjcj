// G10 valid-program negative control: generic_array.
func first<T>(xs: Array<T>): T { xs[0] }
main(): Int64 {
    if (first<Int64>([42, 7]) != 42) { return 1 }
    return 0
}
