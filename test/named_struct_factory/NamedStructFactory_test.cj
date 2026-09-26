package named_struct_factory_regression

import cjcj::codegen.*
import std.unittest.*
import std.unittest.testmacro.*

foreign {
    func LLVMIsOpaqueStruct(ty: LLVMTypeRef): Int32
    func LLVMCountStructElementTypes(ty: LLVMTypeRef): UInt32
    func LLVMInt8TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMInt16TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMInt32TypeInContext(context: LLVMContextRef): LLVMTypeRef
    func LLVMPointerType(ty: LLVMTypeRef, addressSpace: UInt32): LLVMTypeRef
    func LLVMArrayType(elementType: LLVMTypeRef, elementCount: UInt32): LLVMTypeRef
    func LLVMStructGetTypeAtIndex(ty: LLVMTypeRef, index: UInt32): LLVMTypeRef
    func LLVMGetElementType(ty: LLVMTypeRef): LLVMTypeRef
    func LLVMGetArrayLength(ty: LLVMTypeRef): UInt32
    func LLVMStructCreateNamed(context: LLVMContextRef, name: CString): LLVMTypeRef
    func LLVMStructSetBody(structTy: LLVMTypeRef, elementTypes: CPointer<LLVMTypeRef>, elementCount: UInt32,
        packed: Int32): Unit
}

private func SameType(left: LLVMTypeRef, right: LLVMTypeRef): Bool {
    return left.toUIntNative() == right.toUIntNative()
}

private func AssertField(ty: LLVMTypeRef, index: UInt32, expected: LLVMTypeRef): Unit {
    @Assert(SameType(unsafe { LLVMStructGetTypeAtIndex(ty, index) }, expected))
}

