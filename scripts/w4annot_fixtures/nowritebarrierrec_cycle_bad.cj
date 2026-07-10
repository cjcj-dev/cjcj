class CycleItem {}

class CycleHolder {
    var item: CycleItem

    init(value: CycleItem) {
        item = value
    }
}

func cycleA(value: CycleItem, count: Int64): CycleHolder {
    if (count == 0) {
        return CycleHolder(value)
    }
    return cycleB(value, count - 1)
}

func cycleB(value: CycleItem, count: Int64): CycleHolder {
    return cycleA(value, count)
}

@NoWriteBarrierRec
func cycleRoot(value: CycleItem): CycleHolder {
    return cycleA(value, 1)
}

main() {
    let _ = cycleRoot(CycleItem())
}
