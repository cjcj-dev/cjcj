package modalpropgenericneg

public interface HasSize {
    prop size: Int64 {
        get() {
            1
        }
    }
}

// Only a plain-receiver `size` exists, so a @local! receiver must still be rejected.
func localSize<T>(from: T @local!): Int64 where T <: HasSize {
    from.size
}

main(): Int64 {
    0
}
