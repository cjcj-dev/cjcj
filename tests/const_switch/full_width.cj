package const_switch_full_width

const func select16(value: UInt16): Int64 {
    return match (value) {
        case 257 => 12
        case 0 => 10
        case 256 => 11
        case 1 => 13
        case _ => 14
    }
}

const func selectSigned(value: Int16): Int64 {
    return match (value) {
        case -1 => 21
        case 0 => 22
        case 32767 => 23
        case _ => 24
    }
}

const func select64(value: UInt64): Int64 {
    return match (value) {
        case 0x8000000000000000u64 => 31
        case 1u64 => 33
        case 0xffffffffffffffffu64 => 34
        case 0u64 => 32
        case _ => 35
    }
}

const wide256 = select16(256)
const wide257 = select16(257)
const wideDefault = select16(258)
const negative = selectSigned(-1)
const highBit = select64(0x8000000000000000u64)
const lowBit = select64(1)
const allBits = select64(0xffffffffffffffffu64)
const highDefault = select64(0x8000000000000001u64)

func check(name: String, constant: Int64, dynamic: Int64, expected: Int64): Int64 {
    let passed = constant == expected && dynamic == expected
    println("ASSERT ${name} const=${constant} dynamic=${dynamic} expected=${expected} ${if (passed) { "PASS" } else { "FAIL" }}")
    return if (passed) { 0 } else { 1 }
}

main(): Int64 {
    var input16: UInt16 = 256
    var failures = check("uint16_256", wide256, select16(input16), 11)
    input16 = 257
    failures += check("uint16_257", wide257, select16(input16), 12)
    input16 = 258
    failures += check("uint16_default", wideDefault, select16(input16), 14)
    var signedInput: Int16 = -1
    failures += check("int16_negative", negative, selectSigned(signedInput), 21)
    var input64: UInt64 = 0x8000000000000000u64
    failures += check("uint64_high", highBit, select64(input64), 31)
    input64 = 1
    failures += check("uint64_low", lowBit, select64(input64), 33)
    input64 = 0xffffffffffffffffu64
    failures += check("uint64_max", allBits, select64(input64), 34)
    input64 = 0x8000000000000001u64
    failures += check("uint64_default", highDefault, select64(input64), 35)
    return failures
}
