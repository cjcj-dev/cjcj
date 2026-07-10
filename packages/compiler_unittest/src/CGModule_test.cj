package cjcj::compiler_unittest

import std.unittest.*
import std.unittest.testmacro.*
import cjcj::codegen.CGModule
import cjcj::option.{ArchType, EnvironmentType, OSType, TripleInfo, Vendor}

@Test
public class CGModuleTest {
    @TestCase
    public func getTargetTripleString(): Unit {
        @Expect("arm64-apple-macosx12.0.0", "arm64-apple-macosx12.0.0")
        let target = TripleInfo()

        target.arch = ArchType.AARCH64
        target.vendor = Vendor.APPLE
        target.os = OSType.DARWIN
        target.env = EnvironmentType.NOT_AVAILABLE
        @Expect(CGModule.GetTargetTripleString(target), "arm64-apple-macosx12.0.0")
        target.arch = ArchType.ARM64
        @Expect(CGModule.GetTargetTripleString(target), "arm64-apple-macosx12.0.0")
        target.arch = ArchType.ARM32
        @Expect(CGModule.GetTargetTripleString(target), "arm-apple-macosx12.0.0")
        target.os = OSType.IOS
        @Expect(CGModule.GetTargetTripleString(target), "arm-apple-macosx12.0.0")

        target.arch = ArchType.AARCH64
        target.vendor = Vendor.UNKNOWN
        target.os = OSType.LINUX
        target.env = EnvironmentType.OHOS
        @Expect(CGModule.GetTargetTripleString(target), "aarch64-unknown-linux-ohos")
        target.vendor = Vendor.PC
        @Expect(CGModule.GetTargetTripleString(target), "aarch64-unknown-linux-ohos")

        target.arch = ArchType.ARM32
        target.vendor = Vendor.UNKNOWN
        target.os = OSType.LINUX
        target.env = EnvironmentType.OHOS
        @Expect(CGModule.GetTargetTripleString(target), "armv7a-linux-gnu")
    }
}
