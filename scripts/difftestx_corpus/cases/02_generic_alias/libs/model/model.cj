package model
public struct Box<T> { public let value: T; public init(value: T) { this.value = value } }
public let answer = Box<Int64>(42)