@Test
public class NamedStructFactoryTest {
    @TestCase
    public func UnitFirstCreationHasEmptyBody(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let ty = CGType.GetUnitType(context)
            @Assert(!ty.isNull())
            @Assert(unsafe { LLVMIsOpaqueStruct(ty) } == 0)
            @Assert(unsafe { LLVMCountStructElementTypes(ty) } == 0u32)
            println("NAMED_STRUCT_UNIT_LAYOUT_CHECKED fields=0 opaque=0")
        }
    }

    @TestCase
    public func UnitRepeatedLookupReusesCompletedType(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let first = CGType.GetUnitType(context)
            println("NAMED_STRUCT_UNIT_FIRST opaque=${unsafe { LLVMIsOpaqueStruct(first) }}")
            let second = CGType.GetUnitType(context)
            println("NAMED_STRUCT_UNIT_SECOND_RETURNED")
            @Assert(SameType(first, second))
            @Assert(unsafe { LLVMIsOpaqueStruct(second) } == 0)
            @Assert(unsafe { LLVMCountStructElementTypes(second) } == 0u32)
            println("NAMED_STRUCT_UNIT_REUSE_CHECKED")
        }
    }

    @TestCase
    public func BitMapFirstCreationHasRuntimeLayout(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let ty = CGType.GetBitMapType(context)
            let i8 = unsafe { LLVMInt8TypeInContext(context.raw) }
            let i32 = unsafe { LLVMInt32TypeInContext(context.raw) }
            @Assert(unsafe { LLVMIsOpaqueStruct(ty) } == 0)
            @Assert(unsafe { LLVMCountStructElementTypes(ty) } == 2u32)
            AssertField(ty, 0u32, i32)
            let bitmap = unsafe { LLVMStructGetTypeAtIndex(ty, 1u32) }
            @Assert(unsafe { LLVMGetArrayLength(bitmap) } == 0u32)
            @Assert(SameType(unsafe { LLVMGetElementType(bitmap) }, i8))
            println("NAMED_STRUCT_BITMAP_LAYOUT_CHECKED fields=2")
        }
    }

    @TestCase
    public func BitMapRepeatedLookupReusesCompletedType(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let first = CGType.GetBitMapType(context)
            println("NAMED_STRUCT_BITMAP_FIRST fields=${unsafe { LLVMCountStructElementTypes(first) }}")
            let second = CGType.GetBitMapType(context)
            println("NAMED_STRUCT_BITMAP_SECOND_RETURNED")
            @Assert(SameType(first, second))
            @Assert(unsafe { LLVMCountStructElementTypes(second) } == 2u32)
            println("NAMED_STRUCT_BITMAP_REUSE_CHECKED fields=2")
        }
    }

    @TestCase
    public func TypeTemplateFirstCreationHasRuntimeLayout(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let ty = CGType.GetOrCreateTypeTemplateType(context)
            let i8 = unsafe { LLVMInt8TypeInContext(context.raw) }
            let i16 = unsafe { LLVMInt16TypeInContext(context.raw) }
            let ptr = unsafe { LLVMPointerType(i8, 0u32) }
            let extPtr = CGType.GetOrCreateExtensionDefPtrType(context)
            let extPtrPtr = unsafe { LLVMPointerType(extPtr, 0u32) }
            @Assert(unsafe { LLVMIsOpaqueStruct(ty) } == 0)
            @Assert(unsafe { LLVMCountStructElementTypes(ty) } == 11u32)
            let fields = [ptr, i8, i8, i16, i16, ptr, ptr, ptr, ptr, extPtrPtr, i16]
            for (index in 0..fields.size) {
                AssertField(ty, UInt32(index), fields[index])
            }
            println("NAMED_STRUCT_TYPETEMPLATE_LAYOUT_CHECKED fields=11")
        }
    }

    @TestCase
    public func TypeTemplateRepeatedLookupReusesCompletedType(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let first = CGType.GetOrCreateTypeTemplateType(context)
            println("NAMED_STRUCT_TYPETEMPLATE_FIRST fields=${unsafe { LLVMCountStructElementTypes(first) }}")
            let second = CGType.GetOrCreateTypeTemplateType(context)
            println("NAMED_STRUCT_TYPETEMPLATE_SECOND_RETURNED")
            @Assert(SameType(first, second))
            @Assert(unsafe { LLVMCountStructElementTypes(second) } == 11u32)
            println("NAMED_STRUCT_TYPETEMPLATE_REUSE_CHECKED fields=11")
        }
    }

    @TestCase
    public func GenericTypeInfoFirstCreationHasRuntimeLayout(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let ty = GetOrCreateGenericTypeInfoType(context)
            let i8 = unsafe { LLVMInt8TypeInContext(context.raw) }
            let i32 = unsafe { LLVMInt32TypeInContext(context.raw) }
            let ptr = unsafe { LLVMPointerType(i8, 0u32) }
            @Assert(unsafe { LLVMIsOpaqueStruct(ty) } == 0)
            @Assert(unsafe { LLVMCountStructElementTypes(ty) } == 4u32)
            let fields = [ptr, i8, i32, ptr]
            for (index in 0..fields.size) {
                AssertField(ty, UInt32(index), fields[index])
            }
            println("NAMED_STRUCT_GENERICTI_LAYOUT_CHECKED fields=4")
        }
    }

    @TestCase
    public func GenericTypeInfoRepeatedLookupReusesCompletedType(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let first = GetOrCreateGenericTypeInfoType(context)
            println("NAMED_STRUCT_GENERICTI_FIRST fields=${unsafe { LLVMCountStructElementTypes(first) }}")
            let second = GetOrCreateGenericTypeInfoType(context)
            println("NAMED_STRUCT_GENERICTI_SECOND_RETURNED")
            @Assert(SameType(first, second))
            @Assert(unsafe { LLVMCountStructElementTypes(second) } == 4u32)
            println("NAMED_STRUCT_GENERICTI_REUSE_CHECKED fields=4")
        }
    }

    @TestCase
    public func GenericCustomTypeInfoFirstCreationHasRuntimeLayout(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let ty = GetOrCreateGenericCustomTypeInfoType(context)
            let i8 = unsafe { LLVMInt8TypeInContext(context.raw) }
            let ptr = unsafe { LLVMPointerType(i8, 0u32) }
            @Assert(unsafe { LLVMIsOpaqueStruct(ty) } == 0)
            @Assert(unsafe { LLVMCountStructElementTypes(ty) } == 5u32)
            let fields = [ptr, i8, i8, ptr, ptr]
            for (index in 0..fields.size) {
                AssertField(ty, UInt32(index), fields[index])
            }
            println("NAMED_STRUCT_GENERICCUSTOM_LAYOUT_CHECKED fields=5")
        }
    }

    @TestCase
    public func GenericCustomTypeInfoRepeatedLookupReusesCompletedType(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let first = GetOrCreateGenericCustomTypeInfoType(context)
            println("NAMED_STRUCT_GENERICCUSTOM_FIRST fields=${unsafe { LLVMCountStructElementTypes(first) }}")
            let second = GetOrCreateGenericCustomTypeInfoType(context)
            println("NAMED_STRUCT_GENERICCUSTOM_SECOND_RETURNED")
            @Assert(SameType(first, second))
            @Assert(unsafe { LLVMCountStructElementTypes(second) } == 5u32)
            println("NAMED_STRUCT_GENERICCUSTOM_REUSE_CHECKED fields=5")
        }
    }

    @TestCase
    public func TypeInfoGcTibUsesBitMap(): Unit {
        try (context = LLVMContextHandle.Create()) {
            let typeInfo = CGType.GetOrCreateTypeInfoType(context)
            let bitMap = CGType.GetBitMapType(context)
            @Assert(!typeInfo.isNull())
            @Assert(unsafe { LLVMIsOpaqueStruct(typeInfo) } == 0)
            @Assert(unsafe { LLVMCountStructElementTypes(typeInfo) } == 18u32)
            let field = unsafe { LLVMStructGetTypeAtIndex(typeInfo, 5u32) }
            let expected = unsafe { LLVMPointerType(bitMap, 0u32) }
            println("NAMED_STRUCT_TYPEINFO_GCTIB_COMPARE field=${field.toUIntNative()} expected=${expected.toUIntNative()}")
            @Assert(SameType(field, expected))
            println("NAMED_STRUCT_TYPEINFO_GCTIB_CHECKED")
        }
    }
}

@Test
public class NamedStructRulerTest {
    @TestCase
    public func BareSecondSetBodyHitsOpaquePrecondition(): Unit {
        try (context = LLVMContextHandle.Create()) {
            var ty = LLVMNullType()
            try (name = unsafe { LibC.mallocCString("BareSetBody.Probe") }.asResource()) {
                ty = unsafe { LLVMStructCreateNamed(context.raw, name.value) }
            }
            let i8 = unsafe { LLVMInt8TypeInContext(context.raw) }
            try (slot = LibC.malloc<LLVMTypeRef>(count: 1).asResource()) {
                unsafe { slot.value.write(i8) }
                unsafe { LLVMStructSetBody(ty, slot.value, 1u32, 0) }
                println("BARE_SETBODY_FIRST_OK")
                unsafe { LLVMStructSetBody(ty, slot.value, 1u32, 0) }
            }
            println("BARE_SETBODY_SECOND_SHOULD_NOT_PRINT")
        }
    }
}
