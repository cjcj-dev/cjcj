package package_reset_phase

import std.collection.ArrayList

// Keep the normal collection import/init dependency, without materializing
// ArrayList generic bodies that can balance the tiny imports-init back to main.
let firstValue: Int64 = 11
let secondValue: Int64 = 13
let thirdValue: Int64 = 17
let fourthValue: Int64 = 19

public func first(): Int64 { firstValue }
public func second(): Int64 { secondValue }
public func third(): Int64 { thirdValue }
public func fourth(): Int64 { fourthValue }

main(): Int64 {
    if (first() + second() + third() + fourth() != 60) { return 1 }
    println("PACKAGE_RESET_PHASE_OK")
    return 0
}
