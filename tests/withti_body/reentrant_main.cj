import withti_reentrant.*
import std.runtime.*

main(): Int64 {
    let value = Deferred<String>("kept")
    if (enter(value, { => gc(heavy: true) }) != 17) {
        throw IllegalStateException("REENTRANT_NORMAL_FAIL")
    }
    println("REENTRANT_NORMAL_PASS")
    if (enter(value, { => throw IllegalStateException("expected") }) != 29) {
        throw IllegalStateException("REENTRANT_UNWIND_FAIL")
    }
    println("REENTRANT_UNWIND_PASS")
    return 0
}
