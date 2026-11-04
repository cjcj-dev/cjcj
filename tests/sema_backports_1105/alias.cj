type Count = Int64
type Chained = Count
type Word = UInt16
type Real = Float32
type Codepoint = Rune
func choose(x: Int64): Int64 { x + 1 }
func choose(x: Float32): Int64 { Int64(x) + 2 }
main(): Int64 {
    let a = Chained(40)
    let b: Word = Word(20.5)
    let c: Real = Real(a)
    let r: Codepoint = Codepoint(97)
    if (a != 40 || b != 20 || c != 40.0 || UInt32(r) != 97 || choose(Count(1)) != 2) { return 1 }
    // Primitive and ordinary constructor controls use the same source entry.
    if (UInt16(20.5) != b || Int64(40) != a) { return 2 }
    println("ALIAS_CONVERSION_OK")
    return 0
}
