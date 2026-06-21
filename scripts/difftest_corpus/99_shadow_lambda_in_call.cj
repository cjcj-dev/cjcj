func call(f: () -> Int64): Int64 { return f() }
func f(x: Int64): Int64 { return call({ => let x = 99; x }) }
main() { println(f(5)) }
