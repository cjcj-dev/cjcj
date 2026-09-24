package cpointer_mirror
import objc.lang.*
import objc.internal.*
@ObjCMirror["PointerMirror"]
public open class PointerMirror {
    public init(pointer: CPointer<Unit>)
    public func pointerResult(): CPointer<Unit>
    public func integerControl(): Int64
}
@ObjCMirror["PointerChild"]
public class PointerChild <: PointerMirror {
    public init(pointer: CPointer<Unit>)
}
