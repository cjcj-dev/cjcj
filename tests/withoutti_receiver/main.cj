import receiver_copy.*
import std.runtime.*

class ReceiverSource {
    public var value: Snapshot<Cell>
    public init(value: Snapshot<Cell>) { this.value = value }
}

func require(value: Bool, marker: String): Unit {
    if (!value) { throw IllegalStateException(marker) }
    println(marker)
}

main(): Int64 {
    let left = Cell(11)
    let right = Cell(23)
    require(left.value + right.value == 34, "INDEPENDENT_CONTROL_PASS")
    let source = ReceiverSource(Snapshot<Cell>(left, right))
    let observed = source.value.observe({ =>
        source.value.replace(Cell(101), Cell(103))
        left.value = 13
        gc(heavy: true)
    })
    require(observed[2] == 48, "DIRECT_VALUE_COPY_PASS")
    require(observed[0].value == 13 && observed[1].value == 23 && observed[2] == 48,
        "DIRECT_COPY_AND_REFERENTS_PASS")
    require(source.value.first.value == 101 && source.value.last.value == 103 && source.value.tag == 71,
        "MUT_WRITEBACK_PASS")

    let escaped = ReceiverSource(Snapshot<Cell>(left, right))
    let method = escaped.value.observe
    let later = method({ =>
        escaped.value.replace(Cell(107), Cell(109))
        gc(heavy: true)
    })
    require(later[2] == 48, "ESCAPED_VALUE_COPY_PASS")
    require(later[0].value == 13 && later[1].value == 23 && later[2] == 48,
        "ESCAPED_METHOD_COPY_PASS")

    let throwing = ReceiverSource(Snapshot<Cell>(left, right))
    var caught = false
    try {
        throwing.value.fail({ =>
            throwing.value.replace(Cell(127), Cell(131))
            gc(heavy: true)
        })
    } catch (e: IllegalStateException) {
        caught = e.message == "receiver-copy-exception"
    }
    require(caught && throwing.value.first.value == 127 && throwing.value.last.value == 131 && throwing.value.tag == 71,
        "EXCEPTION_NO_VALUE_WRITEBACK_PASS")
    var native = Snapshot<Cell>(left, right)
    let nativeObserved = native.observe({ => gc(heavy: true) })
    require(nativeObserved[0].value == 13 && nativeObserved[1].value == 23 && nativeObserved[2] == 48,
        "NATIVE_VALUE_SOURCE_PASS")
    native.replace(Cell(137), Cell(139))
    require(native.first.value == 137 && native.last.value == 139 && native.tag == 71,
        "NATIVE_MUT_WRITEBACK_PASS")
    return 0
}
