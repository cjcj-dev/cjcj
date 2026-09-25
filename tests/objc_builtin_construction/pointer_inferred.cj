package pointer_inferred
import objc.lang.*
public struct NotCompatible {}
public func check() { let p = ObjCPointer(NotCompatible()) }
