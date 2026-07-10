package cjcj::chir

import std.core.Box as CoreBox
import cjcj::utils.CJC_ASSERT

// flatbuffers/base.h:370-409. The _MSC_VER intrinsics and __ICCARM__
// intrinsics branches are accounted for here; the GNU/Clang byte-swap path is
// the implementation used by the little-endian Linux x86_64 self-host target.
@OverflowWrapping
func EndianSwap<T>(t: T): T {
    if (t is UInt8 || t is Int8 || t is Bool) {
        return t
    } else if (t is UInt16) {
        let value = (t as UInt16).getOrThrow()
        return (((value >> 8) | (value << 8)) as T).getOrThrow()
    } else if (t is Int16) {
        let value = UInt16((t as Int16).getOrThrow())
        return (Int16((value >> 8) | (value << 8)) as T).getOrThrow()
    } else if (t is Float16) {
        let value = (t as Float16).getOrThrow().toBits()
        return (Float16.fromBits((value >> 8) | (value << 8)) as T).getOrThrow()
    } else if (t is UInt32) {
        let value = (t as UInt32).getOrThrow()
        let swapped = ((value & 0x000000ffu32) << 24) | ((value & 0x0000ff00u32) << 8) |
            ((value & 0x00ff0000u32) >> 8) | ((value & 0xff000000u32) >> 24)
        return (swapped as T).getOrThrow()
    } else if (t is Int32) {
        let value = UInt32((t as Int32).getOrThrow())
        let swapped = ((value & 0x000000ffu32) << 24) | ((value & 0x0000ff00u32) << 8) |
            ((value & 0x00ff0000u32) >> 8) | ((value & 0xff000000u32) >> 24)
        return (Int32(swapped) as T).getOrThrow()
    } else if (t is Float32) {
        let value = (t as Float32).getOrThrow().toBits()
        let swapped = ((value & 0x000000ffu32) << 24) | ((value & 0x0000ff00u32) << 8) |
            ((value & 0x00ff0000u32) >> 8) | ((value & 0xff000000u32) >> 24)
        return (Float32.fromBits(swapped) as T).getOrThrow()
    } else if (t is Rune) {
        let value = UInt32((t as Rune).getOrThrow())
        let swapped = ((value & 0x000000ffu32) << 24) | ((value & 0x0000ff00u32) << 8) |
            ((value & 0x00ff0000u32) >> 8) | ((value & 0xff000000u32) >> 24)
        return (Rune(swapped) as T).getOrThrow()
    } else if (t is UInt64) {
        let value = (t as UInt64).getOrThrow()
        let swapped = ((value & 0x00000000000000ffu64) << 56) | ((value & 0x000000000000ff00u64) << 40) |
            ((value & 0x0000000000ff0000u64) << 24) | ((value & 0x00000000ff000000u64) << 8) |
            ((value & 0x000000ff00000000u64) >> 8) | ((value & 0x0000ff0000000000u64) >> 24) |
            ((value & 0x00ff000000000000u64) >> 40) | ((value & 0xff00000000000000u64) >> 56)
        return (swapped as T).getOrThrow()
    } else if (t is Int64) {
        let value = UInt64((t as Int64).getOrThrow())
        let swapped = ((value & 0x00000000000000ffu64) << 56) | ((value & 0x000000000000ff00u64) << 40) |
            ((value & 0x0000000000ff0000u64) << 24) | ((value & 0x00000000ff000000u64) << 8) |
            ((value & 0x000000ff00000000u64) >> 8) | ((value & 0x0000ff0000000000u64) >> 24) |
            ((value & 0x00ff000000000000u64) >> 40) | ((value & 0xff00000000000000u64) >> 56)
        return (Int64(swapped) as T).getOrThrow()
    } else if (t is Float64) {
        let value = (t as Float64).getOrThrow().toBits()
        let swapped = ((value & 0x00000000000000ffu64) << 56) | ((value & 0x000000000000ff00u64) << 40) |
            ((value & 0x0000000000ff0000u64) << 24) | ((value & 0x00000000ff000000u64) << 8) |
            ((value & 0x000000ff00000000u64) >> 8) | ((value & 0x0000ff0000000000u64) >> 24) |
            ((value & 0x00ff000000000000u64) >> 40) | ((value & 0xff00000000000000u64) >> 56)
        return (Float64.fromBits(swapped) as T).getOrThrow()
    }
    CJC_ASSERT(false)
    return t
}

