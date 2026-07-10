class AggregateRef {}

struct AggregatePair {
    var ref: AggregateRef

    init(ref: AggregateRef) {
        this.ref = ref
    }
}

@NoWriteBarrierRec
func aggregateBarrier(values: Array<AggregatePair>, value: AggregatePair): Unit {
    values[0] = value
}

main() {
    let ref = AggregateRef()
    let value = AggregatePair(ref)
    aggregateBarrier([value], value)
}
