package cjcj::driver

import cjcj::frontend_tool.ExecuteFrontend

public func ExecuteFrontendShim(args: Array<String>, cjcPath: String): Int64 {
    return ExecuteFrontend(cjcPath, args, StringifyEnvironment())
}
