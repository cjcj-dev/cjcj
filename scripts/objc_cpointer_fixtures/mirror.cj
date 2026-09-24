package cpointer_mirror
import objc.lang.*
import objc.internal.*
@ObjCMirror["PointerMirror"]
public open class PointerMirror {
    public init(pointer: Int64)
    public func integerControl(): Int64
    public func mirrorResult(): PointerMirror
}
@ObjCMirror["PointerChild"]
public class PointerChild <: PointerMirror {
    public init(pointer: Int64)
}
