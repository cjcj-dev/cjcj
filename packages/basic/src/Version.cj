package cangjie_compiler::basic

public let CANGJIE_VERSION: String = "1.2.0-alpha.20260619020029"
public let CANGJIE_COMPILER_VERSION: String = "Cangjie Compiler: " + CANGJIE_VERSION +
    " (cjnative)\nTarget: x86_64-unknown-linux-gnu"

public func PrintVersion(): Unit {
    Println(value: CANGJIE_COMPILER_VERSION)
}
