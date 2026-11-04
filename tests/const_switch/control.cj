package const_switch_control

const func selectBool(value: Bool): Int64 {
    return match (value) {
        case true => 41
        case false => 42
    }
}

const func select8(value: UInt8): Int64 {
    return match (value) {
        case 255 => 51
        case 0 => 52
        case _ => 53
    }
}

const boolTrue = selectBool(true)
const boolFalse = selectBool(false)
const byteMax = select8(255)
const byteZero = select8(0)

main(): Int64 {
    var truth = true
    var byte: UInt8 = 255
    let passed = boolTrue == 41 && boolFalse == 42 && byteMax == 51 && byteZero == 52 &&
        boolTrue == selectBool(truth) && boolFalse == selectBool(!truth) &&
        byteMax == select8(byte) && byteZero == select8(byte - 255)
    println("ASSERT bool_uint8_control ${if (passed) { "PASS" } else { "FAIL" }}")
    return if (passed) { 0 } else { 1 }
}
