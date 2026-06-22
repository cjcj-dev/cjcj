let A: Int64 = 1
var B: Int64 = 2
let Text: String = "ok"
let Mark: Rune = r'a'
var Flag: Bool = true
let Ratio: Float64 = 1.5
var C: Int64 = 2 + 3

func readGlobals(): Int64 {
    if (Text == "ok" && Mark == r'a' && Flag) {
        return A + B + C
    }
    return -1
}

func mutate(): Unit {
    B = B + 10
    C = C + B
    Flag = false
}

main() {
    println(A)
    println(B)
    println(Text)
    println(Flag)
    println(Ratio)
    println(C)
    println(readGlobals())
    mutate()
    println(B)
    println(C)
    println(Flag)
    println(readGlobals())
}
