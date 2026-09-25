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
    take({ p =>
        var n = 0
        while (let Some(v) <- Some(p)) {
            n = add(v)
            break
        }
        n
    })
}
