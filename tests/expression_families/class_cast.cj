package expression_class_cast
public open class Base {}
public class Derived <: Base {}
public func upcast(value: Derived): Base { return value }
