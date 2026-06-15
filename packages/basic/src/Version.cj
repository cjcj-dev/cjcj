package cangjie_compiler::basic

public let CANGJIE_VERSION: String = "1.1.0"
public let CANGJIE_COMPILER_VERSION: String = "Cangjie Compiler: " + CANGJIE_VERSION

public func PrintVersion(): Unit {
    Println(value: CANGJIE_COMPILER_VERSION)
}