// flatbuffers/base.h:416-422. FlatBuffers wire data and the supported
// Linux x86_64 target are both little-endian.
func EndianScalar<T>(t: T): T {
    return t
}

// flatbuffers/base.h:424-429. A C++ byte pointer is represented by the byte
// array plus its element offset.
@OverflowWrapping
func ReadScalar<T>(data: Array<UInt8>, pos: Int64): T {
    if (UInt8(0) is T) {
        return EndianScalar<T>((data[pos] as T).getOrThrow())
    } else if (Int8(0) is T) {
        return EndianScalar<T>((Int8(data[pos]) as T).getOrThrow())
    } else if (false is T) {
        return EndianScalar<T>(((data[pos] != 0u8) as T).getOrThrow())
    } else if (UInt16(0) is T || Int16(0) is T || Float16(0.0) is T) {
        let value = UInt16(data[pos]) | (UInt16(data[pos + 1]) << 8)
        if (UInt16(0) is T) {
            return EndianScalar<T>((value as T).getOrThrow())
        } else if (Int16(0) is T) {
            return EndianScalar<T>((Int16(value) as T).getOrThrow())
        }
        return EndianScalar<T>((Float16.fromBits(value) as T).getOrThrow())
    } else if (UInt32(0) is T || Int32(0) is T || Float32(0.0) is T || Rune(0) is T) {
        let value = UInt32(data[pos]) | (UInt32(data[pos + 1]) << 8) |
            (UInt32(data[pos + 2]) << 16) | (UInt32(data[pos + 3]) << 24)
        if (UInt32(0) is T) {
            return EndianScalar<T>((value as T).getOrThrow())
        } else if (Int32(0) is T) {
            return EndianScalar<T>((Int32(value) as T).getOrThrow())
        } else if (Float32(0.0) is T) {
            return EndianScalar<T>((Float32.fromBits(value) as T).getOrThrow())
        }
        return EndianScalar<T>((Rune(value) as T).getOrThrow())
    } else if (UInt64(0) is T || Int64(0) is T || Float64(0.0) is T) {
        let value = UInt64(data[pos]) | (UInt64(data[pos + 1]) << 8) |
            (UInt64(data[pos + 2]) << 16) | (UInt64(data[pos + 3]) << 24) |
            (UInt64(data[pos + 4]) << 32) | (UInt64(data[pos + 5]) << 40) |
            (UInt64(data[pos + 6]) << 48) | (UInt64(data[pos + 7]) << 56)
        if (UInt64(0) is T) {
            return EndianScalar<T>((value as T).getOrThrow())
        } else if (Int64(0) is T) {
            return EndianScalar<T>((Int64(value) as T).getOrThrow())
        }
        return EndianScalar<T>((Float64.fromBits(value) as T).getOrThrow())
    }
    CJC_ASSERT(false)
    return (UInt8(0) as T).getOrThrow()
}

// flatbuffers/buffer.h:28-37. Offset<T> is the four-byte uoffset_t wrapper
// used to select IndirectHelper's vector-of-offsets read specialization.
struct Offset<T> {
    let o: UInt32

    init() {
        o = 0u32
    }

    init(o: UInt32) {
        this.o = o
    }

    func Union(): Offset<Any> {
        return Offset<Any>(o)
    }

    func IsNull(): Bool {
        return o == 0u32
    }
}

