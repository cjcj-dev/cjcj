package cangjie_compiler::driver

import std.collection.*

public let GET_COMMAND_LINE_ARGS: String = "getCommandLineArgs"
public let MODULE_SPLIT: String = "/"

public func StandardLibName(fullPackageName: String): Option<String> {
    return match (fullPackageName) {
        case "std.core" => "core"
        case "std.binary" => "binary"
        case "std.io" => "io"
        case "std.math" => "math"
        case "std.overflow" => "overflow"
        case "std.runtime" => "runtime"
        case "std.convert" => "convert"
        case "std.random" => "random"
        case "std.collection" => "collection"
        case "std.unicode" => "unicode"
        case "std.sort" => "sort"
        case "std.argopt" => "argopt"
        case "std.ast" => "ast"
        case "std.interop" => "interop"
        case "std.time" => "time"
        case "std.sync" => "sync"
        case "std.collection.concurrent" => "collection.concurrent"
        case "std.net" => "net"
        case "std.regex" => "regex"
        case "std.unittest.common" => "unittest.common"
        case "std.unittest.prop_test" => "unittest.prop_test"
        case "std.unittest.diff" => "unittest.diff"
        case "std.math.numeric" => "math.numeric"
        case "std.fs" => "fs"
        case "std.unittest.mock.internal" => "unittest.mock.internal"
        case "std.unittest.mock" => "unittest.mock"
        case "std.reflect" => "reflect"
        case "std.ref" => "ref"
        case "std.crypto" => "crypto"
        case "std.crypto.digest" => "crypto.digest"
        case "std.crypto.cipher" => "crypto.cipher"
        case "std.console" => "console"
        case "std.database" => "database"
        case "std.database.sql" => "database.sql"
        case "std.posix" => "posix"
        case "std.process" => "process"
        case "std.env" => "env"
        case "std.objectpool" => "objectpool"
        case "std.unittest" => "unittest"
        case "std.deriving.api" => "deriving.api"
        case "std.deriving.resolve" => "deriving.resolve"
        case "std.deriving.impl" => "deriving.impl"
        case "std.deriving.builtins" => "deriving.builtins"
        case "std.deriving" => "deriving"
        case "std.unittest.testmacro" => "unittest.testmacro"
        case "std.unittest.mock.mockmacro" => "unittest.mock.mockmacro"
        case "std" => "std"
        case "std.ffi.python" => "ffi.python"
        case "fuzz.fuzz" => "fuzz"
        case _ => None
    }
}

public func StandardLibMap(): HashMap<String, String> {
    let values = HashMap<String, String>()
    let keys = [
        "std.core", "std.binary", "std.io", "std.math", "std.overflow", "std.runtime", "std.convert",
        "std.random", "std.collection", "std.unicode", "std.sort", "std.argopt", "std.ast", "std.interop",
        "std.time", "std.sync", "std.collection.concurrent", "std.net", "std.regex", "std.unittest.common",
        "std.unittest.prop_test", "std.unittest.diff", "std.math.numeric", "std.fs", "std.unittest.mock.internal",
        "std.unittest.mock", "std.reflect", "std.ref", "std.crypto", "std.crypto.digest", "std.crypto.cipher",
        "std.console", "std.database", "std.database.sql", "std.posix", "std.process", "std.env",
        "std.objectpool", "std.unittest", "std.deriving.api", "std.deriving.resolve", "std.deriving.impl",
        "std.deriving.builtins", "std.deriving", "std.unittest.testmacro", "std.unittest.mock.mockmacro",
        "std", "std.ffi.python", "fuzz.fuzz"
    ]
    for (key in keys) {
        if (let Some(name) <- StandardLibName(key)) {
            values.add(key, name)
        }
    }
    return values
}
