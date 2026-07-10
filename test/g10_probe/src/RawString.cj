package rt.demangle

// Layer1 code deliberately calls libc directly.  LibC.malloc is not used here:
// its negative-count/error paths construct managed exceptions.
foreign {
    func malloc(size: UIntNative): CPointer<Unit>
    func free(ptr: CPointer<Unit>): Unit
}

private let NATIVE_POINTER_BYTES: Int64 = 8
private let RT_STRING_BYTES: Int64 = 40

@C
struct RtArena {
    var head: CPointer<Unit>

    init(head: CPointer<Unit>) {
        this.head = head
    }
}

// Every arena allocation stores the previous allocation in its first machine
// word.  One linear walk therefore releases every parser temporary, including
// those created along reject paths.
func RtArenaCreate(): CPointer<RtArena> {
    let raw = unsafe { malloc(UIntNative(NATIVE_POINTER_BYTES)) }
    if (raw.isNull()) {
        return CPointer<RtArena>()
    }
    let arena = CPointer<RtArena>(raw)
    unsafe { arena.write(0, RtArena(CPointer<Unit>())) }
    return arena
}

func RtArenaAlloc(arena: CPointer<RtArena>, size: Int64): CPointer<UInt8> {
    if (arena.isNull() || size < 0 || size > Int64.Max - NATIVE_POINTER_BYTES) {
        return CPointer<UInt8>()
    }
    let raw = unsafe { malloc(UIntNative(size + NATIVE_POINTER_BYTES)) }
    if (raw.isNull()) {
        return CPointer<UInt8>()
    }
    let previous = unsafe { arena.read().head }
    unsafe {
        CPointer<CPointer<Unit>>(raw).write(0, previous)
        arena.write(0, RtArena(raw))
    }
    return unsafe { CPointer<UInt8>(raw) + NATIVE_POINTER_BYTES }
}

func RtArenaDestroy(arena: CPointer<RtArena>): Unit {
    if (arena.isNull()) {
        return
    }
    var node = unsafe { arena.read().head }
    unsafe {
        while (!node.isNull()) {
            let previous = CPointer<CPointer<Unit>>(node).read()
            free(node)
            node = previous
        }
        free(CPointer<Unit>(arena))
    }
}

func RtNativeAlloc(size: Int64): CPointer<UInt8> {
    if (size < 0) {
        return CPointer<UInt8>()
    }
    return CPointer<UInt8>(unsafe { malloc(UIntNative(size)) })
}

public func RtNativeFree(ptr: CPointer<UInt8>): Unit {
    if (!ptr.isNull()) {
        unsafe { free(CPointer<Unit>(ptr)) }
    }
}

@C
struct RtString {
    let data: CPointer<UInt8>
    let len: Int64
    let arena: CPointer<RtArena>
    let literalId: Int64
    let offset: Int64

    init(data: CPointer<UInt8>, len: Int64, arena: CPointer<RtArena>, literalId: Int64, offset: Int64) {
        this.data = data
        this.len = len
        this.arena = arena
        this.literalId = literalId
        this.offset = offset
    }

    prop size: Int64 {
        get() { return len }
    }

    func isEmpty(): Bool {
        return len == 0
    }

    operator func [](index: Int64): UInt8 {
        if (index < 0 || index >= len) {
            return 0u8
        }
        if (literalId >= 0) {
            return RtLiteralByte(literalId, offset + index)
        }
        return unsafe { data.read(offset + index) }
    }

    operator func ==(right: RtString): Bool {
        if (len != right.len) {
            return false
        }
        var index: Int64 = 0
        while (index < len) {
            if (this[index] != right[index]) {
                return false
            }
            index++
        }
        return true
    }

    operator func !=(right: RtString): Bool {
        return !(this == right)
    }

    operator func +(right: RtString): RtString {
        return RtConcat(this, right)
    }

    func SubStr(start: Int64): RtString {
        return SubStr(start, len - start)
    }

    func SubStr(start: Int64, count: Int64): RtString {
        if (start < 0 || start >= len || count <= 0) {
            return RtEmpty(RtPickArena(this, this))
        }
        let realCount = if (count > len - start) { len - start } else { count }
        return RtString(data, realCount, arena, literalId, offset + start)
    }

    func Find(pattern: RtString): Int64 {
        return Find(pattern, 0)
    }

    func Find(pattern: RtString, start: Int64): Int64 {
        if (start < 0 || start > len || pattern.len > len - start) {
            return -1
        }
        if (pattern.len == 0) {
            return start
        }
        var pos = start
        while (pos <= len - pattern.len) {
            var index: Int64 = 0
            while (index < pattern.len && this[pos + index] == pattern[index]) {
                index++
            }
            if (index == pattern.len) {
                return pos
            }
            pos++
        }
        return -1
    }

