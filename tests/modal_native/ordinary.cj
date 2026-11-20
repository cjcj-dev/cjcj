package ordinary_consumer

import std.ast.*
import std.runtime.getAllocatedLocalObjectSize

class Cell {
    let payload: Int64
    public init(n: Int64) { this.payload = n }
    public func read(): Int64 { return payload }
}

var activeBytes: Int64 = -1

func exercise(n: Int64): Int64 {
    let c = Cell(n)
    activeBytes = getAllocatedLocalObjectSize()
    return c.read()
}

main(): Int64 {
    let before = getAllocatedLocalObjectSize()
    let answer = exercise(73)
    let after = getAllocatedLocalObjectSize()
    println("ordinary before=${before} active=${activeBytes} after=${after} payload=${answer}")
    if (answer != 73) { return 21 }
    if (activeBytes != before) { return 22 }
    if (after != before) { return 23 }
    // Exercise the SDK's installed std.ast and its native parser after observing the ordinary allocation.
    let expr = parseExpr(Tokens().append(Token(TokenKind.INTEGER_LITERAL, "73")))
    if (let Some(lit) <- (expr as LitConstExpr)) {
        if (lit.literal.kind == TokenKind.INTEGER_LITERAL && lit.literal.value == "73") {
            println("std.ast parsed integer=73")
            return 0
        }
    }
    return 24
}
