package cjcj::modules

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::flatbuffers.*

private func ImportSpecFixture(implicitAdd: Bool, legacy!: Bool = false): Array<UInt8> {
    let builder = FlatBufferBuilder()
    let prefixes = builder.CreateVectorOfStrings(ArrayList<String>())
    let identifier = builder.CreateString("*")
    let alias = builder.CreateString("")
    let position = PackPosition(1u32, 0u32, 2, 1, false)
    var root: FlatBufferOffset = 0u32
    if (legacy) {
        // Exact pre-C12 layout: no tenth field or new attribute.
        builder.StartTable(9)
        builder.AddOffset(4, alias)
        builder.AddOffset(3, identifier)
        builder.AddOffset(2, prefixes)
        builder.AddStruct(1, position, 4)
        builder.AddStruct(0, position, 4)
        root = builder.EndTable()
    } else {
        root = CreateImportSpec(builder, position, position, prefixes, identifier, alias,
            MF_ACCESS_MODIFIER_PRIVATE, false, false, true, implicitAdd)
    }
    builder.Finish(root)
    return builder.GetBufferArray()
}

@Test
public class ImportSpecImplicitTest {
    @TestCase
    public func BindingDefaultsAndPresentSlotValidation(): Unit {
        for ((flag, legacy) in [(true, false), (false, false), (false, true)]) {
            let data = ImportSpecFixture(flag, legacy: legacy)
            let table = Int64(ReadScalar(data, 0, 0u32))
            let spec = PackageFormat_ImportSpec(data, table)
            @Expect(spec.Verify(VerifierTemplate(data)))
            @Expect(spec.GetIsImplicitAdd(), flag)
            @Expect(spec.GetWithImplicitExport(), true)
            @Expect(spec.GetIdentifier().getOrThrow().str(), "*")
        }
        let original = ImportSpecFixture(true)
        let table = Int64(ReadScalar(original, 0, 0u32))
        let spec = PackageFormat_ImportSpec(original, table)
        let slot = spec.GetVTable() + Int64(MF_IMPORT_SPEC_VT_ISIMPLICITADD)
        let field = table + Int64(spec.GetOptionalFieldOffset(MF_IMPORT_SPEC_VT_ISIMPLICITADD))
        let presentFalse = original.clone()
        presentFalse[field] = 0u8
        @Expect(PackageFormat_ImportSpec(presentFalse, table).Verify(VerifierTemplate(presentFalse)))
        @Expect(PackageFormat_ImportSpec(presentFalse, table).GetIsImplicitAdd(), false)
        for (kind in 0..3) {
            let data = original.clone()
            if (kind == 0) {
                data[slot] = 255u8
                data[slot + 1] = 255u8
            } else if (kind == 1) {
                let objectSize = ReadScalar(data, spec.GetVTable() + 2, 0u16)
                data[slot] = UInt8(objectSize & 255u16)
                data[slot + 1] = UInt8(objectSize >> 8)
            } else {
                data[field] = 2u8
            }
            println("IMPORT_SLOT_REJECTION kind=${kind}")
            @Expect(PackageFormat_ImportSpec(data, table).Verify(VerifierTemplate(data)), false)
        }
    }
}
