var evaluationCount: Int64 = 0

struct Empty {}

class EmptyHolder {
    var payload: Empty = Empty()
}

func evaluatedHolder(): EmptyHolder {
    evaluationCount++
    return EmptyHolder()
}

func loadEmpty(): Empty {
    return evaluatedHolder().payload
}

main(): Int64 {
    let _ = loadEmpty()
    if (evaluationCount != 1) {
        throw IllegalStateException("zero-layout operand was not evaluated exactly once")
    }
    println("ZERO_LAYOUT_SIDE_EFFECT_OK count=${evaluationCount}")
    return 0
}
