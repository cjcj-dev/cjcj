package cold_exception_frame

import std.convert.*
import std.runtime.gc

// Public definitions keep the real producer's scalar-only frames inspectable.
public func checkedAdd(x: Int64, y: Int64): Int64 { return x + y }
public func checkedDivide(x: Int64, y: Int64): Int64 { return x / y }
public func checkedShift(x: Int64, y: Int64): Int64 { return x << y }
public func checkedCast(x: Int64): Int8 { return Int8(x) }
public func checkedLoop(x: Int64, step: Int64): Int64 {
    var result = x
    for (_ in 0..3) { result = checkedAdd(result, step) }
    return result
}

// A source-level Nothing helper has a separate parameter-entry block under -g.
public func explicitThrow(message: String): Nothing {
    throw IllegalArgumentException(message)
}
public func explicitGuard(value: Int64): Int64 {
    if (value < 0) { explicitThrow("negative") }
    return value
}

// Complete explicit construction, with a bodyless ordinary call when imported
// by another package. Its scalar input must not pull the String root into guard.
public func rangeMessage(value: Int64): String { return "negative: " + value.toString() }
public func constructedGuard(value: Int64): Int64 {
    if (value < 0) { throw IllegalArgumentException(rangeMessage(value)) }
    return value
}
public func locallyCaughtConstruction(value: Int64): String {
    try { if (value < 0) { throw IllegalArgumentException(rangeMessage(value)) } }
    catch (error: IllegalArgumentException) { return error.message }
    return "normal"
}

// This ordinary aggregate producer is the independent root/copy control.
public func literalControl(): String { return "ordinary literal" }

public func caughtDivision(x: Int64, y: Int64): String {
    try {
        let _ = x / y
    } catch (error: ArithmeticException) {
        return error.message
    }
    return "no exception"
}

class Holder {
    let value: String
    init(value: String) { this.value = value }
}

func require(condition: Bool, label: String): Unit {
    if (!condition) { throw Exception("COLD_FRAME_ASSERT FAIL " + label) }
    println("COLD_FRAME_ASSERT PASS " + label)
}

main(args: Array<String>): Int64 {
    if (args.size != 3) { return 2 }
    let zero = Int64.parse(args[0])
    let largest = Int64.parse(args[1])
    let one = Int64.parse(args[2])
    require(zero == 0 && largest == Int64.Max && one == 1, "dynamic inputs")
    require(checkedAdd(one, one) == 2 && checkedDivide(12, one) == 12 &&
        checkedShift(one, one) == 2 && checkedCast(one) == 1 &&
        checkedLoop(one, one) == 4, "normal paths")
    require(literalControl() == "ordinary literal", "ordinary aggregate control")

    require(explicitGuard(one) == one, "explicit helper normal control")
    var explicitCaught = false
    try { let _ = explicitGuard(zero - one) }
    catch (error: IllegalArgumentException) { explicitCaught = error.message == "negative" }
    require(explicitCaught, "explicit Nothing helper catch and message")

    require(constructedGuard(one) == one, "constructed throw normal control")
    var constructedCaught = false
    try { let _ = constructedGuard(zero - one) }
    catch (error: IllegalArgumentException) { constructedCaught = error.message == "negative: -1" }
    require(constructedCaught, "constructed throw catch and message")
    require(locallyCaughtConstruction(zero - one) == "negative: -1" &&
        locallyCaughtConstruction(one) == "normal", "constructed throw local handler control")

    let left = Holder("left live reference")
    let right = Holder("right live reference")
    let native = unsafe { LibC.malloc<Int64>() }
    require(!native.isNull(), "native allocation")
    var finalized: Int64 = 0
    try {
        unsafe { native.write(73) }
        for (index in 0..2) {
            let selected = if (index == 0) { left } else { right }
            var caught = false
            var message = ""
            try {
                try {
                    let _ = checkedAdd(largest, one)
                } finally {
                    finalized++
                }
            } catch (error: OverflowException) {
                caught = true
                message = error.message
                if (index == 0) { error.printStackTrace() }
                gc(heavy: true)
                require(selected.value == (if (index == 0) { "left live reference" } else { "right live reference" }),
                    "joined managed reference")
                require(unsafe { native.read() } == 73, "native reference across unwind")
            }
            require(caught && message == "add", "overflow type and message")
        }
        require(finalized == 2, "nested finally")
        let message = caughtDivision(one, zero)
        gc(heavy: true)
        require(message == "Divided by zero!", "local invoke and message after collection")
        var shifted = false
        try { let _ = checkedShift(one, zero - one) }
        catch (_: ArithmeticException) { shifted = true }
        require(shifted, "shift exceptional exit")
        var narrowed = false
        try { let _ = checkedCast(largest) }
        catch (_: OverflowException) { narrowed = true }
        require(narrowed, "cast exceptional exit")
    } finally {
        unsafe { LibC.free(native) }
    }
    println("COLD_FRAME_OK")
    return 0
}
