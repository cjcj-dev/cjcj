func choose(flag: Bool): Option<Int64> {
    if (flag) {
        let seed = 40
        return Some(seed + 2)
    }
    return None
}

func id(x: Int64): Int64 { return x }

main() {
    var result = 0
    if (let Some(value) <- choose(true)) {
        result = id(value)
    } else {
        result = id(0)
    }
    println(result)
}
