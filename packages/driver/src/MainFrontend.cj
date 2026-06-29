package cangjie_compiler::driver

import cangjie_compiler::frontend_tool.ExecuteFrontend

public func ExecuteFrontendShim(args: Array<String>, cjcPath: String): Int64 {
    return ExecuteFrontend(cjcPath, args, StringifyEnvironment())
}
