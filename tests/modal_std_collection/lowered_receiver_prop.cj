package modalcolllowered

import std.ast.*
import std.collection.*

// std.unittest shapes: a plain property read through a value bound from sugar that type checking
// lowers to a call. A trailing-closure call (entry_main.cj:48/60 `Framework.launch(...) { }` then
// `result.details`, the prop declared in an interface and implemented in a generic abstract base),
// a `|>` pipeline (testmacro instrumentation.cj:690/697 `... |> collectHashSet` then `result.size`)
// and `quote(...)` (testmacro macro_state.cj:23/37 `attrPrefix.size`).
public interface Result {
    prop details: Int64
}

public abstract class ResultContainer<T> <: Result {
    public prop details: Int64 {
        get() { 3 }
    }
}

public class GroupResult <: ResultContainer<String> {
    public init() {}
}

func launch<T>(tag: String, body: () -> T): T {
    body()
}

func collect(xs: Array<String>): HashSet<String> {
    HashSet<String>(xs)
}

class MacroState {
    private static let attrPrefix = quote(@Attribute[)

    static func prefixSize(): Int64 {
        attrPrefix.size
    }
}

main(): Int64 {
    let result = launch("cli") { GroupResult() }
    let set = ["a", "b", "a"] |> collect
    if (result.details != 3 || set.size != 2 || MacroState.prefixSize() <= 0) {
        return 1
    }
    0
}
