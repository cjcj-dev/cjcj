func onlyZero(f: () -> Int64): Int64 {
    f()
}

main(): Int64 {
    onlyZero({ p => p })
}
