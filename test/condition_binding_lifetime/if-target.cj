import std.ast.*
import std.collection.*
class Holder { let kind: TokenKind = TokenKind.DOT; let value: String = "." }
func valid(t: Token): Bool { t.kind == TokenKind.DOT && t.value == "." && t.pos.line > 0 }
func make(h: Option<Holder>): Token {
    if (let Some(tk) <- h) { Token(tk.kind, tk.value) } else { Token(TokenKind.DOT, ".") }
}
main(): Int64 {
    let result = ArrayList<Token>()
    if (let Some(tk) <- Some(Holder())) { result.add(Token(tk.kind, tk.value)) }
    let tk = Holder()
    if (let Some(tk) <- Some(Holder())) { result.add(Token(tk.kind, tk.value)) }
    result.add(Token(tk.kind, tk.value))
    if (let Some(tk) <- Some(Holder()) && tk.value == ".") { result.add(Token(tk.kind, tk.value)) }
    result.add(make(Some(Holder())))
    if (result.size != 5) { return 1 }
    for (t in result) { if (!valid(t)) { return 2 } }
    println("CONDITION_BINDING_IF_PASS")
    return 0
}
