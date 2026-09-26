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
        var s = 0
        for (i in [p]) {
            s = s + add(i)
        }
        s
    })
}
