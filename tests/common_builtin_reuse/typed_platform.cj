package std.core

public func keepArray(value: RawArray<Object>): RawArray<Object> { value }
public func keepVArray(value: VArray<Int64, $1>): VArray<Int64, $1> { value }
public func keepPointer(value: CPointer<Int64>): CPointer<Int64> { value }
public func keepCFunc(value: CFunc<() -> Unit>): CFunc<() -> Unit> { value }
public func keepCString(value: CString): CString { value }