// flatbuffers/buffer.h:93-135. C++ template return_type is T for scalar
// elements and const T* for Offset<T>; Any carries that type-dependent return
// in Cangjie, with byte-array positions representing C++ byte pointers.
class IndirectHelper<T> {
    static func element_stride(): Int64 {
        if (UInt8(0) is T || Int8(0) is T || false is T) {
            return 1
        } else if (UInt16(0) is T || Int16(0) is T || Float16(0.0) is T) {
            return 2
        } else if (UInt32(0) is T || Int32(0) is T || Float32(0.0) is T || Rune(0) is T) {
            return 4
        } else if (UInt64(0) is T || Int64(0) is T || Float64(0.0) is T) {
            return 8
        }
        return 4
    }

    static func Read(data: Array<UInt8>, p: Int64, i: UInt32): Any {
        let stride = element_stride()
        let elementPos = p + Int64(i) * stride
        if (UInt8(0) is T || Int8(0) is T || false is T || UInt16(0) is T || Int16(0) is T ||
            Float16(0.0) is T || UInt32(0) is T || Int32(0) is T || Float32(0.0) is T || Rune(0) is T ||
            UInt64(0) is T || Int64(0) is T || Float64(0.0) is T) {
            return ReadScalar<T>(data, elementPos)
        }
        return elementPos + Int64(ReadScalar<UInt32>(data, elementPos))
    }
}

// flatbuffers/table.h:27-74. The C++ data_ pointer is represented by data and
// pos; nullable result pointers are represented by Option<Int64> offsets into
// the same byte array.
open class Table {
    let data: Array<UInt8>
    let pos: Int64

    init(data: Array<UInt8>, pos: Int64) {
        this.data = data
        this.pos = pos
    }

    func GetVTable(): Int64 {
        return pos - Int64(ReadScalar<Int32>(data, pos))
    }

    func GetOptionalFieldOffset(field: UInt16): UInt16 {
        let vtable = GetVTable()
        let vtsize = ReadScalar<UInt16>(data, vtable)
        return if (field < vtsize) { ReadScalar<UInt16>(data, vtable + Int64(field)) } else { 0u16 }
    }

    func GetField<T>(field: UInt16, defaultval: T): T {
        let fieldOffset = GetOptionalFieldOffset(field)
        return if (fieldOffset != 0u16) {
            ReadScalar<T>(data, pos + Int64(fieldOffset))
        } else {
            defaultval
        }
    }

    func GetPointer(field: UInt16): Option<Int64> {
        let fieldOffset = GetOptionalFieldOffset(field)
        let pointerPos = pos + Int64(fieldOffset)
        return if (fieldOffset != 0u16) {
            Some(pointerPos + Int64(ReadScalar<UInt32>(data, pointerPos)))
        } else {
            None
        }
    }

    func GetStruct(field: UInt16): Option<Int64> {
        let fieldOffset = GetOptionalFieldOffset(field)
        let pointerPos = pos + Int64(fieldOffset)
        return if (fieldOffset != 0u16) { Some(pointerPos) } else { None }
    }
}

// flatbuffers/vector.h:158-195,269-278. The C++ length_ address is represented
// by pos; Data() is the first byte after its four-byte uoffset_t length.
open class Vector<T> {
    let data: Array<UInt8>
    let pos: Int64

    init(data: Array<UInt8>, pos: Int64) {
        this.data = data
        this.pos = pos
    }

    func size(): UInt32 {
        return EndianScalar<UInt32>(ReadScalar<UInt32>(data, pos))
    }

    func Get(i: UInt32): Any {
        CJC_ASSERT(i < size())
        return IndirectHelper<T>.Read(data, Data(), i)
    }

    func Data(): Int64 {
        return pos + 4
    }

    private func element_stride(): Int64 {
        return IndirectHelper<T>.element_stride()
    }
}

// flatbuffers/string.h:25-28. The namespace-qualified C++ name
// flatbuffers::String is flattened to avoid shadowing Cangjie's core String.
class FlatBufferString <: Vector<UInt8> {
    init(data: Array<UInt8>, pos: Int64) {
        super(data, pos)
    }

