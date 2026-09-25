package func_inferred
import objc.lang.*
public struct NotCompatible {}
public func check() { let f = ObjCFunc({ x: NotCompatible => x }) }
