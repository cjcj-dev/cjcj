// Concrete no-reference aggregates exercise both codegen exits and recursive
// struct -> fixed-array -> struct descent.  The named functions are intentionally
// small so the IR gate can bind each destination/source root independently.
public struct HeapAggLeaf {
    var x: UInt32
    var y: UInt32

    public init(x: UInt32, y: UInt32) {
        this.x = x
        this.y = y
    }
}

public struct HeapAggValue {
    var leaves: VArray<HeapAggLeaf, $2>
    var tag: UInt32

    public init(seed: UInt32) {
        leaves = VArray<HeapAggLeaf, $2>({ index: Int64 =>
            HeapAggLeaf(seed + UInt32(index), seed + UInt32(index) + 1u32)
        })
        tag = seed
    }
}

class HeapAggHolder {
    var value: HeapAggValue = HeapAggValue(0u32)

    func updateFromArgument(value: HeapAggValue): Unit {
        this.value = value
    }

    func updateFromAlloca(): Unit {
        var local = HeapAggValue(10u32)
        this.value = local
    }
}

func callRoot(value: HeapAggValue): HeapAggHolder {
    let holder = HeapAggHolder()
    holder.value = value
    return holder
}

func phiRoot(first: Bool, value: HeapAggValue): HeapAggHolder {
    var holder = if (first) { HeapAggHolder() } else { HeapAggHolder() }
    holder.value = value
    return holder
}

// A plain struct assignment is the narrow route through ArrayImpl's
// TryStoreStructPtrValueForAddress fallback.
func arrayImplExit(value: HeapAggValue): HeapAggValue {
    var result = HeapAggValue(20u32)
    result = value
    return result
}

// Neighbour-family control: constant RawArray materialization keeps its existing
// raw copy lowering and must not be captured by the concrete aggregate copier.
func constArrayControl(): Array<UInt8> {
    return [1u8, 2u8, 3u8, 4u8]
}

// Negative control: reference-bearing aggregates remain on the GC write path.
public struct HeapAggRefPair {
    var left: String
    var right: String

    public init(left: String, right: String) {
        this.left = left
        this.right = right
    }
}

class HeapAggRefHolder {
    var pair: HeapAggRefPair = HeapAggRefPair("left", "right")

    func update(value: HeapAggRefPair): Unit {
        pair = value
    }
}

main() {
    let value = HeapAggValue(1u32)
    let argumentHolder = HeapAggHolder()
    argumentHolder.updateFromArgument(value)
    let allocaHolder = HeapAggHolder()
    allocaHolder.updateFromAlloca()
    let _ = callRoot(value)
    let _ = phiRoot(true, value)
    let _ = arrayImplExit(value)
    let _ = constArrayControl()
    let refHolder = HeapAggRefHolder()
    refHolder.update(HeapAggRefPair("new-left", "new-right"))
}
