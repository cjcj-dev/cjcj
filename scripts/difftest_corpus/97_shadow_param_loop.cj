func g(n: Int64): Int64 { var acc = 0; for (n in 0..3) { acc += n }; return acc + n }
main() { println(g(100)) }