    func EndsWith(suffix: RtString): Bool {
        if (suffix.len > len) {
            return false
        }
        var index: Int64 = 0
        let start = len - suffix.len
        while (index < suffix.len) {
            if (this[start + index] != suffix[index]) {
                return false
            }
            index++
        }
        return true
    }

    func WithArena(owner: CPointer<RtArena>): RtString {
        return RtString(data, len, owner, literalId, offset)
    }
}

func RtLit(id: Int64): RtString {
    return RtString(CPointer<UInt8>(), RtLiteralLength(id), CPointer<RtArena>(), id, 0)
}

func RtEmpty(arena: CPointer<RtArena>): RtString {
    return RtString(CPointer<UInt8>(), 0, arena, -1, 0)
}

func RtPickArena(left: RtString, right: RtString): CPointer<RtArena> {
    if (!left.arena.isNull()) {
        return left.arena
    }
    return right.arena
}

func RtOwned(arena: CPointer<RtArena>, length: Int64): RtString {
    if (length <= 0) {
        return RtEmpty(arena)
    }
    let data = RtArenaAlloc(arena, length)
    if (data.isNull()) {
        return RtEmpty(arena)
    }
    return RtString(data, length, arena, -1, 0)
}

func RtConcat(left: RtString, right: RtString): RtString {
    if (left.len == 0) {
        let arena = RtPickArena(left, right)
        return if (right.arena.isNull() && !arena.isNull()) { right.WithArena(arena) } else { right }
    }
    if (right.len == 0) {
        let arena = RtPickArena(left, right)
        return if (left.arena.isNull() && !arena.isNull()) { left.WithArena(arena) } else { left }
    }
    if (left.len > Int64.Max - right.len) {
        return RtEmpty(RtPickArena(left, right))
    }
    let arena = RtPickArena(left, right)
    let out = RtOwned(arena, left.len + right.len)
    if (out.len != left.len + right.len) {
        return out
    }
    var index: Int64 = 0
    unsafe {
        while (index < left.len) {
            out.data.write(index, left[index])
            index++
        }
        var rightIndex: Int64 = 0
        while (rightIndex < right.len) {
            out.data.write(index + rightIndex, right[rightIndex])
            rightIndex++
        }
    }
    return out
}

func RtByte(arena: CPointer<RtArena>, inputValue: UInt8): RtString {
    let out = RtOwned(arena, 1)
    if (out.len == 1) {
        unsafe { out.data.write(0, inputValue) }
    }
    return out
}

func RtFromCString(input: CPointer<UInt8>, arena: CPointer<RtArena>): RtString {
    if (input.isNull()) {
        return RtEmpty(arena)
    }
    var length: Int64 = 0
    unsafe {
        while (input.read(length) != 0u8 && length < Int64.Max) {
            length++
        }
    }
    return RtString(input, length, arena, -1, 0)
}

func RtClone(inputValue: RtString): RtString {
    let out = RtOwned(inputValue.arena, inputValue.len)
    if (out.len != inputValue.len) {
        return out
    }
    var index: Int64 = 0
    unsafe {
        while (index < inputValue.len) {
            out.data.write(index, inputValue[index])
            index++
        }
    }
    return out
}

func RtToCString(inputValue: RtString): CPointer<UInt8> {
    if (inputValue.len == Int64.Max) {
        return CPointer<UInt8>()
    }
    let out = RtNativeAlloc(inputValue.len + 1)
    if (out.isNull()) {
        return out
    }
    var index: Int64 = 0
    unsafe {
        while (index < inputValue.len) {
            out.write(index, inputValue[index])
            index++
        }
        out.write(inputValue.len, 0u8)
    }
    return out
}

func EndsWith(inputValue: RtString, suffix: RtString): Bool {
    return inputValue.EndsWith(suffix)
}

func IsDigit(inputValue: UInt8): Bool {
    return inputValue >= b'0' && inputValue <= b'9'
}

func IsAlnum(inputValue: UInt8): Bool {
    return (inputValue >= b'0' && inputValue <= b'9') || (inputValue >= b'A' && inputValue <= b'Z') ||
        (inputValue >= b'a' && inputValue <= b'z')
}

// Allocate a mutable RtString cell inside the call arena.  DeCompression uses
// this to preserve the reference semantics of the C++ T& helpers without a
// managed class allocation.
func RtStringCell(inputValue: RtString): CPointer<RtString> {
    let raw = RtArenaAlloc(inputValue.arena, RT_STRING_BYTES)
    if (raw.isNull()) {
        return CPointer<RtString>()
    }
    let cell = CPointer<RtString>(raw)
    unsafe { cell.write(0, inputValue) }
    return cell
}
