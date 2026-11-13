import withti_dispatch.*
import std.runtime.*

func require(ok: Bool, marker: String): Unit {
    if (!ok) { throw IllegalStateException(marker) }
    println(marker)
}
main(): Int64 {
    let left = Cell(11)
    let right = Cell(23)
    require(left.value + right.value == 34, "DISPATCH_INDEPENDENT_CONTROL_PASS")
    let view: Dispatch<Cell> = DynamicParcel<Cell>(left, right)
    let boxed = invokeBox<Cell>(view, { => left.value = 13 })
    let result = (boxed as DynamicParcel<Cell>).getOrThrow()
    require(result.tag == 17, "DISPATCH_BOX_LAYOUT_PASS")
    require(result.value.value == 13 && result.tail.value == 23, "DISPATCH_BOX_REFERENCES_PASS")
    let saved = Holder(DynamicParcel<Cell>(Cell(0), Cell(0)))
    invokeSave<Cell>(view, saved, { => right.value = 29 })
    gc(heavy: true)
    require(saved.value.tag == 17, "DISPATCH_STORE_LAYOUT_PASS")
    require(saved.value.value.value == 13 && saved.value.tail.value == 29,
        "DISPATCH_STORE_REFERENCES_PASS")
    return 0
}
