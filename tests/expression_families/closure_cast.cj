package expression_closure_cast
import std.collection.*
import std.sort.*
public func sortValues(values: ArrayList<Int64>): Unit {
    sort(values, by: { left: Int64, right: Int64 =>
        if (left < right) { Ordering.LT } else if (right < left) { Ordering.GT } else { Ordering.EQ }
    }, stable: true)
}
