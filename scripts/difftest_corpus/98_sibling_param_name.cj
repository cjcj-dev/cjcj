func helper(): Int64 { return 100 }
func f(helper: Int64): Int64 { return helper + 1 }
main() { println(f(7) + helper()) }
