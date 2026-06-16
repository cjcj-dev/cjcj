package cangjie_compiler::basic

public enum Linkage {
    | WEAK_ODR
    | EXTERNAL
    | INTERNAL
    | LINKONCE_ODR
    | EXTERNAL_WEAK
}

public func LinkageToInt(value: Linkage): Int64 {
    return match (value) {
        case Linkage.WEAK_ODR => 0
        case Linkage.EXTERNAL => 1
        case Linkage.INTERNAL => 2
        case Linkage.LINKONCE_ODR => 3
        case Linkage.EXTERNAL_WEAK => 4
    }
}

extend Linkage <: Equatable<Linkage> {
    public operator func ==(right: Linkage): Bool {
        return LinkageToInt(this) == LinkageToInt(right)
    }

    public operator func !=(right: Linkage): Bool {
        return !(this == right)
    }
}
