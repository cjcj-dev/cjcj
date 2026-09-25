package ltoreflectiondirect
import std.reflect.*
public func reflectionName(): String { return TypeInfo.of<Int64>().toString() }
