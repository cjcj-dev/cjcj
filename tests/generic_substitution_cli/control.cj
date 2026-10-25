package generic_substitution_control
func same<T>(left: T, right: T): T { left }
main(): Int64 {
    if (same<Int64>(17, 31) != 17) { return 1 }
    println("ASSERT generic_control=PASS")
    return 0
}
