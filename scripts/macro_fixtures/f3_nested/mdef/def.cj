// f3 macro-definition package: nested macro expansion.
// @Outer expands to code that itself contains a macro call (@Inner). This
// exercises the re-evaluation path (C++ MacroEvaluation::ReEvalAfterEvalMacroCalls
// / NeedCreateMacroCallTree) where expansion output must be scanned and
// expanded again before AST replacement.
macro package f3def

import std.ast.*

public macro Inner(input: Tokens): Tokens {
    quote(let inner_v = 7)
}

public macro Outer(input: Tokens): Tokens {
    quote(
        @Inner
        let outer_v = 0
    )
}
