enum Tree<T> {
    Leaf(T) | Node(Tree<T>, Tree<T>)
}

func sumTree(t: Tree<Int64>): Int64 {
    match (t) {
        case Leaf(v) => v
        case Node(l, r) => sumTree(l) + sumTree(r)
    }
}

main() {
    let t = Node(Node(Leaf(1), Leaf(2)), Leaf(3))
    println(sumTree(t))
}
