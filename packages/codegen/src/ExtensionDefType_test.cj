package cjcj::codegen

import std.unittest.*
import std.unittest.testmacro.*

@Test
public class ExtensionDefTypeTest {
    @TestCase
    public func FirstCreationHasRuntimeLayout(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let ty = CGType.GetOrCreateExtensionDefType(context)
            @Assert(unsafe { LLVMIsOpaqueStruct(ty) } == 0)
            @Assert(unsafe { LLVMCountStructElementTypes(ty) } == 8u32)
            let i8 = unsafe { LLVMInt8TypeInContext(context.raw) }
            let ptr = unsafe { LLVMPointerType(i8, 0u32) }
            let fields = [unsafe { LLVMInt32TypeInContext(context.raw) }, i8, i8,
                unsafe { LLVMInt16TypeInContext(context.raw) }, ptr, ptr, ptr, ptr]
            for (index in 0..fields.size) {
                @Assert(unsafe { LLVMStructGetTypeAtIndex(ty, UInt32(index)) }.toUIntNative() ==
                    fields[index].toUIntNative())
            }
            println("EXTENSION_DEF_LAYOUT_CHECKED fields=8")
        }
    }

    @TestCase
    public func RepeatedLookupReusesCompletedType(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let first = CGType.GetOrCreateExtensionDefType(context)
            let second = CGType.GetOrCreateExtensionDefType(context)
            @Assert(first.toUIntNative() == second.toUIntNative())
            @Assert(unsafe { LLVMCountStructElementTypes(second) } == 8u32)
            println("EXTENSION_DEF_REUSE_CHECKED fields=8")
        }
    }

    @TestCase
    public func PointerConsumerReusesCompletedType(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let first = CGType.GetOrCreateExtensionDefType(context)
            let pointer = CGType.GetOrCreateExtensionDefPtrType(context)
            let expected = unsafe { LLVMPointerType(first, 0u32) }
            @Assert(pointer.toUIntNative() == expected.toUIntNative())
            @Assert(unsafe { LLVMCountStructElementTypes(first) } == 8u32)
            println("EXTENSION_DEF_POINTER_CHECKED fields=8")
        }
    }
}
