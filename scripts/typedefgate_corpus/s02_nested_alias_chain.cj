type A = Int64
type B = A
type C = B
main(): Int64 {
    let x: C = 7
    let y: A = x
    println(x + y)
    0
}