    func str(): String {
        return String.fromUtf8(data[Data()..Data() + Int64(size())])
    }
}

// flatbuffers/verifier.h:29-42. The namespace-qualified nested type
// VerifierTemplate::Options is flattened for Cangjie.
struct VerifierOptions {
    var maxDepth: UInt32 = 64u32
    var maxTables: UInt32 = 1000000u32
    var checkAlignment: Bool = true
    var checkNestedFlatbuffers: Bool = true
    var maxSize: Int64 = Int64(Int32.Max)

    init() {}
}

// flatbuffers/verifier.h:26-360. C++ byte pointers are byte-array positions;
// the verifyRoot/verifyTable closures are the Cangjie form of T::Verify static
// template dispatch and will be supplied by generated table bindings.
class VerifierTemplate {
    private let data: Array<UInt8>
    private let size_: Int64
    private let opts: VerifierOptions
    private let trackVerifierBufferSize: Bool
    private var upperBound: Int64 = 0
    private var depth: UInt32 = 0u32
    private var numTables: UInt32 = 0u32

    init(data: Array<UInt8>, opts!: VerifierOptions = VerifierOptions(),
        trackVerifierBufferSize!: Bool = false) {
        this.data = data
        this.size_ = data.size
        this.opts = opts
        this.trackVerifierBufferSize = trackVerifierBufferSize
        CJC_ASSERT(size_ < opts.maxSize)
    }

    func Check(ok: Bool): Bool {
        // FLATBUFFERS_DEBUG_VERIFICATION_FAILURE is not enabled for the
        // self-host target, matching verifier.h:65-69's compiled-out branch.
        if (trackVerifierBufferSize && !ok) {
            upperBound = 0
        }
        return ok
    }

    func Verify(elem: Int64, elemLen: Int64): Bool {
        if (trackVerifierBufferSize) {
            let bound = elem + elemLen
            if (upperBound < bound) {
                upperBound = bound
            }
        }
        // elem and elemLen represent C++ size_t and therefore cannot be
        // negative; the explicit checks preserve that domain in Int64.
        return Check(elem >= 0 && elemLen >= 0 && elemLen < size_ && elem <= size_ - elemLen)
    }

    func VerifyAlignment(elem: Int64, align: Int64): Bool {
        return Check((elem & (align - 1)) == 0 || !opts.checkAlignment)
    }

    func Verify<T>(elem: Int64): Bool {
        var scalarSize: Int64 = 0
        if (UInt8(0) is T || Int8(0) is T || false is T) {
            scalarSize = 1
        } else if (UInt16(0) is T || Int16(0) is T || Float16(0.0) is T) {
            scalarSize = 2
        } else if (UInt32(0) is T || Int32(0) is T || Float32(0.0) is T || Rune(0) is T) {
            scalarSize = 4
        } else if (UInt64(0) is T || Int64(0) is T || Float64(0.0) is T) {
            scalarSize = 8
        } else {
            CJC_ASSERT(false)
        }
        return VerifyAlignment(elem, scalarSize) && Verify(elem, scalarSize)
    }

    func VerifyFromPointer(pos: Int64, len: Int64): Bool {
        return Verify(pos, len)
    }

    func VerifyFieldStruct(base: Int64, elemOff: UInt16, elemLen: Int64, align: Int64): Bool {
        let field = base + Int64(elemOff)
        return VerifyAlignment(field, align) && Verify(field, elemLen)
    }

    func VerifyField<T>(base: Int64, elemOff: UInt16, align: Int64): Bool {
        let field = base + Int64(elemOff)
        var scalarSize: Int64 = 0
        if (UInt8(0) is T || Int8(0) is T || false is T) {
            scalarSize = 1
        } else if (UInt16(0) is T || Int16(0) is T || Float16(0.0) is T) {
            scalarSize = 2
        } else if (UInt32(0) is T || Int32(0) is T || Float32(0.0) is T || Rune(0) is T) {
            scalarSize = 4
        } else if (UInt64(0) is T || Int64(0) is T || Float64(0.0) is T) {
            scalarSize = 8
        } else {
            CJC_ASSERT(false)
        }
        return VerifyAlignment(field, align) && Verify(field, scalarSize)
    }

