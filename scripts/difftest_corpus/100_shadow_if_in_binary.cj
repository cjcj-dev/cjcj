func f(x: Int64): Int64 { return 1 + (if (x > 0) { let x = 7; x } else { 0 }) }
main() { println(f(5)) }
