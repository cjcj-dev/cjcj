package registry_broken
import objc.internal.*
import objc.lang.*
@ObjCMirror["BrokenMirror"]
public open class BrokenMirror {
    public init(items: Array<Int64>)
}
@ObjCImpl
public open class BrokenImpl <: BrokenMirror {
    public init() { super([]) }
}
@ObjCImpl
public class BrokenChild <: BrokenImpl {
    public init() { super() }
}
@ObjCMirror["HealthyMirror"]
public open class HealthyMirror {
    public init()
}
@ObjCImpl
public class HealthyImpl <: HealthyMirror {
    public init() { super() }
}