    func VerifyTable(table: Option<Int64>, verifyTable: (Int64, VerifierTemplate) -> Bool): Bool {
        return if (let Some(tablePos) <- table) { verifyTable(tablePos, this) } else { true }
    }

    func VerifyVector(vec: Option<Int64>, elemSize: Int64): Bool {
        return if (let Some(vecPos) <- vec) { VerifyVectorOrString(vecPos, elemSize) } else { true }
    }

    func VerifyString(str: Option<Int64>): Bool {
        if (let None <- str) {
            return true
        }
        let end = CoreBox<Int64>(0)
        let strPos = str.getOrThrow()
        return VerifyVectorOrString(strPos, 1, end: Some(end)) && Verify(end.value, 1) &&
            Check(data[end.value] == 0u8)
    }

    func VerifyVectorOrString(vec: Int64, elemSize: Int64, end!: Option<CoreBox<Int64>> = None): Bool {
        if (!Verify<UInt32>(vec)) {
            return false
        }
        let vectorSize = ReadScalar<UInt32>(data, vec)
        let maxElems = opts.maxSize / elemSize
        if (!Check(Int64(vectorSize) < maxElems)) {
            return false
        }
        let byteSize = 4 + elemSize * Int64(vectorSize)
        if (let Some(endPos) <- end) {
            endPos.value = vec + byteSize
        }
        return Verify(vec, byteSize)
    }

    func VerifyVectorOfStrings(vec: Option<Int64>): Bool {
        if (let Some(vecPos) <- vec) {
            let values = Vector<UInt32>(data, vecPos)
            var idx = 0u32
            while (idx < values.size()) {
                let offsetPos = values.Data() + Int64(idx) * 4
                let target = offsetPos + Int64(ReadScalar<UInt32>(data, offsetPos))
                if (!VerifyString(Some(target))) {
                    return false
                }
                idx++
            }
        }
        return true
    }

    func VerifyVectorOfTables(vec: Option<Int64>, verifyTable: (Int64, VerifierTemplate) -> Bool): Bool {
        if (let Some(vecPos) <- vec) {
            let values = Vector<UInt32>(data, vecPos)
            var idx = 0u32
            while (idx < values.size()) {
                let offsetPos = values.Data() + Int64(idx) * 4
                let target = offsetPos + Int64(ReadScalar<UInt32>(data, offsetPos))
                if (!verifyTable(target, this)) {
                    return false
                }
                idx++
            }
        }
        return true
    }

    @OverflowWrapping
    func VerifyTableStart(table: Int64): Bool {
        if (!Verify<Int32>(table)) {
            return false
        }
        let vtable = table - Int64(ReadScalar<Int32>(data, table))
        if (!(VerifyComplexity() && Verify<UInt16>(vtable) &&
            VerifyAlignment(Int64(ReadScalar<UInt16>(data, vtable)), 2))) {
            return false
        }
        let vtableSize = ReadScalar<UInt16>(data, vtable)
        return Check((vtableSize & 1u16) == 0u16) && Verify(vtable, Int64(vtableSize))
    }

    func VerifyBufferFromStart(start: Int64, verifyRoot: (Int64, VerifierTemplate) -> Bool): Bool {
        if (!Check(size_ >= 12)) {
            return false
        }
        // CHIRSerializer.cpp:1523 uses builder.Finish(serializedPackage), and
        // CHIRDeserializer.cpp:65 calls VerifyBuffer<T>() with no identifier.
        let rootOffset = VerifyOffset(start)
        if (!Check(rootOffset != 0)) {
            return false
        }
        if (!verifyRoot(start + rootOffset, this)) {
            return false
        }
        if (trackVerifierBufferSize && GetComputedSize() == 0) {
            return false
        }
        return true
    }

