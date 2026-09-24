package registry_members
import objc.internal.*
import objc.lang.*
@ObjCMirror["RegistryMirror"]
public open class RegistryMirror {
    public init()
}
@ObjCImpl
public open class RegistryImpl <: RegistryMirror {
    public var value: Int64 = 7
    public static var shared: Int64 = 9
    public init() { super() }
    public func readValue(): Int64 { value }
    public static func readShared(): Int64 { shared }
    public func accept(other: RegistryImpl): Int64 { other.value }
}
@ObjCImpl
public class RegistryChild <: RegistryImpl {
    public var childValue: Int64 = 11
    public init() { super() }
    public func readParent(): Int64 { value }
    ~init() { childValue = 0 }
}
public func readOther(obj: RegistryImpl): Int64 { obj.value }
public class Ordinary {
    public var value: Int64 = 1
}
