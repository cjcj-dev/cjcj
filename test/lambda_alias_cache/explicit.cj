func take(f: () -> Int64): Int64 {
    f()
}

func take(f: (Int64) -> Int64): Int64 {
    f(1)
}

func add(x: Int64): Int64 {
    x
}

main(): Int64 {
    take({ p: Int64 =>
        let (x, y) = (p, p)
        add(x) + y
    })
}
