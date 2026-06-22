struct Inner {
    var v: Int64
    init(a: Int64) {
        v = a
    }
}

struct Outer {
    var i: Inner
    var n: Int64
    init(a: Int64, b: Int64) {
        i = Inner(a)
        n = b
    }
}

func get(o: Outer): Int64 {
    return o.i.v + o.n
}

main() {
    let o = Outer(5, 6)
    println(get(o))
    println(o.i.v)
}
