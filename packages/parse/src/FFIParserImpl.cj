package cangjie_compiler::parse

public open class FFIParserImpl {
    public let parser: ParserImpl
    public init(parser: ParserImpl) {
        this.parser = parser
    }

    public func CheckInteropDecl(decl: Decl): Unit {
        // TODO(selfhost:Parse): Native FFI validation must call the real Java/ObjC interop rule set once package deps are enabled.
    }
}
