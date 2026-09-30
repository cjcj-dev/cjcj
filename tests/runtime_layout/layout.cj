package layout_contract

public open class Parent {
    public var tag: Int32
    public init(tag: Int32) { this.tag = tag }
}
public class Child <: Parent {
    public var count: Int64
    public init(tag: Int32, count: Int64) { super(tag); this.count = count }
}
public struct Cell<T> {
    public var value: T
    public init(value: T) { this.value = value }
}
public func childCount(child: Child): Int64 { return child.count }
public func genericCopy<T>(cell: Cell<T>): Cell<T> { return cell }
public func genericGet<T>(values: Array<T>, index: Int64): T { return values[index] }
public func genericSet<T>(values: Array<T>, index: Int64, value: T): Unit { values[index] = value }
public func genericSize<T>(values: Array<T>): Int64 { return values.size }
public func staticGet(values: Array<Int64>, index: Int64): Int64 { return values[index] }
public func staticSet(values: Array<Int64>, index: Int64, value: Int64): Unit { values[index] = value }
public func staticSize(values: Array<Int64>): Int64 { return values.size }
public func boxedCell<T>(value: T): Any { return Cell<T>(value) }
public func newChild(): Child { return Child(7, 11) }
public func concreteCell(): Cell<Int64> { return Cell<Int64>(17) }
// A generic-related value with known size exercises debug boxing of `this`.
public struct FixedCell<T> {
    public var value: Int64
    public init(value: Int64) { this.value = value }
    public mut func set(value: Int64): Unit { this.value = value }
}
public func boxedFixed<T>(value: Int64): FixedCell<T> { return FixedCell<T>(value) }

public enum Tagged { Number(Int64) | Reference(Parent) }
public func makeNumber(): Tagged { return Tagged.Number(23) }
public func makeReference(): Tagged { return Tagged.Reference(Parent(5)) }
