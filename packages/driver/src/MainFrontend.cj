package cangjie_compiler::driver

import cangjie_compiler::frontend_tool.ExecuteFrontend

public func QuoteForWindowsFrontendShim(value: String): String {
    let builder = StringBuilder()
    builder.append("\"")
    for (byte in value.toArray()) {
        if (byte == b'"') {
            builder.append("\\\"")
        } else if (byte == b'\\') {
            builder.append("\"\\\\\"")
        } else {
            builder.append(String.fromUtf8([byte]))
        }
    }
    builder.append("\"")
    return builder.toString()
}

public func ExecuteFrontendShim(args: Array<String>, cjcPath: String): Int64 {
    return ExecuteFrontend(cjcPath, args, StringifyEnvironment())
}
