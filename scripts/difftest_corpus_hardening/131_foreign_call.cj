foreign func abs(x: Int32): Int32

main() {
    let r = unsafe { abs(-7) }
    println(r)
}
