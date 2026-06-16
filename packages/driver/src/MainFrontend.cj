package cangjie_compiler::driver

import std.collection.*
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
    let forwarded = ArrayList<String>()
    var idx: Int64 = 1
    while (idx < args.size) {
        forwarded.add(args[idx])
        idx++
    }
    return ExecuteFrontend(cjcPath, forwarded.toArray(), StringifyEnvironment())
}
