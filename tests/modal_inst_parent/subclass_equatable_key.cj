package modalinstparent

import std.collection.*

// cjcj::ast shape (Node.cj:59, DeclNodes.cj:16): both levels of a class hierarchy implement Equatable at their
// own type, so std HashMap<Decl, V> and HashSet<Decl> reach Equal<K>.eq(this @local?, rhs: K @local?) through
// two parents, Equal<Decl> and Equal<Node>. The call passes a plain Decl to the `K @local?` parameter.
// Decl.== also compares `tag`, so a lookup dispatched through Equal<Node> would find a key that differs only
// in `tag`; the hash ignores `tag`, so such keys share a bucket.
open class Node <: Hashable & Equatable<Node> {
    let id: Int64
    init(id: Int64) { this.id = id }
    public operator func ==(right: Node): Bool { id == right.id }
    public operator func !=(right: Node): Bool { id != right.id }
    public func hashCode(): Int64 { id.hashCode() }
}

open class Decl <: Node & Hashable & Equatable<Decl> {
    let tag: Int64
    init(id: Int64, tag: Int64) {
        super(id)
        this.tag = tag
    }
    public operator func ==(right: Decl): Bool { id == right.id && tag == right.tag }
    public operator func !=(right: Decl): Bool { !(this == right) }
}

main(): Int64 {
    let owner = HashMap<Decl, Int64>()
    owner.add(Decl(1, 1), 10)
    if (owner.get(Decl(1, 1)) != Some(10)) { return 1 }
    if (owner.contains(Decl(1, 2))) { return 2 }
    let touches = HashSet<Decl>()
    touches.add(Decl(2, 1))
    if (!touches.contains(Decl(2, 1)) || touches.contains(Decl(2, 2))) { return 3 }
    let nodes = HashSet<Node>()
    nodes.add(Decl(3, 1))
    if (!nodes.contains(Decl(3, 2))) { return 4 }
    return 0
}
