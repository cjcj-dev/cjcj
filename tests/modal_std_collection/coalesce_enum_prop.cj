package modalcollcoalesce

// Same shape as std.argopt arg_opt.cj:674-691: a value bound by `opt ?? throw E(...)` reads a
// plain property of its enum type (`spec.mode`), exactly as the `if (let Some(spec) <- opt)` form
// at arg_opt.cj:631 does.
enum Mode {
    | OptionalValue
    | RequiredValue
}

enum Spec {
    | Short(String, Mode)
    | Long(String, Mode)

    prop mode: Mode {
        get() {
            match (this) {
                case Short(_, m) => m
                case Long(_, m) => m
            }
        }
    }
}

func find(specs: Array<Spec>, i: Int64): ?Spec {
    if (i < specs.size) { Some(specs[i]) } else { None }
}

main(): Int64 {
    let specs = [Spec.Short("a", Mode.RequiredValue), Spec.Long("bb", Mode.OptionalValue)]
    let spec = find(specs, 1) ?? throw Exception("unknown option")
    let first = match (spec.mode) {
        case OptionalValue => 0
        case RequiredValue => 1
    }
    let other = find(specs, 0) ?? throw Exception("unknown option")
    if (other.mode == Mode.RequiredValue && first == 0) { 0 } else { 1 }
}
