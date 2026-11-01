package package_reset_phase

import std.collection.ArrayList

let values = ArrayList<Int64>([11, 13, 17, 19])

public func first(): Int64 { values[0] }
public func second(): Int64 { values[1] }
public func third(): Int64 { values[2] }
public func fourth(): Int64 { values[3] }

main(): Int64 {
    if (first() + second() + third() + fourth() != 60) { return 1 }
    println("PACKAGE_RESET_PHASE_OK")
    return 0
}
