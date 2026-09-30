package cjcj::driver

import cjcj::option.*
import std.env.getVariable
import std.unittest.*
import std.unittest.testmacro.*

@Test
class DriverOptionsNormalizationTest {
    @TestCase
    func ApcObfuscationNormalization(): Unit {
        let source = (getVariable("PROJECT_SOURCE_DIR") ?? ".") + "/packages/option/testdata/main.cj"
        for (target in ["x86_64-unknown-linux-gnu", "x86_64-w64-mingw32", "aarch64-apple-darwin", "aarch64-apple-ios"]) {
            let args = ArgList()
            let table = CreateOptionTable()
            @Expect(table.ParseArgs(["cjc", "--experimental", "--target", target,
                "--fobf-string", "-j", "7", "--apc=3", source], args), true)
            let opts = DriverOptions()
            let success = opts.ParseFromArgs(args)
            println("NORMALIZED obfuscation target=${target} success=${success} enabled=${opts.IsObfuscationEnabled()} value=${opts.aggressiveParallelCompile.value}")
            @Expect(opts.IsObfuscationEnabled(), true)
            if (target == "aarch64-apple-ios") {
                @Expect(success, false)
            } else {
                @Expect(success, true)
                @Expect(opts.aggressiveParallelCompile.value, 1u64)
            }
        }
    }
}
