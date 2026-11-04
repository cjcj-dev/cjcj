package const_switch_control

import std.convert.*

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

main(args: Array<String>): Int64 {
    if (args.size != 4) { return 2 }
    let truth = args[0] == "true"
    let falsehood = args[1] == "true"
    let byte = UInt8.parse(args[2])
    let zero = UInt8.parse(args[3])
    let passed = boolTrue == 41 && boolFalse == 42 && byteMax == 51 && byteZero == 52 &&
        boolTrue == selectBool(truth) && boolFalse == selectBool(falsehood) &&
        byteMax == select8(byte) && byteZero == select8(zero)
    println("ASSERT bool_uint8_control ${if (passed) { "PASS" } else { "FAIL" }}")
    return if (passed) { 0 } else { 1 }
}