    func VerifyNestedFlatBuffer(buf: Option<Int64>, verifyRoot: (Int64, VerifierTemplate) -> Bool): Bool {
        if (!opts.checkNestedFlatbuffers) {
            return true
        }
        if (let None <- buf) {
            return true
        }
        let vectorPos = buf.getOrThrow()
        let vectorSize = Int64(ReadScalar<UInt32>(data, vectorPos))
        if (!Check(vectorSize >= 12)) {
            return false
        }
        let vectorData = vectorPos + 4
        let nested = VerifierTemplate(data[vectorData..vectorData + vectorSize], opts: opts,
            trackVerifierBufferSize: trackVerifierBufferSize)
        return nested.VerifyBuffer(verifyRoot)
    }

    func VerifyBuffer(verifyRoot: (Int64, VerifierTemplate) -> Bool): Bool {
        return VerifyBufferFromStart(0, verifyRoot)
    }

    func VerifySizePrefixedBuffer(verifyRoot: (Int64, VerifierTemplate) -> Bool): Bool {
        return Verify<UInt32>(0) && Check(Int64(ReadScalar<UInt32>(data, 0)) + 4 <= size_) &&
            VerifyBufferFromStart(4, verifyRoot)
    }

    @OverflowWrapping
    func VerifyOffset(start: Int64): Int64 {
        if (!Verify<UInt32>(start)) {
            return 0
        }
        let offset = ReadScalar<UInt32>(data, start)
        if (!Check(offset != 0u32)) {
            return 0
        }
        if (!Check(Int32(offset) >= 0)) {
            return 0
        }
        if (!Verify(start + Int64(offset), 1)) {
            return 0
        }
        return Int64(offset)
    }

    func VerifyOffset(base: Int64, start: UInt16): Int64 {
        return VerifyOffset(base + Int64(start))
    }

    @OverflowWrapping
    func VerifyComplexity(): Bool {
        depth++
        numTables++
        return Check(depth <= opts.maxDepth && numTables <= opts.maxTables)
    }

    @OverflowWrapping
    func EndTable(): Bool {
        depth--
        return true
    }

    func GetComputedSize(): Int64 {
        if (trackVerifierBufferSize) {
            let computedSize = (upperBound - 1 + 4) & -4
            return if (computedSize > size_) { 0 } else { computedSize }
        }
        CJC_ASSERT(false)
        return 0
    }
}

// flatbuffers/table.h:117-162 verifier-facing Table methods.
extend Table {
    func VerifyTableStart(verifier: VerifierTemplate): Bool {
        return verifier.VerifyTableStart(pos)
    }

    func VerifyField<T>(verifier: VerifierTemplate, field: UInt16, align: Int64): Bool {
        let fieldOffset = GetOptionalFieldOffset(field)
        return fieldOffset == 0u16 || verifier.VerifyField<T>(pos, fieldOffset, align)
    }

    func VerifyFieldRequired<T>(verifier: VerifierTemplate, field: UInt16, align: Int64): Bool {
        let fieldOffset = GetOptionalFieldOffset(field)
        return verifier.Check(fieldOffset != 0u16) && verifier.VerifyField<T>(pos, fieldOffset, align)
    }

    func VerifyOffset(verifier: VerifierTemplate, field: UInt16): Bool {
        let fieldOffset = GetOptionalFieldOffset(field)
        return fieldOffset == 0u16 || verifier.VerifyOffset(pos, fieldOffset) != 0
    }

    func VerifyOffsetRequired(verifier: VerifierTemplate, field: UInt16): Bool {
        let fieldOffset = GetOptionalFieldOffset(field)
        return verifier.Check(fieldOffset != 0u16) && verifier.VerifyOffset(pos, fieldOffset) != 0
    }
}
