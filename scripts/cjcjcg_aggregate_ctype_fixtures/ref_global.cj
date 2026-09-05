struct GlobalRefLeaf {
    var index: Int64
    var text: String

    init(index: Int64, text: String) {
        this.index = index
        this.text = text
    }
}

struct GlobalRefOuter {
    var leaf: GlobalRefLeaf
    var tag: Int64

    init(leaf: GlobalRefLeaf, tag: Int64) {
        this.leaf = leaf
        this.tag = tag
    }
}

var GlobalValue = GlobalRefOuter(GlobalRefLeaf(1, "global"), 2)

func globalRefRead(): String {
    let copied = GlobalValue
    return copied.leaf.text
}

main() {
    if (globalRefRead() != "global") {
        throw Exception("global aggregate mismatch")
    }
}
