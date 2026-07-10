enum TupleChoice<T> {
    | Present(T)
    | Missing
}

@NoWriteBarrierRec
func tupleBarrier<T>(value: T): TupleChoice<T> {
    return TupleChoice<T>.Present(value)
}

main() {
    let _ = tupleBarrier<Int64>(1)
}
