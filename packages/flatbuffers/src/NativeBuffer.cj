package cjcj::flatbuffers

foreign {
    func memcpy(dest: CPointer<UInt8>, src: CPointer<UInt8>, count: UIntNative): CPointer<UInt8>
    func fopen(filename: CString, mode: CString): CPointer<Unit>
    func fwrite(data: CPointer<UInt8>, size: UIntNative, count: UIntNative, file: CPointer<Unit>): UIntNative
    func fclose(file: CPointer<Unit>): Int32
}

// flatbuffers/default_allocator.h:26-36 and allocator.h:41-52.
// Cangjie's native allocator is malloc/free; the allocation never enters the GC heap.
internal func Allocate(size: Int64): CPointer<UInt8> {
    let result = unsafe { LibC.malloc<UInt8>(count: size) }
    if (result.isNull()) {
        throw Exception("flatbuffer native allocation failed")
    }
    return result
}

internal func ReallocateDownward(old: CPointer<UInt8>, oldSize: Int64,
    newSize: Int64, back: Int64): CPointer<UInt8> {
    let result = Allocate(newSize)
    unsafe {
        if (back > 0) {
            memcpy(result + newSize - back, old + oldSize - back, UIntNative(back))
        }
        LibC.free(old)
    }
    return result
}

// detached_buffer.h:29-49,75,101-114. Ownership is transferred, not copied.
public class DetachedBuffer <: Resource {
    private var allocation: CPointer<UInt8>
    private var data: CPointer<UInt8>
    private var length: Int64
    public prop size: Int64 { get() { return length } }

    public init() {
        allocation = CPointer<UInt8>()
        data = CPointer<UInt8>()
        length = 0
    }

    internal init(allocation: CPointer<UInt8>, data: CPointer<UInt8>, size: Int64) {
        this.allocation = allocation
        this.data = data
        this.length = size
    }

    ~init() {
        unsafe { LibC.free(allocation) }
    }

    public func GetBufferPointer(): CPointer<UInt8> { return data }
    public func isEmpty(): Bool { return size == 0 }
    public func isClosed(): Bool { return allocation.isNull() }

    public func close(): Unit {
        unsafe { LibC.free(allocation) }
        allocation = CPointer<UInt8>()
        data = CPointer<UInt8>()
        length = 0
    }
}

// CHIR/Serializer/CHIRSerializer.cpp:1404-1410: write the borrowed native span.
public func WriteFlatBufferToFile(filename: String, data: CPointer<UInt8>, size: Int64): Unit {
    try (name = unsafe { LibC.mallocCString(filename) }.asResource(),
        mode = unsafe { LibC.mallocCString("wb") }.asResource()) {
        let file = unsafe { fopen(name.value, mode.value) }
        if (file.isNull()) {
            throw IllegalStateException("cannot open flatbuffer output: " + filename)
        }
        var written: UIntNative = 0
        var closeResult: Int32 = 0
        try {
            written = unsafe { fwrite(data, 1, UIntNative(size), file) }
        } finally {
            closeResult = unsafe { fclose(file) }
        }
        if (written != UIntNative(size) || closeResult != 0) {
            throw IllegalStateException("cannot write flatbuffer output: " + filename)
        }
    }
}
