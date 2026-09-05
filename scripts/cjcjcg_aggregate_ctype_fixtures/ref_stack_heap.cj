struct RefLeafValue {
    var index: Int64
    var text: String

    init(index: Int64, text: String) {
        this.index = index
        this.text = text
    }
}

struct RefOuterValue {
    var leaf: RefLeafValue
    var tag: Int64

    init(leaf: RefLeafValue, tag: Int64) {
        this.leaf = leaf
        this.tag = tag
    }

    func stackRead(): String {
        return leaf.text
    }
}

class RefHeapValue {
    var payload: RefOuterValue = RefOuterValue(RefLeafValue(1, "heap"), 2)

    func heapRead(): String {
        return payload.stackRead()
    }
}

main() {
    let stack = RefOuterValue(RefLeafValue(3, "stack"), 4)
    if (stack.stackRead() != "stack" || RefHeapValue().heapRead() != "heap") {
        throw Exception("reference aggregate mismatch")
    }
}
