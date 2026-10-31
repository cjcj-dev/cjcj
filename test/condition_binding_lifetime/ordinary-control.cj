import std.ast.*
import std.collection.*
class Holder { let kind: TokenKind = TokenKind.DOT; let value: String = "." }
func valid(t: Token): Bool { t.kind == TokenKind.DOT && t.value == "." && t.pos.line > 0 }
main(): Int64 {
    let tk = Holder()
    let t = Token(tk.kind, tk.value)
    if (!valid(t)) { return 1 }
    println("CONDITION_BINDING_CONTROL_PASS")
    return 0
}
