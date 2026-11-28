import frozenmodals.FrozenBox

main(): Int64 {
    let box = FrozenBox<Int64>()
    if (box.plain() == 42) { 0 } else { 1 }
}
