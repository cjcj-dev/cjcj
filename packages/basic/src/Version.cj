package cjcj::basic

public let CANGJIE_VERSION: String = "1.2.0-alpha.20260619020029"

@When[arch == "x86_64" && os == "Linux"]
private let VERSION_TAIL: String = " (cjnative)\nTarget: x86_64-unknown-linux-gnu"
@When[arch == "aarch64" && os == "Linux"]
private let VERSION_TAIL: String = " (cjnative)\nTarget: aarch64-unknown-linux-gnu"
@When[arch == "x86_64" && os == "macOS"]
private let VERSION_TAIL: String = " (cjnative)\nTarget: x86_64-apple-darwin"
@When[arch == "aarch64" && os == "macOS"]
private let VERSION_TAIL: String = " (cjnative)\nTarget: aarch64-apple-darwin"
@When[arch == "x86_64" && os == "Windows"]
private let VERSION_TAIL: String = " (cjnative)\nTarget: x86_64-unknown-windows-gnu"
@When[arch == "aarch64" && os == "Windows"]
private let VERSION_TAIL: String = " (cjnative)\nTarget: aarch64-unknown-windows-gnu"
@When[(arch != "x86_64" && arch != "aarch64") || (os != "Linux" && os != "macOS" && os != "Windows")]
private let VERSION_TAIL: String = " (cjnative)\nTarget: unknown-unknown-unknown"

public let CANGJIE_COMPILER_VERSION: String = "Cangjie Compiler: cjcj " + CANGJIE_VERSION +
    VERSION_TAIL

public func PrintVersion(): Unit {
    Println(value: CANGJIE_COMPILER_VERSION)
}
