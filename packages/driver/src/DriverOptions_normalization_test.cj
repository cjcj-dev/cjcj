package cjcj::driver

import cjcj::option.*
import std.collection.ArrayList
import std.env.getVariable
import std.unittest.*
import std.unittest.testmacro.*

@Test
class DriverOptionsNormalizationTest {
    @TestCase
    func ApcObfuscationNormalization(): Unit {
        let source = (getVariable("PROJECT_SOURCE_DIR") ?? ".") + "/packages/option/testdata/main.cj"
        for (target in ["x86_64-unknown-linux-gnu", "x86_64-w64-mingw32", "aarch64-apple-darwin", "aarch64-apple-ios"]) {
            for (apc in [Array<String>(), ["--apc"], ["--apc=3"], ["--apc-split-num", "5"]]) {
                println("INPUT obfuscation target=${target} apc=${apc}")
                let input = ArrayList<String>()
                input.add(all: ["cjc", "--experimental", "--target", target, "--fobf-string", "-j", "7"])
                input.add(all: apc)
                input.add(source)
                let args = ArgList()
                let table = CreateOptionTable()
                @Expect(table.ParseArgs(input.toArray(), args), true)
                let opts = DriverOptions()
                let success = opts.ParseFromArgs(args)
                println("NORMALIZED obfuscation target=${target} success=${success} enabled=${opts.IsObfuscationEnabled()} value=${opts.aggressiveParallelCompile.value}")
                @Expect(opts.IsObfuscationEnabled(), true)
                @Expect(success, true)
                @Expect(opts.aggressiveParallelCompile.value, 1u64)
            }
        }
    }
}
