enum NodeBox {
    Node((Int64, Int64), Int64)
}

main() {
    let Node((a, _), c) = Node((2, 9), 4)
    let ((d, e), f) = ((3, 5), 7)
    println(a * 1000 + c * 100 + d * 10 + e + f)
}
