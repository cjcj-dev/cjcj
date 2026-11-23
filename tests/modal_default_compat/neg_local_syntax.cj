// Negative control: local-mode syntax must stay a compile-time diagnostic without --enable-local-mode.
class C {
    var v: Int64 = 1
}

main(): Int64 {
    let c: C @local! = C()
    c.v
}
