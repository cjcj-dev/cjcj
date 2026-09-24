package cpointer_impl
import objc.lang.*
import objc.internal.*
@ObjCMirror["PointerMirror"]
public open class PointerMirror {
    public init(pointer: Int64)
}
@ObjCImpl
public open class PointerImpl <: PointerMirror {
    public init(pointer: Int64) { super(pointer) }
    public init() { this(0) }
}
@ObjCImpl
public class PointerImplChild <: PointerImpl {
    public init(pointer: Int64) { super(pointer) }
}
