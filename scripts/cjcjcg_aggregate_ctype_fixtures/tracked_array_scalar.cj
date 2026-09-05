class NoRefArrayHolder {
    var payload: VArray<UInt32, $2> = VArray<UInt32, $2>({ index: Int64 =>
        if (index == 0) { 17u32 } else { 29u32 }
    })

    func read(): VArray<UInt32, $2> {
        return payload
    }
}

main() {
    let copied = NoRefArrayHolder().read()
    if (copied[0] != 17u32 || copied[1] != 29u32) {
        throw Exception("tracked AS1 array aggregate mismatch")
    }
}
