package cjcj::macro_pkg

import std.env.getVariable
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
        @Assert(sizeOf<RuntimeGCParamC>() == 72)
        try (storage = LibC.malloc<RuntimeGCParamC>().asResource()) {
            @Assert(!storage.value.isNull())
            unsafe {
                storage.value.write(RuntimeGCParamC(101, 0.5, 103, 104,
                    105, 106, 107, 108, true, false, true, false,
                    true, 109, -110, false, true))
                let base = CPointer<UInt8>(storage.value)
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
        @Assert(sizeOf<RuntimeConfigParamC>() == 168)
        try (storage = LibC.malloc<RuntimeConfigParamC>().asResource()) {
            @Assert(!storage.value.isNull())
            unsafe {
                storage.value.write(RuntimeConfigParamC(
                    RuntimeHeapParamC(64, 131072, 0.8, 0.8, 0.15, true, 65536, true),
                    RuntimeGCParamC(201, 0.5, 203, 204, 205, 206, 207, 208,
                        false, true, false, true, false, 209, -210, true, false),
                    RuntimeLogParamC(5), RuntimeConcurrencyParamC(1024, 128, 3)))
                let base = CPointer<UInt8>(storage.value)
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

// This is the host control, not an independent-R lifecycle qualification.
// Public SDK macro cases must separately exercise the paired target runtime.
@C
func RuntimeLifecycleHostCallback(arg: CPointer<Unit>): CPointer<Unit> {
    unsafe { CPointer<Int64>(arg).write(42) }
    return CPointer<Unit>()
}

@Test
public class RuntimeTaskLifecycleTest {
    @TestCase
    public func UninitializedCloseRejectsNewTasks(): Unit {
        let runtime = RuntimeInit()
        runtime.CloseRuntime()
        runtime.CloseRuntime()
        var rejected = false
        try {
            let _ = runtime.SubmitTask(CPointer<Unit>(RuntimeLifecycleHostCallback), CPointer<Unit>())
        } catch (e: IllegalStateException) {
            rejected = true
            @Expect(e.message, "macro task submitted to an unavailable runtime")
        }
        @Expect(rejected, true)
    }

    @TestCase
    public func MissingFiniPropagatesFailure(): Unit {
        var rejected = false
        try {
            FinishRuntime(RuntimeHandle())
        } catch (e: IllegalStateException) {
            rejected = true
            @Expect(e.message, "macro runtime missing FiniCJRuntime")
        }
        @Expect(rejected, true)
    }

}

@When[os == "Linux" && arch == "x86_64"]
@Test
public class RuntimeTaskLifecycleHostTest {
    @TestCase
    public func BorrowedHostSurvivesCloseAndCompletesNullResult(): Unit {
        let library = getVariable("CANGJIE_HOME").getOrThrow() +
            "/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so"
        // Closing the first borrower must not finalize H: a second borrower
        // must still submit and complete an actual task in the same host.
        for (_ in 0..2) {
            let runtime = RuntimeInit()
            @Assert(runtime.InitRuntime(library))
            @Assert(!runtime.taskOnOpenedRuntime)
            try (argument = LibC.malloc<Int64>().asResource()) {
                @Assert(!argument.value.isNull())
                unsafe { argument.value.write(0) }
                let task = runtime.SubmitTask(CPointer<Unit>(RuntimeLifecycleHostCallback),
                    CPointer<Unit>(argument.value))
                runtime.CompleteTask(task)
                @Expect(unsafe { argument.value.read() }, 42)
            }
            runtime.CloseRuntime()
        }
    }
}

// Invalid UTF-8 in one otherwise well-framed native token makes the actual
// decoder throw in H, without throwing from a foreign/@C test function.
@C
func LifecycleMalformedCommon(_: CPointer<UInt8>, _: Int64, _: CPointer<Unit>): CPointer<UInt8> {
    let buffer = LibC.malloc<UInt8>(count: 11)
    if (!buffer.isNull()) {
        unsafe {
            for (i in 0..11) { buffer.write(i, 0u8) }
            buffer.write(0, 1u8)  // token count
            buffer.write(6, 1u8)  // UTF-8 byte length
            buffer.write(10, 0xffu8)
        }
    }
    return buffer
}

@C
func LifecycleMalformedAttr(_: CPointer<UInt8>, _: Int64, _: CPointer<UInt8>, _: Int64,
    context: CPointer<Unit>): CPointer<UInt8> {
    return unsafe { LifecycleMalformedCommon(CPointer<UInt8>(), 0, context) }
}

@C
func LifecycleEmptyCommon(_: CPointer<UInt8>, _: Int64, _: CPointer<Unit>): CPointer<UInt8> {
    return CPointer<UInt8>()
}

@Test
public class RuntimeTaskLifecycleBodyTest {
    @TestCase
    public func CommonAndAttrPreserveDecoderException(): Unit {
        var expectedMessage = ""
        try {
            let _ = String.fromUtf8([0xffu8])
        } catch (e: IllegalArgumentException) {
            expectedMessage = e.message
        }
        @Assert(!expectedMessage.isEmpty())
        for (attribute in [false, true]) {
            let expression = MacroExpandExpr()
            expression.invocation.hasAttr = attribute
            let call = MacroCall(expression)
            call.invokeFunc = if (attribute) { CPointer<Unit>(LifecycleMalformedAttr) }
                else { CPointer<Unit>(LifecycleMalformedCommon) }
            var rejected = false
            try {
                let _ = evaluateNativeMacro(call)
            } catch (e: IllegalArgumentException) {
                rejected = true
                @Expect(e.message, expectedMessage)
            }
            @Expect(rejected, true)
        }
    }

    @TestCase
    public func MissingDefinitionCannotBecomeSuccessfulReadyResult(): Unit {
        let expression = MacroExpandExpr()
        let call = MacroCall(expression)
        @Expect(evaluateNativeMacro(call), false)
        @Expect(call.status, MacroEvalStatus.FAIL)
        @Expect(call.isDataReady, true)
        @Assert(expression.invocation.newTokens.size == 1)
        @Expect(expression.invocation.newTokens[0].kind, TokenKind.ILLEGAL)
    }

    @TestCase
    public func EmptyNativeTokenResultRemainsValid(): Unit {
        let expression = MacroExpandExpr()
        let call = MacroCall(expression)
        call.invokeFunc = CPointer<Unit>(LifecycleEmptyCommon)
        @Expect(evaluateNativeMacro(call), true)
        @Expect(call.isDataReady, true)
        @Expect(expression.invocation.newTokens.isEmpty(), true)
        @Expect(call.status == MacroEvalStatus.FAIL, false)
    }
}

// Finite host tests of the versioned C boundary. The public paired reset gate
// separately supplies actual target Exception/Error values and owns R shutdown.
private func WithResetNotification(action: (CPointer<Unit>, MacroInvoke) -> Unit): Unit {
    let invocation = MacroInvoke()
    let id = synchronized(macroInvokeTableLock) {
        let current = macroInvokeNextId
        macroInvokeNextId++
        macroInvokeTable[current] = invocation
        current
    }
    try {
        try (cell = LibC.malloc<Int64>().asResource()) {
            @Assert(!cell.value.isNull())
            unsafe { cell.value.write(id) }
            action(CPointer<Unit>(cell.value), invocation)
        }
    } finally {
        synchronized(macroInvokeTableLock) { macroInvokeTable.remove(id) }
    }
}

@Test
public class RuntimeTaskLifecycleResetTest {
    @TestCase
    public func ExceptionAndErrorCopyLengthDelimitedBytes(): Unit {
        let originalType = "test:OriginalFailure"
        let originalMessage = String.fromUtf8([65u8, 0u8, 66u8, 0xe4u8, 0xb8u8, 0xadu8])
        for (kind in [1u32, 2u32]) {
            WithResetNotification({ context, invocation =>
                try (typeBytes = unsafe { LibC.mallocCString(originalType) }.asResource(),
                    messageBytes = unsafe { LibC.mallocCString(originalMessage) }.asResource()) {
                    @Assert(!typeBytes.value.isNull() && !messageBytes.value.isNull())
                    let status = unsafe { ResetVariableFinishNotify(context, kind, typeBytes.value.getChars(),
                        UIntNative(originalType.size), messageBytes.value.getChars(), UIntNative(originalMessage.size)) }
                    @Expect(status, 0)
                    // The callback has copied both views before returning.
                    unsafe {
                        typeBytes.value.getChars().write(0, 88u8)
                        messageBytes.value.getChars().write(0, 89u8)
                    }
                }
                @Expect(invocation.isDataReady, true)
                let failure = (invocation.failure.getOrThrow() as MacroResetFailure).getOrThrow()
                @Expect(failure.remoteKind, kind)
                @Expect(failure.remoteType, originalType)
                @Expect(failure.remoteMessage, originalMessage)
            })
        }
    }

    @TestCase
    public func EmptyMessageAndUnknownExportAreDistinctFailures(): Unit {
        WithResetNotification({ context, invocation =>
            let name = "test:EmptyMessage"
            try (bytes = unsafe { LibC.mallocCString(name) }.asResource()) {
                @Expect(unsafe { ResetVariableFinishNotify(context, 1u32, bytes.value.getChars(), UIntNative(name.size),
                    CPointer<UInt8>(), 0) }, 0)
            }
            let failure = (invocation.failure.getOrThrow() as MacroResetFailure).getOrThrow()
            @Expect(failure.remoteMessage, "")
            @Expect(failure.remoteKind, 1u32)
        })
        for (kind in [3u32, 4u32]) {
            WithResetNotification({ context, invocation =>
                @Expect(unsafe { ResetVariableFinishNotify(context, kind, CPointer<UInt8>(), 0,
                    CPointer<UInt8>(), 0) }, 0)
                let failure = (invocation.failure.getOrThrow() as MacroResetFailure).getOrThrow()
                @Expect(failure.remoteKind, kind)
                @Expect(failure.remoteType, "")
                @Expect(failure.remoteMessage, "")
                @Expect(invocation.isDataReady, true)
            })
        }
    }

    @TestCase
    public func InvalidPayloadReturnsFailureWithoutThrowingAcrossC(): Unit {
        WithResetNotification({ context, invocation =>
            @Expect(unsafe { ResetVariableFinishNotify(context, 1u32, CPointer<UInt8>(), 1,
                CPointer<UInt8>(), 0) }, -1)
            @Expect(invocation.failure.isSome(), true)
            @Expect(invocation.isDataReady, true)
        })
        @Expect(unsafe { ResetVariableFinishNotify(CPointer<Unit>(), 0u32, CPointer<UInt8>(), 0,
            CPointer<UInt8>(), 0) }, -1)
    }

    @TestCase
    public func NormalNotificationAndDuplicateCannotHideFirstFailure(): Unit {
        WithResetNotification({ context, invocation =>
            @Expect(unsafe { ResetVariableFinishNotify(context, 0u32, CPointer<UInt8>(), 0,
                CPointer<UInt8>(), 0) }, 0)
            @Expect(invocation.failure.isNone(), true)
            @Expect(invocation.isDataReady, true)
        })
        WithResetNotification({ context, invocation =>
            @Expect(unsafe { ResetVariableFinishNotify(context, 4u32, CPointer<UInt8>(), 0,
                CPointer<UInt8>(), 0) }, 0)
            let first = (invocation.failure.getOrThrow() as MacroResetFailure).getOrThrow()
            @Expect(unsafe { ResetVariableFinishNotify(context, 0u32, CPointer<UInt8>(), 0,
                CPointer<UInt8>(), 0) }, -1)
            let retained = (invocation.failure.getOrThrow() as MacroResetFailure).getOrThrow()
            @Expect(retained.remoteKind, first.remoteKind)
            @Expect(retained.remoteType, first.remoteType)
            @Expect(retained.remoteMessage, first.remoteMessage)
        })
    }
}
