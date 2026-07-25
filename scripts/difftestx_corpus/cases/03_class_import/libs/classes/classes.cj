package classes
public open class Base<T> { public let value: T; public init(value: T) { this.value = value } }
public class Child <: Base<Int64> { public init(value: Int64) { super(value) } }
