class Box {
    Box(let v: Int64) {}
}
main() {
    let a = [[Box(1), Box(2)], [Box(3), Box(4)]]
    println(a[0][0].v)
}
