class BoxRef {}

struct BoxPair {
    var ref: BoxRef

    init(ref: BoxRef) {
        this.ref = ref
    }
}

@NoWriteBarrierRec
func boxBarrier(value: BoxPair): Any {
    return value
}

main() {
    let _ = boxBarrier(BoxPair(BoxRef()))
}
