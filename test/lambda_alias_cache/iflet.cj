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
        if (let Some(v) <- Some(p)) {
            add(v)
        } else {
            0
        }
    })
}
