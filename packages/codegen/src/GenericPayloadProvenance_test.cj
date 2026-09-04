package cjcj::codegen

import std.unittest.*
import std.unittest.testmacro.*
import cjcj::utils.{ICE, TriggerPointSetter}

private let PAYLOAD_SOURCE_IR = """
    define void @native(i8* %source) {
    entry:
      %view = addrspacecast i8* %source to i8 addrspace(1)*
      ret void
    }

    define void @roundtrip(i8 addrspace(1)* %source) {
    entry:
      %native = addrspacecast i8 addrspace(1)* %source to i8*
      %view = addrspacecast i8* %native to i8 addrspace(1)*
      ret void
    }
    """

private func FindFunction(module: LLVMModuleHandle, name: String): LLVMValueRef {
    var result = LLVMNullValue()
    try (rawName = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = unsafe { LLVMGetNamedFunction(module.raw, rawName.value) }
    }
    return result
}

private func FirstInstruction(function: LLVMValueRef): LLVMValueRef {
    return unsafe { LLVMGetFirstInstruction(LLVMGetFirstBasicBlock(function)) }
}

@Test
public class GenericPayloadProvenanceTest {
    @TestCase
    public func NativeViewKeepsNativeSource(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let buffer = LLVMMemoryBufferHandle.CreateFromStringCopy(PAYLOAD_SOURCE_IR).getOrThrow()
            let parsed = LLVMParseIRModule(context, buffer, name: "generic-payload-source")
            @Assert(parsed.ok)
            try (module = parsed.module) {
                let function = FindFunction(module, "native")
                let view = FirstInstruction(function)
                let expected = unsafe { LLVMGetParam(function, 0u32) }
                @Assert(IRBuilder2.GetNativePayloadSource(view).toUIntNative() == expected.toUIntNative())
            }
        }
    }

    @TestCase
    public func ManagedNativeManagedRoundTripIsRejected(): Unit {
        try (trigger = TriggerPointSetter(ICE.UNITTEST_TP), context = LLVMContextHandle.Create()) {
            let buffer = LLVMMemoryBufferHandle.CreateFromStringCopy(PAYLOAD_SOURCE_IR).getOrThrow()
            let parsed = LLVMParseIRModule(context, buffer, name: "generic-payload-source")
            @Assert(parsed.ok)
            try (module = parsed.module) {
                let function = FindFunction(module, "roundtrip")
                let outer = unsafe { LLVMGetNextInstruction(FirstInstruction(function)) }
                @Assert(IRBuilder2.GetNativePayloadSource(outer).isNull())
            }
        }
    }
}
