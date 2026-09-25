package std.reflect

@Intrinsic
func getTypeByMangledName<T>(): CPointer<Unit>

@Intrinsic
func isSubType(ti: CPointer<Unit>, superTypeclassInfo: CPointer<Unit>): Bool

public func genericOf<T>(): CPointer<Unit> {
    getTypeByMangledName<T>()
}

public func concreteInt64(): CPointer<Unit> {
    getTypeByMangledName<Int64>()
}

public func reflectStillCallsRuntime(ti: CPointer<Unit>, superTi: CPointer<Unit>): Bool {
    isSubType(ti, superTi)
}

main() {
    let concrete = concreteInt64()
    let generic = genericOf<Int64>()
    if (concrete.isNull() || generic.isNull()) {
        throw Exception("TypeInfo pointer is null")
    }
    println("GET_TYPE_BY_MANGLED_NAME_OK")
}
