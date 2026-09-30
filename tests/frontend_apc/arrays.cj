package frontend_array_contract

public class Element {
    public var value: Int64
    public init(value: Int64) { this.value = value }
}

public func readValue(values: Array<Int64>, index: Int64): Int64 { return values[index] }
public func writeValue(values: Array<Int64>, index: Int64, value: Int64): Unit { values[index] = value }
public func readReference(values: Array<Element>, index: Int64): Element { return values[index] }
public func writeReference(values: Array<Element>, index: Int64, value: Element): Unit { values[index] = value }
public func arraySize(values: Array<Element>): Int64 { return values.size }
