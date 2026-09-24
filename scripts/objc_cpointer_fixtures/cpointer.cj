package cpointer_compatible
import objc.lang.*
import objc.internal.*
@ObjCMirror["PointerMirror"]
public open class PointerMirror {
    public init(pointer: CPointer<Unit>)
    public func pointerResult(): CPointer<Unit>
    public func integerControl(): Int64
    public func mirrorResult(): PointerMirror
}
@ObjCMirror["PointerChild"]
public class PointerChild <: PointerMirror {
    public init(pointer: CPointer<Unit>)
}
