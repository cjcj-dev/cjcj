package generic_substitution_diagnostic
func same<T>(left: T, right: T): T { left }
main(): Int64 {
    let _: Int64 = same<Int64>(17, "incompatible")
    return 0
}
