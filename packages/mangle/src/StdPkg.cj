package cjcj::mangle

public func StdPackageMangle(pkgName: String): Option<String> {
    return match (pkgName) {
        case "std.ad" => "aa"
        case "std.sync" => "ab"
        case "std.collection" => "ac"
        case "std.deriving" => "ad"
        case "std.database" => "ae"
        case "std.net" => "af"
        case "std.chirad" => "ag"
        case "std.io" => "ah"
        case "std.convert" => "ai"
        case "std.ffi" => "aj"
        case "std.argopt" => "ak"
        case "std.objectpool" => "al"
        case "std.reflect" => "am"
        case "std.fs" => "an"
        case "std.runtime" => "ao"
        case "std.overflow" => "ap"
        case "std.unittest" => "aq"
        case "std.binary" => "ar"
        case "std.unicode" => "as"
        case "std.core" => "at"
        case "std.console" => "au"
        case "std.random" => "av"
        case "std.sort" => "aw"
        case "std.ast" => "ax"
        case "std.env" => "ay"
        case "std.process" => "ba"
        case "std.time" => "bb"
        case "std.regex" => "bc"
        case "std.posix" => "bd"
        case "std.crypto" => "be"
        case "std.ref" => "bf"
        case "std.math" => "bg"
        case "std.collection.concurrent" => "bh"
        case "std.collection.concurrent.native" => "bi"
        case "std.deriving.impl" => "bj"
        case "std.deriving.builtins" => "bk"
        case "std.deriving.api" => "bl"
        case "std.deriving.resolve" => "bm"
        case "std.database.sql" => "bn"
        case "std.net.native" => "bo"
        case "std.convert.native" => "bq"
        case "std.objectpool.native" => "bs"
        case "std.fs.native" => "bt"
        case "std.runtime.native" => "bu"
        case "std.unittest.mock" => "bv"
        case "std.unittest.testmacro" => "bw"
        case "std.unittest.prop_test" => "bx"
        case "std.unittest.common" => "by"
        case "std.unittest.native" => "ca"
        case "std.unittest.diff" => "cb"
        case "std.unittest.mock.mockmacro" => "cc"
        case "std.unittest.mock.internal" => "cd"
        case "std.core.native" => "ce"
        case "std.random.native" => "cf"
        case "std.ast.native" => "cg"
        case "std.env.native" => "ch"
        case "std.process.native" => "ci"
        case "std.time.native" => "cj"
        case "std.regex.native" => "ck"
        case "std.posix.native" => "cl"
        case "std.crypto.digest" => "cm"
        case "std.crypto.cipher" => "cn"
        case "std.math.numeric" => "co"
        case "std.math.native" => "cp"
        case "std.math.numeric.native" => "cq"
        case _ => None
    }
}

public func IsStdPackageMangleCode(code: String): Bool {
    return code == "aa" || code == "ab" || code == "ac" || code == "ad" || code == "ae" || code == "af" ||
        code == "ag" || code == "ah" || code == "ai" || code == "aj" || code == "ak" || code == "al" ||
        code == "am" || code == "an" || code == "ao" || code == "ap" || code == "aq" || code == "ar" ||
        code == "as" || code == "at" || code == "au" || code == "av" || code == "aw" || code == "ax" ||
        code == "ay" || code == "ba" || code == "bb" || code == "bc" || code == "bd" || code == "be" ||
        code == "bf" || code == "bg" || code == "bh" || code == "bi" || code == "bj" || code == "bk" ||
        code == "bl" || code == "bm" || code == "bn" || code == "bo" || code == "bq" || code == "bs" ||
        code == "bt" || code == "bu" || code == "bv" || code == "bw" || code == "bx" || code == "by" ||
        code == "ca" || code == "cb" || code == "cc" || code == "cd" || code == "ce" || code == "cf" ||
        code == "cg" || code == "ch" || code == "ci" || code == "cj" || code == "ck" || code == "cl" ||
        code == "cm" || code == "cn" || code == "co" || code == "cp" || code == "cq"
}
