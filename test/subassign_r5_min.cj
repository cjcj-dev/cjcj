package subassign_r5_min

func victim(module: ?Int64): Unit {
    if (let Some(_) <- module) {
        _ = makeValue()
    }
}

func makeValue(): Bool {
    return true
}

main(): Int64 {
    victim(Some(0))
    return 0
}
