struct ByteValue {
    let value: UInt8

    init(value: UInt8) {
        this.value = value
    }
}

class ByteHolder {
    var payload: ByteValue = ByteValue(UInt8(37))

    func read(): ByteValue {
        return payload
    }
}

main(): Int64 {
    if (ByteHolder().read().value != UInt8(37)) {
        throw IllegalStateException("nonzero no-reference aggregate copy changed")
    }
    println("NONZERO_NOREF_COPY_OK")
    return 0
}
