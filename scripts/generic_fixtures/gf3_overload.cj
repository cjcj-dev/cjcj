func conv<T>(x: T): String { let _ = x; return "generic" }
func conv(x: Int64): String { let _ = x; return "int" }
main(): Int64 {
    println(conv(5))
    println(conv("s"))
    return 0
}
