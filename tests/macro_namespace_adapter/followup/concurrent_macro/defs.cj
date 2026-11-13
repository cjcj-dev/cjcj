macro package cleaner_parallel
import std.ast.*
foreign func CleanerMacroEnter(): Unit
foreign func CleanerMacroLeave(): Unit
public macro Probe(input: Tokens): Tokens {
    unsafe { CleanerMacroEnter() }
    try {
        if (insideParentContext("NoSuchParent")) {
            throw Exception("unexpected macro parent context")
        }
        return input
    } finally {
        unsafe { CleanerMacroLeave() }
    }
}
