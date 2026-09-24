package registry_cache
import objc.lang.*
import objc.internal.*
@ObjCMirror["CacheA"]
public open class CacheA {
    public init()
    public func value(): Int64
}
@ObjCMirror["CacheB"]
public open class CacheB {
    public init()
    public func value(): Int64
}
public func first(obj: ObjCId): Bool { obj is CacheA }
public func middle(obj: ObjCId): Bool { obj is CacheB }
public func last(obj: ObjCId): Bool { obj is CacheA }
