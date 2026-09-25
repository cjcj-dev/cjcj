package expression_class_cast
open class Base {}
class Derived <: Base {}
public func upcast(value: Derived): Base { return value }
