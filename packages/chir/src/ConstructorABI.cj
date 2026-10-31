package cjcj::chir

// CJO major 1 and CHIR CR01 both identify receiver-returning constructors.
// This is a file identifier, not a change to the canonical FlatBuffer layout.
const CONSTRUCTOR_ABI_CHIR_IDENTIFIER: String = "CR01"

func HasCurrentConstructorABI(data: Array<UInt8>): Bool {
    if (data.size < 8) {
        return false
    }
    let identifier = CONSTRUCTOR_ABI_CHIR_IDENTIFIER.toArray()
    for (index in 0..4) {
        if (data[index + 4] != identifier[index]) {
            return false
        }
    }
    return true
}
