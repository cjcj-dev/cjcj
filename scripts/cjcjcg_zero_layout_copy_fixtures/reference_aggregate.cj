struct RefValue {
    let text: String

    init(text: String) {
        this.text = text
    }
}

class RefHolder {
    var payload: RefValue = RefValue("kept")

    func read(): RefValue {
        return payload
    }
}

main(): Int64 {
    if (RefHolder().read().text != "kept") {
        throw IllegalStateException("reference aggregate copy changed")
    }
    println("REFERENCE_AGGREGATE_COPY_OK")
    return 0
}
