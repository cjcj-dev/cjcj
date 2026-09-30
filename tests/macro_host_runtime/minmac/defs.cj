macro package minmac

import std.ast.*

public macro Id(input: Tokens): Tokens {
    return input
}

public macro Empty(input: Tokens): Tokens {
    return Tokens()
}
