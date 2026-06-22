var Events: String = ""

func mark(name: String, value: Int64): Int64 {
    Events = Events + name
    return value
}

var C: Int64 = mark("c", 1)
var B: Int64 = C + mark("b", 20)
var A: Int64 = B + mark("a", 100)
var D: Int64 = A + B + C + mark("d", 1000)

main() {
    println(Events)
    println(A)
    println(B)
    println(C)
    println(D)
}
