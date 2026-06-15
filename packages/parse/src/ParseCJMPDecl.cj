package cangjie_compiler::parse

public class MPParserImpl {
    public let parser: ParserImpl
    public init(parser: ParserImpl) {
        this.parser = parser
    }

    public func ParseCJMPDecl(scopeKind: ScopeKind): Decl {
        // TODO(selfhost:Parse): CJMP declaration parsing depends on the real frontend option and AST contracts.
        return parser.ParseDecl(scopeKind)
    }
}
