package cangjie_compiler::compiler_unittest

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import cangjie_compiler::basic.DiagnosticEngine
import cangjie_compiler::basic.SourceManager
import cangjie_compiler::lex.Lexer
import cangjie_compiler::lex.Token as LexToken
import cangjie_compiler::lex.TokenKind
import cangjie_compiler::macro_pkg.TokenSerialization

private let TOKEN_SERIALIZATION_CODE: String = ##"
?:
    true false
    main(argc:Int64=1, argv:String) {
    let a:Int64=-40
    let pi:float64=3.14
    let alpha=0x1.1p1
    let c:char = '\''
    // grh
    /*/**/*/
    let d:String = "asdqwe"
    let b = 2 ** -a
    print((a+3*b, (a+3) *b))
    @abc
    };
"##

@Test
public class TokenSerializationTest {
    @TestCase
    public func bufferCase(): Unit {
        let lexer = Lexer(TOKEN_SERIALIZATION_CODE, DiagnosticEngine(), SourceManager())
        let tokens = ArrayList<LexToken>()
        while (true) {
            let tok = lexer.Next()
            tokens.add(tok)
            if (tok.kind == TokenKind.END) {
                break
            }
        }
        let buf = TokenSerialization.GetTokensBytes(tokens)
        let backTokens = TokenSerialization.GetTokensFromBytes(buf)
        @Expect(tokens.size, 93)
        @Assert(tokens.size == backTokens.size)
        var idx: Int64 = 0
        while (idx < 93) {
            @Expect(tokens[idx].kind, backTokens[idx].kind)
            @Expect(tokens[idx].Value(), backTokens[idx].Value())
            @Expect(tokens[idx].Begin(), backTokens[idx].Begin())
            idx++
        }
    }
}
