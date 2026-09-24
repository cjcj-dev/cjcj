package cpointer_impl
import objc.lang.*
import objc.internal.*
@ObjCMirror["PointerMirror"]
public open class PointerMirror {
    public init(pointer: CPointer<Unit>)
}
@ObjCImpl
public open class PointerImpl <: PointerMirror {
    public init(pointer: CPointer<Unit>) { super(pointer) }
    public init() { this(CPointer<Unit>()) }
}
@ObjCImpl
public class PointerImplChild <: PointerImpl {
    public init(pointer: CPointer<Unit>) { super(pointer) }
}
