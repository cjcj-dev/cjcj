package nothrow_fixture
import objc.internal.*
import objc.lang.*
@ObjCMirror["NothrowForeign"]
public open class ForeignObject {}
public class OrdinaryObject {
    public init() {}
    ~init() {}
}
public func control(x: Int64): Int64 { x + 1 }
@ObjCMirror
public interface ForeignProtocol {}
@ObjCMirror["DerivedForeign"]
public class DerivedForeign <: ForeignObject {}
public func noSideEffectControl(x: Int64): Int64 { x.hashCode() }
