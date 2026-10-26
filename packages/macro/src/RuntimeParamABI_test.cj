package cjcj::macro_pkg

import std.unittest.*
import std.unittest.testmacro.*

// The native side is fixed R ee7cd9f5/runtime/src/Cangjie.h, not another
// Cangjie declaration. The offsets below are that public 64-bit C ABI.
// The installed-macro gate separately exercises CallRuntime/InitCJRuntime.
@When[arch == "x86_64" || arch == "aarch64"]
@Test
public class RuntimeParamABITest {
    @TestCase
    public func NativeRecordSizes(): Unit {
        @Expect(sizeOf<RuntimeHeapParamC>(), 64)
        @Expect(sizeOf<RuntimeGCParamC>(), 72)
        @Expect(sizeOf<RuntimeLogParamC>(), 4)
        @Expect(sizeOf<RuntimeConcurrencyParamC>(), 24)
        @Expect(sizeOf<RuntimeConfigParamC>(), 168)
    }

    @TestCase
    public func NativeWorkerAndOriginOffsets(): Unit {
        try (storage = LibC.malloc<RuntimeGCParamC>().asResource()) {
            @Assert(!storage.value.isNull())
            unsafe {
                storage.value.write(RuntimeGCParamC(101, 0.5, 103, 104,
                    105, 106, 107, 108, true, false, true, false,
                    true, 109, -110, false, true))
                let base = storage.value.toUIntNative()
                @Expect(CPointer<UIntNative>(base).read(), 101)
                @Expect(CPointer<Float64>(base + 8).read(), 0.5)
                @Expect(CPointer<UInt64>(base + 16).read(), 103)
                @Expect(CPointer<UInt64>(base + 24).read(), 104)
                @Expect(CPointer<UInt32>(base + 32).read(), 105)
                @Expect(CPointer<UInt32>(base + 36).read(), 106)
                @Expect(CPointer<UInt32>(base + 40).read(), 107)
                @Expect(CPointer<UInt32>(base + 44).read(), 108)
                @Expect(CPointer<Bool>(base + 48).read(), true)
                @Expect(CPointer<Bool>(base + 49).read(), false)
                @Expect(CPointer<Bool>(base + 50).read(), true)
                @Expect(CPointer<Bool>(base + 51).read(), false)
                @Expect(CPointer<Bool>(base + 52).read(), true)
                @Expect(CPointer<UInt32>(base + 56).read(), 109)
                @Expect(CPointer<Int32>(base + 60).read(), -110)
                @Expect(CPointer<Bool>(base + 64).read(), false)
                @Expect(CPointer<Bool>(base + 65).read(), true)
            }
        }
    }

    @TestCase
    public func NativeTrailingRecordsRemainAligned(): Unit {
        try (storage = LibC.malloc<RuntimeConfigParamC>().asResource()) {
            @Assert(!storage.value.isNull())
            unsafe {
                storage.value.write(RuntimeConfigParamC(
                    RuntimeHeapParamC(64, 131072, 0.8, 0.8, 0.15, true, 65536, true),
                    RuntimeGCParamC(201, 0.5, 203, 204, 205, 206, 207, 208,
                        false, true, false, true, false, 209, -210, true, false),
                    RuntimeLogParamC(5), RuntimeConcurrencyParamC(1024, 128, 3)))
                let base = storage.value.toUIntNative()
                @Expect(CPointer<UIntNative>(base + 8).read(), 131072)
                @Expect(CPointer<Bool>(base + 40).read(), true)
                @Expect(CPointer<UIntNative>(base + 48).read(), 65536)
                @Expect(CPointer<Bool>(base + 56).read(), true)
                @Expect(CPointer<UIntNative>(base + 64).read(), 201)
                @Expect(CPointer<Int32>(base + 136).read(), 5)
                @Expect(CPointer<UIntNative>(base + 144).read(), 1024)
                @Expect(CPointer<UIntNative>(base + 152).read(), 128)
                @Expect(CPointer<UInt32>(base + 160).read(), 3)
            }
        }
    }
}
