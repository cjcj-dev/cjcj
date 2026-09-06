public class RefBox {
    var value: Int64

    public init(value: Int64) {
        this.value = value
    }
}

public struct RefAggregate {
    var value: String

    public init(value: String) {
        this.value = value
    }
}

func referenceCopies(): String {
    let classSrc = [RefBox(7), RefBox(8)]
    let classDst = [RefBox(0), RefBox(0)]
    let structSrc = [RefAggregate("a"), RefAggregate("b")]
    let structDst = [RefAggregate("x"), RefAggregate("y")]
    classSrc.copyTo(classDst, 0, 0, classSrc.size)
    structSrc.copyTo(structDst, 0, 0, structSrc.size)
    return "${classDst[0].value + classDst[1].value}:${structDst[0].value}${structDst[1].value}"
}

main() {
    println("REF_ELEMENTS_OK ${referenceCopies()}")
}
