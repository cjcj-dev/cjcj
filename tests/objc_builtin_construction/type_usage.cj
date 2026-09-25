package type_usage
import objc.lang.*
public struct NotCompatible {}
public func check(p: ObjCPointer<NotCompatible>, b: ObjCBlock<(NotCompatible) -> Unit>) {}
