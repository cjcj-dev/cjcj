package installed_string

public class Holder {
    public var text: String
    public init(text: String) { this.text = text }
}
func heapReceiver(h: Holder, needle: String): ?Int64 { h.text.indexOf(needle) }
func heapArgument(text: String, h: Holder): ?Int64 { text.indexOf(h.text) }
func heapBoth(h: Holder, n: Holder): ?Int64 { h.text.indexOf(n.text) }
func heapArray(h: Holder): Array<Byte> { h.text.toArray() }
func plainIndex(text: String, needle: String): ?Int64 { text.indexOf(needle) }
func plainArray(text: String): Array<Byte> { text.toArray() }
func indexIs(value: ?Int64, wanted: Int64): Bool {
    if (let Some(actual) <- value) { return actual == wanted }
    return wanted == -1
}
func bytesAre(actual: Array<Byte>, expected: Array<Byte>): Bool {
    if (actual.size != expected.size) { return false }
    for (i in 0..actual.size) { if (actual[i] != expected[i]) { return false } }
    return true
}
main(args: Array<String>): Int64 {
    var text = ""
    var needle = ""
    var unicode = ""
    var plain = false
    for (arg in args) {
        if (arg == "xxabcabczz") { text = arg }
        if (arg == "bc") { needle = arg }
        if (arg == "仓颉") { unicode = arg }
        if (arg == "plain") { plain = true }
    }
    if (text.size != 10 || needle.size != 2) { println("STRING_INPUT_MISSING"); return 41 }
    if (plain) {
        println("STRING_PLAIN_ASSERTION_REACHED")
        if (!indexIs(plainIndex(text, needle), 3) || !indexIs(plainIndex(text, "q"), -1)) { return 42 }
        println("STRING_PLAIN_PASS")
        return 0
    }
    let h = Holder(text)
    let n = Holder(needle)
    let elements = [text, needle]
    println("STRING_INDEX_ASSERTION_REACHED")
    if (!indexIs(heapReceiver(h, needle), 3) || !indexIs(heapArgument(text, n), 3)
        || !indexIs(heapBoth(h, n), 3) || !indexIs(plainIndex(elements[0], elements[1]), 3)
        || !indexIs(plainIndex(text, ""), 0) || !indexIs(plainIndex(text, "b"), 3)
        || !indexIs(plainIndex(text, "q"), -1) || !indexIs(plainIndex(text, "xyz"), -1)
        || !indexIs(plainIndex(text[2..8], needle), 1)) { return 42 }
    println("STRING_ARRAY_ASSERTION_REACHED")
    let sliced = heapArray(Holder(text[2..8]))
    if (!bytesAre(sliced, [97u8,98u8,99u8,97u8,98u8,99u8])) { return 42 }
    if (!bytesAre(plainArray(""), []) || !bytesAre(plainArray("abc"), [97u8,98u8,99u8])) { return 42 }
    if (!bytesAre(plainArray(unicode), [228u8,187u8,147u8,233u8,162u8,137u8])) { return 42 }
    sliced[0] = 120u8
    if (text[2] != 97u8 || !indexIs(heapReceiver(h, needle), 3)) { return 42 }
    println("STRING_VALUES_PASS")
    return 0
}
