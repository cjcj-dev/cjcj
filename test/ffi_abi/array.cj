@C[align: 16]
struct ArrayElement { var x: UInt8 = 7u8 }
@C
struct ArrayBox {
    var prefix: UInt8 = 3u8
    var values: VArray<ArrayElement, $2> = [ArrayElement(), ArrayElement()]
    var tail: UInt8 = 9u8
}
foreign {
    func c_array(p: ArrayBox): ArrayBox
    func c_array_callbacks(): Int32
}
@C
func cj_array(p: ArrayBox): ArrayBox {
    var q = p
    var first = p.values[0]
    var second = p.values[1]
    first.x += 1u8
    second.x += 2u8
    q.values = [first, second]
    return q
}
main(): Int64 {
    unsafe {
        let q = c_array(ArrayBox())
        if (q.prefix != 3u8 || q.values[0].x != 8u8 || q.values[1].x != 9u8 || q.tail != 9u8) {
            println("FAIL nested overalign array args return copy")
            return 1
        }
        if (c_array_callbacks() != 1i32) { println("FAIL nested overalign array callbacks"); return 2 }
    }
    println("PASS nested overalign array args return copy callbacks")
    return 0
}
