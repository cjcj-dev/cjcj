import withti_body.*
import std.runtime.*

func require(ok: Bool, marker: String): Unit {
    if (!ok) { throw IllegalStateException(marker) }
    println(marker)
}

main(): Int64 {
    let left = Cell(11)
    let right = Cell(23)
    require(left.value + right.value == 34, "INDEPENDENT_CONTROL_PASS")
    let source = Holder(Parcel<Cell>(left, right))
    let boxed = source.value.boxed({ =>
        source.value.replace(Cell(101), Cell(103))
        left.value = 13
    })
    let copy = (boxed as Parcel<Cell>).getOrThrow()
    require(copy.tag == 17, "BOX_THIS_VALUE_COPY_PASS")
    require(copy.value.value == 13 && copy.tail.value == 23, "BOX_THIS_REFERENCES_PASS")
    require(source.value.tag == 71 && source.value.value.value == 101 && source.value.tail.value == 103,
        "MUTATING_WRITEBACK_PASS")

    let saved = Holder(Parcel<Cell>(Cell(0), Cell(0)))
    let original = Holder(Parcel<Cell>(left, right))
    let escaped = original.value.save
    escaped(saved, { => original.value.replace(Cell(107), Cell(109)) })
    gc(heavy: true)
    require(saved.value.tag == 17, "STORE_THIS_VALUE_COPY_PASS")
    require(saved.value.value.value == 13 && saved.value.tail.value == 23, "STORE_THIS_REFERENCES_PASS")
    require(original.value.tag == 71 && original.value.value.value == 107,
        "ESCAPED_MUTATING_WRITEBACK_PASS")
    return 0
}
