import std.ast.*
import std.collection.*
class Holder { let kind: TokenKind = TokenKind.DOT; let value: String = "." }
func valid(t: Token): Bool { t.kind == TokenKind.DOT && t.value == "." && t.pos.line > 0 }
main(): Int64 {
    var h: Option<Holder> = Some(Holder())
    let result = ArrayList<Token>()
    while (let Some(tk) <- h) { result.add(Token(tk.kind, tk.value)); h = None }
    if (result.size != 1 || !valid(result[0])) { return 1 }
    println("CONDITION_BINDING_WHILE_PASS")
    return 0
}
