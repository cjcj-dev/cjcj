package instantiate_function
func identity<T>(value: T): T { return value }
func capture<T>(): (T) -> T { return identity<T> }
main(): Int64 { return capture<Int64>()(17) }
