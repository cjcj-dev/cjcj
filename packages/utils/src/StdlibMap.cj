package cangjie_compiler::utils

private let STANDARD_LIBS: Array<(String, String)> = [
    ("std.core", "core"), ("std.binary", "binary"), ("std.io", "io"), ("std.math", "math"),
    ("std.overflow", "overflow"), ("std.runtime", "runtime"), ("std.convert", "convert"),
    ("std.random", "random"), ("std.collection", "collection"), ("std.unicode", "unicode"),
    ("std.sort", "sort"), ("std.argopt", "argopt"), ("std.ast", "ast"), ("std.interop", "interop"),
    ("std.time", "time"), ("std.sync", "sync"), ("std.collection.concurrent", "collection.concurrent"),
    ("std.net", "net"), ("std.regex", "regex"), ("std.unittest.common", "unittest.common"),
    ("std.unittest.prop_test", "unittest.prop_test"), ("std.unittest.diff", "unittest.diff"),
    ("std.math.numeric", "math.numeric"), ("std.fs", "fs"),
    ("std.unittest.mock.internal", "unittest.mock.internal"), ("std.unittest.mock", "unittest.mock"),
    ("std.reflect", "reflect"), ("std.ref", "ref"), ("std.crypto", "crypto"),
    ("std.crypto.digest", "crypto.digest"), ("std.crypto.cipher", "crypto.cipher"),
    ("std.console", "console"), ("std.database", "database"), ("std.database.sql", "database.sql"),
    ("std.posix", "posix"), ("std.process", "process"), ("std.env", "env"),
    ("std.objectpool", "objectpool"), ("std.unittest", "unittest"), ("std.deriving.api", "deriving.api"),
    ("std.deriving.resolve", "deriving.resolve"), ("std.deriving.impl", "deriving.impl"),
    ("std.deriving.builtins", "deriving.builtins"), ("std.deriving", "deriving"),
    ("std.unittest.testmacro", "unittest.testmacro"), ("std.unittest.mock.mockmacro", "unittest.mock.mockmacro"),
    ("std", "std"), ("std.ffi.python", "ffi.python"), ("fuzz.fuzz", "fuzz")
]

public func StandardLibName(fullPackageName: String): Option<String> {
    for ((name, mapped) in STANDARD_LIBS) {
        if (name == fullPackageName) {
            return mapped
        }
    }
    return None
}
