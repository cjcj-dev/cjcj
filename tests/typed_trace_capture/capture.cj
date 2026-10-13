// Compile with the paired typed-trace compiler and LLVM; never execute this ABI fixture.
package std.core

@Intrinsic
func fillInStackTrace(seed: TraceCapture, message: RawArray<UInt8>): TraceCapture

@Intrinsic
func decodeStackTrace(capture: TraceCapture, frameIndex: Int64): StackTraceData

// Decoder output layout is unchanged; raw native fields remain distinct.
protected struct StackTraceData {
    public let className: RawArray<UInt8> = RawArray<UInt8>(0, repeat: 0)
    public let methodName: RawArray<UInt8> = RawArray<UInt8>(0, repeat: 0)
    public let fileName: RawArray<UInt8> = RawArray<UInt8>(0, repeat: 0)
    public let lineNumber: Int64 = 0
}

protected struct TraceFrame {
    public let mangledName: RawArray<UInt8> = RawArray<UInt8>(0, repeat: 0)
    public let directory: RawArray<UInt8> = RawArray<UInt8>(0, repeat: 0)
    public let filename: RawArray<UInt8> = RawArray<UInt8>(0, repeat: 0)
    public let resolved: StackTraceData = StackTraceData()
    public let lineNumber: Int64 = 0
    public let format: Int64 = 0
    public let kind: Int64 = 0 // native=0; interpreted=1
}

protected class TraceCapture {
    public let frames: RawArray<TraceFrame> = RawArray<TraceFrame>(0, repeat: TraceFrame())
    public let fold: Int64 = 0
    public init() {}
    public prop size: Int64 { get() { arraySize(frames) } }
    public func isEmpty(): Bool { size == 0 }
    public func frame(index: Int64): TraceFrame { arrayGet(frames, index) }
}

protected func typedTraceQualification(message: RawArray<UInt8>): StackTraceData {
    let capture = fillInStackTrace(TraceCapture(), message)
    return decodeStackTrace(capture, 0)
}
