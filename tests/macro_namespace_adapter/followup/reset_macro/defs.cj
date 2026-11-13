macro package cleaner_reset_failure
import std.ast.*
func initialize(): Int64 {
    throw Exception("CLEANER_RESET_EXCEPTION_SENTINEL")
}
let mustInitialize: Int64 = initialize()
public macro Never(input: Tokens): Tokens {
    if (mustInitialize == 0) { return input }
    return input
}
