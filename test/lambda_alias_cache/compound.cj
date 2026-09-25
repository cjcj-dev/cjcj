func take(f: () -> Int64): Int64 {
    f()
}

func take(f: (Int64) -> Int64): Int64 {
    f(1)
}

func add(x: Int64): Int64 {
    x
}

func cond(x: Int64): Bool {
    x > 0
}

main(): Int64 {
    take({ p =>
        if (let Some(v) <- Some(p) && cond(p)) {
            add(v)
        } else {
            0
        }
    })
}
