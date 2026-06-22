func mark(x: Int64): Int64 { println(x); return x }
func make(): () -> Int64 { return { => 3 } }

main() {
    let f = mark
    f
    (7)
    let g = make()
    g
    { => 5 }
    println(g())
}
