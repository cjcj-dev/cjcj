package canonical_alias_store

import std.convert.*

class Leaf {
    public var value: Int64 = 3
    public func replace(value: Int64): Unit { this.value = value }
}

class Root {
    public let leaf = Leaf()
}

func observe(root: Root, alias: Leaf, value: Int64): Int64 {
    let before = root.leaf.value
    alias.replace(value)
    let afterCall = root.leaf.value
    alias.value = value + 5
    let afterStore = root.leaf.value
    if (before != 3 || afterCall != value || afterStore != value + 5) { return 1 }
    return 0
}

main(args: Array<String>): Int64 {
    if (args.size != 1) { return 2 }
    let value = Int64.parse(args[0])
    let root = Root()
    if (observe(root, root.leaf, value) != 0) { return 3 }
    // A distinct object is the independent no-alias arm.
    let other = Root()
    root.leaf.replace(value + 7)
    if (other.leaf.value != 3) { return 4 }
    println("ASSERT alias_store=PASS")
    return 0
}
